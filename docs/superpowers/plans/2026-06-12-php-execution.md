# PHP Execution in Web Agents — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run `.php` files from the web agents app as served web pages (forms, navigation, sessions) in the preview iframe, plus a `php` shell command, `/php` slash command, and agent tool.

**Architecture:** Lazy-loaded `@php-wasm/web` + `@php-wasm/universal` (WordPress Playground) from jsdelivr. A persistent `PHP` instance + `PHPRequestHandler` with document root `/disk`; the virtual disk (IndexedDB) is mirrored in/out of PHP's Emscripten FS around every execution (same pattern as Pyodide). Preview navigation works by injecting a postMessage bridge into the generated HTML inside the existing sandboxed `srcdoc` iframe.

**Tech Stack:** Vanilla JS in a single file (`docs/index.html`, ~2125 lines, no build step), `@php-wasm/web`/`@php-wasm/universal` ESM from `cdn.jsdelivr.net` (`/+esm` bundles).

**Spec:** `docs/superpowers/specs/2026-06-12-php-execution-design.md`

---

## Read this first — codebase facts

- **Everything lives in `docs/index.html`.** One giant HTML file with inline JS. Dense, compact style: one-statement-per-line, `try{...}catch(e){}` swallowing, two-space indent. Match it. Do NOT reformat existing lines.
- **The file contains exactly 2 literal NUL bytes** (intentional/legacy — grep reports it as binary). After every edit run `tr -dc '\0' < docs/index.html | wc -c` and confirm the output is still `2`. If a tool stripped them, restore via `git checkout -- docs/index.html` and redo the edit with another method.
- **No automated test infra for this app.** Project convention (see previous specs/commits) is manual browser verification. Each task ends with a manual verification step instead of unit tests. Serve locally with `python -m http.server 8000 --directory docs` and open `http://localhost:8000`.
- `T(es, en)` is the i18n helper — Spanish first, English second.
- `tool(msg)` prints a status line in the chat. `termLine(cmd, out, cwd)` prints a terminal card.
- `fsList()` → `[{path, content}]` (whole virtual disk), `fsGet(path)`, `fsPut(path, content)` — IndexedDB. Binary contents are stored as `' B64 ' + base64` (note the leading space).
- `shResolve(p)` resolves a shell path against `SHCWD` to a disk-relative path. `escHtml(s)` escapes HTML. `isUtf8Text(u8)` (index.html:595) decides text vs binary.
- `setWorking(bool)` toggles the spinner.
- Line numbers below are from the current file (commit `88c6105`); they shift as you insert code — anchor on the quoted code, not the number.

## File structure

Single file modified throughout: `docs/index.html`. New code goes in one new block (PHP runtime, after the C/clang section) plus small touch-points: `SHELL_CMDS` (line 270), `shRun` (line 378), `TOOLS` (line 1287), `execToolRaw` (line 1354), tool descriptions (line 1424), `toolMeta` (line 1487), editor (lines 978, 988–992), `slashCmd` (line 1786), cmds list (line 1959), `toolSafety` (line 2021), `BUILD` marker (line 34) + `docs/version.txt`.

---

### Task 1: PHP runtime core — `ensurePhp`, mirrors, `phpRequest`, `runPhp`, `runPhpCode`

**Files:**
- Modify: `docs/index.html` — insert a new section right after the line `async function ccRun(code){ return await ccExec([], code); }   // inline code path (/cc <code>, cc tool)` (line ~945)

- [ ] **Step 1: Insert the PHP runtime block**

Insert after the `ccRun` line:

```js
/* =====================================================================
   Real PHP via @php-wasm (WordPress Playground build). Lazy-loaded
   (~10MB). The virtual disk is mirrored into PHP's FS at /disk
   (document root), so PHP can read/write the same files. One PHP
   instance lives for the whole session -> $_SESSION persists.
   ===================================================================== */
let phpInst=null, phpHandler=null, phpLoading=null, phpCookies={};
async function ensurePhp(){ if(phpHandler) return phpHandler; if(phpLoading) return phpLoading;
  tool('🐘 '+T('Cargando PHP (~10MB, primera vez)…','Loading PHP (~10MB, first time)…'));
  phpLoading=(async()=>{
    const web=await import('https://cdn.jsdelivr.net/npm/@php-wasm/web/+esm');
    const uni=await import('https://cdn.jsdelivr.net/npm/@php-wasm/universal/+esm');
    phpInst=new uni.PHP(await web.loadWebRuntime('8.3'));
    try{ phpInst.mkdir('/disk'); }catch(e){} try{ phpInst.mkdir('/tmp'); }catch(e){}
    phpHandler=new uni.PHPRequestHandler({ phpFactory: async()=>phpInst, documentRoot:'/disk' });
    return phpHandler; })();
  try{ return await phpLoading; }catch(e){ phpLoading=null; throw e; } }
async function phpMirrorIn(){ const php=phpInst; try{php.mkdir('/disk');}catch(e){} const items=await fsList();
  for(const f of items){ const full='/disk/'+f.path; const dir=full.slice(0,full.lastIndexOf('/'));
    try{ php.mkdir(dir); }catch(e){}   // @php-wasm mkdir is recursive (mkdirTree)
    try{ const c=f.content||'';
      if(c.startsWith(' B64 ')){ const bin=atob(c.slice(5)); const u=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i); php.writeFile(full,u); }
      else php.writeFile(full,c);
    }catch(e){} } }
async function phpMirrorOut(){ const php=phpInst; const walk=(d,base)=>{ let out=[]; let names; try{names=php.listFiles(d);}catch(e){return out;}
    for(const n of names){ const full=d+'/'+n, rel=base?base+'/'+n:n;
      let isdir=false; try{ isdir=php.isDir(full); }catch(e){}
      if(isdir) out=out.concat(walk(full,rel));
      else { let content; try{ const u=php.readFileAsBuffer(full);
          if(isUtf8Text(u)){ content=new TextDecoder('utf-8').decode(u); }
          else { let bin=''; for(let i=0;i<u.length;i++)bin+=String.fromCharCode(u[i]); content=' B64 '+btoa(bin); }
        }catch(e){ content=''; }
        out.push({path:rel,content}); } } return out; };
  for(const f of walk('/disk','')) await fsPut(f.path, f.content); refreshDisk(); }
// One simulated HTTP request: cookie jar + follow local 3xx redirects (max 5 hops).
async function phpRequest(url, method, body){
  const handler=await ensurePhp(); await phpMirrorIn();
  let resp=null, hops=0, m=(method||'GET').toUpperCase(), b=body;
  while(hops<5){
    const headers={}; const jar=Object.entries(phpCookies).map(([k,v])=>k+'='+v).join('; '); if(jar) headers['cookie']=jar;
    resp=await handler.request({url, method:m, headers, body:b});
    const sc=resp.headers&&resp.headers['set-cookie'];
    if(sc) for(const c of [].concat(sc)){ const mm=/^([^=;]+)=([^;]*)/.exec(c); if(mm) phpCookies[mm[1]]=mm[2]; }
    const loc=resp.headers&&resp.headers['location'];
    if(resp.httpStatusCode>=300&&resp.httpStatusCode<400&&loc&&!/^https?:/i.test([].concat(loc)[0])){ url=[].concat(loc)[0]; m='GET'; b=undefined; hops++; continue; }
    break; }
  await phpMirrorOut(); return resp; }
// CLI-style execution (shell `php f.php`, /php, agent tool). path is disk-relative.
async function runPhp(path){
  try{ await ensurePhp(); }catch(e){ return 'PHP no disponible: '+e; }
  await phpMirrorIn();
  try{ const r=await phpInst.runStream({scriptPath:'/disk/'+path}); const out=await r.stdoutText, err=await r.stderrText;
    await phpMirrorOut(); return ((out||'')+(err?('\n'+err):'')).trim()||'(sin salida)'; }
  catch(e){ await phpMirrorOut(); return 'php error: '+(e.message||e); } }
async function runPhpCode(code){
  try{ await ensurePhp(); }catch(e){ return 'PHP no disponible: '+e; }
  await phpMirrorIn(); if(!/^\s*<\?/.test(code)) code='<?php '+code;
  try{ phpInst.writeFile('/tmp/__inline.php', code); const r=await phpInst.runStream({scriptPath:'/tmp/__inline.php'});
    const out=await r.stdoutText, err=await r.stderrText; await phpMirrorOut();
    return ((out||'')+(err?('\n'+err):'')).trim()||'(sin salida)'; }
  catch(e){ await phpMirrorOut(); return 'php error: '+(e.message||e); } }
```

- [ ] **Step 2: API-reality check (known risk from spec)**

The `/+esm` bundle or the `@php-wasm` API surface may differ from the above (`runStream` return shape, `mkdir` recursiveness, `headers` casing, `loadWebRuntime` asset URLs). Verify in the browser console at `http://localhost:8000`:

```js
const web = await import('https://cdn.jsdelivr.net/npm/@php-wasm/web/+esm');
const uni = await import('https://cdn.jsdelivr.net/npm/@php-wasm/universal/+esm');
const php = new uni.PHP(await web.loadWebRuntime('8.3'));
php.writeFile('/t.php','<?php echo "hi".(1+1);');
const r = await php.runStream({scriptPath:'/t.php'}); console.log(await r.stdoutText);   // expect "hi2"
const h = new uni.PHPRequestHandler({phpFactory:async()=>php, documentRoot:'/'});
const resp = await h.request({url:'/t.php'}); console.log(resp.text, resp.httpStatusCode, resp.headers);
```

If something differs (e.g. wasm fails to load from the `/+esm` bundle): pin exact versions (`@php-wasm/web@3.1.38/+esm`), or check `loadWebRuntime`'s options for an explicit asset/wasm URL. Adjust the inserted code to match reality and note the deviation in the commit message.

- [ ] **Step 3: Verify NUL bytes survived the edit**

Run: `tr -dc '\0' < docs/index.html | wc -c`
Expected: `2`

- [ ] **Step 4: Smoke-test in the app**

Serve, open the app, open the browser console, run: `await runPhpCode('echo 2+2;')`
Expected: `"4"` (first run shows the 🐘 loading toast and takes a while).

Then create a file via the disk UI or console (`await fsPut('hola.php','<?php echo "hola ".date("Y");')`) and run `await runPhp('hola.php')`.
Expected: `hola 2026`.

- [ ] **Step 5: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): PHP runtime core via @php-wasm — ensurePhp, FS mirror, phpRequest, runPhp"
```

---

### Task 2: Preview — `phpPreview`, bridge, asset inlining, editor wiring

**Files:**
- Modify: `docs/index.html` — append to the PHP block from Task 1; touch editor lines 978 and 988–992

- [ ] **Step 1: Append preview code to the PHP block**

```js
// ---- PHP web preview: serve .php into the editor iframe with working links/forms ----
// Injected into every rendered page: turns local link clicks and form submits into
// postMessage({type:'phpnav'}) so the parent re-runs PHP. NOTE the <\/script> escape:
// this string lives inside index.html's own <script>.
const PHP_BRIDGE='<scr'+'ipt>(function(){function send(u,m,b){parent.postMessage({type:"phpnav",url:u,method:m,body:b},"*");}'+
 'document.addEventListener("click",function(e){var a=e.target.closest("a");if(!a)return;var h=a.getAttribute("href")||"";'+
 'if(/^(https?:|mailto:|#|javascript:)/i.test(h))return;e.preventDefault();send(h,"GET");},true);'+
 'document.addEventListener("submit",function(e){var f=e.target;e.preventDefault();'+
 'var u=f.getAttribute("action")||"";var m=(f.getAttribute("method")||"GET").toUpperCase();'+
 'var d={};new FormData(f).forEach(function(v,k){d[k]=String(v);});'+
 'if(m==="GET"){var q=new URLSearchParams(d).toString();send(u+(q?(u.indexOf("?")>=0?"&":"?")+q:""),"GET");}'+
 'else send(u,"POST",d);},true);})();</scr'+'ipt>';
// Rewrite local src/href asset refs to data: URIs (srcdoc has no server to fetch from).
async function phpInlineAssets(html, curDir){
  const items=await fsList(); const map={}; for(const f of items) map[f.path]=f;
  const mime=p=>/\.css$/i.test(p)?'text/css':/\.js$/i.test(p)?'text/javascript':/\.png$/i.test(p)?'image/png':/\.jpe?g$/i.test(p)?'image/jpeg':/\.gif$/i.test(p)?'image/gif':/\.svg$/i.test(p)?'image/svg+xml':/\.ico$/i.test(p)?'image/x-icon':'application/octet-stream';
  return html.replace(/(src|href)=["']([^"']+)["']/gi,(m0,attr,val)=>{
    if(/^(https?:|data:|mailto:|#|javascript:|\/\/)/i.test(val)) return m0;
    if(/\.php([?#]|$)/i.test(val)) return m0;   // navigation -> bridge handles it
    const clean=val.replace(/[?#].*$/,'').replace(/^\.?\//,''); const f=map[curDir?curDir+'/'+clean:clean]||map[clean]; if(!f) return m0;
    const c=f.content||''; const b64=c.startsWith(' B64 ')?c.slice(5):btoa(unescape(encodeURIComponent(c)));
    return attr+'="data:'+mime(clean)+';base64,'+b64+'"'; });
}
let phpPrevUrl=null;
async function phpPreview(url, method, body){
  const fr=document.getElementById('edhtmlframe');
  let resp; try{ resp=await phpRequest(url, method, body); }
  catch(e){ fr.srcdoc='<pre style="color:#c00;padding:1em">PHP no disponible: '+escHtml(String(e))+'</pre>'; return; }
  phpPrevUrl=url;
  let html=resp.text||'';
  const ct=[].concat((resp.headers&&resp.headers['content-type'])||[])[0]||'';
  if(ct&&!/text\/html/i.test(ct)) html='<pre style="padding:1em">'+escHtml(html)+'</pre>';
  const curDir=url.replace(/^\//,'').split('/').slice(0,-1).join('/');
  html=await phpInlineAssets(html,curDir);
  fr.srcdoc=html+PHP_BRIDGE;
}
window.addEventListener('message', async ev=>{ const d=ev.data; if(!d||d.type!=='phpnav') return;
  let u=String(d.url||''); if(!u){ u=phpPrevUrl||'/'; }
  if(!u.startsWith('/')){ const base=(phpPrevUrl||'/').split('/').slice(0,-1).join('/'); u=base+'/'+u; }
  setWorking(true); try{ await phpPreview(u, d.method||'GET', d.body); } finally{ setWorking(false); } });
```

- [ ] **Step 2: Show the «🌐 Ver» button for `.php`**

At line ~978, change:

```js
  document.getElementById('edhtml').classList.toggle('hidden', !/\.(html?|svg)$/i.test(path));   // rendered view for .html/.svg
```

to:

```js
  document.getElementById('edhtml').classList.toggle('hidden', !/\.(html?|svg|php)$/i.test(path));   // rendered view for .html/.svg/.php
```

- [ ] **Step 3: Route `.php` through `phpPreview` in `toggleHtmlView`**

Replace the `if` branch of `toggleHtmlView` (line ~990):

```js
  if(fr.classList.contains('hidden')){ fr.srcdoc=ta.value; fr.classList.remove('hidden'); ta.classList.add('hidden'); b.textContent='✎ Editar'; }
```

with:

```js
  if(fr.classList.contains('hidden')){
    if(/\.php$/i.test(edCur||'')){ fsPut(edCur, ta.value).then(()=>{ refreshDisk(); phpCookies={}; return phpPreview('/'+edCur); });   // save buffer first; fresh cookie jar per preview session
      fr.srcdoc='<p style="font-family:sans-serif;color:#888;padding:1em">🐘 PHP…</p>'; }
    else fr.srcdoc=ta.value;
    fr.classList.remove('hidden'); ta.classList.add('hidden'); b.textContent='✎ Editar'; }
```

- [ ] **Step 4: Verify NUL bytes**

Run: `tr -dc '\0' < docs/index.html | wc -c` → `2`

- [ ] **Step 5: Manual verification — full navigation demo**

In the app, create these files (disk UI or console `fsPut`):

`index.php`:
```php
<?php include 'header.php'; session_start(); $_SESSION['n']=($_SESSION['n']??0)+1; ?>
<p>Visitas: <?php echo $_SESSION['n']; ?></p>
<a href="page2.php?x=hola">Ir a page2</a>
```

`header.php`:
```php
<h1>Demo PHP</h1>
```

`page2.php`:
```php
<?php session_start(); ?>
<p>GET x = <?php echo htmlspecialchars($_GET['x'] ?? '(nada)'); ?></p>
<form method="post" action="page2.php">
  <input name="nombre" placeholder="nombre"><button>Enviar</button>
</form>
<?php if($_SERVER['REQUEST_METHOD']==='POST'){ echo '<p>POST nombre = '.htmlspecialchars($_POST['nombre']??'').'</p>'; file_put_contents('out.txt','escrito por PHP'); } ?>
<a href="index.php">Volver</a>
```

Checklist — open `index.php`, click «🌐 Ver»:
1. Renders `Demo PHP` heading (include works) + visit counter.
2. Click `Ir a page2` → page2 renders, `GET x = hola`.
3. Type a name, submit → `POST nombre = <name>` shown.
4. `out.txt` appears in the virtual disk panel (mirror out works).
5. Click `Volver` → counter incremented (session persisted across navigations).
6. Break `index.php` (call `nope();`), re-preview → readable fatal error in the iframe.

- [ ] **Step 6: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): PHP web preview — forms, navigation, sessions via postMessage bridge"
```

---

### Task 3: Shell command, /php slash command, agent tool

**Files:**
- Modify: `docs/index.html` lines ~270, ~378, ~1287, ~1354, ~1424, ~1487, ~1786, ~1959, ~2021

- [ ] **Step 1: `SHELL_CMDS`** (line ~270) — add `'php'` to the set, e.g. after `'py'`:

```js
...,'python','python3','py','php','curl','wget',...
```

- [ ] **Step 2: `shRun` case** — insert right after the `case 'python': ...` line (~378):

```js
    case 'php': { if(!a0[0]){SH_EXIT=1;return T('uso: php <fichero.php> | php -r <código>','usage: php <file.php> | php -r <code>');}
      if(a0[0]==='-r'){ return await runPhpCode(a0.slice(1).join(' ')); }
      const p=shResolve(a0[0]); const f=await fsGet(p); if(!f){SH_EXIT=1;return 'php: '+T('no existe ','no such file ')+a0[0];} return await runPhp(p); }
```

- [ ] **Step 3: `TOOLS` entry** — insert after the `cc` tool entry (~line 1288):

```js
 {type:'function',function:{name:'php',description:'Run real PHP 8 (@php-wasm/WASM). Pass path to a .php file on the virtual disk (document root /disk, includes work) OR inline code. Returns stdout (HTML/text).',parameters:{type:'object',properties:{path:{type:'string',description:'.php file to run'},code:{type:'string',description:'inline PHP code (alternative to path)'}}}}}
```

(Mind the comma after the `cc` entry.)

- [ ] **Step 4: `execToolRaw` handler** — insert after the `if(name==='cc')` line (~1355):

```js
  if(name==='php'){ const out=args.path? await runPhp(shResolve(args.path)) : await runPhpCode(args.code||''); termLine('php '+(args.path||'‹code›'), out, SHCWD); return out; }
```

- [ ] **Step 5: tool descriptions** (line ~1424) — add `php:'Ejecuta PHP'` next to `cc:'Compila C'`.

- [ ] **Step 6: `toolMeta`** (line ~1487) — add to the map next to `cc:`:

```js
php:{v:'PHP',i:IC_TERM,a:'path'}
```

- [ ] **Step 7: `toolSafety`** (line ~2021) — add `'php'` to the warn array:

```js
function toolSafety(name){ return ['write_file','delete_file','git','dispatch_agents','shell','python','cc','php'].includes(name)?'warn':'safe'; }
```

- [ ] **Step 8: `slashCmd` case** — insert after the `case '/py': ...` line (~1786):

```js
    case '/php': { setWorking(true); let out; const a=arg.trim();
      if(/^[\w./-]+\.php$/.test(a)) out=await runPhp(shResolve(a)); else out=await runPhpCode(arg);
      setWorking(false); termLine('php '+(/\.php$/.test(a)?a:'‹code›'), out, SHCWD); break; }
```

- [ ] **Step 9: cmds list** (line ~1959) — after `['/cc','C con clang (WASM)']` add:

```js
['/php','PHP 8 (@php-wasm/WASM)'],
```

- [ ] **Step 10: Verify NUL bytes** — `tr -dc '\0' < docs/index.html | wc -c` → `2`

- [ ] **Step 11: Manual verification**

1. Shell (`/sh`): `php index.php` → prints HTML source. `php -r echo 40+2;` → `42`. `php nope.php` → `php: no existe nope.php`.
2. Slash: `/php echo PHP_VERSION;` → `8.3.x`. `/php index.php` → HTML.
3. Agent: prompt «ejecuta index.php con php y dime qué devuelve» → agent calls the `php` tool, action row shows `PHP`, permission prompt appears (warn).

- [ ] **Step 12: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): php shell command, /php slash command and agent tool"
```

---

### Task 4: Cache-bust marker, changelog, roadmap

**Files:**
- Modify: `docs/index.html` line ~34 (`var BUILD='u40'`), `docs/version.txt`, `docs/changelog.md`

- [ ] **Step 1: Bump build marker**

In `docs/index.html` line ~34: `var BUILD='u40'` → next value (`u41`, or whatever is current at implementation time). Write the same value to `docs/version.txt`.

- [ ] **Step 2: Changelog entry**

Prepend to `docs/changelog.md` following its existing format: PHP execution — web preview with forms/navigation/sessions (@php-wasm), `php` shell command, `/php`, agent tool.

- [ ] **Step 3: Final full pass**

Re-run the Task 2 Step 5 checklist end-to-end on a hard-reloaded page (DevTools → empty cache). Confirm `tr -dc '\0' < docs/index.html | wc -c` → `2`.

- [ ] **Step 4: Commit**

```bash
git add docs/index.html docs/version.txt docs/changelog.md
git commit -m "chore(web): bump build marker + changelog for PHP execution"
```

---

## Out of scope (spec)

Service-Worker serving, JS fetch/XHR to `.php` endpoints from previewed pages, `multipart/form-data` file uploads, php.ini UI, Composer, extra extensions.
