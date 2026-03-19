# Notifier V3 Backend Core (Skeleton)

This is an API-first broker skeleton for the v3 product track.

It is intentionally minimal and isolated from the existing Telegram controller.

## What is included

1. Health endpoint
2. Pair-code flow (admin create -> mobile consume)
3. Agent event ingestion
4. Mobile command submission
5. Agent pending-command polling
6. Agent command acknowledgements
7. Mobile event feed

## Start

```powershell
cd C:\001_dev\notifier\v3\backend
npm start
```

Default bind: `http://127.0.0.1:8787`

## Auth tokens (dev defaults)

Environment variables:

1. `V3_AGENT_TOKEN` (default: `dev-agent-token`)
2. `V3_MOBILE_TOKEN` (default: `dev-mobile-token`)
3. `V3_ADMIN_TOKEN` (default: `dev-admin-token`)

## Useful local checks

Health:

```powershell
curl http://127.0.0.1:8787/health
```

Create pair code (admin):

```powershell
curl -X POST http://127.0.0.1:8787/v1/admin/pair/code `
  -H "Authorization: Bearer dev-admin-token"
```

End-to-end smoke:

```powershell
cd C:\001_dev\notifier\v3\backend
npm run smoke
```

## Notes

1. Storage is in-memory only (no persistence yet).
2. This is a development skeleton for architecture validation.
3. Telegram production path remains unchanged.
