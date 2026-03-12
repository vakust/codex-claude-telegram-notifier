# Telegram Notifier for Codex Desktop (Windows)

Location: `c:\001_dev\notifier\`

## Quick start
1. Create config with your own Telegram credentials:
   - Option A: `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\bootstrap-telegram.ps1 -BotToken "<YOUR_BOT_TOKEN>"`
   - Option B: copy `.env.example.ps1` to `.env.ps1` and fill `TG_BOT_TOKEN` + `TG_CHAT_ID`.
2. Start controller: `c:\001_dev\notifier\RUN_telegram_controller.bat`
3. Send `/start` to your bot to see in-bot help.

## Telegram buttons
- `Continue`: send standard continue prompt to active Codex thread.
- `Fix+Retest`: send fix/retest cycle prompt to active Codex thread.
- `Set Custom`: next Telegram message is saved as custom prompt.
- `Send Custom`: send saved custom prompt to active Codex thread.
- `Show Custom`: show current saved custom prompt.
- `Clear Custom`: clear saved custom prompt.
- `Last Text`: send latest final assistant text from Codex session.
- `Status`: show local notifier state.
- `Stop`: stop local task wrapper PID (if running).

`Stop` does not close Codex Desktop and does not terminate the Codex app itself.

## How input targeting works (Codex + Cloud Code)
Common flow:
1. Find target app window process (`Codex` or `claude`) with non-zero `MainWindowHandle`.
2. Restore and focus that exact window (`ShowWindow` + `SetForegroundWindow` + `AppActivate` retries).
3. Resolve input coordinates via UI Automation (UIA) and click/send there.

### Codex specifics (`scripts/codex-bridge.ps1`)
- UIA first tries known composer placeholder names (including `Ask for follow-up changes`).
- If placeholder name changed, fallback scans `ControlType.Edit` controls and scores likely input fields near the bottom.
- `xterm-helper-textarea` remains a last-resort candidate.
- Codex also keeps geometric fallback candidates (saved bind point, bottom offsets, percentages) for resilience.

### Cloud Code specifics (`scripts/cc-bridge.ps1`)
- Uses UIA placeholder-name targeting first (fast list: `Reply...`, `Reply to Claude...`, `Type a message...`, `How can Claude help?`).
- If placeholder is not found, uses UIA anchor fallback from `Bypass permissions` button (click point above that control).
- Does **not** use geometric (`bottom/%/saved`) candidates in send flow.
- Does **not** use no-click (`Esc/Ctrl+A/Ctrl+V`) send path in Cloud Code bridge.
- Uses `delivered=trusted` for UIA send when JSONL append confirmation is delayed (to avoid duplicate retries/multi-click spam).

### Why this survives window moves
- Coordinates are taken fresh from the current window/UIA tree before each send.
- Stored bind point is normalized (`x_factor`, `y_factor`) relative to the current window size.
- `Bind Point` is optional and primarily useful for Codex fallback scenarios.

## Security and sharing
- Never share `.env.ps1` (contains your bot token).
- Before publishing/sharing, rotate token in BotFather if it was ever exposed.
- Use `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\prepare-share.ps1` to create a safe ZIP without secrets/logs/state.
- Friend onboarding text is in `ONBOARDING.md` (one short paragraph).
