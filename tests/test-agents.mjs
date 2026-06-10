// usage: node test-agents.mjs [chromium|firefox|webkit] [url]
import { chromium, firefox, webkit } from 'playwright';

const ENGINE = { chromium, firefox, webkit }[process.argv[2] || 'chromium'] || chromium;
const URL = process.argv[3] || process.env.AGENTS_URL || 'https://fivetechsoft.github.io/Agents/';
console.log(`engine=${process.argv[2] || 'chromium'} url=${URL}`);
const results = [];
const consoleErrors = [];
const pageErrors = [];
const ok = (name, detail = '') => results.push({ pass: true, name, detail });
const ko = (name, detail = '') => results.push({ pass: false, name, detail });

const browser = await ENGINE.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await ctx.newPage();
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text() + ' @ ' + (m.location().url || '')); });
page.on('pageerror', e => pageErrors.push(String(e)));
page.on('dialog', d => d.dismiss().catch(() => {}));

// ---------- helpers ----------
async function waitStable() {
  // the coi service worker may reload the page once on first visit
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForSelector('#prompt', { timeout: 15000 });
  await page.waitForTimeout(1500);
}
async function send(text) {
  await page.fill('#prompt', text);
  await page.press('#prompt', 'Enter');
}
async function sh(cmd, timeout = 10000) {
  const before = await page.locator('#chat .font-mono').count();
  await send(cmd);
  await page.waitForFunction(
    n => document.querySelectorAll('#chat .font-mono').length > n,
    before, { timeout }
  );
  const block = page.locator('#chat .font-mono').last();
  const out = block.locator('div.whitespace-pre-wrap');
  return (await out.count()) ? ((await out.innerText()) || '').trim() : '';
}
async function card(cmd, marker) {
  await send(cmd);
  try {
    await page.waitForFunction(
      m => document.getElementById('chat').innerText.toLowerCase().includes(m.toLowerCase()),
      marker, { timeout: 8000 }
    );
    ok(`${cmd} muestra card`, `"${marker}" presente`);
  } catch {
    ko(`${cmd} muestra card`, `"${marker}" NO apareció en el chat`);
  }
}

// ---------- 1. fresh load, console errors ----------
await page.goto(URL, { waitUntil: 'domcontentloaded' });
await waitStable();
const title = await page.title();
if (title.includes('Agents')) ok('Carga inicial', `title="${title}"`);
else ko('Carga inicial', `title="${title}"`);
const iso = await page.evaluate(() => self.crossOriginIsolated);
ok('crossOriginIsolated (coi-sw)', String(iso));

// clean slate: wipe the virtual disk + session so tests are deterministic
await page.evaluate(async () => {
  localStorage.clear();
  const dbs = await indexedDB.databases();
  await Promise.all(dbs.map(d => new Promise(r => { const q = indexedDB.deleteDatabase(d.name); q.onsuccess = q.onerror = q.onblocked = r; })));
});
await page.reload({ waitUntil: 'domcontentloaded' });
await waitStable();

// ---------- 2. shell ----------
try {
  const t = {};
  t.ls0 = await sh('ls');
  t.pwd = await sh('pwd');
  t.pwd === '/' ? ok('pwd', '/') : ko('pwd', JSON.stringify(t.pwd));
  await sh('mkdir src');
  t.ls1 = await sh('ls');
  t.ls1.includes('src/') ? ok('mkdir src + ls', t.ls1) : ko('mkdir src + ls', t.ls1);
  await sh('echo "hola mundo" > src/a.txt');
  t.cat = await sh('cat src/a.txt');
  t.cat === 'hola mundo' ? ok('echo > fichero / cat', t.cat) : ko('echo > fichero / cat', JSON.stringify(t.cat));
  t.q = await sh('echo "a > b"');
  t.q === 'a > b' ? ok('echo "a > b" (no redirige dentro de comillas)', t.q) : ko('echo "a > b"', JSON.stringify(t.q));
  t.wc = await sh('grep hola src/a.txt | wc');
  /^1\s+2\s+10$/.test(t.wc) ? ok('grep | wc', t.wc) : ko('grep | wc', JSON.stringify(t.wc));
  t.app = await sh('echo extra >> src/a.txt && cat src/a.txt');
  t.app === 'hola mundo\nextra' ? ok('>> append && cat', t.app.replace('\n', '\\n')) : ko('>> append && cat', JSON.stringify(t.app));
  // append to a file that already ends in \n must not produce a blank line
  await sh('printf "uno\\n" > src/nl.txt');
  t.app2 = await sh('echo dos >> src/nl.txt && cat src/nl.txt');
  !t.app2.includes('\n\n') && t.app2.includes('uno') && t.app2.includes('dos')
    ? ok('>> sin línea en blanco extra (fichero acaba en \\n)', JSON.stringify(t.app2))
    : ko('>> sin línea en blanco extra', JSON.stringify(t.app2));
  // diff command
  await sh('printf "a\\nb\\n" > src/f1.txt');
  await sh('printf "a\\nc\\n" > src/f2.txt');
  t.diff = await sh('diff src/f1.txt src/f2.txt');
  t.diff.includes('< b') && t.diff.includes('> c')
    ? ok('diff f1 f2', t.diff.replace(/\n/g, ' | '))
    : ko('diff f1 f2', JSON.stringify(t.diff));
  t.diffSame = await sh('diff src/f1.txt src/f1.txt && echo IGUALES');
  t.diffSame.includes('IGUALES') ? ok('diff iguales → exit 0', t.diffSame) : ko('diff iguales → exit 0', JSON.stringify(t.diffSame));
  // redirect target with a loop variable must expand ($i)
  await sh('for i in $(seq 1 3); do echo "v$i" > src/var$i.txt; done');
  t.loop = await sh('cat src/var1.txt src/var2.txt src/var3.txt');
  t.loop === 'v1\nv2\nv3' ? ok('bucle for + redirect con $i', t.loop.replace(/\n/g, '|')) : ko('bucle for + redirect con $i', JSON.stringify(t.loop));
} catch (e) { ko('Shell (excepción)', String(e)); }

// ---------- 3. disk panel via real UI ----------
try {
  await page.fill('#newpath', 'ruta/archivo.txt');
  await page.click('button:text-is("+")');
  await page.waitForSelector('#ed:not(.hidden)', { timeout: 5000 });
  const edpath = await page.textContent('#edpath');
  edpath === 'ruta/archivo.txt' ? ok('Panel: crear fichero abre editor', edpath) : ko('Panel: crear fichero abre editor', edpath);
  await page.fill('#edtext', 'contenido de prueba');
  await page.click('button:text-is("Guardar")');
  await page.waitForSelector('#ed.hidden', { state: 'attached', timeout: 5000 });
  const saved = await sh('cat ruta/archivo.txt');
  saved === 'contenido de prueba' ? ok('Panel: guardar desde editor', saved) : ko('Panel: guardar desde editor', JSON.stringify(saved));
  // delete via the ✕ button on the file row
  const row = page.locator('#files div.group', { hasText: '📄 archivo.txt' }).first();
  await row.hover();
  await row.locator('button:text-is("✕")').click({ force: true });
  await page.waitForTimeout(800);
  const after = await sh('cat ruta/archivo.txt');
  after.includes('no existe') || after.includes('No such file') ? ok('Panel: borrar con ✕', after) : ko('Panel: borrar con ✕', JSON.stringify(after));
} catch (e) { ko('Panel disco (excepción)', String(e)); }

// ---------- 3b. cc + run wasm binary (heavy: downloads Wasmer/clang) ----------
if (process.env.AGENTS_CC === '1') {
  try {
    await page.evaluate(() => fsPut('hello.c', '#include <stdio.h>\nint main(){ printf("hola wasm 7x10=70\\n"); return 0; }'));
    const c = await sh('cc hello.c -o hola', 180000);
    c.includes('hola wasm') || c.includes('✓') ? ok('cc hello.c -o hola', c.split('\n')[0]) : ko('cc hello.c -o hola', c.slice(0, 150));
    const r = await sh('./hola > out.txt && grep 7x10 out.txt', 60000);
    r.trim() === 'hola wasm 7x10=70' ? ok('./hola > out.txt && grep', r.trim()) : ko('./hola > out.txt && grep', JSON.stringify(r));
  } catch (e) { ko('cc/run wasm (excepción)', String(e).slice(0, 200)); }
}

// ---------- 4. cards ----------
await card('/help', 'Comandos Disponibles');
await card('/cost', 'Métricas de Sesión');
await card('/compact', 'Contexto Compactado');
await card('/goal', 'Objetivo Activo');
await card('/skill', 'Habilidades Activas');
await card('/tool', 'Registro de Herramientas');

// ---------- 5. history: ArrowUp real tras recargar ----------
try {
  await send('echo HIST_MARKER_42');
  await page.waitForTimeout(800);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitStable();
  await page.focus('#prompt');
  await page.press('#prompt', 'ArrowUp');
  const v = await page.inputValue('#prompt');
  v === 'echo HIST_MARKER_42' ? ok('Historial: ↑ tras recargar', v) : ko('Historial: ↑ tras recargar', `valor="${v}"`);
} catch (e) { ko('Historial (excepción)', String(e)); }

// ---------- 5b. shared session link (#s=) ----------
try {
  const enc = await page.evaluate(() => deflateB64(JSON.stringify({
    v: 1, convo: [
      { role: 'user', content: 'hola SHARE_MARKER' },
      { role: 'assistant', content: '**respuesta** compartida <img src=x onerror="window.__xss=1">' }
    ]
  })));
  await page.goto('about:blank');   // hash-only navigation is same-document; force a real load
  await page.goto(URL.replace(/[#?].*$/, '') + '#s=' + enc, { waitUntil: 'domcontentloaded' });
  await waitStable();
  const chatTxt = await page.innerText('#chat');
  chatTxt.includes('hola SHARE_MARKER') && chatTxt.includes('respuesta')
    ? ok('Share: #s= renderiza la sesión', 'mensajes visibles')
    : ko('Share: #s= renderiza la sesión', chatTxt.slice(0, 150));
  /solo lectura|read-only/i.test(chatTxt) ? ok('Share: banner solo-lectura') : ko('Share: banner solo-lectura');
  const xss = await page.evaluate(() => window.__xss);
  !xss ? ok('Share: HTML malicioso sanitizado (DOMPurify)') : ko('Share: HTML malicioso EJECUTADO', '__xss=1');
  await page.evaluate(() => { location.hash = ''; });
} catch (e) { ko('Share (excepción)', String(e).slice(0, 200)); }

// ---------- 5c. share button in the header ----------
try {
  const btn = page.locator('button:text-is("🔗 Share")');
  await btn.isVisible() ? ok('Share: botón en cabecera') : ko('Share: botón en cabecera');
  await btn.click();
  await page.waitForFunction(
    () => /Sesión compartida|Nada que compartir|Shared session|Nothing to share/i.test(document.getElementById('chat').innerText),
    null, { timeout: 8000 }
  );
  ok('Share: click genera enlace o aviso');
} catch (e) { ko('Share: botón cabecera (excepción)', String(e).slice(0, 150)); }

// ---------- 6. markdown preview ----------
try {
  await page.fill('#newpath', 'notas.md');
  await page.click('button:text-is("+")');
  await page.waitForSelector('#ed:not(.hidden)', { timeout: 5000 });
  await page.fill('#edtext', '# Titulo Demo\n\n- punto uno\n- punto dos');
  const prevBtn = page.locator('#edprev');
  await prevBtn.isVisible() ? ok('Preview: botón visible para .md') : ko('Preview: botón visible para .md');
  await prevBtn.click();
  await page.waitForSelector('#edpreview:not(.hidden)', { timeout: 5000 });
  const html = await page.innerHTML('#edpreview');
  html.includes('<h1') && html.includes('<li') ? ok('Preview: markdown renderizado', 'h1 + li presentes') : ko('Preview: markdown renderizado', html.slice(0, 120));
  await page.click('button:text-is("Cerrar")');
} catch (e) { ko('Preview (excepción)', String(e)); }

// ---------- report ----------
console.log('\n================ REPORTE PLAYWRIGHT (black-box) ================');
for (const r of results) console.log(`  [${r.pass ? 'PASS' : 'FAIL'}] ${r.name}${r.detail ? ' — ' + r.detail : ''}`);
const pass = results.filter(r => r.pass).length;
console.log(`\n  Total: ${results.length} | PASS: ${pass} | FAIL: ${results.length - pass}`);
console.log('\n--- Errores de consola (' + consoleErrors.length + ') ---');
consoleErrors.forEach(e => console.log('  ' + e.slice(0, 200)));
console.log('--- Page errors (' + pageErrors.length + ') ---');
pageErrors.forEach(e => console.log('  ' + e.slice(0, 200)));
await browser.close();
