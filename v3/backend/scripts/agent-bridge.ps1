param(
  [string]$BaseUrl = "http://127.0.0.1:8787",
  [string]$AgentToken = "",
  [int]$PollSeconds = 2,
  [string]$LogPath = "C:\001_dev\notifier\logs\v3-agent-bridge.log"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AgentToken)) {
  $AgentToken = $env:V3_AGENT_TOKEN
}
if ([string]::IsNullOrWhiteSpace($AgentToken)) {
  $AgentToken = "dev-agent-token"
}

$continueTemplate = "If everything is clear and you know what to do next, continue working and testing in this thread. Provide brief status updates."
$fixRetestTemplate = "Continue testing. If you find errors, fix them, then run tests again. Keep working until all bugs for this task are fixed. Provide brief status updates."
$codexBridge = "C:\001_dev\notifier\scripts\codex-bridge.ps1"
$ccBridge = "C:\001_dev\notifier\scripts\cc-bridge.ps1"
$codexSessionsRoot = "C:\Users\Vitaly\.codex\sessions"
$shotDir = "C:\001_dev\notifier\state\screenshots"
$codexCompletionWatchPath = "C:\001_dev\notifier\state\v3-codex-completion-watch.json"
$completionPollSec = [Math]::Max(1, [int]$PollSeconds)

$script:codexWatchInitialized = $false
$script:codexLastCompletionKey = ""
$script:codexLastCompletionCheck = [DateTime]::MinValue

if (-not (Test-Path $shotDir)) {
  New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
}

if (-not (Test-Path (Split-Path -Parent $LogPath))) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
}

Add-Type -AssemblyName System.Drawing | Out-Null
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")]
  public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")]
  public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
}
"@ | Out-Null

[NativeWin]::SetProcessDPIAware() | Out-Null

function Write-AgentLog([string]$message) {
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
  Add-Content -Path $LogPath -Value "$ts | $message" -Encoding UTF8
}

function Invoke-AgentApi([string]$method, [string]$path, $body = $null) {
  $headers = @{ Authorization = "Bearer $AgentToken" }
  $uri = "$BaseUrl$path"
  if ($null -ne $body) {
    $json = ($body | ConvertTo-Json -Depth 10 -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 12
  }
  return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 12
}

function Get-CodexWindowProcess {
  return Get-Process Codex -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1
}

function Get-CCWindowProcess {
  return Get-Process claude -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 1
}

function Capture-CodexScreenshot {
  $proc = Get-CodexWindowProcess
  if (-not $proc) {
    return [PSCustomObject]@{ ok = $false; error = "Codex window not found." }
  }
  $hWnd = [IntPtr]$proc.MainWindowHandle

  if ([NativeWin]::IsIconic($hWnd)) {
    [NativeWin]::ShowWindow($hWnd, 9) | Out-Null
    Start-Sleep -Milliseconds 220
  }

  $captureRect = New-Object NativeWin+RECT
  $origin = New-Object NativeWin+POINT
  $origin.X = 0
  $origin.Y = 0

  $hasClient = [NativeWin]::GetClientRect($hWnd, [ref]$captureRect)
  if ($hasClient) {
    [NativeWin]::ClientToScreen($hWnd, [ref]$origin) | Out-Null
    $captureRect.Left = $origin.X
    $captureRect.Top = $origin.Y
    $captureRect.Right = $origin.X + ($captureRect.Right - 0)
    $captureRect.Bottom = $origin.Y + ($captureRect.Bottom - 0)
  } else {
    if (-not [NativeWin]::GetWindowRect($hWnd, [ref]$captureRect)) {
      return [PSCustomObject]@{ ok = $false; error = "GetWindowRect/GetClientRect failed." }
    }
  }

  $width = $captureRect.Right - $captureRect.Left
  $height = $captureRect.Bottom - $captureRect.Top
  if ($width -lt 100 -or $height -lt 100) {
    return [PSCustomObject]@{ ok = $false; error = "Window rect is too small ($width x $height)." }
  }

  $bmp = $null
  $gfx = $null
  $hDc = [IntPtr]::Zero
  $path = $null
  $captureMethod = ""
  try {
    [NativeWin]::ShowWindow($hWnd, 9) | Out-Null
    [NativeWin]::SetForegroundWindow($hWnd) | Out-Null
    Start-Sleep -Milliseconds 140

    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hDc = $gfx.GetHdc()
    $printed2 = [NativeWin]::PrintWindow($hWnd, $hDc, 2)
    $gfx.ReleaseHdc($hDc)
    $hDc = [IntPtr]::Zero

    if ($printed2) {
      $captureMethod = "PrintWindow(2)"
    } else {
      $hDc = $gfx.GetHdc()
      $printed0 = [NativeWin]::PrintWindow($hWnd, $hDc, 0)
      $gfx.ReleaseHdc($hDc)
      $hDc = [IntPtr]::Zero

      if ($printed0) {
        $captureMethod = "PrintWindow(0)"
      } else {
        throw "PrintWindow failed for flags 2 and 0."
      }
    }

    $path = Join-Path $shotDir ("codex-shot-{0}.png" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  } catch {
    return [PSCustomObject]@{ ok = $false; error = "Capture failed: $($_.Exception.Message)" }
  } finally {
    if ($hDc -ne [IntPtr]::Zero -and $gfx) { $gfx.ReleaseHdc($hDc) }
    if ($gfx) { $gfx.Dispose() }
    if ($bmp) { $bmp.Dispose() }
  }

  if (-not $path -or -not (Test-Path $path)) {
    return [PSCustomObject]@{ ok = $false; error = "Screenshot file was not created." }
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  $b64 = [Convert]::ToBase64String($bytes)
  return [PSCustomObject]@{
    ok = $true
    path = $path
    base64 = $b64
    bytes = $bytes.Length
    width = $width
    height = $height
    capture_method = $captureMethod
  }
}

function Capture-CCScreenshot {
  $proc = Get-CCWindowProcess
  if (-not $proc) {
    return [PSCustomObject]@{ ok = $false; error = "Claude Code window not found." }
  }
  $hWnd = [IntPtr]$proc.MainWindowHandle

  if ([NativeWin]::IsIconic($hWnd)) {
    [NativeWin]::ShowWindow($hWnd, 9) | Out-Null
    Start-Sleep -Milliseconds 220
  }

  $rect = New-Object NativeWin+RECT
  if (-not [NativeWin]::GetWindowRect($hWnd, [ref]$rect)) {
    return [PSCustomObject]@{ ok = $false; error = "GetWindowRect failed." }
  }

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -lt 100 -or $height -lt 100) {
    return [PSCustomObject]@{ ok = $false; error = "Window rect is too small ($width x $height)." }
  }

  $bmp = $null
  $gfx = $null
  $hDc = [IntPtr]::Zero
  $path = $null
  $captureMethod = ""
  try {
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hDc = $gfx.GetHdc()
    $printed2 = [NativeWin]::PrintWindow($hWnd, $hDc, 2)
    $gfx.ReleaseHdc($hDc)
    $hDc = [IntPtr]::Zero

    if ($printed2) {
      $captureMethod = "PrintWindow(2)"
    } else {
      $hDc = $gfx.GetHdc()
      $printed0 = [NativeWin]::PrintWindow($hWnd, $hDc, 0)
      $gfx.ReleaseHdc($hDc)
      $hDc = [IntPtr]::Zero
      if (-not $printed0) {
        throw "PrintWindow failed for flags 2 and 0."
      }
      $captureMethod = "PrintWindow(0)"
    }

    $path = Join-Path $shotDir ("cc-shot-{0}.png" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  } catch {
    return [PSCustomObject]@{ ok = $false; error = "Capture failed: $($_.Exception.Message)" }
  } finally {
    if ($hDc -ne [IntPtr]::Zero -and $gfx) { $gfx.ReleaseHdc($hDc) }
    if ($gfx) { $gfx.Dispose() }
    if ($bmp) { $bmp.Dispose() }
  }

  if (-not $path -or -not (Test-Path $path)) {
    return [PSCustomObject]@{ ok = $false; error = "Screenshot file was not created." }
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  $b64 = [Convert]::ToBase64String($bytes)
  return [PSCustomObject]@{
    ok = $true
    path = $path
    base64 = $b64
    bytes = $bytes.Length
    width = $width
    height = $height
    capture_method = $captureMethod
  }
}

function Send-CodexPrompt([string]$prompt) {
  if (-not (Test-Path $codexBridge)) {
    return [PSCustomObject]@{ ok = $false; out = "codex-bridge.ps1 not found." }
  }
  $out = & $codexBridge -Action send_continue -ContinueText $prompt 2>&1
  $exitCode = $LASTEXITCODE
  $outText = (($out | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
  }) -join " ").Trim()
  if ($outText.Length -gt 1200) {
    $outText = $outText.Substring(0, 1200) + "...(truncated)"
  }
  return [PSCustomObject]@{
    ok = ($exitCode -eq 0)
    out = $outText
    exit_code = $exitCode
  }
}

function Send-BridgePrompt([string]$bridgePath, [string]$prompt) {
  if (-not (Test-Path $bridgePath)) {
    return [PSCustomObject]@{ ok = $false; out = "bridge not found: $bridgePath"; exit_code = -1 }
  }
  $job = Start-Job -ScriptBlock {
    param($path, $text)
    $out = & $path -Action send_continue -ContinueText $text 2>&1
    [PSCustomObject]@{
      exit_code = $LASTEXITCODE
      out = $out
    }
  } -ArgumentList $bridgePath, $prompt
  $done = Wait-Job -Job $job -Timeout 55
  if (-not $done) {
    try { Stop-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    return [PSCustomObject]@{ ok = $false; out = "bridge send timeout"; exit_code = -2 }
  }
  $raw = $null
  try { $raw = Receive-Job -Job $job -ErrorAction SilentlyContinue } catch {}
  try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
  $exitCode = [int]$raw.exit_code
  $out = $raw.out
  $outText = (($out | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
  }) -join " ").Trim()
  if ($outText.Length -gt 1200) {
    $outText = $outText.Substring(0, 1200) + "...(truncated)"
  }
  return [PSCustomObject]@{
    ok = ($exitCode -eq 0)
    out = $outText
    exit_code = $exitCode
  }
}

function Get-BridgeLastText([string]$bridgePath) {
  if (-not (Test-Path $bridgePath)) {
    return [PSCustomObject]@{ ok = $false; text = ""; out = "bridge not found: $bridgePath"; exit_code = -1 }
  }
  $job = Start-Job -ScriptBlock {
    param($path)
    $out = & $path -Action last_text 2>&1
    [PSCustomObject]@{
      exit_code = $LASTEXITCODE
      out = $out
    }
  } -ArgumentList $bridgePath
  $done = Wait-Job -Job $job -Timeout 20
  if (-not $done) {
    try { Stop-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    return [PSCustomObject]@{ ok = $false; text = ""; out = "bridge last_text timeout"; exit_code = -2 }
  }
  $raw = $null
  try { $raw = Receive-Job -Job $job -ErrorAction SilentlyContinue } catch {}
  try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
  $exitCode = [int]$raw.exit_code
  $out = $raw.out
  $outText = (($out | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
  }) -join "`n").Trim()

  if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($outText) -and $outText -ne "NO_TEXT") {
    return [PSCustomObject]@{
      ok = $true
      text = $outText
      out = $outText
      exit_code = $exitCode
    }
  }
  return [PSCustomObject]@{
    ok = $false
    text = ""
    out = $outText
    exit_code = $exitCode
  }
}

function Get-BridgeLastMeta([string]$bridgePath) {
  if (-not (Test-Path $bridgePath)) {
    return [PSCustomObject]@{
      ok = $false
      text = ""
      key = ""
      timestamp_utc = ""
      out = "bridge not found: $bridgePath"
      exit_code = -1
    }
  }

  $job = Start-Job -ScriptBlock {
    param($path)
    $out = & $path -Action last_meta 2>&1
    [PSCustomObject]@{
      exit_code = $LASTEXITCODE
      out = $out
    }
  } -ArgumentList $bridgePath

  $done = Wait-Job -Job $job -Timeout 20
  if (-not $done) {
    try { Stop-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    return [PSCustomObject]@{
      ok = $false
      text = ""
      key = ""
      timestamp_utc = ""
      out = "bridge last_meta timeout"
      exit_code = -2
    }
  }

  $raw = $null
  try { $raw = Receive-Job -Job $job -ErrorAction SilentlyContinue } catch {}
  try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
  $exitCode = [int]$raw.exit_code
  $out = $raw.out
  $outText = (($out | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
  }) -join "`n").Trim()

  if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($outText)) {
    return [PSCustomObject]@{
      ok = $false
      text = ""
      key = ""
      timestamp_utc = ""
      out = $outText
      exit_code = $exitCode
    }
  }

  try {
    $meta = $outText | ConvertFrom-Json -ErrorAction Stop
    $key = [string]$meta.key
    $tsRaw = [string]$meta.timestamp_utc
    $txt = [string]$meta.text
    if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($tsRaw)) {
      throw "last_meta missing key/timestamp_utc"
    }
    $ts = [DateTime]::Parse($tsRaw).ToUniversalTime()
    return [PSCustomObject]@{
      ok = $true
      text = $txt
      key = $key
      timestamp_utc = $ts.ToString("o")
      out = $outText
      exit_code = $exitCode
    }
  } catch {
    return [PSCustomObject]@{
      ok = $false
      text = ""
      key = ""
      timestamp_utc = ""
      out = "invalid last_meta json: $($_.Exception.Message) | raw=$outText"
      exit_code = $exitCode
    }
  }
}

function Get-LatestCodexSessionFile {
  if (-not (Test-Path $codexSessionsRoot)) { return $null }
  return Get-ChildItem $codexSessionsRoot -Recurse -File -Filter "*.jsonl" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
}

function Read-FileTailUtf8([string]$path, [int]$maxBytes = 1048576) {
  if ([string]::IsNullOrWhiteSpace($path)) { return "" }
  if (-not (Test-Path $path)) { return "" }

  $fs = $null
  try {
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    if ($fs.Length -le 0) { return "" }

    $toRead = [int][Math]::Min([int64]$maxBytes, $fs.Length)
    if ($toRead -le 0) { return "" }
    $offset = $fs.Length - $toRead

    $buf = New-Object byte[] $toRead
    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $read = $fs.Read($buf, 0, $toRead)
    if ($read -le 0) { return "" }
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
  } catch {
    return ""
  } finally {
    if ($fs) { $fs.Dispose() }
  }
}

function Get-LatestCodexCompletionFromJsonl {
  $f = Get-LatestCodexSessionFile
  if (-not $f) { return $null }

  # Newer Codex builds may emit many commentary lines; scan progressively deeper tail windows.
  foreach ($tailBytes in @(2097152, 6291456, 12582912)) {
    $tail = Read-FileTailUtf8 -path $f.FullName -maxBytes $tailBytes
    if ([string]::IsNullOrWhiteSpace($tail)) { continue }

    $lines = $tail -split "`n"
    if (-not $lines -or $lines.Count -le 0) { continue }

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $line = ([string]$lines[$i]).TrimEnd("`r")
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ($line.Length -gt 200000) { continue }
      if (-not $line.StartsWith('{"timestamp":"')) { continue }
      if (-not $line.Contains('","type":"response_item","payload":{"type":"message","role":"assistant"')) { continue }
      try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        if ($obj.type -ne "response_item") { continue }
        if ($obj.payload.type -ne "message" -or $obj.payload.role -ne "assistant") { continue }

        $phase = [string]$obj.payload.phase
        if ($phase -ne "final" -and $phase -ne "final_answer") { continue }

        $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
        $text = ""
        foreach ($c in $obj.payload.content) {
          if ($c.type -eq "output_text" -and $c.text) {
            $text = [string]$c.text
          }
        }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $key = "$($ts.ToString('o'))|$([Math]::Abs($text.GetHashCode()))"
        return [PSCustomObject]@{
          key = $key
          timestamp = $ts
          text = $text
        }
      } catch {}
    }
  }
  return $null
}

function Get-LatestCodexCompletion {
  $jsonl = Get-LatestCodexCompletionFromJsonl
  if ($null -ne $jsonl) { return $jsonl }

  $meta = Get-BridgeLastMeta -bridgePath $codexBridge
  if ($meta.ok) {
    return [PSCustomObject]@{
      key = [string]$meta.key
      timestamp = [DateTime]::Parse([string]$meta.timestamp_utc).ToUniversalTime()
      text = [string]$meta.text
    }
  }

  # Fallback: should be rare, but keeps notifier alive if last_meta temporarily fails.
  if ([int]$meta.exit_code -eq -2) {
    return $null
  }
  $lt = Get-BridgeLastText -bridgePath $codexBridge
  if ($lt.ok -and -not [string]::IsNullOrWhiteSpace($lt.text)) {
    $text = [string]$lt.text
    return [PSCustomObject]@{
      key = "fallback|$([Math]::Abs($text.GetHashCode()))"
      timestamp = (Get-Date).ToUniversalTime()
      text = $text
    }
  }

  return $null
}

function Get-CommandCustomText($cmd) {
  if ($null -eq $cmd) { return "" }
  $meta = $cmd.metadata
  if ($null -eq $meta) { return "" }
  foreach ($name in @("custom_text", "text", "prompt", "message")) {
    if ($meta.PSObject.Properties.Name -contains $name) {
      $value = [string]$meta.$name
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value.Trim()
      }
    }
  }
  return ""
}

function Limit-Text([string]$text, [int]$maxLen = 6000) {
  if ([string]::IsNullOrEmpty($text)) { return "" }
  $clean = Sanitize-JsonText -text $text
  if ([string]::IsNullOrEmpty($clean)) { return "" }
  if ($clean.Length -le $maxLen) { return $clean }
  return $clean.Substring(0, $maxLen) + "`n...(truncated)"
}

function Sanitize-JsonText([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return "" }
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $text.Length; $i++) {
    $ch = [int][char]$text[$i]

    # Drop nulls and unsupported C0 controls (keep tab/newline/CR)
    if ($ch -eq 0) { continue }
    if ($ch -lt 32 -and $ch -ne 9 -and $ch -ne 10 -and $ch -ne 13) { continue }

    # Keep valid surrogate pairs only.
    if ($ch -ge 0xD800 -and $ch -le 0xDBFF) {
      if ($i + 1 -lt $text.Length) {
        $next = [int][char]$text[$i + 1]
        if ($next -ge 0xDC00 -and $next -le 0xDFFF) {
          [void]$sb.Append($text[$i])
          [void]$sb.Append($text[$i + 1])
          $i++
        }
      }
      continue
    }
    if ($ch -ge 0xDC00 -and $ch -le 0xDFFF) { continue }

    [void]$sb.Append($text[$i])
  }
  return $sb.ToString()
}

function Load-CodexCompletionWatchState {
  if (-not (Test-Path $codexCompletionWatchPath)) { return }
  try {
    $s = Get-Content $codexCompletionWatchPath -Raw | ConvertFrom-Json
    $script:codexWatchInitialized = [bool]$s.initialized
    $script:codexLastCompletionKey = [string]$s.last_key
  } catch {
    $script:codexWatchInitialized = $false
    $script:codexLastCompletionKey = ""
  }
}

function Save-CodexCompletionWatchState {
  $obj = [ordered]@{
    initialized = $script:codexWatchInitialized
    last_key = $script:codexLastCompletionKey
    updated_at = (Get-Date).ToString("o")
  }
  $obj | ConvertTo-Json | Set-Content -Path $codexCompletionWatchPath -Encoding UTF8
}

function Initialize-CodexCompletionBaseline {
  $latest = Get-LatestCodexCompletion
  $script:codexWatchInitialized = $true
  if ($null -eq $latest) {
    $script:codexLastCompletionKey = ""
    Save-CodexCompletionWatchState
    Write-AgentLog "Codex watcher initialized without baseline key (waiting for first final)."
    return
  }
  $script:codexLastCompletionKey = [string]$latest.key
  Save-CodexCompletionWatchState
  Write-AgentLog "Codex watcher baseline key=$($latest.key)"
}

function Check-CodexCompletionWatcher {
  $now = Get-Date
  if (($now - $script:codexLastCompletionCheck).TotalSeconds -lt $completionPollSec) { return }
  $script:codexLastCompletionCheck = $now

  $latest = Get-LatestCodexCompletion
  if ($null -eq $latest) { return }

  if (-not $script:codexWatchInitialized) {
    $script:codexWatchInitialized = $true
    $script:codexLastCompletionKey = [string]$latest.key
    Save-CodexCompletionWatchState
    Write-AgentLog "Codex watcher initialized key=$($latest.key)"
    return
  }

  if ([string]$latest.key -eq $script:codexLastCompletionKey) { return }

  # Commit first to prevent duplicate notifications.
  $script:codexLastCompletionKey = [string]$latest.key
  Save-CodexCompletionWatchState
  Write-AgentLog "Codex completion detected key=$($latest.key)"

  $doneLine = "Codex done $($latest.timestamp.ToString('HH:mm:ss')) UTC."
  $okDone = Safe-Event -eventType "done" -source "codex" -payload @{
    text = $doneLine
    completion_key = [string]$latest.key
    timestamp_utc = $latest.timestamp.ToString("o")
  }

  $completionText = [string]$latest.text
  if ([string]::IsNullOrWhiteSpace($completionText)) {
    $lt = Get-BridgeLastText -bridgePath $codexBridge
    if ($lt.ok) { $completionText = [string]$lt.text }
  }
  if ([string]::IsNullOrWhiteSpace($completionText)) {
    $completionText = "(last assistant text is not available yet)"
  }

  $okText = Safe-Event -eventType "last_text" -source "codex" -payload @{
    text = (Limit-Text -text $completionText)
    completion_key = [string]$latest.key
    timestamp_utc = $latest.timestamp.ToString("o")
  }

  if ($okDone -and $okText) {
    Write-AgentLog "Codex completion events posted key=$($latest.key)"
  } else {
    Write-AgentLog "Codex completion events failed key=$($latest.key) done_ok=$okDone last_text_ok=$okText"
  }
}

function Safe-Ack([string]$commandId, [string]$status, [string]$message) {
  try {
    Invoke-AgentApi -method "POST" -path "/v1/agents/actions/ack" -body @{
      command_id = $commandId
      status = $status
      message = $message
    } | Out-Null
    return $true
  } catch {
    Write-AgentLog "ACK failed command_id=$commandId status=$status err=$($_.Exception.Message)"
    return $false
  }
}

function Safe-Event([string]$eventType, [hashtable]$payload, [string]$source = "codex") {
  try {
    Invoke-AgentApi -method "POST" -path "/v1/agents/events" -body @{
      source = $source
      event_type = $eventType
      payload = $payload
    } | Out-Null
    return $true
  } catch {
    Write-AgentLog "EVENT failed type=$eventType err=$($_.Exception.Message)"
    return $false
  }
}

Write-AgentLog "Agent bridge started. BaseUrl=$BaseUrl PollSeconds=$PollSeconds"
Load-CodexCompletionWatchState
if (-not $script:codexWatchInitialized -or [string]::IsNullOrWhiteSpace($script:codexLastCompletionKey)) {
  Initialize-CodexCompletionBaseline
}

while ($true) {
  try {
    try {
      Check-CodexCompletionWatcher
    } catch {
      Write-AgentLog "Codex watcher error (pre-poll): $($_.Exception.Message)"
    }

    $pending = Invoke-AgentApi -method "GET" -path "/v1/agents/commands/pending?limit=25"
    $items = @($pending.items)
    foreach ($cmd in $items) {
      $commandId = [string]$cmd.command_id
      $target = [string]$cmd.target
      $action = [string]$cmd.action

      if ([string]::IsNullOrWhiteSpace($commandId)) { continue }

      if ($target -ne "codex" -and $target -ne "cc") {
        Safe-Ack -commandId $commandId -status "ignored" -message "Unsupported target: $target" | Out-Null
        Safe-Event -eventType "agent_note" -source "codex" -payload @{
          command_id = $commandId
          text = "Ignored command: unsupported target '$target'."
        } | Out-Null
        continue
      }

      $targetSource = if ($target -eq "cc") { "cc" } else { "codex" }
      $targetTitle = if ($target -eq "cc") { "Cloud Code" } else { "Codex" }
      $bridgePath = if ($target -eq "cc") { $ccBridge } else { $codexBridge }

      Write-AgentLog "Processing command_id=$commandId target=$targetSource action=$action"

      switch ($action.ToLowerInvariant()) {
        "continue" {
          $r = Send-BridgePrompt -bridgePath $bridgePath -prompt $continueTemplate
          if ($r.ok) {
            Safe-Ack -commandId $commandId -status "done" -message "continue sent" | Out-Null
            Safe-Event -eventType "command_result" -source $targetSource -payload @{
              command_id = $commandId
              text = "Continue delivered to $targetTitle."
              bridge_out = $r.out
            } | Out-Null
          } else {
            Safe-Ack -commandId $commandId -status "failed" -message "continue failed" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "Continue failed for $targetTitle."
              bridge_out = $r.out
            } | Out-Null
          }
        }
        "fix_retest" {
          $r = Send-BridgePrompt -bridgePath $bridgePath -prompt $fixRetestTemplate
          if ($r.ok) {
            Safe-Ack -commandId $commandId -status "done" -message "fix_retest sent" | Out-Null
            Safe-Event -eventType "command_result" -source $targetSource -payload @{
              command_id = $commandId
              text = "Fix+Retest delivered to $targetTitle."
              bridge_out = $r.out
            } | Out-Null
          } else {
            Safe-Ack -commandId $commandId -status "failed" -message "fix_retest failed" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "Fix+Retest failed for $targetTitle."
              bridge_out = $r.out
            } | Out-Null
          }
        }
        "last_text" {
          $lt = $null
          if ($targetSource -eq "codex") {
            $local = Get-LatestCodexCompletion
            if ($null -ne $local -and -not [string]::IsNullOrWhiteSpace([string]$local.text)) {
              $lt = [PSCustomObject]@{
                ok = $true
                text = [string]$local.text
                out = "local-codex-jsonl"
                exit_code = 0
              }
            }
          }
          if ($null -eq $lt) {
            $lt = Get-BridgeLastText -bridgePath $bridgePath
          }
          if ($lt.ok) {
            Safe-Ack -commandId $commandId -status "done" -message "last_text returned" | Out-Null
            Safe-Event -eventType "last_text" -source $targetSource -payload @{
              command_id = $commandId
              text = (Limit-Text -text $lt.text)
            } | Out-Null
          } else {
            Safe-Ack -commandId $commandId -status "failed" -message "last_text failed" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "Last text is unavailable for $targetTitle."
              bridge_out = $lt.out
            } | Out-Null
          }
        }
        "custom" {
          $customText = Get-CommandCustomText -cmd $cmd
          if ([string]::IsNullOrWhiteSpace($customText)) {
            Safe-Ack -commandId $commandId -status "failed" -message "custom text is empty" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "Custom text is empty."
            } | Out-Null
            break
          }
          $r = Send-BridgePrompt -bridgePath $bridgePath -prompt $customText
          if ($r.ok) {
            Safe-Ack -commandId $commandId -status "done" -message "custom sent" | Out-Null
            Safe-Event -eventType "command_result" -source $targetSource -payload @{
              command_id = $commandId
              text = "Custom prompt delivered to $targetTitle."
              custom_text = (Limit-Text -text $customText -maxLen 1000)
              bridge_out = $r.out
            } | Out-Null
          } else {
            Safe-Ack -commandId $commandId -status "failed" -message "custom failed" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "Custom prompt failed for $targetTitle."
              custom_text = (Limit-Text -text $customText -maxLen 1000)
              bridge_out = $r.out
            } | Out-Null
          }
        }
        "shot" {
          $shot = if ($targetSource -eq "cc") { Capture-CCScreenshot } else { Capture-CodexScreenshot }
          if ($shot.ok) {
            Safe-Ack -commandId $commandId -status "done" -message "screenshot captured" | Out-Null
            Safe-Event -eventType "screenshot" -source $targetSource -payload @{
              command_id = $commandId
              text = "$targetTitle screenshot captured."
              image_base64 = $shot.base64
              mime_type = "image/png"
              width = $shot.width
              height = $shot.height
              size_bytes = $shot.bytes
              capture_method = $shot.capture_method
            } | Out-Null
            Write-AgentLog "Screenshot posted command_id=$commandId target=$targetSource bytes=$($shot.bytes) method=$($shot.capture_method) path=$($shot.path)"
          } else {
            Safe-Ack -commandId $commandId -status "failed" -message "screenshot failed" | Out-Null
            Safe-Event -eventType "command_failed" -source $targetSource -payload @{
              command_id = $commandId
              text = "$targetTitle screenshot failed: $($shot.error)"
            } | Out-Null
          }
        }
        default {
          Safe-Ack -commandId $commandId -status "ignored" -message "unsupported action '$action'" | Out-Null
          Safe-Event -eventType "agent_note" -source $targetSource -payload @{
            command_id = $commandId
            text = "Unsupported action '$action'."
          } | Out-Null
        }
      }

      try {
        Check-CodexCompletionWatcher
      } catch {
        Write-AgentLog "Codex watcher error (post-command): $($_.Exception.Message)"
      }
    }
  } catch {
    Write-AgentLog "Loop error: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds $PollSeconds
}
