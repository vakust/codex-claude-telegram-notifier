param(
    [string]$ApiUrl = "http://127.0.0.1:8787",
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8787,
    [string]$AdminToken = "dev-admin-token",
    [string]$MobileToken = "dev-mobile-token",
    [string]$AgentToken = "dev-agent-token",
    [switch]$SkipDesktop,
    [switch]$SkipAndroidBuild,
    [switch]$TryAndroidDeploy,
    [switch]$LeaveBackendRunning
)

$ErrorActionPreference = "Stop"

function Step($text) {
    Write-Host ""
    Write-Host "== $text ==" -ForegroundColor Cyan
}

function Test-BackendHealth([string]$Url) {
    try {
        $health = Invoke-RestMethod -Uri "$Url/health" -Method Get -TimeoutSec 3
        return ($health.ok -eq $true)
    } catch {
        return $false
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$v3Dir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $v3Dir

$backendDir = Join-Path $v3Dir "backend"
$desktopDir = Join-Path $v3Dir "desktop-app"
$androidDir = Join-Path $v3Dir "android-app"

$startedBackend = $false
$backendPid = $null

$results = [ordered]@{
    backend_running = $false
    backend_smoke = "skip"
    desktop_smoke = "skip"
    android_build = "skip"
    android_deploy = "skip"
}

try {
    Step "Backend availability"
    if (Test-BackendHealth -Url $ApiUrl) {
        $results.backend_running = $true
        Write-Host "Backend already reachable at $ApiUrl"
    } else {
        if (-not (Test-Path $backendDir)) {
            throw "Backend directory not found: $backendDir"
        }
        Write-Host "Backend not reachable, starting local server..."
        $env:HOST = $BindHost
        $env:PORT = "$Port"
        $env:V3_ADMIN_TOKEN = $AdminToken
        $env:V3_MOBILE_TOKEN = $MobileToken
        $env:V3_AGENT_TOKEN = $AgentToken
        $proc = Start-Process -FilePath "node" -ArgumentList "src/server.js" -WorkingDirectory $backendDir -PassThru
        $backendPid = $proc.Id
        $startedBackend = $true
        Start-Sleep -Seconds 2
        if (-not (Test-BackendHealth -Url $ApiUrl)) {
            throw "Backend failed to start at $ApiUrl"
        }
        $results.backend_running = $true
        Write-Host "Started backend pid=$backendPid"
    }

    Step "Backend smoke"
    if (Test-Path (Join-Path $backendDir "package.json")) {
        Push-Location $backendDir
        try {
            npm run smoke
            $results.backend_smoke = "ok"
        } finally {
            Pop-Location
        }
    }

    if (-not $SkipDesktop) {
        Step "Desktop smoke"
        if (Test-Path (Join-Path $desktopDir "scripts\local-smoke.ps1")) {
            Push-Location $desktopDir
            try {
                .\scripts\local-smoke.ps1 -ApiUrl $ApiUrl -MobileToken $MobileToken -AgentToken $AgentToken
                $results.desktop_smoke = "ok"
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "Desktop smoke script not found, skipping."
            $results.desktop_smoke = "missing"
        }
    }

    if (-not $SkipAndroidBuild) {
        Step "Android build"
        if (Test-Path (Join-Path $androidDir "scripts\local-build.ps1")) {
            Push-Location $androidDir
            try {
                .\scripts\local-build.ps1
                $results.android_build = "ok"
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "Android build script not found, skipping."
            $results.android_build = "missing"
        }
    }

    if ($TryAndroidDeploy) {
        Step "Android deploy"
        if (Test-Path (Join-Path $androidDir "scripts\deploy-device.ps1")) {
            Push-Location $androidDir
            try {
                .\scripts\deploy-device.ps1
                $results.android_deploy = "ok"
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "Android deploy script not found, skipping."
            $results.android_deploy = "missing"
        }
    }
}
finally {
    if ($startedBackend -and -not $LeaveBackendRunning) {
        if ($backendPid -and (Get-Process -Id $backendPid -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $backendPid -Force
            Write-Host ""
            Write-Host "Stopped backend pid=$backendPid"
        }
    }
}

Step "Summary"
$results | ConvertTo-Json -Depth 4 | Write-Host
