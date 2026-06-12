# Agents Web — Roadmap

Próximos pasos para la app web (https://fivetechsoft.github.io/Agents/).

## Almacenamiento y sincronización
- [ ] **OPFS** (Origin Private File System) como backend del disco, además de IndexedDB.
- [ ] **git push real** vía smart-http (CORS proxy propio en Cloudflare Worker) en vez de Contents API.
- [ ] Subir/bajar carpetas completas y árboles grandes con menos llamadas (Git Data API: un solo commit).
- [ ] Snapshots del disco (guardar/restaurar estado completo) — card "Workspace Snapshot".

## Runtimes
- [ ] **Más lenguajes WASM**: TypeScript/JS (QuickJS), Ruby (ruby.wasm), Lua, SQLite (sql.js).
- [x] **PHP** (@php-wasm): CLI + preview web con forms/sesiones. ✅ 2026-06-12
- [ ] **C++** y stdlib pesada con clang (sysroot completo) además del C básico.
- [ ] `pip install` de wheels puros en Python (micropip) expuesto en el shell.
- [ ] Caché persistente de los runtimes (clang/Pyodide) en Cache Storage para arranque rápido.

## Linux / sistema
- [ ] **Linux real** opcional vía v86 / JSLinux (emulador x86) para quien lo necesite.
- [ ] **SSH** sobre WebSocket a través de un gateway (wetty / ws→ssh) — requiere backend.
- [ ] Procesos en segundo plano simulados (jobs, `&`, `ps`).

## Agente
- [ ] Selector de **modelo** en la UI (flash / pro) y de **reasoning_effort** (high / max).
- [ ] **/loop** con métricas más ricas (tokens por iteración, coste acumulado, criterio de parada).
- [ ] Memoria de largo plazo persistente (vector store en IndexedDB) para `memory`.
- [ ] Editor de **skills** con frontmatter y activación por contexto.
- [ ] Conexiones tipo **MCP**: card de estado de servicios (GitHub, web, runtimes).

## UI / plataforma
- [ ] **PWA** instalable (offline, icono, splash) — el disco ya es local.
- [ ] Pestañas de **varios agentes** a la vez (como la app Android).
- [ ] Traducción completa de la interfaz (no solo la demo) a los 6 idiomas.
- [ ] Tema claro / oscuro.

## Web como unidad de almacenamiento compartida
- [ ] Backend opcional (Worker) para que cada visitante tenga su carpeta sin exponer token.
- [ ] OAuth device-flow de GitHub para push con la cuenta del usuario.

## Colaboración y tiempo real
- [ ] Disco compartido en vivo entre varios usuarios (WebRTC / Yjs CRDT).
- [ ] Sesiones de pair-programming con el agente (cursor y selección compartidos).
- [ ] Historial de conversación exportable (Markdown / JSON) e importable.

## Seguridad
- [ ] Almacenar tokens en un backend o cifrados, nunca en texto en el campo (`/ghtoken`).
- [ ] Sandbox por herramienta y lista blanca de dominios para `web_fetch`.
- [ ] Límites de gasto (token budget) con corte automático y aviso.
- [ ] Confirmación obligatoria para `rm -rf`, `delete_file` masivo y push a `main`.

## Rendimiento
- [ ] Lazy-load de las librerías pesadas (git, Pyodide, Wasmer) solo al usarlas — hecho parcialmente.
- [ ] Web Workers para shell/diff/parseo y no bloquear la UI.
- [ ] Virtualizar el árbol del disco y el chat para miles de entradas.
- [ ] Streaming incremental del Markdown (render por bloques).

## Calidad / testing
- [ ] Suite de tests del shell simulado y del diff (LCS) en CI.
- [ ] Lint del HTML/JS en GitHub Actions antes de publicar Pages.
- [ ] Modo "grabar/reproducir" de demos para regresión visual.

## Integraciones
- [ ] Más proveedores LLM (OpenAI, Anthropic, Gemini, Ollama local) con selector.
- [ ] Conectores: Gists, Issues/PRs de GitHub, Google Drive, S3.
- [ ] Webhooks / cron para tareas autónomas programadas.

## Accesibilidad e i18n
- [ ] Navegación completa por teclado y roles ARIA en todas las cards.
- [ ] Lector de pantalla para el chat y el terminal.
- [ ] Traducción completa de la UI a los 6 idiomas (no solo la demo).
- [ ] Tamaño de fuente y alto contraste configurables.

## Observabilidad
- [ ] Panel de métricas (tokens, coste, latencia, comandos) por sesión.
- [ ] Log de herramientas exportable.
- [ ] Telemetría opcional anónima (opt-in) para mejorar la demo.
