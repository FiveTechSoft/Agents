# Virtual Database Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a virtual database engine to the web agents — multiple `.db` files in the virtual disk powered by Python `sqlite3` via Pyodide, accessible from agent tool, shell, and a visual DB viewer panel.

**Architecture:** Single JavaScript function `pyDbExec(path, sql)` handles all DB operations (Pyodide sqlite3 in `:memory:` with dump/restore to IndexedDB). Agent tool `sql` and shell command `sql` both call it. `.db` files click opens a phpMyAdmin-like viewer in the existing editor modal. `.db` files stored as SQL text — portable natively.

**Tech Stack:** Vanilla JS, Pyodide (already loaded), Python sqlite3 (built into Pyodide). Zero new dependencies. Single file changed: `docs/index.html`.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `docs/index.html` | All changes: DB engine, agent tool, shell command, viewer UI |

---

### Task 1: Add DB engine core (`pyDbExec`) and shell `sql` command

**Files:**
- Modify: `docs/index.html` — add new functions after `runPython()` block (~line 511), add `sql` to `SHELL_CMDS` set, add parser in `shRun`

- [ ] **Step 1: Add `pyDbExec()` function after `runPython()` block (after line 511)**

Insert after the closing `}` of `runPython()`:

```javascript
/* =====================================================================
   Virtual Database Engine — Python sqlite3 via Pyodide.
   Each .db file is stored as SQL text (sqlite3 dump) in IndexedDB.
   Read: load dump into :memory: DB → execute query → return rows.
   Write: execute DDL/DML → iter dump → save back to IndexedDB.
   ===================================================================== */
async function pyDbExec(path, sql){
  try { await ensurePy(); } catch(e) { return 'SQL Error: Python (Pyodide) no disponible: '+e; }
  const f = await fsGet(path);
  const py = pyodide;

  // Pass data safely via pyodide globals (no string escaping issues)
  const dump = (f && f.content) ? (f.content.startsWith(' B64 ') ? atob(f.content.slice(5)) : f.content) : '';
  py.globals.set('_db_dump', dump);
  py.globals.set('_db_sql', sql);
  py.globals.set('_db_is_write', /^\s*(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|PRAGMA)/i.test(sql.trim()));

  const script = `import sqlite3, json
_conn = sqlite3.connect(':memory:')
_error = None
if _db_dump:
    try:
        _conn.executescript(_db_dump)
    except Exception as e:
        _error = str(e)
try:
    _cur = _conn.execute(_db_sql)
    _rows = _cur.fetchall()
    _cols = [d[0] for d in _cur.description] if _cur.description else []
    _changes = _conn.changes()
    _dump = '\\n'.join([l for l in _conn.iterdump()]) if _db_is_write else None
except Exception as e:
    _error = str(e)
    _rows = []; _cols = []; _changes = 0; _dump = None
_ok = _error is None
json.dumps({'ok':_ok,'cols':_cols,'rows':_rows,'changes':_changes,'dump':_dump,'error':_error})`;

  let raw;
  try {
    raw = await py.runPythonAsync(script);
  } catch(e) {
    return 'SQL Error: ' + (e.message || e);
  }
  const result = JSON.parse(raw);

  if (!result.ok) {
    return 'SQL Error: ' + (result.error || 'unknown error');
  }

  // Save dump back to disk on write
  if (py.globals.get('_db_is_write') && result.dump !== null && result.dump !== undefined) {
    await fsPut(path, result.dump);
    refreshDisk();
  }

  return { columns: result.cols, rows: result.rows, changes: result.changes };
}
```

- [ ] **Step 2: Add `sql` to `SHELL_CMDS` set (line 213)**

Change:
```javascript
const SHELL_CMDS=new Set(['ls','cat',...]);
```
Add `'sql'` to the set — insert alphabetically after `'sort'` and before `'uniq'`.

Exact edit: change `'sort','uniq'` to `'sort','sql','uniq'` in the SHELL_CMDS initializer on line 213.

- [ ] **Step 3: Add `sql` command parser in `shRun()`**

In `shRun()`, find the block of command parsers (after `ls`, `cat`, etc.). Add before the `else { return cmd+' no encontrado' }` fallback:

```javascript
else if(cmd === 'sql'){
  // sql <archivo.db> <SQL query>
  const m = args.match(/^(\S+\.db)\s+(.+)$/i);
  if (!m) return 'sql archivo.db <SQL>\nEj: sql clientes.db SELECT * FROM customers';
  const dbPath = shResolve(m[1]);
  const query = m[2];
  const result = await pyDbExec(dbPath, query);
  if (typeof result === 'string') return result;  // error message
  if (!result.columns || !result.columns.length) {
    return result.changes > 0 ? result.changes + ' rows affected' : '(ok)';
  }
  // ASCII table format
  return shFormatTable(result.columns, result.rows);
}
```

- [ ] **Step 4: Add `shFormatTable()` helper function**

Insert near other shell helpers:

```javascript
function shFormatTable(cols, rows){
  if (!rows.length) return '(empty)\n0 rows';
  // Calculate column widths
  const widths = cols.map((c, i) => {
    let w = String(c).length;
    rows.forEach(r => { const v = r[i]; const s = v === null ? 'NULL' : String(v); if (s.length > w) w = s.length; });
    return w;
  });
  const sep = '─'.repeat(widths.reduce((a,b)=>a+b+3, 1));
  let out = '┌' + sep + '┐\n';
  out += '│ ' + cols.map((c,i) => String(c).padEnd(widths[i])).join(' │ ') + ' │\n';
  out += '├' + sep + '┤\n';
  for (const r of rows) {
    out += '│ ' + r.map((v, i) => {
      const s = v === null ? 'NULL' : String(v);
      return s.padEnd(widths[i]);
    }).join(' │ ') + ' │\n';
  }
  out += '└' + sep + '┘\n';
  out += rows.length + ' rows';
  return out;
}
```

- [ ] **Step 5: Verify shell `sql` command**

Open `docs/index.html` in browser. In the prompt type:
```
/sh sql inventario.db CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER)
/sh sql inventario.db INSERT INTO products VALUES (1, 'Widget', 42)
/sh sql inventario.db INSERT INTO products VALUES (2, 'Gadget', 17)
/sh sql inventario.db SELECT * FROM products
```
Expected: ASCII table with 3 columns and 2 rows.

- [ ] **Step 6: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): add virtual DB engine (pyDbExec) + shell sql command

pyDbExec uses Python sqlite3 via Pyodide to execute SQL on .db files
stored as SQL dumps in IndexedDB. Shell /sh sql <file.db> <query>
prints results as ASCII table. Writes auto-save via iter dump.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Add agent `sql` tool

**Files:**
- Modify: `docs/index.html` — `TOOLS` array (~line 889), `execToolRaw()` (~line 954)

- [ ] **Step 1: Add `sql` tool to `TOOLS` array (after `shell` tool, line 899)**

Insert after the `shell` tool entry (line 899):

```javascript
 {type:'function',function:{name:'sql',description:'Execute a SQL query on a .db virtual database file (SQLite via sqlite3). Use for SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, DROP, ALTER. If the .db file does not exist, it is created automatically on CREATE TABLE. Returns rows as JSON with columns, rows, and changes count.',parameters:{type:'object',properties:{db:{type:'string',description:'Path to the .db file, e.g. "clientes.db" or "data/clientes.db"'},query:{type:'string',description:'SQL query to execute'}},required:['db','query']}}},
```

- [ ] **Step 2: Add `sql` case in `execToolRaw()` (after `cc` case, line 969)**

Insert after line 969 (`if(name==='cc'){...}`):

```javascript
  if(name==='sql'){ const result = await pyDbExec(shResolve(args.db), args.query);
    return typeof result === 'string' ? result : JSON.stringify(result, null, 2); }
```

- [ ] **Step 3: Add `sql` to `SUBTOOLS` filter (line 904)**

The `sql` tool should be available to sub-agents. Since it's not in the exclusion list on line 904, it's already included. No change needed. Verify: the filter excludes `dispatch_agents`, `ask_user`, `git` — `sql` is not excluded → sub-agents can use it.

- [ ] **Step 4: Verify agent tool**

Open `docs/index.html` in browser. Type:
```
crea una base de datos clientes.db con una tabla customers con columnas id, name, city. Inserta 3 registros de prueba. Luego haz un SELECT de todos.
```
Expected: agent calls `sql` tool, creates table, inserts data, selects. File `clientes.db` appears in disk sidebar.

- [ ] **Step 5: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): add sql agent tool for .db virtual databases

Agent can now call sql(db, query) to execute SQL on .db files stored
in the virtual disk. Uses pyDbExec → Python sqlite3 via Pyodide.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Add DB viewer (phpMyAdmin-like panel) when clicking `.db` files

**Files:**
- Modify: `docs/index.html` — add viewer HTML to `#ed` modal, add viewer JS functions, modify `openEd()` routing

- [ ] **Step 1: Add DB viewer panel to editor modal HTML (after `#edhtmlframe`, line 127)**

Insert after `</iframe>` on line 127, before `</div>` on line 128:

```html
        <div id="eddbviewer" class="hidden flex-1 flex flex-col overflow-hidden">
          <div class="flex-1 flex overflow-hidden">
            <div id="dbv-tables" class="w-44 shrink-0 border-r border-gray-700 overflow-y-auto p-2 space-y-1 bg-gray-850">
              <div class="text-[10px] text-gray-500 uppercase tracking-wide px-2 mb-1">Tablas</div>
            </div>
            <div class="flex-1 flex flex-col overflow-hidden">
              <div class="flex items-center justify-between px-3 py-1 border-b border-gray-800">
                <span id="dbv-info" class="text-xs text-gray-400"></span>
                <div class="flex items-center gap-1">
                  <button id="dbv-prev" onclick="dbvPage(-1)" class="px-2 py-0.5 bg-gray-700 rounded text-xs hover:bg-gray-600 hidden">←</button>
                  <span id="dbv-pageinfo" class="text-[10px] text-gray-500 hidden"></span>
                  <button id="dbv-next" onclick="dbvPage(1)" class="px-2 py-0.5 bg-gray-700 rounded text-xs hover:bg-gray-600 hidden">→</button>
                </div>
              </div>
              <div id="dbv-rows" class="flex-1 overflow-auto p-2">
                <div class="text-xs text-gray-500 p-4 text-center">Selecciona una tabla para ver los datos</div>
              </div>
            </div>
          </div>
          <div class="border-t border-gray-700">
            <div id="dbv-sql-toggle" onclick="toggleDbvSql()" class="text-xs text-gray-500 px-3 py-1.5 cursor-pointer hover:text-gray-300 select-none border-b border-gray-800">▸ SQL</div>
            <div id="dbv-sql-panel" class="hidden p-2 space-y-2">
              <textarea id="dbv-sql-input" rows="3" class="w-full bg-gray-900 border border-gray-700 rounded p-2 text-xs text-gray-200 font-mono focus:outline-none focus:border-blue-500" placeholder="SELECT * FROM ... WHERE ..."></textarea>
              <div class="flex items-center gap-2">
                <button onclick="dbvRunSql()" class="text-xs bg-blue-700 hover:bg-blue-600 px-3 py-1 rounded">Ejecutar SQL</button>
                <span id="dbv-sql-result" class="text-[10px] text-gray-500"></span>
              </div>
            </div>
          </div>
        </div>
```

- [ ] **Step 2: Add DB viewer state variables and functions (after `pyDbExec`, before `runPython`)**

```javascript
/* ---- DB Viewer state ---- */
let dbvPath = '';
let dbvTable = '';
let dbvPage = 0;
const DBV_PAGE = 100;

async function openDbViewer(path){
  dbvPath = path; dbvTable = ''; dbvPage = 0;
  // Show editor modal with DB viewer content
  document.getElementById('edpath').textContent = '🗄 ' + path;
  document.getElementById('edtext').classList.add('hidden');
  document.getElementById('edpreview').classList.add('hidden');
  document.getElementById('edhtmlframe').classList.add('hidden');
  document.getElementById('edprev').classList.add('hidden');
  document.getElementById('edhtml').classList.add('hidden');
  document.getElementById('eddbviewer').classList.remove('hidden');
  document.getElementById('ed').classList.remove('hidden');
  // Reset
  document.getElementById('dbv-rows').innerHTML = '<div class="text-xs text-gray-500 p-4 text-center">Cargando tablas…</div>';
  document.getElementById('dbv-info').textContent = '';
  document.getElementById('dbv-pageinfo').classList.add('hidden');
  document.getElementById('dbv-prev').classList.add('hidden');
  document.getElementById('dbv-next').classList.add('hidden');
  document.getElementById('dbv-sql-input').value = '';
  document.getElementById('dbv-sql-panel').classList.add('hidden');
  document.getElementById('dbv-sql-toggle').textContent = '▸ SQL';
  
  // Load table list
  const result = await pyDbExec(path, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  const tb = document.getElementById('dbv-tables');
  if (typeof result === 'string' || !result.rows.length) {
    tb.innerHTML = '<div class="text-[10px] text-gray-600 px-2">(sin tablas)</div>';
  } else {
    tb.innerHTML = result.rows.map(r => {
      const t = r[0];
      return `<button onclick="dbvOpenTable('${t.replace(/'/g,"\\'")}')" class="w-full text-left text-xs px-2 py-1 rounded hover:bg-gray-700 text-gray-300">📋 ${t}</button>`;
    }).join('');
  }
}

async function dbvOpenTable(name){
  dbvTable = name; dbvPage = 0;
  await dbvLoadPage();
}

async function dbvLoadPage(){
  const off = dbvPage * DBV_PAGE;
  // Get count
  const cnt = await pyDbExec(dbvPath, `SELECT COUNT(*) FROM "${dbvTable.replace(/"/g,'""')}"`);
  const total = typeof cnt === 'string' ? 0 : cnt.rows[0][0];
  // Get page
  const data = await pyDbExec(dbvPath,
    `SELECT * FROM "${dbvTable.replace(/"/g,'""')}" LIMIT ${DBV_PAGE} OFFSET ${off}`);
  
  const rowsDiv = document.getElementById('dbv-rows');
  if (typeof data === 'string') {
    rowsDiv.innerHTML = `<div class="text-xs text-red-400 p-4">${data}</div>`;
    return;
  }
  if (!data.rows.length) {
    rowsDiv.innerHTML = '<div class="text-xs text-gray-500 p-4 text-center">(tabla vacía)</div>';
  } else {
    const w = data.columns.length;
    rowsDiv.innerHTML = `<table class="w-full text-xs text-gray-300 border-collapse">
      <thead><tr class="sticky top-0 bg-gray-800">${data.columns.map(c => `<th class="px-2 py-1.5 text-left border-b border-gray-700 text-blue-300 font-medium whitespace-nowrap">${c}</th>`).join('')}</tr></thead>
      <tbody>${data.rows.map(r => `<tr class="hover:bg-gray-800/50">${r.map(v => {
        const cls = v === null ? 'text-gray-600' : typeof v === 'number' ? 'text-green-400' : 'text-gray-200';
        const txt = v === null ? 'NULL' : String(v).length > 200 ? String(v).slice(0,200)+'…' : String(v);
        return `<td class="px-2 py-0.5 border-b border-gray-800/50 max-w-[300px] truncate ${cls}">${txt}</td>`;
      }).join('')}</tr>`).join('')}</tbody></table>`;
  }
  document.getElementById('dbv-info').textContent = `${dbvTable} · ${total} rows`;
  // Pagination
  const info = document.getElementById('dbv-pageinfo');
  const prev = document.getElementById('dbv-prev');
  const next = document.getElementById('dbv-next');
  if (total > DBV_PAGE) {
    const end = Math.min((dbvPage+1)*DBV_PAGE, total);
    info.textContent = `${dbvPage*DBV_PAGE+1}-${end} de ${total}`;
    info.classList.remove('hidden');
    prev.classList.remove('hidden');
    next.classList.remove('hidden');
    prev.disabled = dbvPage === 0;
    next.disabled = end >= total;
  } else {
    info.classList.add('hidden');
    prev.classList.add('hidden');
    next.classList.add('hidden');
  }
}

async function dbvPage(dir){
  dbvPage += dir;
  if (dbvPage < 0) dbvPage = 0;
  await dbvLoadPage();
}

function toggleDbvSql(){
  const panel = document.getElementById('dbv-sql-panel');
  const toggle = document.getElementById('dbv-sql-toggle');
  if (panel.classList.contains('hidden')) {
    panel.classList.remove('hidden');
    toggle.textContent = '▾ SQL';
  } else {
    panel.classList.add('hidden');
    toggle.textContent = '▸ SQL';
  }
}

async function dbvRunSql(){
  const input = document.getElementById('dbv-sql-input');
  const resultEl = document.getElementById('dbv-sql-result');
  const sql = input.value.trim();
  if (!sql) return;
  resultEl.textContent = 'Ejecutando…';
  resultEl.className = 'text-[10px] text-gray-400';
  
  const result = await pyDbExec(dbvPath, sql);
  if (typeof result === 'string') {
    resultEl.textContent = result;
    resultEl.className = 'text-[10px] text-red-400';
    return;
  }
  resultEl.textContent = result.changes > 0 ? result.changes + ' rows affected' : (result.rows ? result.rows.length + ' rows' : 'OK');
  resultEl.className = 'text-[10px] text-green-400';
  
  // Refresh table list and current table data
  const tb = document.getElementById('dbv-tables');
  const tableResult = await pyDbExec(dbvPath, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  if (typeof tableResult !== 'string') {
    tb.innerHTML = tableResult.rows.length
      ? tableResult.rows.map(r => `<button onclick="dbvOpenTable('${r[0].replace(/'/g,"\\'")}')" class="w-full text-left text-xs px-2 py-1 rounded hover:bg-gray-700 text-gray-300">📋 ${r[0]}</button>`).join('')
      : '<div class="text-[10px] text-gray-600 px-2">(sin tablas)</div>';
  }
  if (dbvTable) await dbvLoadPage();
}
```

- [ ] **Step 3: Modify `openEd()` to route `.db` files to DB viewer (line 591)**

Change the beginning of `openEd()` (line 591):

```javascript
async function openEd(path){
  if (/\.db$/i.test(path)) { await openDbViewer(path); return; }
  const f = await fsGet(path); edCur = path;
```

- [ ] **Step 4: Modify `closeEd()` to also hide DB viewer (line 599)**

Change `closeEd()` to also clean up the DB viewer:

```javascript
function closeEd(){
  document.getElementById('ed').classList.add('hidden');
  document.getElementById('eddbviewer').classList.add('hidden');
  const fr = document.getElementById('edhtmlframe'); if(fr) fr.srcdoc='';
}
```

- [ ] **Step 5: Update `downloadFile()` MIME for `.db` extension (line 177)**

Add `db:'application/sql'` to the MIME map on line 177:

Change:
```javascript
const MIME={pdf:'application/pdf',png:'image/png',...};
```
Add `db:'application/sql',` — insert alphabetically after `csv:'text/csv',`.

- [ ] **Step 6: Verify DB viewer**

Open `docs/index.html`. Create a `.db` file with some tables (via `/sh sql`). Click on the `.db` file in the disk sidebar.

Expected:
- Editor modal opens showing 🗄 filename
- Left sidebar lists tables (📋 icon)
- Click a table → shows paginated data table
- SQL panel at bottom (collapsed) → type a query → execute → result shown, table refreshes
- Close button works
- Download button (↓) on the file row downloads as `.sql`

- [ ] **Step 7: Commit**

```bash
git add docs/index.html
git commit -m "feat(web): add DB viewer panel for .db files

Clicking a .db file opens a phpMyAdmin-like viewer: table list
sidebar, paginated data grid, collapsible SQL editor. .db files
route through openDbViewer() instead of text editor.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: End-to-end verification

**Files:**
- None (verification only)

- [ ] **Step 1: Full flow test — agent creates and queries a DB**

Open `docs/index.html` in browser. Type:
```
Crea una base de datos tienda.db con tablas products (id, name, price) y orders (id, product_id, qty, date). Inserta 5 productos y 3 orders. Luego haz un JOIN que muestre orders con el nombre del producto.
```

Expected:
- `tienda.db` appears in disk sidebar
- Agent creates tables, inserts data
- JOIN query returns results
- Click on `tienda.db` → viewer shows 2 tables
- Click each table → data visible
- `/sh sql tienda.db SELECT * FROM products` → ASCII table

- [ ] **Step 2: Test download/export**

Click ↓ on `tienda.db` in disk sidebar → downloads as SQL text.
Open downloaded file → should be valid SQL with CREATE TABLE + INSERT statements.

- [ ] **Step 3: Test multiple DBs**

```
/sh sql clientes.db CREATE TABLE customers (id INTEGER, name TEXT)
/sh sql inventario.db CREATE TABLE stock (id INTEGER, item TEXT)
```
Expected: both `.db` files appear in disk, each independent.

- [ ] **Step 4: Test error handling**

```
/sh sql clientes.db SELECT * FROM nonexistent
```
Expected: `SQL Error: no such table: nonexistent` (or similar).

- [ ] **Step 5: Commit verification notes**

```bash
git add docs/index.html
git commit -m "chore(web): verified virtual DB engine end-to-end

All paths tested: agent sql tool, shell /sh sql, DB viewer,
multiple .db files, export/download, error handling.

Co-Authored-By: Claude <noreply@anthropic.com>"
```
