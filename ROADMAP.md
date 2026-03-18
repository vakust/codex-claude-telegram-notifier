# Notifier Roadmap (Next Stage)

Date: 2026-03-18

## Goal
Keep `main` stable and move new work into isolated feature branches:

1. macOS script version (for technical users)
2. macOS app (simple GUI launcher/controller)
3. Desktop app (cross-platform UX direction)

## Branching Rules

1. `main` is production-stable only.
2. Each big stream gets its own branch from `main`.
3. No direct experimental commits to `main`.
4. Merge to `main` only after smoke tests and manual Telegram checks.

Planned branches:

1. `codex/feature-macos-script`
2. `codex/feature-macos-app`
3. `codex/feature-desktop-app`

## Stream A: macOS Script (MVP)

### Scope

1. Start/stop controller on macOS.
2. Telegram command handling parity for core buttons:
   1. Continue
   2. Fix+Retest
   3. Last Text
   4. Screenshot request
3. Replace Windows-specific automation with macOS-compatible approach.

### Technical Targets

1. Replace UI Automation calls with AppleScript/Accessibility flow.
2. Replace window screenshot path with macOS capture method.
3. Keep `.env` token/chat model and command templates compatible.

### Exit Criteria

1. User can run one command and start controller on macOS.
2. Continue/Last Text/Screenshot work reliably in Telegram.
3. No regressions in Windows branch.

## Stream B: macOS App (GUI)

### Scope

1. Minimal app window for non-technical users.
2. Fields:
   1. Bot token
   2. Chat ID
   3. Target app mode
3. Buttons:
   1. Start
   2. Stop
   3. Check status

### Technical Targets

1. Store secrets in macOS Keychain (not in repo, not in plaintext logs).
2. Add optional "Start at login".
3. Show clear runtime state and last error.

### Exit Criteria

1. Non-technical user can configure and run without terminal.
2. App survives restart and can recover controller state.
3. Secrets are not committed and not leaked to logs.

## Stream C: Desktop App (Cross-Platform Direction)

### Scope

1. Common UX shell for Windows + macOS.
2. Platform adapters for automation and screenshot.
3. Shared command/config model.

### Technical Targets

1. Separate core controller logic from OS-specific adapters.
2. Keep Telegram behavior compatible with current stable semantics.
3. Add packaging story:
   1. Windows installer/exe
   2. macOS app bundle

### Exit Criteria

1. Same user-facing flow on both OSes.
2. Stable Start/Stop/Status/Screenshot behavior.
3. Clear release build process.

## Suggested Delivery Order

1. A1: macOS script bootstrap + health check
2. A2: macOS Continue/Last Text
3. A3: macOS screenshot + reliability pass
4. B1: macOS GUI MVP
5. B2: secure credential storage + startup
6. C1: shared core extraction
7. C2: cross-platform desktop packaging

## Merge Policy to Main

Before any merge:

1. `git status` clean
2. smoke test pass (manual Telegram flow)
3. no secrets in diff
4. short changelog note in PR
