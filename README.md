<div align="center">

# 😎 Agents

### An autonomous AI coding agent for Android — written 100% in Harbour

*The same agentic engine that powers the `cc` console, on your phone:
streaming chat, real tool-calling, and multiple agents running in parallel.*

</div>

---

## What is this?

**Agents** is a native Android application that runs an autonomous **AI coding
agent** — it chats, reasons, and **executes real tools** (read/write/edit files,
run shell commands, search the web, remember things) to accomplish tasks you give
it in natural language.

What makes it unusual: the entire application — the agent loop, the tool engine,
the HTTP plumbing, the multi-threading — is written in **[Harbour](https://harbour.github.io/)**
(the open-source xBase compiler), cross-compiled to an Android `.so`. The UI is a
modern HTML chat panel hosted in a system WebView. There is no Kotlin/Java app
logic beyond a thin bridge.

It reuses the **[ccharbour](https://github.com/FiveTechSoft)** agentic core
(`CC_Client` / `CC_AgentRun`) unchanged — the very same code that drives the
desktop FiveWin app and the `cc.exe` console agent.

<div align="center">
<em>Built with FiveWin / Harbour &nbsp;·&nbsp; powered by the ccharbour API</em>
</div>

---

## Features

- 🤖 **Real agentic loop** — streaming chat + tool-calling (OpenAI-style function
  calling) via the ccharbour engine.
- 🧰 **Full tool set** — `read`, `write`, `edit`, `glob`, `grep`, `shell`,
  `web_search`, `web_fetch`, `memory`, and an interactive `ask_user` multiple-choice tool.
- 🧵 **Multiple agents in parallel** — each agent runs on its **own Harbour OS
  thread** (Harbour MT VM). Open as many as you need with the `+` tab; they work
  concurrently and independently.
- 🤝 **Synchronized orchestration** — the `dispatch_team` tool fans a task into
  2–4 parallel sub-agents (each in its own tab) and **joins** them
  (`hb_threadJoin`) before returning the combined result.
- 🎨 **Rich chat UI** — Markdown rendering (tables, code, lists), syntax-aware
  bubbles, and **colored diffs** (green `+` / red `−`) for every write/edit.
- 🔐 **Permission gate** — with *Auto-approve* off, every mutating tool
  (`shell`/`write`/`edit`) shows a permit / reject card and blocks until you decide.
- 🗣️ **Voice dictation** — a mic button feeds speech-to-text into the prompt
  (where the WebView supports it).
- ⚙️ **In-app settings** — text size, new agent, clear chat, and an *About* dialog,
  from a top-right kebab menu. No Android system settings required.
- 🔑 **Bring your own key** — reads the LLM key from a local file on the device, or
  set it at runtime with `/key <api-key>`.

---

## How it works

```
 ┌──────────────────────────── Android process ────────────────────────────┐
 │                                                                          │
 │   Android WebView  ◀── HTML chat panel (Tailwind, marked.js) ── tabs     │
 │        │  ▲                                                              │
 │  evaluateJavascript │ @JavascriptInterface  (== Eval / SendToFWH)        │
 │        ▼  │                                                              │
 │   JNI bridge  (android_webview.c)                                        │
 │        │  ▲                                                              │
 │        ▼  │   per-agent event queues (pthread mutex + condvar)           │
 │   libharbour (MT VM) + ccharbour                                         │
 │     • dispatcher thread  — spawns agents with hb_threadStart             │
 │     • agent thread #1..N — CC_AgentRun, own client + history             │
 │        │                                                                │
 │        ▼  transport codeblock                                           │
 │   Java HttpsURLConnection (JNI)  ──▶  LLM API (SSE)                       │
 │                                                                          │
 └──────────────────────────────────────────────────────────────────────────┘
```

| Concern        | Desktop (FiveWin)                | Android (this app)                         |
|----------------|----------------------------------|--------------------------------------------|
| UI host        | `TWebView2` (Edge WebView2)      | Android system `WebView`                   |
| PRG → page     | `oWeb:Eval(js)`                  | `WebView.evaluateJavascript` (JNI)         |
| page → PRG     | `SendToFWH(...)` → `bOnBind`     | `@JavascriptInterface` → JNI → event queue |
| HTTP transport | in-process libcurl (hbcurl)      | Java `HttpsURLConnection` over JNI         |
| Concurrency    | one GUI thread                   | one Harbour **MT** thread per agent        |

The LLM HTTP is injected into ccharbour through its pluggable
`hOpts["transport"]` codeblock, so **no curl or OpenSSL is cross-compiled** — the
request rides Android's own TLS stack via a tiny Java method.

---

## How the app was built

Agents was built by **reusing the desktop FiveWin agent and swapping only the two
platform-specific layers** — the UI host and the HTTP transport — so the entire
ccharbour brain travels to Android untouched.

1. **Start from the engine, not the UI.** The desktop `samples/AgenticAI` already
   wraps the ccharbour loop (`CC_Client` / `CC_AgentRun`) behind an injectable
   transport codeblock and a tool registry. Those same `.prg` modules compile for
   Android — only the glue changes.

2. **Cross-compile Harbour for arm64.** The app `.prg` + the ccharbour core are
   compiled to C by the host `harbour.exe`, then the C is cross-compiled with the
   Android NDK clang and linked against prebuilt `libharbour` static libs. The app
   links the **multi-thread VM** (`libhbvmmt`) so several agents can run at once.

3. **Host the same HTML in an Android WebView.** Instead of `TWebView2` (Edge),
   the chat panel lives in the system `WebView`. `evaluateJavascript` replaces
   `oWeb:Eval`, and an `@JavascriptInterface` replaces `SendToFWH` — a one-to-one
   mapping, so the HTML/JS chat panel (Tailwind + marked.js) is essentially shared.

4. **Bridge JS ⇄ Harbour over JNI.** `android_webview.c` exposes `AWV_Eval`,
   `AWV_SetHtml`, `AWV_WaitEvent` and `AWV_Http` to Harbour, and routes JS calls
   into per-agent event queues (pthread mutex + condvar) that the Harbour threads
   block on. No callback re-entrancy: a turn never runs inside a JS→native call.

5. **Borrow Android's TLS for the LLM call.** Rather than cross-compiling
   libcurl + OpenSSL, the transport codeblock calls a Java `HttpsURLConnection`
   through JNI. Smaller binary, native certificate handling.

6. **Make the filesystem writable.** Android's process CWD is `/` (read-only), so
   on startup the JNI layer `chdir`s into the app's private `getFilesDir()` — now
   `read`/`write`/`edit`/`memory` work with relative paths.

7. **Multiple agents, synchronized.** Each agent is an independent Harbour thread
   (`hb_threadStart`) with its own client, history and tab. The `dispatch_team`
   tool lets the model fan a task into 2–4 parallel sub-agents and **join**
   (`hb_threadJoin`) them before returning the combined answer.

The whole thing was developed and verified **on a physical device**, iterating
through the real failure modes — an `hb_threadStart` no-op on the single-thread
VM, a `const` symbol table crashing `hb_vmProcessSymbols`, `TEXT INTO` eating
backslashes in the embedded JS, codepage mojibake through `evaluateJavascript` —
each captured in *Engineering notes* below.

## Build from source

### Prerequisites

| Tool                 | Default path (override with env)                 |
|----------------------|--------------------------------------------------|
| Android NDK r26+     | `C:\Android\android-ndk-r26d` (`NDK_ROOT`)       |
| Android SDK + bt 34  | `C:\Android\Sdk`                                 |
| JDK 17               | `C:\Android\jdk17\...` (`JDK_ROOT`)              |
| Harbour for Android  | prebuilt libs in `C:\HarbourAndroid` (MT VM)     |
| Host Harbour         | `C:\harbour` (hbmk2/hbpp bootstrap)              |
| ccharbour sources    | `C:\ccharbour\src`                               |

### Compile + sign the APK

```bash
cd samples/AgenticAI/Android
bash build-apk.sh          # -> build/agents.apk
```

The script: compiles the app PRG + the ccharbour core with the host `harbour.exe`,
cross-compiles the generated C with NDK clang for `arm64-v8a`, links against the
**multi-thread** Harbour VM (`libhbvmmt`), packages with `aapt2`/`d8`, and signs
with a debug keystore.

### Install + run

```bash
adb install -r build/agents.apk
adb shell am start -n com.harbour.agenticai/.MainActivity
```

Provide an API key — either:

```bash
adb push deepseek.key /data/local/tmp/deepseek.key   # read on startup
```

or type `/key <your-api-key>` inside the app.

---

## Engineering notes (gotchas solved)

- **`hb_threadStart` did nothing** until the app was linked against `libhbvmmt`
  (the MT VM); the single-thread VM ships a no-op stub. Multi-agent needs the MT VM.
- **`hb_vmProcessSymbols` crashed** registering the C functions — the `HB_SYMB`
  table must **not** be `const` (the VM writes back resolved dynsym pointers).
- **WebView2/WebView bound calls are not re-entrant** — a turn cannot run inside a
  JS→native callback, so prompts are queued and launched from a separate context.
- **`TEXT INTO` is C-escape-processed** — the embedded JS must stay backslash-free
  (`String.fromCharCode(10)` instead of `\n`, character-class regexes).
- **Non-ASCII via `evaluateJavascript`** is `\uXXXX`-escaped to survive codepage
  conversion (avoids mojibake).
- **Android process CWD is `/` (read-only)** — the app `chdir`s to its private
  files dir so the `memory`/`write`/`edit` tools work.

---

## Roadmap

- Token-by-token streaming over the Java transport (currently the answer arrives
  in one piece).
- Synchronized agent orchestration (dispatch sub-tasks across agents and join).
- Persistent key storage in the app's private storage + an in-app key screen.

---

## Credits

Developed by **© FiveTech Software 2026**.
Contact: [antonio.fivetech@gmail.com](mailto:antonio.fivetech@gmail.com)

Built with [Harbour](https://harbour.github.io/) ·
[FiveWin (FWH)](https://www.fivetechsoft.com/) ·
the **ccharbour** agentic engine ·
[Tailwind CSS](https://tailwindcss.com/) · [marked.js](https://marked.js.org/).
