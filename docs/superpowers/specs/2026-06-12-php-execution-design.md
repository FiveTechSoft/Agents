# PHP Execution in Web Agents — Design Spec

**Date:** 2026-06-12
**Status:** approved
**Author:** Antonio Linares + Claude

## Overview

Add PHP execution to the web agents app (`docs/index.html`). Scope: **web preview with forms and navigation** — a `.php` file in the virtual disk renders as a served web page in the editor's preview iframe, with working links between `.php` pages (`$_GET`), form submissions (`$_POST`), and sessions (`$_SESSION`). Bonus: a `php` shell command and agent tool for CLI-style execution.

Runtime: **`@php-wasm/web` + `@php-wasm/universal`** (WordPress Playground packages), loaded lazily from jsdelivr. Chosen over `php-cgi-wasm` (Service Worker conflict with `coi-serviceworker.min.js` — one SW per scope) and over hand-rolling superglobals on seanmorris `php-wasm` (its `PHPRequestHandler` already implements full HTTP request semantics: `$_GET`, `$_POST`, `$_SERVER`, cookies, sessions, redirects).

## Architecture

```
┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐
│ Editor 🌐 Ver │  │ Shell        │  │ Agent tool: php     │
│ on .php file │  │ php file.php │  │ (like python tool)  │
└──────┬───────┘  └──────┬───────┘  └──────────┬──────────┘
       │                 │                     │
       ▼                 └──────────┬──────────┘
┌───────────────────┐               ▼
│ phpPreview(path)  │     ┌──────────────────┐
│ request loop +    │     │ runPhp(file|code)│
│ bridge messages   │     │ stdout as text   │
└──────┬────────────┘     └────────┬─────────┘
       │                           │
       └─────────────┬─────────────┘
                     ▼
       ┌─────────────────────────────────┐
       │ ensurePhp() — lazy singleton    │
       │ PHP instance + PHPRequestHandler│
       │ documentRoot /disk              │
       ├─────────────────────────────────┤
       │ phpMirrorIn() / phpMirrorOut()  │
       │ IndexedDB ⇄ Emscripten FS       │
       └─────────────────────────────────┘
```

### ensurePhp()

Lazy singleton, same pattern as `ensurePy()`:

```js
const web = await import('https://cdn.jsdelivr.net/npm/@php-wasm/web/+esm');
const uni = await import('https://cdn.jsdelivr.net/npm/@php-wasm/universal/+esm');
const php = new uni.PHP(await web.loadWebRuntime('8.3'));
const handler = new uni.PHPRequestHandler({ phpFactory: async () => php, documentRoot: '/disk' });
```

- Shows `tool('🐘 Cargando PHP (~10MB, primera vez)…')` during first load.
- Single PHP instance kept alive for the whole session → `$_SESSION` files persist between requests.
- **Known risk:** the jsdelivr `/+esm` bundle may break relative `.wasm`/asset resolution inside `loadWebRuntime`. Fallback: import version-pinned files directly (e.g. `@php-wasm/web@3.1.38/index.js`) or pass an explicit asset/wasm URL if the API allows. Resolved during implementation.

### phpMirrorIn() / phpMirrorOut()

Same logic as `pyMirrorIn`/`pyMirrorOut` (index.html:579): walk the virtual disk (`fsList()`), `mkdir -p` + write each file into PHP's Emscripten FS under `/disk`; ` B64 `-prefixed content decoded to raw bytes. After execution, walk `/disk` back, UTF-8 heuristic (`isUtf8Text`) decides text vs ` B64 ` base64, `fsPut` each file, `refreshDisk()`. Real directories in the FS → `include`/`require` with relative and subdirectory paths work.

`phpMirrorOut` runs after every request so PHP writes (SQLite files, uploads, generated files) land back in the virtual disk.

## Request flow (preview)

1. User opens a `.php` file in the editor → «🌐 Ver» button (extend regex at index.html:978 from `\.(html?|svg)$` to include `php`). Click → `phpPreview(path)`.
2. `phpPreview`: `ensurePhp()` → `phpMirrorIn()` → `handler.request({ url: '/' + path, method: 'GET' })` → HTML response.
3. **Post-processing before `srcdoc`:**
   - **Bridge script** injected (appended to the HTML): captures clicks on relative `<a href>` and `<form>` submits, serializes method + URL + form body, calls `parent.postMessage({ type: 'phpnav', url, method, body }, '*')`, `preventDefault()`. Works under the current sandbox `allow-scripts allow-modals allow-forms allow-popups` (opaque origin can still postMessage to parent).
   - **Static assets**: `srcdoc` has no server to fetch from. Rewrite relative `src=`/`href=` attributes pointing at files that exist in the virtual disk into `data:` URIs (binary files already stored as base64). Documented limitation: assets requested dynamically from JS are not resolved.
4. Parent `message` listener: on `phpnav`, run `handler.request({ url, method, body })`, post-process, replace `srcdoc`. Each navigation = one PHP request, GET or POST.
5. **Redirects:** if the handler does not auto-follow, loop on 3xx with a local `Location` header, max 5 hops.
6. **Cookies:** `PHPRequestHandler` manages them; if the bundled version does not, keep a simple JS cookie jar (store `Set-Cookie` from responses, send back on subsequent requests).
7. `phpMirrorOut()` after each request.

## Shell command + agent tool

- `shRun` gains case `php`:
  - `php fichero.php` → mirror in → `php.runStream({ scriptPath: '/disk/<resolved>' })` → stdout text to terminal → mirror out.
  - `php -r 'código'` → inline snippet (write temp file or `runStream` with code).
- New agent tool `php` registered like the existing `python` tool: takes file path or inline code, returns stdout. `toolMeta` entry + system-prompt tool list.
- `/php` entry added to the `cmds` slash-command list (index.html:1959).

## Error handling

- CDN/load failure → return `'PHP no disponible: ' + e` (same pattern as `runPython`).
- PHP fatal errors / parse errors: `display_errors=On` (dev mode); the error output is the response body, shown in the iframe (wrapped in `<pre>` if the response is not HTML). In shell/tool: raw text.
- Missing file → usage message, same style as `cc`.
- Redirect loop → stop at 5 hops, show last response plus a note.

## Testing

Manual checklist with a demo placed in the virtual disk:

1. `index.php` — `include 'header.php';`, prints a variable, link `<a href="page2.php?x=1">`.
2. `page2.php` — reads `$_GET['x']`, has a `<form method="post" action="page2.php">`.
3. POST submit → `$_POST` value rendered.
4. `$_SESSION` counter incremented on each visit → persists across navigations.
5. `file_put_contents('out.txt', …)` → file appears in the virtual disk after the request (mirror out).
6. Shell: `php index.php` prints HTML source to terminal.
7. Fatal error (`undefined_function()`) → readable error in preview and in shell.

## Out of scope (this iteration)

- Service-Worker-based serving (real URLs in iframe).
- JS-initiated fetch/XHR from the previewed page to `.php` endpoints.
- File uploads (`multipart/form-data` with files).
- php.ini configuration UI, Composer, extensions beyond the defaults.
