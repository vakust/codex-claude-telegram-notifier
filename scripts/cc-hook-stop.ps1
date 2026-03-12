param(
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1",
  [string]$HookStatePath = "c:\001_dev\notifier\state\cc-hook-state.json",
  [string]$LogPath = "c:\001_dev\notifier\logs\cc-hook.log"
)

$ErrorActionPreference = "Continue"
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-HookLog([string]$msg) {
  try {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    Add-Content -Path $LogPath -Value "$ts | $msg" -Encoding UTF8
  } catch {}
}

if (-not (Test-Path $ConfigPath)) { Write-HookLog "Config not found: $ConfigPath"; exit 0 }
. $ConfigPath
$bot = $env:TG_BOT_TOKEN
$chat = $env:TG_CHAT_ID
if (-not $bot -or -not $chat) { Write-HookLog "Missing TG creds"; exit 0 }

$sender = "c:\001_dev\notifier\scripts\send-telegram.ps1"
$menu = '{"keyboard":[[{"text":"Status"},{"text":"Continue"},{"text":"CC: Continue"}],[{"text":"Fix+Retest"},{"text":"CC: Fix+Retest"},{"text":"Stop"}],[{"text":"Set Custom"},{"text":"Send Custom"},{"text":"CC: Custom"}],[{"text":"Show Custom"},{"text":"Clear Custom"}],[{"text":"Last Text"},{"text":"CC: Last Text"},{"text":"Bind Point"},{"text":"CC: Bind"}]],"resize_keyboard":true,"is_persistent":true}'

function Send-Tg([string]$text) {
  & $sender -BotToken $bot -ChatId $chat -Text $text -ReplyMarkup $menu
}

# --- Read stdin (hook data from Claude Code) ---
$stdinText = ""
try {
  $stdinText = [Console]::In.ReadToEnd()
} catch {
  Write-HookLog "stdin read error: $($_.Exception.Message)"
}

$hookData = $null
$sessionId = ""
$lastText = ""

if (-not [string]::IsNullOrWhiteSpace($stdinText)) {
  try {
    $hookData = $stdinText | ConvertFrom-Json
    $sessionId = [string]$hookData.session_id
    $eventName = [string]$hookData.hook_event_name
    Write-HookLog "Hook received session=$sessionId event=$eventName"

    # Only process Stop events - ignore Notification, PreToolUse, PostToolUse, etc.
    if ($eventName -ne 'Stop') {
      Write-HookLog "Ignoring non-Stop event: $eventName"
      exit 0
    }

    # Extract last assistant text from transcript
    if ($hookData.transcript -and $hookData.transcript.Count -gt 0) {
      for ($i = $hookData.transcript.Count - 1; $i -ge 0; $i--) {
        $msg = $hookData.transcript[$i]
        if ([string]$msg.role -eq 'assistant') {
          $txt = ($msg.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { [string]$_.text }) -join ""
          if (-not [string]::IsNullOrWhiteSpace($txt)) {
            $lastText = $txt
            break
          }
        }
      }
    }
  } catch {
    Write-HookLog "JSON parse error: $($_.Exception.Message)"
  }
}

# Fallback: read from JSONL if no text from stdin
if ([string]::IsNullOrWhiteSpace($lastText)) {
  Write-HookLog "Fallback: reading JSONL for last text"
  try {
    $ccRoot = Join-Path $env:USERPROFILE ".claude\projects"
    $latestFile = Get-ChildItem $ccRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestFile) {
      $lines = Get-Content $latestFile.FullName -Tail 80 -Encoding UTF8 -ErrorAction SilentlyContinue
      for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 100000) { continue }
        if (-not $line.Contains('"type":"assistant"')) { continue }
        try {
          $obj = $line | ConvertFrom-Json
          if ([string]$obj.type -ne 'assistant') { continue }
          $sr = [string]$obj.message.stop_reason
          if ([string]::IsNullOrWhiteSpace($sr)) { continue }
          if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = [string]$obj.sessionId }
          $lastText = ($obj.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { [string]$_.text }) -join ""
          if (-not [string]::IsNullOrWhiteSpace($lastText)) { break }
        } catch {}
      }
    }
  } catch {
    Write-HookLog "JSONL fallback error: $($_.Exception.Message)"
  }
}

# --- Deduplication ---
$key = "$sessionId|$([Math]::Abs($lastText.GetHashCode()))"
$lastKey = ""
if (Test-Path $HookStatePath) {
  try { $lastKey = [string]((Get-Content $HookStatePath -Raw | ConvertFrom-Json).last_key) } catch {}
}
if ($key -eq $lastKey) {
  Write-HookLog "Duplicate key=$key, skip"
  exit 0
}
try {
  @{ last_key = $key; ts = (Get-Date).ToString('o') } | ConvertTo-Json |
    Set-Content -Path $HookStatePath -Encoding UTF8
} catch {}

# --- Notify ---
$ts = (Get-Date).ToString("HH:mm:ss")
$notify = "[CC] Done $ts"
Write-HookLog "Sending notification key=$key"
Send-Tg $notify | Out-Null

if (-not [string]::IsNullOrWhiteSpace($lastText)) {
  $max = 3200
  $preview = $lastText
  if ($preview.Length -gt $max) { $preview = $preview.Substring(0, $max) + " ..." }
  $safe = [System.Web.HttpUtility]::HtmlEncode($preview)
  Send-Tg "[CC] <pre>$safe</pre>" | Out-Null
}

Write-HookLog "Done"
exit 0
