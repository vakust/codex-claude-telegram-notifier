param(
  [ValidateSet('send_continue','last_text','last_meta','bind_here','scan_inputs')][string]$Action,
  [string]$ContinueText = 'If everything is clear, continue working and testing in this thread. Provide brief status updates.',
  [int]$WaitAfterSendMs = 500,
  [string]$PointConfigPath = 'c:\001_dev\notifier\state\cc-input-point.json',
  [string]$LogPath = 'c:\001_dev\notifier\logs\cc-bridge-debug.log',
  [string]$SendLockPath = 'c:\001_dev\notifier\state\cc-bridge-send.lock',
  [int]$MaxRuntimeSec = 35,
  [int]$MaxAttempts = 8
)

Add-Type -AssemblyName System.Windows.Forms
try {
  Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
  Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
  $script:UIAutomationReady = $true
} catch {
  $script:UIAutomationReady = $false
}

if (-not ("Win32CCApi" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32CCApi {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char ch);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
}

function Write-Dbg([string]$msg) {
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
  Add-Content -Path $LogPath -Value "$ts | pid=$PID | $msg" -Encoding UTF8
}

function Acquire-SendLock {
  $dir = Split-Path -Parent $SendLockPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $SendLockPath) {
    try {
      $raw = Get-Content $SendLockPath -Raw -ErrorAction Stop
      $parts = $raw.Split('|')
      if ($parts.Count -gt 0) {
        $prevPid = [int]$parts[0]
        if ($prevPid -gt 0 -and (Get-Process -Id $prevPid -ErrorAction SilentlyContinue)) { return $false }
      }
    } catch {}
  }
  Set-Content -Path $SendLockPath -Value "$PID|$((Get-Date).ToString('o'))" -Encoding ASCII
  return $true
}

function Release-SendLock {
  try {
    if (Test-Path $SendLockPath) {
      $raw = Get-Content $SendLockPath -Raw -ErrorAction SilentlyContinue
      if ($raw -and $raw.StartsWith("$PID|")) {
        Remove-Item $SendLockPath -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {}
}

# Get main claude.exe process (largest working set = main UI process)
function Get-ClaudeWindowProcess {
  $procs = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero }
  if (-not $procs) { return $null }
  # Prefer largest working set (main UI process)
  return ($procs | Sort-Object WorkingSet64 -Descending | Select-Object -First 1)
}

# Known placeholder names for Claude Code input area (try all)
$script:CCPlaceholders = @(
  'Reply to Claude...',
  'How can Claude help?',
  'Plan and execute your software tasks',
  'Type a message...',
  'Message Claude...',
  'Ask Claude...',
  'Chat...',
  'Send a message'
)

function Get-UiaInputPoints([IntPtr]$hWnd) {
  $result = @()
  if (-not $script:UIAutomationReady) { return $result }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hWnd)
    if (-not $root) { return $result }
    $winRect = New-Object Win32CCApi+RECT
    [Win32CCApi]::GetWindowRect($hWnd, [ref]$winRect) | Out-Null
    $winW = $winRect.Right - $winRect.Left
    $winH = $winRect.Bottom - $winRect.Top
    $scope = [System.Windows.Automation.TreeScope]::Descendants

    # Try each known placeholder
    $placeholder = $null
    foreach ($ph in $script:CCPlaceholders) {
      $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $ph)
      $allPH = $root.FindAll($scope, $nameCond)
      if ($allPH -and $allPH.Count -gt 0) {
        $bestY = -1.0
        for ($pi = 0; $pi -lt $allPH.Count; $pi++) {
          $cand = $allPH.Item($pi)
          try {
            $cb = $cand.Current.BoundingRectangle
            if ($cb.Width -le 0 -or $cb.Height -le 0) { continue }
            if ($cb.Y -gt $bestY) { $bestY = $cb.Y; $placeholder = $cand }
          } catch {}
        }
        if ($placeholder) {
          Write-Dbg "UIA found placeholder '$ph'"
          break
        }
      }
    }

    if ($placeholder) {
      $pb = $placeholder.Current.BoundingRectangle
      if ($pb.Width -gt 0 -and $pb.Height -gt 0) {
        $cx = [int][Math]::Round($pb.X + [Math]::Min(180.0, ($pb.Width * 0.6)))
        $cy = [int][Math]::Round($pb.Y + ($pb.Height * 0.5))
        $result += [PSCustomObject]@{ x = $cx; y = $cy; source = "uia-placeholder" }
        $result += [PSCustomObject]@{ x = [int]($cx + 220); y = [int]($cy + 2); source = "uia-placeholder-right" }
        Write-Dbg "UIA placeholder=($cx,$cy) w=$([Math]::Round($pb.Width,1)) h=$([Math]::Round($pb.Height,1))"
      }
    }

    # Fallback: xterm-helper-textarea (same as Codex, Electron-based)
    $classCond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'xterm-helper-textarea')
    $xterm = $root.FindFirst($scope, $classCond)
    if ($xterm) {
      $b = $xterm.Current.BoundingRectangle
      if ($b.Width -gt 0 -and $b.Height -gt 0) {
        $rawX = [int][Math]::Round($b.X + ($b.Width / 2.0))
        $rawY = [int][Math]::Round($b.Y + ($b.Height / 2.0))
        $rawInside = ($rawX -ge $winRect.Left -and $rawX -le $winRect.Right -and $rawY -ge $winRect.Top -and $rawY -le $winRect.Bottom)
        $mappedX = $rawX; $mappedY = $rawY
        if (-not $rawInside -and $winW -gt 0 -and $winH -gt 0) {
          $rb = $root.Current.BoundingRectangle
          if ($rb.Width -gt 0 -and $rb.Height -gt 0) {
            $nx = [Math]::Max(0.0, [Math]::Min(1.0, ($rawX - $rb.X) / $rb.Width))
            $ny = [Math]::Max(0.0, [Math]::Min(1.0, ($rawY - $rb.Y) / $rb.Height))
            $mappedX = $winRect.Left + [int]($winW * $nx)
            $mappedY = $winRect.Top + [int]($winH * $ny)
          }
        }
        if ($mappedX -ne $rawX -or $mappedY -ne $rawY) {
          $result += [PSCustomObject]@{ x = $mappedX; y = $mappedY; source = "uia-xterm-mapped" }
        }
        $result += [PSCustomObject]@{ x = $rawX; y = $rawY; source = "uia-xterm" }
        Write-Dbg "UIA xterm=($rawX,$rawY)"
      }
    }

    if ($result.Count -eq 0 -and $winW -gt 0 -and $winH -gt 0) {
      $result += [PSCustomObject]@{
        x = $winRect.Left + [int]($winW * 0.55)
        y = $winRect.Top + [int]($winH * 0.88)
        source = "uia-fallback"
      }
    }
    return $result
  } catch {
    Write-Dbg "UIA point read failed: $($_.Exception.Message)"
    return @()
  }
}

function Ensure-WindowForeground([IntPtr]$hWnd, [int]$maxTries = 8) {
  $HWND_TOPMOST = [IntPtr](-1); $HWND_NOTOPMOST = [IntPtr](-2)
  $SWP_NOMOVE = 0x0002; $SWP_NOSIZE = 0x0001; $SWP_NOACTIVATE = 0x0010
  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell } catch {}
  $targetPid = $null
  try {
    $proc = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -eq $hWnd } | Select-Object -First 1
    if ($proc) { $targetPid = $proc.Id }
  } catch {}

  for ($i = 0; $i -lt $maxTries; $i++) {
    if ([Win32CCApi]::IsIconic($hWnd)) {
      [Win32CCApi]::ShowWindow($hWnd, 9) | Out-Null; Start-Sleep -Milliseconds 180
    } else {
      [Win32CCApi]::ShowWindow($hWnd, 5) | Out-Null; Start-Sleep -Milliseconds 70
    }
    [Win32CCApi]::SetWindowPos($hWnd, $HWND_TOPMOST, 0,0,0,0, ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)) | Out-Null
    [Win32CCApi]::SetWindowPos($hWnd, $HWND_NOTOPMOST, 0,0,0,0, ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)) | Out-Null
    [Win32CCApi]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [Win32CCApi]::keybd_event(0x12, 0, 0x0002, [UIntPtr]::Zero)
    [Win32CCApi]::BringWindowToTop($hWnd) | Out-Null
    [Win32CCApi]::SetForegroundWindow($hWnd) | Out-Null
    if ($shell) {
      try {
        if ($targetPid) { [void]$shell.AppActivate([int]$targetPid) }
        [void]$shell.AppActivate("Claude")
      } catch {}
    }
    Start-Sleep -Milliseconds 180
    $fg = [Win32CCApi]::GetForegroundWindow()
    if ($fg -eq $hWnd) { return $true }
  }
  return $false
}

# Read latest Claude Code session JSONL
function Get-LatestCCSessionFile {
  $root = Join-Path $env:USERPROFILE ".claude\projects"
  if (-not (Test-Path $root)) { return $null }
  return Get-ChildItem $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# For last_text: return last assistant entry that has text content (any stop_reason or none)
function Get-LatestCCLastText {
  $f = Get-LatestCCSessionFile
  if (-not $f) { return $null }
  $tailCandidates = @(80, 160, 300)
  foreach ($tailSize in $tailCandidates) {
    $lines = Get-Content $f.FullName -Tail $tailSize -Encoding UTF8 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $line = $lines[$i]
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ($line.Length -gt 100000) { continue }
      if (-not $line.Contains('"type":"assistant"')) { continue }
      try {
        $obj = $line | ConvertFrom-Json
        if ([string]$obj.type -ne 'assistant') { continue }
        $text = ($obj.message.content | Where-Object { $_.type -eq 'text' } |
          ForEach-Object { [string]$_.text }) -join ""
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
        $msgId = [string]$obj.message.id
        return [PSCustomObject]@{
          timestamp = $ts; text = $text
          key = "$($ts.ToString('o'))|$msgId"
          sessionId = [string]$obj.sessionId
        }
      } catch {}
    }
  }
  return $null
}

# For completion watcher / last_meta: return last "end_turn" finalized assistant reply with text
function Get-LatestCCFinalAssistant([switch]$IncludeText) {
  $f = Get-LatestCCSessionFile
  if (-not $f) { return $null }
  $tailCandidates = @(80, 160, 300)
  foreach ($tailSize in $tailCandidates) {
    $lines = Get-Content $f.FullName -Tail $tailSize -Encoding UTF8 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $line = $lines[$i]
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ($line.Length -gt 100000) { continue }
      if (-not $line.Contains('"type":"assistant"')) { continue }
      try {
        $obj = $line | ConvertFrom-Json
        if ([string]$obj.type -ne 'assistant') { continue }
        $sr = [string]$obj.message.stop_reason
        # Accept end_turn (natural finish) or tool_use (agent using tools = also "done" for this turn)
        if ($sr -ne 'end_turn' -and $sr -ne 'tool_use' -and $sr -ne 'max_tokens') { continue }
        $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
        $text = ""
        if ($IncludeText) {
          $text = ($obj.message.content | Where-Object { $_.type -eq 'text' } |
            ForEach-Object { [string]$_.text }) -join ""
          # For tool_use turns, text may be empty - that's OK, still counts as completion
        }
        $msgId = [string]$obj.message.id
        $key = "$($ts.ToString('o'))|$msgId"
        return [PSCustomObject]@{ timestamp = $ts; text = $text; key = $key; sessionId = [string]$obj.sessionId }
      } catch {}
    }
  }
  return $null
}

function Read-AppendedText([string]$path, [int64]$offset) {
  if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) { return "" }
  try {
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      if ($offset -lt 0) { $offset = 0 }
      if ($offset -gt $fs.Length) { $offset = 0 }
      $toRead = [int]([Math]::Min($fs.Length - $offset, 262144))
      if ($toRead -le 0) { return "" }
      $buf = New-Object byte[] $toRead
      $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
      $read = $fs.Read($buf, 0, $toRead)
      if ($read -le 0) { return "" }
      return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    } finally { $fs.Close() }
  } catch { return "" }
}

function Wait-ForCCDelivery([string]$sessionPath, [int64]$beforeBytes, [string]$probe, [int]$timeoutMs = 1800) {
  $started = Get-Date
  while (((Get-Date) - $started).TotalMilliseconds -lt $timeoutMs) {
    $path = $sessionPath
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {
      $sf = Get-LatestCCSessionFile
      if ($sf) { $path = $sf.FullName }
    }
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
      $appended = Read-AppendedText -path $path -offset $beforeBytes
      if (-not [string]::IsNullOrWhiteSpace($appended)) {
        if ([string]::IsNullOrWhiteSpace($probe) -or $appended.Contains($probe)) {
          Write-Dbg "Delivered: probe found in appended bytes."
          return $true
        }
      }
    }
    Start-Sleep -Milliseconds 220
  }
  return $false
}

function Runtime-Exceeded([datetime]$startedAt) {
  return (((Get-Date) - $startedAt).TotalSeconds -ge $MaxRuntimeSec)
}

function Click-At([int]$x, [int]$y) {
  Write-Dbg "Click at x=$x y=$y"
  [Win32CCApi]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 120
  [Win32CCApi]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [Win32CCApi]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 120
}

function Key-Down([byte]$vk) { [Win32CCApi]::keybd_event($vk, 0, 0, [UIntPtr]::Zero) }
function Key-Up([byte]$vk)   { [Win32CCApi]::keybd_event($vk, 0, 0x0002, [UIntPtr]::Zero) }
function Press-Key([byte]$vk, [int]$holdMs = 25) {
  Key-Down $vk; Start-Sleep -Milliseconds $holdMs; Key-Up $vk
}
function Send-CtrlV    { Key-Down 0x11; Start-Sleep -Milliseconds 35; Press-Key 0x56; Start-Sleep -Milliseconds 35; Key-Up 0x11 }
function Send-ShiftIns { Key-Down 0x10; Start-Sleep -Milliseconds 35; Press-Key 0x2D; Start-Sleep -Milliseconds 35; Key-Up 0x10 }
function Send-CtrlA    { Key-Down 0x11; Start-Sleep -Milliseconds 30; Press-Key 0x41; Start-Sleep -Milliseconds 30; Key-Up 0x11 }

function Send-AsciiText([string]$text) {
  foreach ($ch in $text.ToCharArray()) {
    $vkInfo = [Win32CCApi]::VkKeyScan([char]$ch)
    if ($vkInfo -eq -1) { continue }
    $vk = [byte]($vkInfo -band 0x00FF)
    $sh = (($vkInfo -band 0xFF00) -shr 8)
    if (($sh -band 1) -ne 0) { Key-Down 0x10 }
    if (($sh -band 2) -ne 0) { Key-Down 0x11 }
    if (($sh -band 4) -ne 0) { Key-Down 0x12 }
    Press-Key $vk 18
    if (($sh -band 4) -ne 0) { Key-Up 0x12 }
    if (($sh -band 2) -ne 0) { Key-Up 0x11 }
    if (($sh -band 1) -ne 0) { Key-Up 0x10 }
    Start-Sleep -Milliseconds 10
  }
}

function Try-SendAt([IntPtr]$hWnd, [int]$x, [int]$y, [string]$text, [string]$sessionPath, [int64]$beforeBytes, [string]$probe, [datetime]$startedAt) {
  if (Runtime-Exceeded $startedAt) { return $false }
  if (-not (Ensure-WindowForeground $hWnd 2)) {
    Write-Dbg "Focus not confirmed at x=$x y=$y, continuing"
  }
  Click-At $x $y
  try { Set-Clipboard -Value $text } catch { Write-Dbg "Clipboard failed: $($_.Exception.Message)" }

  # Method 1: Shift+Insert
  Send-ShiftIns
  Start-Sleep -Milliseconds 140
  Press-Key 0x0D  # Enter
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForCCDelivery $sessionPath $beforeBytes $probe) { return $true }
  Write-Dbg "Method ShiftInsert failed at x=$x y=$y"

  # Method 2: Ctrl+V
  Click-At $x $y
  Send-CtrlV
  Start-Sleep -Milliseconds 140
  Press-Key 0x0D
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForCCDelivery $sessionPath $beforeBytes $probe) { return $true }
  Write-Dbg "Method CtrlV failed at x=$x y=$y"

  # Method 3: Direct type
  Click-At $x $y
  Send-CtrlA
  Start-Sleep -Milliseconds 60
  Press-Key 0x08  # Backspace
  Start-Sleep -Milliseconds 80
  Send-AsciiText $text
  Start-Sleep -Milliseconds 120
  Press-Key 0x0D
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForCCDelivery $sessionPath $beforeBytes $probe) { return $true }
  Write-Dbg "Method TypeText failed at x=$x y=$y"

  Press-Key 0x1B  # Esc
  Start-Sleep -Milliseconds 120
  return $false
}

function Clamp01([double]$v) {
  if ($v -lt 0.0) { return 0.0 }
  if ($v -gt 1.0) { return 1.0 }
  return $v
}
function Save-Point([double]$xf, [double]$yf) {
  $dir = Split-Path -Parent $PointConfigPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  @{ x_factor = $xf; y_factor = $yf } | ConvertTo-Json | Set-Content -Path $PointConfigPath -Encoding UTF8
}
function Load-Point {
  if (Test-Path $PointConfigPath) {
    try { return Get-Content $PointConfigPath -Raw | ConvertFrom-Json } catch {}
  }
  return $null
}

# ─── scan_inputs ─────────────────────────────────────────────────────────────
if ($Action -eq 'scan_inputs') {
  if (-not $script:UIAutomationReady) { Write-Output 'UIA_NOT_READY'; exit 1 }
  $p = Get-ClaudeWindowProcess
  if (-not $p) { Write-Output 'NO_CLAUDE_WINDOW'; exit 3 }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    $scope = [System.Windows.Automation.TreeScope]::Descendants
    $condEdit = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Edit)
    $edits = $root.FindAll($scope, $condEdit)
    for ($i = 0; $i -lt $edits.Count; $i++) {
      $el = $edits.Item($i)
      $b = $el.Current.BoundingRectangle
      Write-Output "Edit[$i] name='$($el.Current.Name)' class='$($el.Current.ClassName)' bounds=($([int]$b.X),$([int]$b.Y),$([int]$b.Width)x$([int]$b.Height))"
    }
  } catch { Write-Output "SCAN_ERROR: $($_.Exception.Message)" }
  exit 0
}

# ─── bind_here ───────────────────────────────────────────────────────────────
if ($Action -eq 'bind_here') {
  $p = Get-ClaudeWindowProcess
  if (-not $p) { Write-Output 'NO_CLAUDE_WINDOW'; exit 3 }
  $fgOk = Ensure-WindowForeground $p.MainWindowHandle
  if (-not $fgOk) { Write-Output 'WINDOW_NOT_FOCUSED'; exit 5 }
  $rect = New-Object Win32CCApi+RECT
  [Win32CCApi]::GetWindowRect($p.MainWindowHandle, [ref]$rect) | Out-Null
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  if ($w -le 0 -or $h -le 0) { Write-Output 'WINDOW_RECT_INVALID'; exit 4 }
  $pt = [System.Windows.Forms.Cursor]::Position
  $xf = Clamp01(($pt.X - $rect.Left) / [double]$w)
  $yf = Clamp01(($pt.Y - $rect.Top) / [double]$h)
  Save-Point $xf $yf
  Write-Output "BOUND xf=$([Math]::Round($xf,4)) yf=$([Math]::Round($yf,4)) cursor=($($pt.X),$($pt.Y))"
  exit 0
}

# ─── last_text ───────────────────────────────────────────────────────────────
if ($Action -eq 'last_text') {
  $final = Get-LatestCCLastText
  if (-not $final -or [string]::IsNullOrWhiteSpace($final.text)) { Write-Output 'NO_TEXT'; exit 2 }
  Write-Output $final.text
  exit 0
}

# ─── last_meta ───────────────────────────────────────────────────────────────
if ($Action -eq 'last_meta') {
  $final = Get-LatestCCFinalAssistant
  if (-not $final) { Write-Output 'NO_TEXT'; exit 2 }
  [ordered]@{
    timestamp_utc = $final.timestamp.ToString('o')
    key = $final.key
    session_id = $final.sessionId
  } | ConvertTo-Json -Compress
  exit 0
}

# ─── send_continue ───────────────────────────────────────────────────────────
if ($Action -eq 'send_continue') {
  if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue }
  Write-Dbg 'send_continue start'

  if (-not (Acquire-SendLock)) {
    Write-Dbg 'Busy: another cc-bridge process active'
    Write-Output 'SEND_BUSY'; exit 11
  }

  $p = Get-ClaudeWindowProcess
  if (-not $p) {
    Write-Dbg 'No claude.exe window found'
    Release-SendLock
    Write-Output 'NO_CLAUDE_WINDOW'; exit 3
  }

  $fgOk = Ensure-WindowForeground $p.MainWindowHandle
  if (-not $fgOk) { Write-Dbg "Focus not confirmed for claude.exe pid=$($p.Id), continuing" }
  Write-Dbg "Target: claude.exe pid=$($p.Id) hwnd=$($p.MainWindowHandle)"

  $oldClip = ''
  try { $oldClip = Get-Clipboard -Raw } catch {}

  $startedAt = Get-Date
  $sessionFile = Get-LatestCCSessionFile
  $sessionPath = $null; $beforeBytes = 0
  if ($sessionFile) {
    $sessionPath = $sessionFile.FullName
    try { $beforeBytes = (Get-Item $sessionPath).Length } catch {}
  }

  $sendText = $ContinueText
  $probe = $ContinueText.Substring(0, [Math]::Min(24, $ContinueText.Length))
  Write-Dbg "probe=[$probe]"

  $rect = New-Object Win32CCApi+RECT
  [Win32CCApi]::GetWindowRect($p.MainWindowHandle, [ref]$rect) | Out-Null
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top

  # Build candidate list: UIA first, then saved, then fallbacks
  $candidates = @()
  $uiaPoints = Get-UiaInputPoints $p.MainWindowHandle
  foreach ($u in $uiaPoints) {
    $candidates += [PSCustomObject]@{ source = [string]$u.source; abs = $true; x = [int]$u.x; y = [int]$u.y; xf = 0.0; yf = 0.0 }
  }
  $saved = Load-Point
  if ($saved) {
    $sx = [double]$saved.x_factor; $sy = [double]$saved.y_factor
    @($sx, (Clamp01($sx-0.03)), (Clamp01($sx+0.03))) | ForEach-Object {
      $xf2 = $_
      @($sy, (Clamp01($sy-0.03)), (Clamp01($sy+0.03))) | ForEach-Object {
        $candidates += [PSCustomObject]@{ source = "saved"; abs = $false; x = 0; y = 0; xf = $xf2; yf = $_ }
      }
    }
  }
  # Claude Code input is typically near bottom-right (send button area)
  @(
    @(0.55, 0.88), @(0.62, 0.88), @(0.50, 0.88),
    @(0.55, 0.92), @(0.50, 0.92), @(0.62, 0.92),
    @(0.50, 0.85), @(0.46, 0.88), @(0.54, 0.88),
    @(0.50, 0.95)
  ) | ForEach-Object {
    $candidates += [PSCustomObject]@{ source = "fallback-$($_[0])-$($_[1])"; abs = $false; x = 0; y = 0; xf = $_[0]; yf = $_[1] }
  }

  Write-Dbg "Candidates: $(($candidates | ForEach-Object { $_.source }) -join ', ')"

  $attempt = 0
  $used = @{}
  foreach ($pt in $candidates) {
    if ($attempt -ge $MaxAttempts) { break }
    if (Runtime-Exceeded $startedAt) { Write-Dbg 'Runtime exceeded'; break }
    $isAbs = ($pt.PSObject.Properties.Name -contains 'abs' -and $pt.abs)
    $key = if ($isAbs) { "abs:$([int]$pt.x):$([int]$pt.y)" } else { "rel:$($pt.xf)|$($pt.yf)" }
    if ($used.ContainsKey($key)) { continue }
    $used[$key] = $true
    $attempt++
    $x = if ($isAbs) { [int]$pt.x } else { $rect.Left + [int]($w * $pt.xf) }
    $y = if ($isAbs) { [int]$pt.y } else { $rect.Top + [int]($h * $pt.yf) }
    Write-Dbg "Attempt=$attempt source=$($pt.source) x=$x y=$y"

    if (Try-SendAt $p.MainWindowHandle $x $y $sendText $sessionPath $beforeBytes $probe $startedAt) {
      if (-not $isAbs) { Save-Point $pt.xf $pt.yf }
      try { if ($oldClip) { Set-Clipboard -Value $oldClip } } catch {}
      Write-Dbg "SUCCESS attempt=$attempt source=$($pt.source)"
      Release-SendLock
      Write-Output "SENT attempt=$attempt source=$($pt.source) x=$x y=$y pid=$($p.Id) delivered=1"
      exit 0
    }
  }

  try { if ($oldClip) { Set-Clipboard -Value $oldClip } } catch {}
  Write-Dbg "Unconfirmed after $attempt attempts"
  Release-SendLock
  Write-Output "SEND_UNCONFIRMED attempts=$attempt pid=$($p.Id) delivered=0"
  exit 12
}
