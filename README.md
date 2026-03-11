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

## Security and sharing
- Never share `.env.ps1` (contains your bot token).
- Before publishing/sharing, rotate token in BotFather if it was ever exposed.
- Use `powershell -ExecutionPolicy Bypass -File c:\001_dev\notifier\scripts\prepare-share.ps1` to create a safe ZIP without secrets/logs/state.
- Friend onboarding text is in `ONBOARDING.md` (one short paragraph).
