<div align="center">

# Agents

### Autonomous AI coding agent — Web, Windows/Linux/macOS console, and Android

*Streaming chat, 17 built-in tools, skills system, multi-agent dispatch.
One engine, three platforms. Written 100% in Harbour.*

**Version 2.1.0**

**Web:** https://fivetechsoft.github.io/Agents/

**Console:** `agents` / `agents.exe` (static binary at repo root)

**Android:** `agents.apk` (native ARM, WebView UI)

**Releases:** https://github.com/FiveTechSoft/Agents/releases

</div>

---

## What is Agents?

Agents is an autonomous AI coding assistant — you describe what you need in natural language, and the agent uses its tools to accomplish it: read/write/edit files, run shell commands, search the web, query GitHub, and more.

The core agent engine (ReAct loop + tool-calling + streaming SSE) is shared across all three platforms. Only the UI host and HTTP transport differ per platform.

### Three platforms, one engine

| | Web | Console | Android (APK) |
|---|---|---|---|
| **UI** | HTML5 browser | Terminal TUI (VT100/ANSI) | Android WebView |
| **Transport** | `fetch()` (browser) | curl subprocess | Java `HttpsURLConnection` |
| **Storage** | IndexedDB + GitHub sync | Local filesystem | App private storage |
| **Concurrency** | Web Workers | Single-thread | Harbour MT threads |
| **Binary / size** | ~500 KB (HTML+JS+Wasm) | ~2.2 MB Linux static / ~1.3 MB Windows | ~773 KB APK |
| **Runtimes** | Python, PHP, C, SQLite | Native shell | Shell via `/sh` |
| **Keyboard (console)** | — | Harbour GT: `Inkey` + `hb_keyStd` / `hb_keyChar` | Soft keyboard |

---

## Features (all platforms)

- **17 built-in tools:** `read`, `write`, `edit`, `glob`, `grep`, `shell`, `web_search`, `web_fetch`, `github_read`, `github_write`, `memory`, `ask_user`, `todo_write`, `use_skill`, `dispatch_agent`, `dispatch_agent_background`, `propose_agents`
- **Streaming SSE:** token-by-token responses
- **Skills system:** Markdown skills with YAML frontmatter, auto-activation via triggers
- **Multi-agent dispatch:** blocking or background subagents
- **Permission gate:** `allow` / `deny` / `ask` per tool + plan-mode lock
- **Sessions:** save/load conversations as JSON
- **Multi-backend:** DeepSeek, OpenAI, GLM, Moonshot, Ollama

---

## Repository layout (2.0)

```
.
├── agents / agents.exe   # Console binaries (built into repo root)
├── go.sh                 # Linux one-shot build → ./agents
├── source/               # Console Harbour sources + .hbp
├── android/              # APK (manifest, src/, HarbourAndroid libs, build-apk.sh)
├── docs/                 # Web UI (GitHub Pages)
├── tests/                # Automated tests
├── scripts/              # Helpers (ssh-proxy, check.js, …)
├── screenshots/          # UI screenshots
├── .agents/              # Runtime config & skills (see Configuration)
├── CHANGELOG.md
├── whatsnew.txt
└── README.md
```

---

## Agents Console (Windows / Linux / macOS)

Native terminal app with a persistent prompt box, cards (goal, plan, cost, tools, …), and slash commands.

### Requirements

- **Harbour 3.2+** (with `hbmk2`)
- **curl** (HTTP transport; available on Windows 10+, macOS, Linux)
- Linux: **gcc** and static Harbour libs for a fully portable binary

### Build

From the repository root:

```bash
# Linux (recommended: static + gttrm)
./go.sh
# or
cd source && hbmk2 agents_linux.hbp

# Windows (MSVC)
cd source
go.bat
# or
hbmk2 agents.hbp -comp=msvc64

# macOS
cd source && hbmk2 agents_mac.hbp
```

Outputs land in the **repo root**:

| Platform | Output |
|----------|--------|
| Linux | `./agents` |
| Windows | `./agents.exe` |
| macOS | `./agents` |

Linux `agents_linux.hbp` flags: `-mt -static -gttrm -o../agents`  
(no `libharbour.so` dependency).

### Quick start

```bash
# API key (any of these)
export DEEPSEEK_API_KEY=sk-...
# or configure inside the app:  /provider key <secret>

./agents          # Linux / macOS
agents.exe        # Windows
```

### Console slash commands

Type `/help` inside the app for the full list. Main commands:

| Command | Description |
|---------|-------------|
| `/help` | List all commands |
| `/demo` | **Full random offline session** (cards + most cmds, **no API key**) |
| `/init` | Analyse project and write `CC.md` |
| `/model [name]` | Show or switch model |
| `/provider` | Show/switch backend (deepseek, glm, moonshot, openai, ollama) |
| `/key <secret>` | Save API key (alias of `/provider key`) |
| `/cost` | Token usage and estimated cost |
| `/save` / `/load` | Session JSON |
| `/clear` | Reset conversation |
| `/plan` / `/run` | Plan card and step execution |
| `/goal` | Goal loop |
| `/sh` `/git` `/clone` | Shell / git without LLM |
| `/skill` / `/tool` | Skills and tools registry cards |
| `/lean` | Smaller system prompt (fewer tokens) |
| `/compact` / `/ctx` | Context compact / window size |
| `/tasks` | Background subagent tasks |
| `/loop` / `/rewind` / `/btw` | Loop, undo turn, mid-turn note |
| `/exit` | Quit (`/quit`, `/bye`; also bare `exit`/`quit`/`bye`) |

### Configuration

Runtime settings live under **`.agents/`** in the working directory (or path from `AGENTS_CONFIG`):

| File | Tracked? | Purpose |
|------|----------|---------|
| `.agents/settings.json` | **No** (gitignored) | Local keys and preferences |
| `.agents/settings.example.json` | Yes | Template without secrets |
| `.agents/skills/*.md` | Optional | Skill definitions |

Set the key with `/provider key …` or environment variables — **never commit API keys**.

### Console implementation notes (2.0)

- **Keyboard:** same model as hbIDE — blocking `Inkey()`, specials via `hb_keyStd()`, text via `hb_keyChar()`.
- **Linux GT:** `gttrm` (Harbour standard terminal GT).
- **Prompt box:** ANSI TUI via raw stdout; input is GT-driven so typing is visible on WSL/Windows Terminal.
- **`/demo`:** offline showcase (random scenario): real `/help`, `/provider`, `/tool`, `/skill`, shell, git, write/edit cards, goal/plan/todo, cost/compact/context — restores session state afterward.

---

## Agents Web

Runs entirely in the browser. No install, no server.

- Virtual disk in **IndexedDB**
- Runtimes: Python (Pyodide), C (clang/Wasmer), PHP (@php-wasm), SQLite
- Embedded SSH terminal (WebSocket→TCP)
- GitHub sync (pull/push)
- Live demo: https://fivetechsoft.github.io/Agents/

Sources: `docs/` (GitHub Pages).

---

## Agents Android

Native Android app: Harbour cross-compiled to ARM64, packaged as APK.

### Build

```bash
cd android
bash build-apk.sh
```

Requires: Android NDK r26+, Android SDK 34, JDK 17, Harbour-for-Android static libs (`android/HarbourAndroid`).

Core console PRGs are taken from **`source/`** (`AGENTS_SRC` in `build-apk.sh`).

### Install

```bash
adb install -r build/agents.apk
```

API key: `/key sk-...` in the app, or:

```bash
adb push deepseek.key /data/local/tmp/deepseek.key
```

---

## CLASS Agent API

Reusable Harbour class for embedding the engine:

```harbour
oAgent := Agent():New( cApiKey, cModel, hOpts )
hResult := oAgent:Run( "Find all .prg files and summarize them" )
? hResult[ "content" ]
? "Cost: $", oAgent:UsageReport()
```

Wiki: https://github.com/FiveTechSoft/Agents/wiki/Class-Agent

---

## Source map (`source/`)

| File | Role |
|------|------|
| `agents_linux.hbp` / `agents.hbp` / `agents_mac.hbp` | Platform builds |
| `agents_repl.prg` | `Main()`, REPL, `/demo`, slash handlers |
| `agents.prg` | `CLASS Agent` |
| `agents_console.prg` | Harbour-standard keyboard / console size |
| `agents_ui.prg` | TUI cards, `AGUI_Help()`, version string |
| `agents_prompt.prg` / `agents_input.prg` | Persistent prompt box + line editor |
| `agents_http.prg` / `agents_sse.prg` / `agents_curl.prg` | API + SSE + curl transport |
| `agents_tool_*.prg` | Tool handlers |
| `agents_settings.prg` | Load/save `.agents/settings.json` |
| `go.sh` / `go.bat` | One-shot build helpers |

Version string: `AGUI_Version()` in `agents_ui.prg` (currently **2.1.0**).

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `DEEPSEEK_API_KEY` | API key (primary) |
| `AGENTS_API_KEY` | API key (generic) |
| `OPENAI_API_KEY` / `GLM_API_KEY` / `MOONSHOT_API_KEY` | Provider-specific keys |
| `AGENTS_CONFIG` | Override path to `settings.json` |
| `AGENTS_ASK_TIMEOUT` | Permission prompt timeout (seconds) |
| `HB_BIN` | Optional Harbour bin dir for `go.sh` |

---

## Tests

```bash
# See tests/README.md — typically against a local web serve of docs/
cd tests
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) and [whatsnew.txt](whatsnew.txt).

---

## Wiki

https://github.com/FiveTechSoft/Agents/wiki

- [Web Agents](https://github.com/FiveTechSoft/Agents/wiki/Web-Agents)
- [Agents EXE](https://github.com/FiveTechSoft/Agents/wiki/Agents-EXE)
- [Agents APK](https://github.com/FiveTechSoft/Agents/wiki/Agents-APK)
- [Class Agent API](https://github.com/FiveTechSoft/Agents/wiki/Class-Agent)

---

## Credits

© FiveTech Software 2026 · [antonio.fivetech@gmail.com](mailto:antonio.fivetech@gmail.com)

Built with [Harbour](https://harbour.github.io/) · [FiveWin](https://www.fivetechsoft.com/) · [Tailwind CSS](https://tailwindcss.com/) · [marked.js](https://marked.js.org/).
