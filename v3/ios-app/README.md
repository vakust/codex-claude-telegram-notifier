# Notifier V3 iOS App (Skeleton)

SwiftUI companion app skeleton for API-first Notifier v3.

## Scope in this commit

1. Pairing + token bootstrap model
2. Feed loading from broker API
3. Quick action command calls
4. Basic status/errors rendering

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

## Notes

1. Uses placeholder dev tokens by default.
2. Telegram production path is unchanged.
