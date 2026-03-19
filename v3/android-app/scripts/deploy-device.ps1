param(
    [string]$SdkRoot = "C:\Users\Vitaly\AppData\Local\Android\Sdk",
    [string]$PackageName = "com.vakust.notifierv3",
    [int]$BackendPort = 8787
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $SdkRoot "platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    throw "adb not found: $adb"
}

Write-Host "[1/5] Build debug APK..."
& (Join-Path $PSScriptRoot "local-build.ps1") -SdkRoot $SdkRoot

Write-Host "[2/5] Start adb server..."
& $adb start-server | Out-Null

Write-Host "[3/5] Detect authorized USB devices..."
$lines = & $adb devices
$devices = @()
foreach ($line in $lines) {
    if ($line -match "^\s*([^\s]+)\s+device\s*$") {
        $devices += $matches[1]
    }
}
if ($devices.Count -eq 0) {
    throw "No authorized Android device found. Check USB cable and confirm 'Allow USB debugging' on phone."
}

$apk = Join-Path $PSScriptRoot "..\app\build\outputs\apk\debug\app-debug.apk"
$apk = (Resolve-Path $apk).Path

Write-Host "[4/5] Install APK on $($devices[0])..."
& $adb -s $devices[0] install -r $apk

Write-Host "[5/5] Configure reverse port and launch app..."
& $adb -s $devices[0] reverse "tcp:$BackendPort" "tcp:$BackendPort"
& $adb -s $devices[0] shell am start -n "$PackageName/.MainActivity"

Write-Host ""
Write-Host "Done."
Write-Host "- Device: $($devices[0])"
Write-Host "- APK: $apk"
Write-Host "- Backend URL in app: http://127.0.0.1:$BackendPort"
Write-Host "- Token in app: dev-mobile-token (or your configured mobile token)"
