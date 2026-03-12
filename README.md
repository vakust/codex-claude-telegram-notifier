# Telegram Notifier for Codex + Claude Code (Windows)

Location: `c:\001_dev\notifier\`

## Quick start (4 steps)
1. Create a bot in Telegram via BotFather and copy the bot token.
2. Configure local secrets: run `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\bootstrap-telegram.ps1 -BotToken "<YOUR_BOT_TOKEN>"` (or fill `.env.ps1` from `.env.example.ps1` with `TG_BOT_TOKEN` and `TG_CHAT_ID`).
3. Start controller: `c:\001_dev\notifier\RUN_telegram_controller.bat`.
4. Open your bot chat, press `Start`, then use keyboard buttons (`Continue`, `CC: Continue`, etc.).

## Architecture
Core parts:
- `scripts/telegram-controller.ps1`: Telegram long-poll loop, command router, completion watchers.
- `scripts/codex-bridge.ps1`: focus + prompt delivery to Codex Desktop input.
- `scripts/cc-bridge.ps1`: focus + prompt delivery to Claude Code Desktop input.
- `scripts/send-telegram.ps1`: Telegram API sender helper.
- `state/*`: runtime state (offsets, watcher keys, custom prompt, task status).
- `logs/*`: controller/bridge logs.

Data flow:
1. Telegram message/button arrives in `telegram-controller.ps1`.
2. Controller routes to Codex or CC action.
3. Corresponding bridge focuses the app and sends prompt.
4. Controller reports action result and watcher completions back to Telegram.

## Telegram keyboard
Codex:
- `Continue`
- `Fix+Retest`
- `Send Custom`
- `Last Text`
- `Bind Point`

Claude Code:
- `CC: Continue`
- `CC: Fix+Retest`
- `CC: Custom`
- `CC: Last Text`
- `CC: Bind`

Common:
- `Set Custom`: next non-command message becomes shared custom prompt.
- `Show Custom`
- `Clear Custom`
- `Status`: controller runtime + last wrapper task state.
- `Stop`: stops only local wrapper task PID, does not close Codex/Claude app windows.

Note: `Send Custom` and `CC: Custom` use one shared custom prompt value.

## Input targeting
Common:
1. Find target process window (`Codex` or `claude`) with non-zero `MainWindowHandle`.
2. Restore/focus window (`ShowWindow`, `SetForegroundWindow`, `AppActivate` retries).
3. Resolve UI target via UIA and send prompt.

Codex (`scripts/codex-bridge.ps1`):
- UIA placeholder-name targeting first (includes `Ask for follow-up changes`).
- Fallback to scored `ControlType.Edit` candidates near bottom.
- Additional resilience fallbacks: saved bind point, bottom offsets, percentage points.

Claude Code (`scripts/cc-bridge.ps1`):
- Fast placeholder-name targeting first (`Reply...`, `Reply to Claude...`, `Type a message...`, `How can Claude help?`).
- If placeholder is absent, UIA anchor fallback from `Bypass permissions` button (click point above it).
- No geometric (`bottom/%/saved`) send candidates.
- No no-click (`Esc/Ctrl+A/Ctrl+V`) send path.
- Uses `delivered=trusted` after UIA send when JSONL append confirmation is delayed (prevents duplicate multi-click retries).

## Security and sharing
- Secrets stay local in `.env.ps1` (bot token/chat id).
- `.env.ps1`, `state/`, `logs/`, `dist/`, `*.pid`, `*.log` are ignored by git.
- Before sharing/publishing, rotate token in BotFather if it was ever exposed.
- Create safe share package without secrets/logs/state:
  `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\prepare-share.ps1`
- Short friend onboarding text is in `ONBOARDING.md`.
