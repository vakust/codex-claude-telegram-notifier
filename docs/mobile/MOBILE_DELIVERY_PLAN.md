# Mobile Companion Delivery Plan

Date: 2026-03-19

## Branching Strategy

1. `main`: stable production baseline.
2. `codex/feature-mobile-companion`: product and API design + broker foundation.
3. `codex/feature-mobile-ios`: iOS implementation.
4. `codex/feature-mobile-android`: Android implementation.
5. `codex/feature-mobile-backend`: broker service implementation.

## Phase 0: Design Freeze

Outputs:

1. Product direction approved.
2. MVP scope approved.
3. API draft approved.

Gate:

1. No open blockers on auth, push, or fallback policy.

## Phase 1: Backend Broker MVP

Tasks:

1. Agent event ingestion endpoint.
2. Mobile command endpoint.
3. Event feed persistence and pagination.
4. Push worker skeleton (APNs/FCM adapter boundaries).
5. Audit log and idempotency keys.

Gate:

1. End-to-end local test with mocked mobile client.

## Phase 2: Mobile Apps MVP

Tasks:

1. Pairing screen and token storage.
2. Feed screen with completion cards.
3. Action buttons with command acks.
4. Screenshot rendering (signed URLs).
5. Health status display.

Gate:

1. Internal dogfooding with at least 3 sessions and no data-loss events.

## Phase 3: Telegram Coexistence Hardening

Tasks:

1. Unified event fanout rules.
2. Fallback policy:
   1. default: mobile + Telegram
   2. optional: mobile-only
3. Alerting for broker/push failures.

Gate:

1. Mobile failure does not break Telegram channel.

## Phase 4: Beta Release

Tasks:

1. Signed beta builds for iOS and Android.
2. Setup guide for non-technical users.
3. Crash/error telemetry.

Gate:

1. Reliability and latency metrics pass target thresholds.

## Risk Register

1. Push reliability variance across vendors.
2. Secure pairing implementation mistakes.
3. Complexity creep if Telegram replacement starts too early.
4. Screenshot storage cost and retention policy.

## Recommended Next Execution Order

1. Build backend broker skeleton.
2. Wire desktop notifier event publishing in optional mode.
3. Ship minimal iOS and Android feed-only build.
4. Enable action buttons after feed reliability is validated.
