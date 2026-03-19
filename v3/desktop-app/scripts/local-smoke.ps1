param(
    [string]$ApiUrl = "http://127.0.0.1:8787",
    [string]$MobileToken = "dev-mobile-token",
    [string]$AgentToken = "dev-agent-token"
)

$ErrorActionPreference = "Stop"

Write-Host "[1/3] Backend health check: $ApiUrl/health"
try {
    $health = Invoke-RestMethod -Uri "$ApiUrl/health" -Method Get
    if (-not $health.ok) {
        throw "Health response ok=false"
    }
} catch {
    throw "Backend is not reachable at $ApiUrl. Start v3 backend first."
}

$env:V3_API_URL = $ApiUrl
$env:V3_MOBILE_TOKEN = $MobileToken
$env:V3_AGENT_TOKEN = $AgentToken

Write-Host "[2/3] Syntax checks..."
npm run check

Write-Host "[3/3] Desktop API smoke..."
npm run smoke

Write-Host "Desktop local smoke passed."
