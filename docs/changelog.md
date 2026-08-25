# Agents Web — Novedades

Aplicación web estática (GitHub Pages) en **https://fivetechsoft.github.io/Agents/**.
Un agente IA en el navegador con disco virtual, runtimes WASM y herramientas reales. Versión actual: **2.2.0**.

## Runtimes en el navegador
- **Shell POSIX simulado** sobre el disco virtual (`/sh`, `/shell`, `/bash` y comandos sueltos):
  `ls · cat · echo · pwd · cd · mkdir · touch · rm · mv · cp · grep · head · tail · wc · find`,
  con **pipes** (`|`) y **redirección** (`>`, `>>`) y `cwd` persistente.
- **Python real** (Pyodide / CPython en WASM): `python file.py` · `/py` · tool `python`.
  El disco se espeja a `/disk`, así Python lee/escribe los mismos ficheros.
- **C real con clang** (Wasmer SDK en WASM): `cc/clang/gcc file.c` · `/cc` · tool `cc`.
  Compila C → módulo wasm → lo ejecuta. Cross-origin isolation vía `coi-serviceworker`.
- **PHP 8 real** (@php-wasm / WordPress Playground en WASM): `php file.php` · `php -r <código>` · `/php` · tool `php`.
  **Preview web** de `.php` en el editor (botón 🌐 Ver): formularios (`$_POST`), navegación entre páginas (`$_GET`),
  sesiones (`$_SESSION`) y cookies simuladas; el disco se espeja a `/disk` (document root).
- **SQL real** (SQLite en WASM): tool `sql` sobre ficheros `.db` del disco virtual
  (SELECT/INSERT/UPDATE/CREATE TABLE…; el `.db` se crea solo al crear la primera tabla).

## Disco virtual (unidad de almacenamiento simulada)
- Filesystem sobre **IndexedDB**, persistente por navegador.
- **Árbol de carpetas** plegable (rutas con `/`), borrar carpeta, editor con **preview Markdown**.
- Adjuntar ficheros locales, botón **Erase** (con confirmación).
- **Sincronización con GitHub**: ⬇ Pull / ⬆ Push (Contents API) + **git real** (isomorphic-git):
  `/clone` · `/git status|log|commit|push|pull|branch` · tool `git` (red vía GitHub API, sin proxy).
- **Proxy CORS opcional** (`/proxy` + `docs/cloudflare-worker.js`) para git smart-http y binarios.

## Agente y modelos
- **Ox Alpha por defecto** (`x-preview-f-free`) vía OpenCode Zen — gratis, sin API key — con
  **fallback dinámico** entre los modelos `-free` disponibles (`mimo-v2.5-free`, DeepSeek Flash, Hy3,
  Nemotron Ultra, Nemotron Lightning, Laguna). Descubrimiento vía `GET /models`.
- **🧠 Modo razonamiento** (thinking mode) con `reasoning_content` en vivo — y **con tools**.
- **Multi-agente**: tool `dispatch_agents` lanza 2–4 sub-agentes concurrentes (Promise.all)
  alrededor de un **contrato técnico compartido** (nombres de tablas/columnas, firmas, rutas)
  que se antepone a cada sub-agente para evitar divergencia.
- **web_search / web_fetch** (vía jina, CORS-friendly, sin API key).
- **Límite de pasos** que **pregunta** antes de continuar (+25) en vez de bloquear.
- **User tools dinámicas**: tools `register_tool` / `user_tools` / `unregister_tool` permiten al agente
  crear nuevas tools desde scripts. Sobreviven a recargas (localStorage).
  Python recibe `sys.argv`, shell recibe `$1..$n`. El agente se expande a sí mismo.
- **Memoria persistente**: tool `remember` guarda hechos duraderos en **MEMORY.md**, disponibles en
  sesiones futuras (`/memory` la muestra; `/distill` destila la sesión → resumen + facts).

## Tareas programadas, SSH y voz
- **Tareas recurrentes**: tool `schedule_task` y `/cron <30m|2h|1d> <cmd>` ejecutan un prompt o comando
  cada intervalo mientras la página esté abierta; también schedules vía GitHub Actions (`/cron gh "..." tarea`).
- **SSH gateway** (`/ssh` · `/exit`): conexión a servidores remotos mediante WebSocket→TCP (ssh2),
  con terminal embebida.
- **Voz TTS** (`/voice`): lee las respuestas en voz alta; lista y selección de voces (1,2…, del).
- **Interjecciones** (`/btw`): nota para el agente en marcha sin interrumpirlo (cola de interrupciones).

## Comandos slash
`/help · /clear · /key · /ghtoken · /goal · /plan · /run · /loop · /clone · /git · /action · /cron ·
/skill · /tool · /perm · /proxy · /ssh · /exit · /voice · /btw · /memory · /distill · /export · /share ·
/sh · /shell · /bash · /py · /cc · /php · /classify · /cost · /compact · /init`

## Cards (replican los mockups de Claude Code)
Objetivo, Plan de Acción (editable: editar/borrar/+paso/estado), Telemetría del Bucle,
panel colapsable de acciones con iconos, diff coloreado + "Código generado" con **revisión multi-fichero por turno**,
permit/reject, ask_user (con **clarificación enriquecida**: radios + descripción + Recomendado),
pensamiento (glass box), error + Auto-corregir, fin de tarea, métricas /cost, /compact, /init,
**Skills** (toggle activo), **Registro de Herramientas** (dots de seguridad + Auto-Aprobar), terminal, delegación, git.

## UX
- **Demo** automática (botón ▶): sin key simula las cards; con key usa el LLM (tema distinto cada vez).
- **Idioma** seleccionable con banderas (persistente); la demo y el agente responden en ese idioma.
- Icono 😎 **parpadea** mientras trabaja. **↑/↓** historial de prompts, **Tab** acepta el hint.
- **Ctrl+K** limpiar · **Ctrl+L/Ctrl+R** atajos · **Esc** parar. Conversación y uso **persisten** entre recargas.
- **PWA instalable** (`manifest.webmanifest`).
- Responsive (disco como cajón en móvil, `100dvh`).
