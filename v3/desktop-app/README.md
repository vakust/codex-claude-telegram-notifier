# Notifier V3 Desktop App (Skeleton)

Electron desktop shell for the API-first control center.

## Scope in this branch

1. Main window shell with persisted API/mobile token
2. Pair device flow (`POST /v1/mobile/pair/start`)
3. Refresh-token flow (`POST /v1/mobile/auth/refresh`) on startup and 401 retry
4. Broker feed loading + quick action command dispatch
5. Health/workspace status and debug feed panel

## Run

```powershell
cd C:\001_dev\notifier\v3\desktop-app
npm install
npm run check
npm run smoke
npm start
```

Environment overrides:

1. `V3_API_URL` (default: `http://127.0.0.1:8787`)
2. `V3_MOBILE_TOKEN` (default: `dev-mobile-token`)

`npm run smoke` requires a running local backend on the configured `V3_API_URL`.

One-command local smoke (PowerShell):

```powershell
cd C:\001_dev\notifier\v3\desktop-app
.\scripts\local-smoke.ps1
```

## Notes

1. This is a skeleton for iterative UX and reliability work.
2. Existing Telegram flow is untouched.
3. Token persistence is currently via localStorage (desktop app profile).
