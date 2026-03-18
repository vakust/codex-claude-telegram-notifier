# Notifier V3 Android App (Skeleton)

Android companion app for the API-first Notifier V3 backend.

Current scope:
- Configure backend URL + mobile token.
- Fetch mobile feed (`GET /v1/mobile/feed`).
- Send quick commands (`POST /v1/mobile/commands`) for Codex/Cloud Code.

## Run (Android Studio)

1. Open this folder in Android Studio: `v3/android-app`.
2. Let Gradle sync.
3. Run the `app` target on an emulator/device (API 26+).
4. In app UI, set:
   - `API URL` (example: `http://10.0.2.2:8787` for emulator to local host)
   - `Mobile Token` (example: `dev-mobile-token`)

## Notes

- This is a bootstrap implementation to validate end-to-end API flow.
- No secure keystore/token persistence yet (will be added in hardening phase).
