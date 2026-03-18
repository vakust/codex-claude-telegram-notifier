# Mobile Companion Product Direction

Date: 2026-03-19

## Problem
Current remote control works through Telegram only. It is reliable and quick to use, but:

1. UX is limited for non-technical users.
2. Event history is fragmented.
3. Screenshots and long outputs are hard to browse over time.
4. Product branding and onboarding are weak.

## Product Goal
Build a mobile companion app (iOS + Android) that improves UX without breaking the working Telegram channel.

## Key Principle
Telegram remains first-class fallback until mobile reaches production reliability.

## Product Positioning
The mobile app is a companion control center for desktop agent sessions:

1. receive completion notifications;
2. view structured results;
3. request screenshots;
4. trigger safe action buttons;
5. inspect session history.

## Why Not Replace Telegram Immediately
Telegram currently provides:

1. delivery infrastructure;
2. simple auth model;
3. low operational overhead;
4. robust fallback when custom services fail.

Immediate replacement would increase risk and likely break current reliability.

## Recommended Rollout

1. Keep Telegram as baseline.
2. Add backend broker for structured events and mobile delivery.
3. Release mobile app as optional channel.
4. Move to app-first only after reliability and support metrics are met.

## Success Metrics

1. Notification delivery success >= 99%.
2. P95 action response latency <= 3s (for command ack).
3. Zero secret leakage incidents.
4. At least 80% of test users can complete setup without terminal help.

## Scope Boundaries

In scope:

1. mobile notifications and action buttons;
2. session feed and screenshot gallery;
3. pairing flow from desktop to mobile;
4. secure token handling in backend and apps.

Out of scope for initial MVP:

1. full desktop automation logic rewrite;
2. replacing Telegram transport completely;
3. advanced billing/paywall mechanics.
