# Integration tests for Codex + Claude Code notifier
param(
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1",
  [switch]$SkipTelegram,
  [switch]$SkipSend
)

$ErrorActionPreference = "Continue"
$pass = 0; $fail = 0

function Test-Case([string]$name, [scriptblock]$body) {
  Write-Host "  [ ] $name" -NoNewline
  try {
    $result = & $body
    if ($result -eq $true -or ([string]$result) -match '^ok') {
      Write-Host "`r  [OK] $name" -ForegroundColor Green
      $script:pass++
    } else {
      Write-Host "`r  [FAIL] $name : $result" -ForegroundColor Red
      $script:fail++
    }
  } catch {
    Write-Host "`r  [FAIL] $name : $($_.Exception.Message)" -ForegroundColor Red
    $script:fail++
  }
}

Write-Host ""
Write-Host "=== Notifier Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# --- Environment --------------------------------------------------------------
Write-Host "--- Environment ---" -ForegroundColor Yellow

Test-Case "Config file exists" {
  Test-Path $ConfigPath
}

Test-Case "Config loads TG credentials" {
  . $ConfigPath
  ($env:TG_BOT_TOKEN -ne "" -and $env:TG_CHAT_ID -ne "")
}

Test-Case "Scripts directory complete" {
  $required = @(
    'telegram-controller.ps1','codex-bridge.ps1','cc-bridge.ps1',
    'cc-hook-stop.ps1','send-telegram.ps1','run-with-notify.ps1'
  )
  $missing = $required | Where-Object { -not (Test-Path "c:\001_dev\notifier\scripts\$_") }
  if ($missing) { return "Missing: $($missing -join ', ')" }
  return $true
}

Test-Case "State directory exists" {
  Test-Path "c:\001_dev\notifier\state"
}

Test-Case "Logs directory exists" {
  Test-Path "c:\001_dev\notifier\logs"
}

Test-Case "Claude Code settings.json has Stop hook" {
  $sPath = Join-Path $env:USERPROFILE ".claude\settings.json"
  if (-not (Test-Path $sPath)) { return "settings.json not found" }
  $content = Get-Content $sPath -Raw
  if ($content -contains "Stop" -or $content -match '"Stop"') { return $true }
  return "Stop hook not configured"
}

# --- Codex session detection --------------------------------------------------
Write-Host ""
Write-Host "--- Codex session detection ---" -ForegroundColor Yellow

Test-Case "Codex sessions directory accessible" {
  $root = Join-Path $env:USERPROFILE ".codex\sessions"
  Test-Path $root
}

Test-Case "Codex: latest session file found" {
  $root = Join-Path $env:USERPROFILE ".codex\sessions"
  $f = Get-ChildItem $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { return "No session files found" }
  return $true
}

Test-Case "Codex: codex-bridge last_meta works" {
  $out = & "c:\001_dev\notifier\scripts\codex-bridge.ps1" -Action last_meta 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($out -join " ").Trim()
  if ($exitCode -eq 0 -and $text.Contains("timestamp_utc")) { return $true }
  return "exit=$exitCode out=$text"
}

Test-Case "Codex: last text readable" {
  $out = & "c:\001_dev\notifier\scripts\codex-bridge.ps1" -Action last_text 2>&1
  $exitCode = $LASTEXITCODE
  $text = (($out -join " ").Trim())
  if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($text) -and $text -ne "NO_TEXT") { return $true }
  return "exit=$exitCode text='$($text.Substring(0,[Math]::Min(60,$text.Length)))'"
}

# --- Claude Code session detection --------------------------------------------
Write-Host ""
Write-Host "--- Claude Code session detection ---" -ForegroundColor Yellow

Test-Case "Claude Code sessions directory accessible" {
  $root = Join-Path $env:USERPROFILE ".claude\projects"
  Test-Path $root
}

Test-Case "Claude Code: latest session file found" {
  $root = Join-Path $env:USERPROFILE ".claude\projects"
  $f = Get-ChildItem $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { return "No session files found" }
  return $true
}

Test-Case "Claude Code: cc-bridge last_meta works" {
  $out = & "c:\001_dev\notifier\scripts\cc-bridge.ps1" -Action last_meta 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($out -join " ").Trim()
  if ($exitCode -eq 0 -and $text.Contains("timestamp_utc")) { return $true }
  return "exit=$exitCode out=$text"
}

Test-Case "Claude Code: last text readable" {
  $out = & "c:\001_dev\notifier\scripts\cc-bridge.ps1" -Action last_text 2>&1
  $exitCode = $LASTEXITCODE
  $text = (($out -join " ").Trim())
  if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($text) -and $text -ne "NO_TEXT") { return $true }
  return "exit=$exitCode text='$($text.Substring(0,[Math]::Min(60,$text.Length)))'"
}

# --- Process detection --------------------------------------------------------
Write-Host ""
Write-Host "--- Process detection ---" -ForegroundColor Yellow

Test-Case "Codex.exe running with window" {
  $p = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 }
  if ($p) { return "ok" }
  return "Codex.exe not found (is it running?)"
}

Test-Case "claude.exe running with window" {
  $p = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero }
  if ($p) { return "ok" }
  return "claude.exe not found (is Claude Code open?)"
}

# --- CC UIA scan --------------------------------------------------------------
Write-Host ""
Write-Host "--- CC UIA scan (informational) ---" -ForegroundColor Yellow

$p = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
  Sort-Object WorkingSet64 -Descending | Select-Object -First 1

if ($p) {
  Write-Host "  Scanning input elements in claude.exe pid=$($p.Id)..." -ForegroundColor Gray
  $scanOut = & "c:\001_dev\notifier\scripts\cc-bridge.ps1" -Action scan_inputs 2>&1
  if ($scanOut) {
    $scanOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
  } else {
    Write-Host "    (no Edit elements found via UIA)" -ForegroundColor Gray
  }
} else {
  Write-Host "  Skipped: no claude.exe window" -ForegroundColor Gray
}

# --- Hook test ----------------------------------------------------------------
if (-not $SkipTelegram) {
  Write-Host ""
  Write-Host "--- Hook / Telegram ---" -ForegroundColor Yellow

  Test-Case "cc-hook-stop.ps1 sends Telegram notification" {
    . $ConfigPath
    # Feed a fake hook payload via stdin
    $fakePayload = '{"session_id":"test-integration","hook_event_name":"Stop","transcript":[{"role":"assistant","content":[{"type":"text","text":"Test notification from test-integration.ps1"}]}]}'
    $out = $fakePayload | & "c:\001_dev\notifier\scripts\cc-hook-stop.ps1" 2>&1
    if ($LASTEXITCODE -eq 0) { return $true }
    return "exit=$LASTEXITCODE out=$($out -join ' ')"
  }

  Test-Case "send-telegram.ps1 direct send works" {
    . $ConfigPath
    & "c:\001_dev\notifier\scripts\send-telegram.ps1" `
      -BotToken $env:TG_BOT_TOKEN -ChatId $env:TG_CHAT_ID `
      -Text "[test-integration] Direct send test OK" 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
  }
}

# --- Send test (optional, requires open windows) -----------------------------
if (-not $SkipSend) {
  Write-Host ""
  Write-Host "--- Send tests (DRY RUN - checks bridge without sending) ---" -ForegroundColor Yellow

  Test-Case "Codex bridge: process found" {
    $p = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 }
    if ($p) { return "ok pid=$($p.Id)" }
    return "No Codex window"
  }

  Test-Case "CC bridge: process found" {
    $p = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
      Sort-Object WorkingSet64 -Descending | Select-Object -First 1
    if ($p) { return "ok pid=$($p.Id) mem=$([Math]::Round($p.WorkingSet64/1MB,0))MB" }
    return "No claude window"
  }
}

# --- Controller PID check ----------------------------------------------------
Write-Host ""
Write-Host "--- Controller ---" -ForegroundColor Yellow

Test-Case "Controller PID file exists" {
  Test-Path "c:\001_dev\notifier\state\controller.pid"
}

Test-Case "Controller process running" {
  $pidFile = "c:\001_dev\notifier\state\controller.pid"
  if (-not (Test-Path $pidFile)) { return "PID file missing" }
  $ctrlPid = [int](Get-Content $pidFile -Raw)
  $proc = Get-Process -Id $ctrlPid -ErrorAction SilentlyContinue
  if ($proc) { return "ok pid=$ctrlPid" }
  return "Controller not running (pid=$ctrlPid dead)"
}

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "---------------------------------" -ForegroundColor Cyan
$total = $pass + $fail
$color = if ($fail -eq 0) { "Green" } else { "Yellow" }
Write-Host "Results: $pass/$total passed, $fail failed" -ForegroundColor $color
if ($fail -gt 0) {
  Write-Host "Some tests failed. Check above for details." -ForegroundColor Yellow
}
Write-Host ""
