# Mobile Companion MVP Spec

Date: 2026-03-19

## MVP Objective
Deliver a production-testable mobile companion for iOS and Android while preserving Telegram workflow.

## User Stories

1. As a user, I can pair my desktop notifier with the mobile app in under 2 minutes.
2. As a user, I receive completion notifications with short preview text.
3. As a user, I can tap a button to send `Continue`, `Fix+Retest`, or `Screenshot`.
4. As a user, I can open recent events and screenshots in one feed.
5. As a user, I can always fall back to Telegram if mobile channel fails.

## Platforms

1. iOS (latest + previous major).
2. Android (API 26+).

## UX Surfaces

1. Pairing Screen
2. Home Feed
3. Session Details
4. Actions Panel
5. Settings and Channel Health

## Core Features

1. Device pairing via one-time code generated on desktop.
2. Push notifications for:
   1. Codex completion
   2. Claude Code completion
   3. Action delivery status
3. Action buttons:
   1. Continue
   2. Fix+Retest
   3. Last Text
   4. Shot Codex
   5. Shot CC
4. Structured feed:
   1. timestamp
   2. source app
   3. summary text
   4. screenshot thumbnail if present
5. Health indicators:
   1. controller online/offline
   2. Telegram fallback active
   3. last successful command time

## Non-Goals (MVP)

1. In-app prompt composer for long custom prompts.
2. Multi-user tenant management.
3. Billing and subscription flows.
4. Rich analytics dashboards.

## Reliability Model

1. Desktop notifier publishes event to broker.
2. Broker fans out to:
   1. mobile push pipeline
   2. Telegram fallback pipeline
3. If mobile push fails, Telegram still receives core notification.

## Security Requirements

1. No bot tokens stored in plain text on mobile.
2. Pairing codes are short-lived and one-time.
3. All API calls use TLS and signed auth tokens.
4. Screenshot URLs must be signed and expiring.

## Acceptance Criteria

1. New user pairs device and gets first notification in <= 2 minutes.
2. `Continue` action reaches desktop and returns ack status.
3. Screenshot request returns image in feed and push.
4. Telegram fallback still works when mobile is disabled.
