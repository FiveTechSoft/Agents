# Changelog

## [2.2.0] — 2026-07-16

### Fixed
- **Single Enter for slash commands** (`/exit`, `/quit`, `/bye`, `/help`, …):
  prompt idle submits on Enter via pure Harbour `Inkey(0)`; removed the
  post-Enter `KeyPending` drain that could hang on CR-only terminals.
- **`AGCON_KeyPending` / `_ReadKeyNB`**: true non-blocking peeks with
  `NextKey` (never block with `Inkey(0)` when only checking for input).

### Added
- **Auto-Ollama**: with no API key, if a local Ollama daemon answers on
  port 11434, switch to it, pick an installed model, save settings, and
  show a switch notice plus `[model -> …]` under the banner.

### Binaries
- Linux static `./agents` (gttrm) and Windows `agents.exe` (gtwin) for 2.2.0.

## [2.1.0] ? 2026-07-16

### Fixed
- **`/help`**: normalize CR/LF/BOM so the command always matches; pin prompt box and redraw so the command list is visible above the TUI.
- **`/exit` / `/quit` / `/bye`**: same robust parsing; clean terminal teardown (drop scroll region, restore cooked TTY) and print `[bye]`.
- Accept bare `help`, `?`, `exit`, `quit`, `bye` as aliases.

### Changed
- `AGREPL_ShowHelp` / `AGREPL_DoExit` helpers for reliable slash-command UX in box mode.

## [2.0.0] ? 2026-07-16

### Highlights
- Harbour-standard keyboard (`Inkey` + `hb_keyStd` / `hb_keyChar`); Linux `gttrm` + static binary.
- Repo layout 2.0: binaries at root; `source/`, `android/`, `scripts/`, `screenshots/`.
- `/demo` full random offline session; `/help` command list.
- Local `settings.json` gitignored (no API keys in tree).

## [0.8.28] ? previous

- Console TUI baseline with tools, skills, multi-agent dispatch.
