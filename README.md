# Inspire Notifier
Remote Telegram control for desktop coding agents: Codex Desktop + Claude Code Desktop.

This project turns your phone into a practical command console for local AI coding sessions.  
Press a button in Telegram, push a prompt into the active desktop app, and get completion updates back in chat.

## Why this is useful
When long-running tasks are in progress, you should not need to sit in front of the same machine all the time.

With this notifier you can:
- send `Continue` / `Fix+Retest` prompts remotely;
- keep one shared custom prompt and send it to either app;
- receive completion notifications with latest assistant text;
- keep secrets local and out of git.

## What it feels like
1. You run Codex or Claude Code on your Windows machine.
2. You leave the desk, open Telegram, tap `Continue`.
3. The notifier focuses the desktop app and sends the prompt.
4. You receive completion text in Telegram when the turn finishes.

## Platform support
- Windows + PowerShell (current implementation).
- Not implemented for macOS/Linux yet.

## Next product track (mobile companion)
Planned iOS/Android companion direction and implementation plan:

1. `docs/mobile/PRODUCT_DIRECTION.md`
2. `docs/mobile/MOBILE_MVP_SPEC.md`
3. `docs/mobile/MOBILE_API_CONTRACT.md`
4. `docs/mobile/MOBILE_DELIVERY_PLAN.md`

## Quick start
1. Create a Telegram bot with BotFather and copy the token.
2. Bootstrap local config:
   - `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\bootstrap-telegram.ps1 -BotToken "<YOUR_BOT_TOKEN>"`
   - This writes local `.env.ps1` with `TG_BOT_TOKEN` and `TG_CHAT_ID`.
3. Start controller:
   - `c:\001_dev\notifier\RUN_telegram_controller.bat`
4. In Telegram, open your bot chat, press `Start`, then try:
   - `Continue` (Codex),
   - `CC: Continue` (Claude Code).

If messages do not arrive:
- verify chat with the bot is started;
- run `c:\001_dev\notifier\RUN_test_telegram.bat`.

## Telegram controls
Prompt templates used by main action buttons:
- `Continue` / `CC: Continue`:
  `If everything is clear and you know what to do next, continue working and testing in this thread. Provide brief status updates.`
- `Fix+Retest` / `CC: Fix+Retest`:
  `Continue testing. If you find errors, fix them, then run tests again. Keep working until all bugs for this task are fixed. Provide brief status updates.`

Codex buttons:
- `Continue`
- `Fix+Retest`
- `Send Custom`
- `Last Text`
- `Bind Point`

Claude Code buttons:
- `CC: Continue`
- `CC: Fix+Retest`
- `CC: Custom`
- `CC: Last Text`
- `CC: Bind`

Shared buttons:
- `Set Custom`: next non-command message becomes shared custom prompt.
- `Show Custom`
- `Clear Custom`
- `Status`: controller runtime + last wrapper-task state.
- `Stop`: stops local wrapper PID only; does not close Codex/Claude windows.

Note: `Send Custom` and `CC: Custom` use the same shared custom prompt value.

## How it works
Core files:
- `scripts/telegram-controller.ps1`:
  Telegram long-polling, command routing, completion watchers, keyboard handling.
- `scripts/codex-bridge.ps1`:
  Focus + input delivery for Codex Desktop.
- `scripts/cc-bridge.ps1`:
  Focus + input delivery for Claude Code Desktop.
- `scripts/send-telegram.ps1`:
  Telegram API sender helper.

Runtime directories:
- `state/`: offsets, prompt state, watcher keys, task-state files.
- `logs/`: controller and bridge logs.

Flow:
1. Telegram update is received by `telegram-controller.ps1`.
2. Controller maps text/button to a Codex or CC action.
3. Bridge focuses the target window and sends input.
4. Controller replies in Telegram and posts completion notifications.

## Input targeting strategy
Common:
1. Find target window (`Codex` or `claude`) with non-zero `MainWindowHandle`.
2. Restore/focus (`ShowWindow`, `SetForegroundWindow`, `AppActivate` retries).
3. Resolve input target via UIA and send prompt.

Codex bridge:
- Placeholder-name targeting first (`Ask for follow-up changes`, etc.).
- Fallback scored `ControlType.Edit` candidates near bottom.
- Extra resilience fallbacks: saved bind point, bottom offsets, percentages.

Claude Code bridge:
- Placeholder-name targeting first (`Reply...`, `Reply to Claude...`, `Type a message...`, `How can Claude help?`).
- UIA anchor fallback via `Bypass permissions` if placeholder is absent.
- No geometric (`bottom/%/saved`) send candidates.
- No no-click (`Esc/Ctrl+A/Ctrl+V`) path.
- Uses `delivered=trusted` when JSONL confirmation is delayed to prevent duplicate send spam.

## Security
Secrets remain local:
- `.env.ps1` stores token/chat id and is ignored by git.
- `state/`, `logs/`, `dist/`, `*.pid`, `*.log` are ignored by git.

Before sharing/publishing:
1. Run:
   `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\prepare-share.ps1`
2. Share generated ZIP (no secrets/runtime artifacts).
3. If token was ever exposed, rotate it in BotFather before public release.

Current repository safety status:
- `.env.ps1` is not tracked.
- No Telegram token-like pattern found in `HEAD` or git history.

## For contributors
If you want to improve reliability/UI:
- keep README and keyboard behavior synchronized;
- preserve non-destructive defaults (`Stop` should not close app windows);
- prioritize deterministic input targeting over blind key injection.

If this project helps your workflow, star the repository and share your setup notes.
