param(
  [ValidateSet('send_continue','last_text','last_meta','bind_here')][string]$Action,
  [string]$ContinueText = 'If everything is clear, continue working and testing in this thread. Provide brief status updates.',
  [int]$WaitAfterSendMs = 500,
  [string]$PointConfigPath = 'c:\001_dev\notifier\state\codex-input-point.json',
  [string]$LogPath = 'c:\001_dev\notifier\logs\continue-debug.log',
  [string]$SendLockPath = 'c:\001_dev\notifier\state\bridge-send.lock',
  [int]$MaxRuntimeSec = 35,
  [int]$MaxAttempts = 8,
  [bool]$UseNonce = $false
)

Add-Type -AssemblyName System.Windows.Forms
try {
  Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
  Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
  $script:UIAutomationReady = $true
} catch {
  $script:UIAutomationReady = $false
}
if (-not ("Win32BridgeApi" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32BridgeApi {
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
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
}
# Make GetWindowRect return physical pixels (matches UIA coords, fixes multi-monitor DPI scaling)
try { [Win32BridgeApi]::SetProcessDPIAware() | Out-Null } catch {}

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
        if ($prevPid -gt 0 -and (Get-Process -Id $prevPid -ErrorAction SilentlyContinue)) {
          return $false
        }
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

function Get-CodexWindowProcess {
  return Get-Process Codex -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

function Get-UiaInputPoints([IntPtr]$hWnd) {
  $result = @()
  if (-not $script:UIAutomationReady) { return $result }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hWnd)
    if (-not $root) { return $result }

    $winRect = New-Object Win32BridgeApi+RECT
    [Win32BridgeApi]::GetWindowRect($hWnd, [ref]$winRect) | Out-Null
    $winW = $winRect.Right - $winRect.Left
    $winH = $winRect.Bottom - $winRect.Top
    $scope = [System.Windows.Automation.TreeScope]::Descendants
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::NameProperty,
      'Ask for follow-up changes'
    )
    $placeholder = $null
    $allPlaceholders = $root.FindAll($scope, $nameCond)
    if ($allPlaceholders -and $allPlaceholders.Count -gt 0) {
      $bestY = -1.0
      for ($pi = 0; $pi -lt $allPlaceholders.Count; $pi++) {
        $cand = $allPlaceholders.Item($pi)
        try {
          $cb = $cand.Current.BoundingRectangle
          if ($cb.Width -le 0 -or $cb.Height -le 0) { continue }
          if ($cb.Y -gt $bestY) {
            $bestY = $cb.Y
            $placeholder = $cand
          }
        } catch {}
      }
    }
    if ($placeholder) {
      $pb = $placeholder.Current.BoundingRectangle
      if ($pb.Width -gt 0 -and $pb.Height -gt 0) {
        $cx = [int][Math]::Round($pb.X + [Math]::Min(180.0, ($pb.Width * 0.6)))
        $cy = [int][Math]::Round($pb.Y + ($pb.Height * 0.5))
        $result += [PSCustomObject]@{ x = $cx; y = $cy; source = "uia-composer-placeholder" }
        $result += [PSCustomObject]@{
          x = [int][Math]::Round($cx + 220)
          y = [int][Math]::Round($cy + 2)
          source = "uia-composer-right"
        }
        Write-Dbg "UIA composer placeholder=($cx,$cy) width=$([Math]::Round($pb.Width,1)) height=$([Math]::Round($pb.Height,1))"
      }
    }

    # Keep terminal textarea as a last-resort candidate.
    $classCond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ClassNameProperty,
      'xterm-helper-textarea'
    )
    $xterm = $root.FindFirst($scope, $classCond)
    if ($xterm) {
      $b = $xterm.Current.BoundingRectangle
      if ($b.Width -gt 0 -and $b.Height -gt 0) {
        $rawX = [int][Math]::Round($b.X + ($b.Width / 2.0))
        $rawY = [int][Math]::Round($b.Y + ($b.Height / 2.0))
        Write-Dbg "UIA xterm raw center=($rawX,$rawY) winRect=($($winRect.Left),$($winRect.Top),$($winRect.Right),$($winRect.Bottom))"
        $rawInside = ($rawX -ge $winRect.Left -and $rawX -le $winRect.Right -and $rawY -ge $winRect.Top -and $rawY -le $winRect.Bottom)
        $mappedX = $rawX
        $mappedY = $rawY
        if (-not $rawInside -and $winW -gt 0 -and $winH -gt 0) {
          $rb = $root.Current.BoundingRectangle
          if ($rb.Width -gt 0 -and $rb.Height -gt 0) {
            $nx = ($rawX - $rb.X) / $rb.Width
            $ny = ($rawY - $rb.Y) / $rb.Height
            if ($nx -lt 0) { $nx = 0.0 }
            if ($nx -gt 1) { $nx = 1.0 }
            if ($ny -lt 0) { $ny = 0.0 }
            if ($ny -gt 1) { $ny = 1.0 }
            $mappedX = $winRect.Left + [int][Math]::Round($winW * $nx)
            $mappedY = $winRect.Top + [int][Math]::Round($winH * $ny)
            Write-Dbg "UIA xterm mapped center=($mappedX,$mappedY)"
          }
        }
        if ($mappedX -ne $rawX -or $mappedY -ne $rawY) {
          $result += [PSCustomObject]@{ x = $mappedX; y = $mappedY; source = "uia-input-mapped" }
        }
        $result += [PSCustomObject]@{ x = $rawX; y = $rawY; source = "uia-input" }
      }
    }

    # Note: no stale geometric fallback — coords would be wrong if window moved since UIA query
    return $result
  } catch {
    Write-Dbg "UIA point read failed: $($_.Exception.Message)"
    return @()
  }
}

function Ensure-WindowForeground([IntPtr]$hWnd, [int]$maxTries = 8) {
  $HWND_TOPMOST = [IntPtr](-1)
  $HWND_NOTOPMOST = [IntPtr](-2)
  $SWP_NOMOVE = 0x0002
  $SWP_NOSIZE = 0x0001
  $SWP_NOACTIVATE = 0x0010

  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell } catch {}
  $targetPid = $null
  try {
    $proc = Get-Process Codex -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -eq $hWnd } | Select-Object -First 1
    if ($proc) { $targetPid = $proc.Id }
  } catch {}

  for ($i = 0; $i -lt $maxTries; $i++) {
    if ([Win32BridgeApi]::IsIconic($hWnd)) {
      [Win32BridgeApi]::ShowWindow($hWnd, 9) | Out-Null
      Start-Sleep -Milliseconds 180
    } else {
      [Win32BridgeApi]::ShowWindow($hWnd, 5) | Out-Null
      Start-Sleep -Milliseconds 70
    }

    # Nudge z-order and focus.
    [Win32BridgeApi]::SetWindowPos($hWnd, $HWND_TOPMOST, 0, 0, 0, 0, ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)) | Out-Null
    [Win32BridgeApi]::SetWindowPos($hWnd, $HWND_NOTOPMOST, 0, 0, 0, 0, ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)) | Out-Null

    # Foreground lock workaround: synthesize Alt key before SetForegroundWindow.
    [Win32BridgeApi]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [Win32BridgeApi]::keybd_event(0x12, 0, 0x0002, [UIntPtr]::Zero)

    [Win32BridgeApi]::BringWindowToTop($hWnd) | Out-Null
    [Win32BridgeApi]::SetForegroundWindow($hWnd) | Out-Null

    if ($shell) {
      try {
        if ($targetPid) { [void]$shell.AppActivate([int]$targetPid) }
        [void]$shell.AppActivate("Codex")
      } catch {}
    }

    Start-Sleep -Milliseconds 180
    $fg = [Win32BridgeApi]::GetForegroundWindow()
    if ($fg -eq $hWnd) { return $true }
  }
  return $false
}

function Get-LatestSessionFile {
  return Get-ChildItem 'C:\Users\Vitaly\.codex\sessions' -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-LatestAssistantFinal([switch]$IncludeText) {
  $f = Get-LatestSessionFile
  if (-not $f) { return $null }
  # Keep tails small: very large tails can stall on compacted mega-lines.
  $tailCandidates = @(60, 120, 200)
  foreach ($tailSize in $tailCandidates) {
    $lines = Get-Content $f.FullName -Tail $tailSize -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $line = $lines[$i]
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      # Guard against huge compaction lines that embed escaped JSON payloads.
      if ($line.Length -gt 50000) { continue }
      if (-not $line.StartsWith('{"timestamp":"')) { continue }
      if (-not $line.Contains('","type":"response_item","payload":{"type":"message","role":"assistant"')) { continue }
      try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        if ($obj.type -eq 'response_item' -and $obj.payload.type -eq 'message' -and $obj.payload.role -eq 'assistant') {
          $phase = [string]$obj.payload.phase
          if ($phase -ne 'final' -and $phase -ne 'final_answer') { continue }
          $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
          $text = ""
          if ($IncludeText) {
            foreach ($c in $obj.payload.content) {
              if ($c.type -eq 'output_text' -and $c.text) { $text = [string]$c.text }
            }
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
          }
          $key = $ts.ToString('o')
          if ($IncludeText) {
            $key = "$key|$([Math]::Abs($text.GetHashCode()))"
          }
          return [PSCustomObject]@{
            timestamp = $ts
            text = $text
            key = $key
          }
        }
      } catch {}
    }
  }
  return $null
}

function Get-LatestUserItem {
  $f = Get-LatestSessionFile
  if (-not $f) { return $null }
  $tailCandidates = @(40, 80, 160)
  foreach ($tailSize in $tailCandidates) {
    $lines = Get-Content $f.FullName -Tail $tailSize -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $line = $lines[$i]
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ($line.Length -gt 50000) { continue }
      if (-not $line.StartsWith('{"timestamp":"')) { continue }
      if (-not $line.Contains('","type":"response_item","payload":{"type":"message","role":"user"')) { continue }
      try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        if ($obj.type -ne 'response_item') { continue }
        if ($obj.payload.type -ne 'message' -or $obj.payload.role -ne 'user') { continue }

        $txt = ''
        foreach ($c in $obj.payload.content) {
          if ($c.type -eq 'input_text' -and $c.text) { $txt = [string]$c.text }
        }
        if ([string]::IsNullOrWhiteSpace($txt)) { continue }

        $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
        return [PSCustomObject]@{ timestamp = $ts; text = $txt }
      } catch {}
    }
  }
  return $null
}

function Read-AppendedText([string]$path, [int64]$offset) {
  if ([string]::IsNullOrWhiteSpace($path)) { return "" }
  if (-not (Test-Path $path)) { return "" }
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
    } finally {
      $fs.Close()
    }
  } catch {
    return ""
  }
}

function Wait-ForUserDelivery([string]$sessionPath, [int64]$beforeBytes, [string]$probe, [int]$timeoutMs = 1800) {
  $started = Get-Date
  while (((Get-Date) - $started).TotalMilliseconds -lt $timeoutMs) {
    $path = $sessionPath
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {
      $sf = Get-LatestSessionFile
      if ($sf) { $path = $sf.FullName }
    }
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
      $appended = Read-AppendedText -path $path -offset $beforeBytes
      if (-not [string]::IsNullOrWhiteSpace($appended)) {
        if ([string]::IsNullOrWhiteSpace($probe) -or $appended.Contains($probe)) {
          Write-Dbg "Delivered. probe found in appended session bytes."
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
  [Win32BridgeApi]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 120
  [Win32BridgeApi]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
  [Win32BridgeApi]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 120
}

function Key-Down([byte]$vk) {
  [Win32BridgeApi]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
}

function Key-Up([byte]$vk) {
  [Win32BridgeApi]::keybd_event($vk, 0, 0x0002, [UIntPtr]::Zero)
}

function Press-Key([byte]$vk, [int]$holdMs = 25) {
  Key-Down -vk $vk
  Start-Sleep -Milliseconds $holdMs
  Key-Up -vk $vk
}

function Send-CtrlV {
  Key-Down -vk 0x11 # Ctrl
  Start-Sleep -Milliseconds 35
  Press-Key -vk 0x56 # V
  Start-Sleep -Milliseconds 35
  Key-Up -vk 0x11
}

function Send-ShiftInsert {
  Key-Down -vk 0x10 # Shift
  Start-Sleep -Milliseconds 35
  Press-Key -vk 0x2D # Insert
  Start-Sleep -Milliseconds 35
  Key-Up -vk 0x10
}

function Send-CtrlA {
  Key-Down -vk 0x11 # Ctrl
  Start-Sleep -Milliseconds 30
  Press-Key -vk 0x41 # A
  Start-Sleep -Milliseconds 30
  Key-Up -vk 0x11
}

function Send-AsciiText([string]$text) {
  foreach ($ch in $text.ToCharArray()) {
    $vkInfo = [Win32BridgeApi]::VkKeyScan([char]$ch)
    if ($vkInfo -eq -1) { continue }

    $vk = [byte]($vkInfo -band 0x00FF)
    $shiftState = (($vkInfo -band 0xFF00) -shr 8)

    if (($shiftState -band 1) -ne 0) { Key-Down -vk 0x10 } # Shift
    if (($shiftState -band 2) -ne 0) { Key-Down -vk 0x11 } # Ctrl
    if (($shiftState -band 4) -ne 0) { Key-Down -vk 0x12 } # Alt

    Press-Key -vk $vk -holdMs 18

    if (($shiftState -band 4) -ne 0) { Key-Up -vk 0x12 }
    if (($shiftState -band 2) -ne 0) { Key-Up -vk 0x11 }
    if (($shiftState -band 1) -ne 0) { Key-Up -vk 0x10 }
    Start-Sleep -Milliseconds 10
  }
}

function Try-SendAt([IntPtr]$hWnd, [int]$x, [int]$y, [string]$text, [string]$sessionPath, [int64]$beforeBytes, [string]$probe, [datetime]$startedAt) {
  if (Runtime-Exceeded -startedAt $startedAt) { return $false }
  if (-not (Ensure-WindowForeground -hWnd $hWnd -maxTries 2)) {
    Write-Dbg "Try-SendAt: focus not confirmed before attempt x=$x y=$y, continuing with click"
  }
  $fgNow = [Win32BridgeApi]::GetForegroundWindow()
  Write-Dbg "Try-SendAt focus check: fg=$fgNow target=$hWnd"

  Click-At -x $x -y $y
  try {
    Set-Clipboard -Value $text
    Write-Dbg 'Clipboard set OK'
  } catch {
    Write-Dbg "Clipboard set failed: $($_.Exception.Message)"
  }

  # Method 1: Shift+Insert
  Send-ShiftInsert
  Start-Sleep -Milliseconds 140
  Press-Key -vk 0x0D # Enter
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForUserDelivery -sessionPath $sessionPath -beforeBytes $beforeBytes -probe $probe) { return $true }
  Write-Dbg "Send failed (method=ShiftInsert) at x=$x y=$y"

  # Method 2 fallback: Ctrl+V
  Click-At -x $x -y $y
  Send-CtrlV
  Start-Sleep -Milliseconds 140
  Press-Key -vk 0x0D # Enter
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForUserDelivery -sessionPath $sessionPath -beforeBytes $beforeBytes -probe $probe) { return $true }
  Write-Dbg "Send failed (method=CtrlV) at x=$x y=$y"

  # Method 3 fallback: direct typing via virtual keys (ASCII-oriented)
  Click-At -x $x -y $y
  Send-CtrlA
  Start-Sleep -Milliseconds 60
  Press-Key -vk 0x08 # Backspace
  Start-Sleep -Milliseconds 80
  Send-AsciiText -text $text
  Start-Sleep -Milliseconds 120
  Press-Key -vk 0x0D # Enter
  Start-Sleep -Milliseconds $WaitAfterSendMs
  if (Wait-ForUserDelivery -sessionPath $sessionPath -beforeBytes $beforeBytes -probe $probe) { return $true }
  Write-Dbg "Send failed (method=TypeText) at x=$x y=$y"

  Press-Key -vk 0x1B # Esc
  Start-Sleep -Milliseconds 120
  return $false
}

function Save-Point([double]$xf, [double]$yf) {
  $dir = Split-Path -Parent $PointConfigPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  @{ x_factor = $xf; y_factor = $yf } | ConvertTo-Json | Set-Content -Path $PointConfigPath -Encoding UTF8
}

function Load-Point {
  if (Test-Path $PointConfigPath) {
    try { return Get-Content $PointConfigPath -Raw | ConvertFrom-Json } catch { return $null }
  }
  return $null
}

function Clamp01([double]$v) {
  if ($v -lt 0.0) { return 0.0 }
  if ($v -gt 1.0) { return 1.0 }
  return $v
}

if ($Action -eq 'bind_here') {
  $p = Get-CodexWindowProcess
  if (-not $p) { Write-Output 'NO_CODEX_WINDOW'; exit 3 }

  $fgOk = Ensure-WindowForeground -hWnd $p.MainWindowHandle
  if (-not $fgOk) { Write-Output 'WINDOW_NOT_FOCUSED'; exit 5 }

  $rect = New-Object Win32BridgeApi+RECT
  [Win32BridgeApi]::GetWindowRect($p.MainWindowHandle, [ref]$rect) | Out-Null
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  if ($w -le 0 -or $h -le 0) { Write-Output 'WINDOW_RECT_INVALID'; exit 4 }

  $pt = [System.Windows.Forms.Cursor]::Position
  $xf = Clamp01 (($pt.X - $rect.Left) / [double]$w)
  $yf = Clamp01 (($pt.Y - $rect.Top) / [double]$h)
  Save-Point -xf $xf -yf $yf
  Write-Output "BOUND xf=$([Math]::Round($xf,4)) yf=$([Math]::Round($yf,4)) cursor=($($pt.X),$($pt.Y))"
  exit 0
}

if ($Action -eq 'last_text') {
  $final = Get-LatestAssistantFinal -IncludeText
  if (-not $final -or [string]::IsNullOrWhiteSpace($final.text)) { Write-Output 'NO_TEXT'; exit 2 }
  Write-Output $final.text
  exit 0
}

if ($Action -eq 'last_meta') {
  $final = Get-LatestAssistantFinal
  if (-not $final) { Write-Output 'NO_TEXT'; exit 2 }
  $out = [ordered]@{
    timestamp_utc = $final.timestamp.ToString('o')
    key = $final.key
  } | ConvertTo-Json -Depth 4 -Compress
  Write-Output $out
  exit 0
}

if ($Action -eq 'send_continue') {
  if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue }
  Write-Dbg 'send_continue start'

  if (-not (Acquire-SendLock)) {
    Write-Dbg 'send_continue busy (another bridge process is active)'
    Write-Output 'SEND_BUSY'
    exit 11
  }

  $p = Get-CodexWindowProcess
  if (-not $p) {
    Write-Dbg 'No Codex window'
    Release-SendLock
    Write-Output 'NO_CODEX_WINDOW'
    exit 3
  }

  $fgOk = Ensure-WindowForeground -hWnd $p.MainWindowHandle
  if (-not $fgOk) {
    Write-Dbg "Failed to focus Codex window pid=$($p.Id), continuing with click attempts"
  }
  Write-Dbg "Focus stage done for Codex pid=$($p.Id)"

  $oldClipboard = ''
  try { $oldClipboard = Get-Clipboard -Raw } catch {}

  $startedAt = Get-Date
  $sessionFile = Get-LatestSessionFile
  $sessionPath = $null
  $beforeBytes = 0
  if ($sessionFile) {
    $sessionPath = $sessionFile.FullName
    try { $beforeBytes = (Get-Item $sessionPath).Length } catch { $beforeBytes = 0 }
  }

  $sendText = $ContinueText
  $probe = $ContinueText.Substring(0, [Math]::Min(24, $ContinueText.Length))
  if ($UseNonce) {
    $nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $sendText = "$ContinueText #$nonce"
    $probe = $nonce
    Write-Dbg "Nonce enabled: $nonce"
  }
  Write-Dbg "Probe=[$probe] sendText=[$sendText]"

  $rect = New-Object Win32BridgeApi+RECT
  [Win32BridgeApi]::GetWindowRect($p.MainWindowHandle, [ref]$rect) | Out-Null
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  $midX = $rect.Left + [int]($w / 2)

  # Attempt 0: no-click paste (works if input field is already focused from last session)
  Write-Dbg "Attempt 0: no-click (Esc + CtrlA + CtrlV + Enter)"
  if (-not (Runtime-Exceeded -startedAt $startedAt)) {
    try { Set-Clipboard -Value $sendText } catch {}
    Press-Key -vk 0x1B          # Escape - dismiss any modal
    Start-Sleep -Milliseconds 200
    Send-CtrlA                  # Select all in input
    Start-Sleep -Milliseconds 80
    Send-CtrlV                  # Paste
    Start-Sleep -Milliseconds 250
    Press-Key -vk 0x0D          # Enter
    Start-Sleep -Milliseconds $WaitAfterSendMs
    if (Wait-ForUserDelivery -sessionPath $sessionPath -beforeBytes $beforeBytes -probe $probe) {
      try { if ($oldClipboard) { Set-Clipboard -Value $oldClipboard } } catch {}
      Write-Dbg "SUCCESS no-click"
      Release-SendLock
      Write-Output "SENT attempt=0 source=no-click delivered=1"
      exit 0
    }
    Write-Dbg "No-click failed, trying coordinate-based"
  }

  $saved = Load-Point
  $savedCandidates = @()
  if ($saved) {
    $sx = [double]$saved.x_factor
    $sy = [double]$saved.y_factor
    $savedCandidates += [PSCustomObject]@{ xf = $sx; yf = $sy; source = "saved" }
    $savedCandidates += [PSCustomObject]@{ xf = (Clamp01 ($sx - 0.03)); yf = $sy; source = "saved-left" }
    $savedCandidates += [PSCustomObject]@{ xf = (Clamp01 ($sx + 0.03)); yf = $sy; source = "saved-right" }
    $savedCandidates += [PSCustomObject]@{ xf = $sx; yf = (Clamp01 ($sy - 0.03)); source = "saved-up" }
    $savedCandidates += [PSCustomObject]@{ xf = $sx; yf = (Clamp01 ($sy + 0.03)); source = "saved-down" }
  }

  $fallbackCandidates = @(
    [PSCustomObject]@{ xf = 0.55; yf = 0.84; source = "fallback-x55-y84" },
    [PSCustomObject]@{ xf = 0.62; yf = 0.84; source = "fallback-x62-y84" },
    [PSCustomObject]@{ xf = 0.50; yf = 0.84; source = "fallback-center-y84" },
    [PSCustomObject]@{ xf = 0.50; yf = 0.87; source = "fallback-center-y87" },
    [PSCustomObject]@{ xf = 0.62; yf = 0.87; source = "fallback-x62-y87" },
    [PSCustomObject]@{ xf = 0.46; yf = 0.84; source = "fallback-left-y84" },
    [PSCustomObject]@{ xf = 0.54; yf = 0.84; source = "fallback-right-y84" },
    [PSCustomObject]@{ xf = 0.50; yf = 0.90; source = "fallback-center-y90" },
    [PSCustomObject]@{ xf = 0.50; yf = 0.94; source = "fallback-center-y94" }
  )

  $candidates = @()
  $uiaPoints = Get-UiaInputPoints -hWnd $p.MainWindowHandle

  # 1. UIA composer/placeholder candidates first (most accurate when follow-up input is visible)
  foreach ($uiaPoint in ($uiaPoints | Where-Object { $_.source -notmatch 'xterm|uia-input' })) {
    $candidates += [PSCustomObject]@{
      source = [string]$uiaPoint.source
      abs = $true
      x = [int]$uiaPoint.x
      y = [int]$uiaPoint.y
      xf = 0.0
      yf = 0.0
    }
  }
  # 2. Bottom-anchored: reliable position-independent clicks (now DPI-aware, so rect is correct)
  @(55, 75, 95, 40, 115, 130) | ForEach-Object {
    $candidates += [PSCustomObject]@{
      source = "bottom-${_}px"; abs = $true
      x = $midX; y = $rect.Bottom - [int]$_; xf = 0.0; yf = 0.0
    }
  }
  # 3. Saved point (percentage-based, valid across window positions)
  $candidates += $savedCandidates
  # 4. UIA xterm candidates last (often has wrong/outside-window coords on DPI-scaled monitors)
  foreach ($uiaPoint in ($uiaPoints | Where-Object { $_.source -match 'xterm|uia-input' })) {
    $candidates += [PSCustomObject]@{
      source = [string]$uiaPoint.source
      abs = $true
      x = [int]$uiaPoint.x
      y = [int]$uiaPoint.y
      xf = 0.0
      yf = 0.0
    }
  }
  $candidates += $fallbackCandidates
  Write-Dbg "Candidate order: $((($candidates | ForEach-Object { $_.source }) -join ', '))"

  $attempt = 0
  $used = @{}
  foreach ($pt in $candidates) {
    if ($attempt -ge $MaxAttempts) { break }
    if (Runtime-Exceeded -startedAt $startedAt) {
      Write-Dbg 'Runtime exceeded before next attempt'
      break
    }

    $isAbs = ($pt.PSObject.Properties.Name -contains 'abs' -and $pt.abs)
    if ($isAbs) {
      $key = "abs:$([int]$pt.x):$([int]$pt.y)"
    } else {
      $key = "rel:$($pt.xf)|$($pt.yf)"
    }
    if ($used.ContainsKey($key)) { continue }
    $used[$key] = $true

    $attempt++
    if ($isAbs) {
      $x = [int]$pt.x
      $y = [int]$pt.y
    } else {
      $x = $rect.Left + [int]($w * $pt.xf)
      $y = $rect.Top + [int]($h * $pt.yf)
    }
    Write-Dbg "Try attempt=$attempt source=$($pt.source) xf=$($pt.xf) yf=$($pt.yf)"

    if (Try-SendAt -hWnd $p.MainWindowHandle -x $x -y $y -text $sendText -sessionPath $sessionPath -beforeBytes $beforeBytes -probe $probe -startedAt $startedAt) {
      if (-not ($pt.PSObject.Properties.Name -contains 'abs' -and $pt.abs)) {
        Save-Point -xf $pt.xf -yf $pt.yf
      }
      try { if ($oldClipboard) { Set-Clipboard -Value $oldClipboard } } catch {}
      Write-Dbg "Success attempt=$attempt source=$($pt.source)"
      Release-SendLock
      Write-Output "SENT attempt=$attempt source=$($pt.source) x=$x y=$y pid=$($p.Id) delivered=1"
      exit 0
    }
  }

  try { if ($oldClipboard) { Set-Clipboard -Value $oldClipboard } } catch {}
  Write-Dbg "Unconfirmed delivery after attempts=$attempt"
  Release-SendLock
  Write-Output "SEND_UNCONFIRMED attempts=$attempt pid=$($p.Id) delivered=0"
  exit 12
}

