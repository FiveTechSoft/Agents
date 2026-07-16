# Changelog

## [2.0.0] ? 2026-07-16

### Highlights
- **Harbour-standard keyboard** (hbIDE style): `Inkey()` + `hb_keyStd()` / `hb_keyChar()`; no more silent input on Linux/WSL.
- **Linux build**: `gttrm` + **static** Harbour link; binary at repo root without `libharbour.so`.
- **Repo layout 2.0**: binaries at root; `source/`, `android/`, `scripts/`, `screenshots/`, `.agents/`.
- **`/demo`**: full random offline session (cards + most slash commands, no API key).
- **`/help`**: complete command list (plan, goal, tools, skills, provider, tasks, loop, ?).

### Fixed
- Prompt box did not show typed characters on Linux (`hb_keyVal` returned 0 for plain ASCII).
- VT/ANSI enable path for non-Windows terminals so the persistent prompt box mounts.
- Secrets: `.agents/settings.json` is gitignored; only `settings.example.json` is shipped (no API keys).

### Changed
- Build helpers: `./go.sh` / `source/go.sh` ? `./agents` at root.
- README paths and repository layout section updated.

## [0.8.28] ? previous console TUI baseline
