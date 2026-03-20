# Notifier V3 iOS App (Skeleton)

SwiftUI companion app skeleton for API-first Notifier v3.

## Scope in this branch

1. Persisted API URL + access token (`UserDefaults`)
2. Pair device via `POST /v1/mobile/pair/start`
3. Refresh access token via `POST /v1/mobile/auth/refresh`
4. Feed loading + quick action commands with 401 retry
5. Polling feed updates in background while app is active
6. Tab-based UX (`Codex` / `Cloud Code` / `All`) with action grouping
7. Event cards with screenshot preview + fullscreen open
8. Command parity with Android core flow:
   - `continue`, `fix_retest`, `shot`, `last_text` for Codex and Cloud Code
   - per-target `custom` prompt send (`metadata.custom_text`)
9. Fullscreen screenshot gestures: pinch-to-zoom, pan, double-tap reset
10. Local in-app notifications parity:
   - notification permission request
   - notification + sound toggles
   - test local notification action

## Structure

1. `project.yml` for XcodeGen
2. `NotifierV3/` Swift sources

## Quick start

1. Install XcodeGen.
2. Run:

```bash
cd v3/ios-app
xcodegen generate
```

3. Open generated `NotifierV3.xcodeproj` in Xcode.
4. Run on iPhone or iOS Simulator from Xcode.

## Notes

1. Uses dev defaults (`http://127.0.0.1:8787`, `dev-mobile-token`) until paired.
2. Telegram production path is unchanged.
3. Edited on Windows, but iOS build/simulator validation must be done on macOS (Xcode requirement).
