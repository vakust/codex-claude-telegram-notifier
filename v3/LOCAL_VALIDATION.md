# V3 Local Validation Checklist

This checklist validates the API-first V3 track without touching Telegram legacy flow.

## 1. Backend smoke

```powershell
cd C:\001_dev\notifier\v3\backend
npm run smoke
```

Expected: JSON with `ok: true`, `command_id`, `event_id`, `feed_count`.

## 2. Desktop smoke (against local backend)

Start backend (terminal A):

```powershell
cd C:\001_dev\notifier
$env:PORT='8787'
$env:HOST='127.0.0.1'
$env:V3_ADMIN_TOKEN='dev-admin-token'
$env:V3_MOBILE_TOKEN='dev-mobile-token'
$env:V3_AGENT_TOKEN='dev-agent-token'
node v3/backend/src/server.js
```

Run desktop smoke (terminal B):

```powershell
cd C:\001_dev\notifier\v3\desktop-app
.\scripts\local-smoke.ps1
```

Expected: health check + syntax checks + smoke JSON with `ok: true`.

## 3. Android APK build

```powershell
cd C:\001_dev\notifier\v3\android-app
.\scripts\local-build.ps1
```

Expected artifact:

- `C:\001_dev\notifier\v3\android-app\app\build\outputs\apk\debug\app-debug.apk`

## 4. Android USB deploy (real device)

Prerequisites:

1. USB debugging enabled on phone.
2. Device is authorized in adb (`adb devices` shows `device`).
3. Local backend running on `127.0.0.1:8787`.

Deploy:

```powershell
cd C:\001_dev\notifier\v3\android-app
.\scripts\deploy-device.ps1
```

Expected:

1. APK install success.
2. `adb reverse tcp:8787 tcp:8787` applied.
3. App launched on device and status shows backend connected.

## 5. Optional UI evidence capture

```powershell
$adb='C:\Users\Vitaly\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb -s <device-id> shell screencap -p /sdcard/Download/notifier-v3-proof.png
& $adb -s <device-id> pull /sdcard/Download/notifier-v3-proof.png C:\001_dev\notifier\logs\notifier-v3-proof.png
```

## Safety note

V3 testing and branches are isolated from existing Telegram controller scripts and runtime.
