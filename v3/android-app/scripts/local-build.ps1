param(
    [string]$SdkRoot = "C:\Users\Vitaly\AppData\Local\Android\Sdk",
    [string]$JavaHome = "C:\Program Files\Android\Android Studio\jbr"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SdkRoot)) {
    throw "Android SDK not found: $SdkRoot"
}
if (-not (Test-Path $JavaHome)) {
    throw "JAVA_HOME path not found: $JavaHome"
}

$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME = $SdkRoot
$env:JAVA_HOME = $JavaHome

$escaped = $SdkRoot -replace "\\", "\\\\"
Set-Content -Path (Join-Path $PSScriptRoot "..\\local.properties") -Value "sdk.dir=$escaped"

Push-Location (Join-Path $PSScriptRoot "..")
try {
    .\gradlew.bat --no-daemon assembleDebug testDebugUnitTest
} finally {
    Pop-Location
}
