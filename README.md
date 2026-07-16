<div align="center">

# Agents

### Autonomous AI coding agent — Web, Windows/Linux/macOS console, and Android

*Streaming chat, 17 built-in tools, skills system, multi-agent dispatch.
One engine, three platforms. Written 100% in Harbour.*

**🌐 Web:** https://fivetechsoft.github.io/Agents/

**🖥️ Console:** `agents.exe` (1.27 MB, zero dependencies)

**📱 Android:** `agents.apk` (native ARM, WebView UI)

</div>

---

## What is Agents?

Agents is an autonomous AI coding assistant — you describe what you need in natural language, and the agent uses its tools to accomplish it: read/write/edit files, run shell commands, search the web, query GitHub, and more.

The core agent engine (ReAct loop + tool-calling + streaming SSE) is shared across all three platforms. Only the UI host and HTTP transport differ per platform.

### Three platforms, one engine

| | Web | Console (EXE) | Android (APK) |
|---|---|---|---|
| **UI** | HTML5 browser / WebView2 | Terminal TUI (VT100) | Android WebView |
| **Transport** | `fetch()` (browser) | curl subprocess | Java `HttpsURLConnection` |
| **Storage** | IndexedDB + GitHub sync | Local filesystem | App private storage |
| **Concurrency** | Web Workers | Single-thread | Harbour MT threads |
| **Size** | ~500 KB (HTML+JS+Wasm) | 1.27 MB (single .exe) | 773 KB (.apk) |
| **Runtimes** | Python, PHP, C, SQLite | Native shell | Shell via `/sh` |

---

## Features (all platforms)

- **17 Built-in Tools:** `read`, `write`, `edit`, `glob`, `grep`, `shell`, `web_search`, `web_fetch`, `github_read`, `github_write`, `memory`, `ask_user`, `todo_write`, `use_skill`, `dispatch_agent`, `dispatch_agent_background`, `propose_agents`
- **Streaming SSE:** Real-time token-by-token responses
- **Skills System:** Markdown-based skills with YAML frontmatter, auto-activation via trigger regex
- **Multi-Agent Dispatch:** Spawn subagents (blocking or background) for parallel task execution
- **Permission Gate:** `allow` / `deny` / `ask` per tool + plan-mode lock
- **Session Management:** Save/load conversations as JSON
- **Multi-Backend:** DeepSeek, OpenAI, GLM, Moonshot, Ollama
- **Slash Commands:** `/help`, `/model`, `/plan`, `/goal`, `/run`, `/key`, `/provider`, `/clear`, `/save`, `/load`, `/lean`, `/compact`, `/rewind`, `/loop`, `/tasks`, `/btw`, `/hook`

---

## Agents Console (Windows/Linux/macOS)

Native terminal app with full TUI:

```
┌─────────────────────────────────────┐
│  █████╗   █████╗  ...  (AG logo)   │
│       A g e n t s                   │
│   Autonomous AI agents              │
└─────────────────────────────────────┘
│  > Write a script that...           │
└─────────────────────────────────────┘
```

### Build

```bash
cd source
hbmk2 -comp=msvc64 agents.hbp    # Windows (MSVC)
# or
hbmk2 agents_linux.hbp           # Linux (gcc)
hbmk2 agents_mac.hbp             # macOS (clang)
```

Requires: Harbour 3.2+, curl (included in Windows 10+/macOS/Linux).

### Quick Start

```bash
set DEEPSEEK_API_KEY=sk-...
agents.exe
```

### Download

Latest release: https://github.com/FiveTechSoft/Agents/releases/latest

---

## Agents Web

Runs entirely in the browser. No install, no server.

- **Virtual disk** in IndexedDB — files persist between sessions
- **Real runtimes** — Python (Pyodide), C (clang/Wasmer), PHP (@php-wasm), SQLite
- **SSH Terminal** embedded in chat — WebSocket→TCP tunnel
- **GitHub Sync** — push/pull to any repo
- **AI Disk Classifier** — classify files with transformers.js (local, no cloud)

Live demo: https://fivetechsoft.github.io/Agents/

---

## Agents Android

Native Android application. Harbour cross-compiled to ARM64, packaged as APK.

### How it works

```
┌─────────────────────── Android process ───────────────────────┐
│  Android WebView  ◀── HTML chat panel ── tabs                 │
│       │  ▲                                                     │
│  evaluateJavascript │ @JavascriptInterface                     │
│       ▼  │                                                     │
│  JNI bridge (android_webview.c)                                │
│       │  ▲                                                     │
│       ▼  │   per-agent event queues (pthread mutex + condvar)  │
│  libharbour (MT VM) + Agents core                              │
│    • dispatcher thread — spawns agents with hb_threadStart    │
│    • agent thread #1..N — AG_AgentRun, own client + history   │
│       │                                                        │
│       ▼  transport codeblock                                   │
│  Java HttpsURLConnection (JNI) ──▶ LLM API (SSE)              │
└────────────────────────────────────────────────────────────────┘
```

### Build

```bash
cd android
bash build-apk.sh
```

Requires: Android NDK r26+, Android SDK 34, JDK 17, Harbour for Android (prebuilt static libs).

### Install

```bash
adb install -r build/agents.apk
```

Set API key: `/key sk-...` inside the app, or push a key file:
```bash
adb push deepseek.key /data/local/tmp/deepseek.key
```

---

## CLASS Agent API

The agent engine is exposed as a reusable Harbour class:

```harbour
oAgent := Agent():New( cApiKey, cModel, hOpts )
hResult := oAgent:Run( "Find all .prg files and summarize them" )
? hResult[ "content" ]
? "Cost: $", oAgent:UsageReport()
```

Full API reference: https://github.com/FiveTechSoft/Agents/wiki/Class-Agent

---

## Repository layout

```
.
??? agents / agents.exe   # Console binaries (root)
??? source/               # Console Harbour sources + .hbp
??? android/              # APK sources, manifest, HarbourAndroid libs
??? docs/                 # Web UI (GitHub Pages)
??? tests/                # Automated tests
??? scripts/              # Helper scripts (ssh-proxy, etc.)
??? screenshots/          # UI screenshots
??? .agents/              # Runtime settings & skills
```

## Source Structure

```
source/
  agents.hbp              Build file (Windows)
  agents_linux.hbp        Build file (Linux, static + gttrm)
  agents_mac.hbp          Build file (macOS)
  agents_repl.prg         Main() entry, REPL loop
  agents.prg              CLASS Agent
  agents_ui.prg           TUI: banner, cards, cost report
  agents_prompt.prg       Persistent input box
  agents_input.prg        Multi-line line editor
  agents_markdown.prg     Markdown-to-ANSI renderer
  agents_http.prg         API client
  agents_sse.prg          SSE parser
  agents_curl.prg         curl subprocess transport
  agents_tool_*.prg       Tool handler files
  agents_settings.prg     .agents/settings.json
  agents_perm.prg         Permission gate
  agents_skill.prg        Skills registry
  agents_diff.prg         Line-level diff engine
  agents_console.prg      Harbour-standard console backend
                            (Inkey + hb_keyStd/hb_keyChar; gttrm/gtwin)
  go.bat / go.sh          One-shot build helpers
```

---

## Environment Variables

| Variable | Description |
|----------|------------|
| `DEEPSEEK_API_KEY` | API key (primary) |
| `AGENTS_API_KEY` | API key (alternative) |
| `OPENAI_API_KEY` | OpenAI key |
| `AGENTS_CONFIG` | Override settings.json path |
| `AGENTS_ASK_TIMEOUT` | Permission prompt timeout (seconds) |

---

## Wiki

Full documentation: https://github.com/FiveTechSoft/Agents/wiki

- [Web Agents](https://github.com/FiveTechSoft/Agents/wiki/Web-Agents)
- [Agents EXE](https://github.com/FiveTechSoft/Agents/wiki/Agents-EXE)
- [Agents APK](https://github.com/FiveTechSoft/Agents/wiki/Agents-APK)
- [Class Agent API](https://github.com/FiveTechSoft/Agents/wiki/Class-Agent)

---

## Credits

Developed by **© FiveTech Software 2026**.
Contact: [antonio.fivetech@gmail.com](mailto:antonio.fivetech@gmail.com)

Built with [Harbour](https://harbour.github.io/) · [FiveWin](https://www.fivetechsoft.com/) · [Tailwind CSS](https://tailwindcss.com/) · [marked.js](https://marked.js.org/).
