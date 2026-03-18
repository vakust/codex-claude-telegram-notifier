# Mobile Companion API Contract (Draft)

Date: 2026-03-19

## Overview
This contract defines the backend broker interface between desktop notifier and mobile apps.

## Actors

1. Desktop Controller Agent
2. Broker API
3. Mobile Client
4. Push Worker

## Event Envelope

All events share:

```json
{
  "event_id": "evt_01H...",
  "event_type": "completion|action_ack|screenshot|health",
  "source": "codex|claude_code|controller",
  "session_key": "2026-03-19T00:12:02Z|msg_...",
  "created_at": "2026-03-19T00:12:02Z",
  "payload": {}
}
```

## Desktop -> Broker

### POST `/v1/agents/events`

Purpose: publish completion/action/screenshot events.

Headers:

1. `Authorization: Bearer <agent_token>`
2. `Content-Type: application/json`

Response:

```json
{
  "ok": true,
  "event_id": "evt_01H..."
}
```

### POST `/v1/agents/actions/ack`

Purpose: confirm command execution result from desktop side.

Body:

```json
{
  "command_id": "cmd_01H...",
  "status": "delivered|failed|timeout",
  "message": "optional detail",
  "completed_at": "2026-03-19T00:15:42Z"
}
```

## Mobile -> Broker

### POST `/v1/mobile/pair/start`

Purpose: start pairing with one-time code.

Body:

```json
{
  "pair_code": "583-921",
  "device_name": "iPhone 15",
  "platform": "ios"
}
```

Response:

```json
{
  "ok": true,
  "access_token": "jwt...",
  "refresh_token": "jwt...",
  "workspace_id": "ws_01H..."
}
```

### GET `/v1/mobile/feed?cursor=...`

Purpose: fetch event feed.

Response:

```json
{
  "items": [
    {
      "event_id": "evt_01H...",
      "event_type": "completion",
      "source": "claude_code",
      "title": "Done 19:42 UTC",
      "preview": "Short text preview...",
      "screenshot_url": "https://.../signed",
      "created_at": "2026-03-19T00:42:04Z"
    }
  ],
  "next_cursor": "..."
}
```

### POST `/v1/mobile/commands`

Purpose: send command from mobile to desktop controller.

Body:

```json
{
  "target": "codex|cc",
  "action": "continue|fix_retest|last_text|shot",
  "metadata": {
    "client_request_id": "req_01H..."
  }
}
```

Response:

```json
{
  "ok": true,
  "command_id": "cmd_01H...",
  "status": "accepted"
}
```

## Push Events

Push payload should be compact:

```json
{
  "type": "completion",
  "source": "codex",
  "title": "Codex done",
  "event_id": "evt_01H..."
}
```

Deep-link app to feed item by `event_id`.

## Failure Handling

1. Broker stores event even if push fails.
2. Mobile can always pull missed events through feed API.
3. Telegram fallback may still send critical completion notifications.
