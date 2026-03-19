# Notifier V3 Android App (Skeleton)

Android companion app for the API-first Notifier V3 backend.

Current scope:
- Configure backend URL + mobile token.
- Persist API URL and token between app restarts.
- Connection chip with backend health status.
- Auto-fallback between `127.0.0.1` and `10.0.2.2` local URLs.
- Fetch mobile feed (`GET /v1/mobile/feed`).
- Send quick commands (`POST /v1/mobile/commands`) for Codex/Cloud Code.

## Run (Android Studio)

1. Open this folder in Android Studio: `v3/android-app`.
2. Let Gradle sync.
3. Run the `app` target on an emulator/device (API 26+).
4. In app UI, set:
   - `API URL` (example: `http://10.0.2.2:8787` for emulator to local host)
   - `Mobile Token` (example: `dev-mobile-token`)

## Run (CLI, Windows PowerShell)

```powershell
cd C:\001_dev\notifier\v3\android-app
.\scripts\local-build.ps1
```

Build artifact:

- `C:\001_dev\notifier\v3\android-app\app\build\outputs\apk\debug\app-debug.apk`

## Real USB phone (recommended after emulator)

1. On Android phone enable Developer options + USB debugging.
2. Connect via USB and approve "Allow USB debugging" prompt on the phone.
3. Start local backend (port `8787` by default).
4. Deploy and launch:

```powershell
cd C:\001_dev\notifier\v3\android-app
.\scripts\deploy-device.ps1
```

This script:

- builds `app-debug.apk`
- installs it on authorized USB device
- configures `adb reverse tcp:8787 tcp:8787`
- starts the app automatically

## Notes

- This is a bootstrap implementation to validate end-to-end API flow.
- No secure keystore/token persistence yet (will be added in hardening phase).
