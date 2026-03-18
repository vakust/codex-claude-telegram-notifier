# Notifier V3 macOS App (Skeleton)

macOS companion app for API-first Notifier V3.

Current scope:
- Configure backend URL + mobile token.
- Read feed (`GET /v1/mobile/feed`).
- Send quick actions (`POST /v1/mobile/commands`) for Codex and Cloud Code.

## Build

1. Open `v3/macos-app` in your macOS environment.
2. Run `xcodegen generate` to create Xcode project.
3. Open generated project in Xcode and run `NotifierV3Mac`.

## Notes

- This is a bootstrap shell for product direction validation.
- Secure token storage (Keychain) is planned in hardening.
