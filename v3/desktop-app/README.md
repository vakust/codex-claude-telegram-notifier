# Notifier V3 Desktop App (Skeleton)

Electron desktop shell for the API-first control center.

## Scope in this commit

1. Main window shell
2. Broker feed loading
3. Quick action command dispatch
4. Minimal visual status and debug feed panel

## Run

```powershell
cd C:\001_dev\notifier\v3\desktop-app
npm install
npm start
```

Environment overrides:

1. `V3_API_URL` (default: `http://127.0.0.1:8787`)
2. `V3_MOBILE_TOKEN` (default: `dev-mobile-token`)

## Notes

1. This is a skeleton for iterative UX and reliability work.
2. Existing Telegram flow is untouched.
