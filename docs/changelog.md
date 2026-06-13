# Agents Web — Novedades

Aplicación web estática (GitHub Pages) en **https://fivetechsoft.github.io/Agents/**.
Un agente IA en el navegador con disco virtual, runtimes WASM y herramientas reales.

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

## Disco virtual (unidad de almacenamiento simulada)
- Filesystem sobre **IndexedDB**, persistente por navegador.
- **Árbol de carpetas** plegable (rutas con `/`), borrar carpeta, editor con **preview Markdown**.
- Adjuntar ficheros locales, botón **Erase** (con confirmación).
- **Sincronización con GitHub**: ⬇ Pull / ⬆ Push (Contents API) + **git real** (isomorphic-git):
  `/clone` · `/git status|log|commit|push|pull|branch` · tool `git` (red vía GitHub API, sin proxy).

## Agente y modelos
- **DeepSeek V4** (`deepseek-v4-flash` / `deepseek-v4-pro`), respuesta en **streaming** (token a token).
- **🧠 Modo razonamiento** (thinking mode) con `reasoning_content` en vivo — y **con tools**.
- **Multi-agente**: tool `dispatch_agents` lanza 2–4 sub-agentes concurrentes (Promise.all) + card "Delegando tarea".
- **web_search / web_fetch** (vía jina, CORS-friendly, sin API key).
- **Límite de pasos** que **pregunta** antes de continuar (+14) en vez de bloquear.
- **User tools dinámicas**: tool `register_tool` permite al agente crear nuevas tools desde scripts.
  El agente escribe un script → lo registra → queda disponible como comando. Sobrevive a recargas.
  Python recibe `sys.argv`, shell recibe `ARG1..ARGn`. El agente se expande a sí mismo.

## Comandos slash
`/help · /clear · /key · /ghtoken · /goal · /plan · /run · /loop · /clone · /git · /skill · /tool · /sh · /py · /cc · /php · /cost · /compact · /init`

## Cards (replican los mockups de Claude Code)
Objetivo, Plan de Acción (editable: editar/borrar/+paso/estado), Telemetría del Bucle,
panel colapsable de acciones con iconos, diff coloreado + "Código generado",
permit/reject, ask_user (con **clarificación enriquecida**: radios + descripción + Recomendado),
pensamiento (glass box), error + Auto-corregir, fin de tarea, métricas /cost, /compact, /init,
**Skills** (toggle activo), **Registro de Herramientas** (dots de seguridad + Auto-Aprobar), terminal, delegación, git.

## UX
- **Demo** automática (botón ▶): sin key simula las cards; con key usa el LLM (tema distinto cada vez).
- **Idioma** seleccionable con banderas (persistente); la demo y el agente responden en ese idioma.
- Icono 😎 **parpadea** mientras trabaja. **↑/↓** historial de prompts, **Tab** acepta el hint.
- **Ctrl+K** limpiar · **Esc** parar. Conversación y uso **persisten** entre recargas.
- Responsive (disco como cajón en móvil, `100dvh`).
