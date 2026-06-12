# Virtual Database Engine — Design Spec

**Date:** 2026-06-12
**Status:** approved
**Author:** Antonio Linares + Claude

## Overview

Add a virtual database engine to the web agents. Multiple `.db` files live in the virtual disk (IndexedDB). Each `.db` is an independent SQLite database. The engine is accessible from: the agent (tool `sql`), the shell (`/sh sql`), and a visual DB viewer panel (type phpMyAdmin, simplified).

## Engine: Python `sqlite3` via Pyodide

Pyodide is already loaded (used by the `python` tool). It includes `sqlite3` built-in. Zero additional bytes to download.

- **Format on disk:** `.db` files are stored as SQL text (the output of `sqlite3 .dump`). Portable — the `.db` file IS a valid `.sql` file.
- **In memory:** a new `sqlite3.connect(':memory:')` database is created, the dump is loaded via `conn.executescript(dump)`, queries are executed, and after any write the full DB is re-dumped and written back to IndexedDB.
- **Multiple DBs:** each `.db` file is independent. Opening `clientes.db` gives one schema; opening `inventario.db` gives another.

## Architecture

```
┌──────────┐  ┌──────────┐  ┌────────────────────┐
│ Agent    │  │ Shell    │  │ DB Viewer (sidebar) │
│ tool:sql │  │ /sh sql  │  │ tables + data + SQL │
└────┬─────┘  └────┬─────┘  └─────────┬──────────┘
     │             │                  │
     └─────────────┼──────────────────┘
                   ▼
     ┌─────────────────────────────┐
     │      pyDbExec(path, sql)    │
     │  - load dump from IndexedDB │
     │  - run in Pyodide sqlite3   │
     │  - write dump back on DDL/DML│
     │  - return {cols, rows, changes}
     └─────────────┬───────────────┘
                   ▼
     ┌─────────────────────────────┐
     │  Pyodide (already loaded)   │
     │  import sqlite3             │
     └─────────────┬───────────────┘
                   ▼
     ┌─────────────────────────────┐
     │  IndexedDB (fsGet / fsPut)  │
     │  .db files as SQL text      │
     └─────────────────────────────┘
```

## Components

### 1. DB Manager (`pyDbExec`)

New JavaScript function `pyDbExec(path, sql)`:
- Ensures Pyodide is initialized (`pyInit()` — already exists).
- Reads the `.db` file from IndexedDB via `fsGet(path)`.
  - If the file exists: extract SQL dump, build Python script that creates `:memory:` DB + `executescript(dump)` + executes the user query.
  - If the file doesn't exist: create empty `:memory:` DB + execute the user query (typically `CREATE TABLE`).
- After INSERT/UPDATE/DELETE/CREATE/DROP/ALTER: runs `conn.iterdump()` and writes the full SQL dump back to IndexedDB via `fsPut()`.
- Returns `{ columns: string[], rows: any[][], changes: number }`.

### 2. Agent Tool (`sql`)

Added to the `TOOLS` array:
```json
{
  "type": "function",
  "function": {
    "name": "sql",
    "description": "Execute a SQL query on a .db virtual database file (SQLite via sqlite3). Use for SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, DROP, ALTER, etc. Returns rows as JSON.",
    "parameters": {
      "type": "object",
      "properties": {
        "db": { "type": "string", "description": "Path to the .db file, e.g. 'clientes.db'" },
        "query": { "type": "string", "description": "SQL query to execute" }
      },
      "required": ["db", "query"]
    }
  }
}
```

Added to `execToolRaw()`:
```javascript
if(name==='sql'){
  try {
    const result = await pyDbExec(shResolve(args.db), args.query);
    return JSON.stringify(result, null, 2);
  } catch(e) {
    return 'SQL Error: ' + e.message;
  }
}
```

### 3. Shell Command (`/sh sql`)

New command in `shRun()`:
- Syntax: `/sh sql <archivo.db> <SQL query>`
- Calls `pyDbExec()` and formats output as an ASCII table.
- Non-SELECT statements print "N rows affected" or similar.

ASCII table format:
```
┌────┬───────────┬──────┐
│ id │ name      │ city │
├────┼───────────┼──────┤
│ 1  │ Acme SA   │ MD   │
│ 2  │ Beta Inc  │ BCN  │
└────┴───────────┴──────┘
3 rows
```

### 4. DB Viewer (phpMyAdmin-like panel)

Opened when the user clicks a `.db` file in the disk sidebar (instead of the text editor).

**Layout:**
- **Header:** 🗄 filename + ⬇ Export .sql button + ✕ Close
- **Left sidebar:** list of tables (📋 icon each). Click loads table data.
- **Main panel:** data table with column headers, paginated (100 rows/page), NULL shown in dim gray, numbers in green.
- **Bottom panel:** collapsible SQL editor with "Ejecutar SQL" button and result feedback.
- **Pagination:** ← → buttons, "1-100 de 42" label.

**Integration in `renderNode()`:**
```javascript
nm.onclick = () => /\.db$/i.test(f.path) ? openDbViewer(f.path) : openEd(f.path);
```

### 5. Export

- `.db` files are stored as SQL text. The existing download button (↓) works as-is for `.db` files — the user gets a `.sql` file they can import into any SQLite.
- The DB viewer also has an explicit "⬇ .sql" export button that triggers the same `downloadFile()`.

### 6. Auto-creation

If a `.db` file doesn't exist and a CREATE TABLE statement is executed, the engine creates the file automatically:
1. No file at path → create empty `:memory:` DB
2. Execute the SQL (typically `CREATE TABLE ...`)
3. Dump and save to path
4. File appears in the disk sidebar via `refreshDisk()`

## Data Flow

### SELECT (read-only)
```
User/Agent/Shell → pyDbExec('clientes.db', 'SELECT ...')
  → fsGet('clientes.db') → load dump into :memory: DB
  → conn.execute(SELECT) → fetch results
  → return {columns, rows} (NO save — read-only)
```

### INSERT/UPDATE/DELETE/CREATE/DROP (write)
```
User/Agent/Shell → pyDbExec('clientes.db', 'INSERT ...')
  → fsGet('clientes.db') → load dump into :memory: DB
  → conn.execute(INSERT) → get changes count
  → conn.iterdump() → full SQL dump
  → fsPut('clientes.db', dump) → save to IndexedDB
  → return {columns:[], rows:[], changes: N}
```

### Export as .sql
```
User clicks ↓ on clientes.db → downloadFile('clientes.db')
  → fsGet('clientes.db') → already SQL text
  → Blob([content], {type:'application/sql'}) → download as clientes.db (or .sql)
```

## Storage Format

| Extension | Content | Encoding in IndexedDB |
|-----------|---------|-----------------------|
| `.db` | SQL text (sqlite3 dump) | Plain UTF-8 text (no B64 prefix needed for pure SQL) |

If the dump contains binary data (BLOBs), it will be hex-encoded in the SQL dump by sqlite3. The existing ` B64 ` prefix handling in `fsGet`/`fsPut` is only needed for actual binary files (PDF, images, etc.).

## Error Handling

- **Invalid SQL:** Pyodide raises `sqlite3.Error` → caught, returned as `"SQL Error: <message>"` to agent/shell.
- **Missing DB file + SELECT:** `"SQL Error: no such table: ..."` → the agent should CREATE TABLE first.
- **Missing DB file + CREATE:** Creates the file automatically.
- **Pyodide not loaded:** `pyInit()` blocks until Pyodide is ready.

## Files Changed

| File | Changes |
|------|---------|
| `docs/index.html` | Add `pyDbExec()` function, `openDbViewer()` + viewer functions, `sql` tool in TOOLS + execToolRaw, `sql` command in shRun, modify `renderNode()` for .db click, modify `downloadFile()` MIME for .db |

## Non-goals (out of scope for v1)

- No BLOB/binary column support with UI preview (binary data stored as hex in dump is OK)
- No multi-user / concurrent access
- No indexes UI (agent can CREATE INDEX via SQL)
- No ERD diagram / schema visualization
- No query history
- No connection to external databases (MySQL, PostgreSQL)
