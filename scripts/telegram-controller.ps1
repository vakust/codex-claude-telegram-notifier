param(
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1",
  [string]$CommandsPath = "c:\001_dev\notifier\commands.json",
  [string]$OffsetPath = "c:\001_dev\notifier\state\telegram.offset",
  [string]$StatePath = "c:\001_dev\notifier\state\current-task.json",
  [string]$PidPath = "c:\001_dev\notifier\state\current-task.pid",
  [string]$ActionStampPath = "c:\001_dev\notifier\state\action-last.txt",
  [string]$CompletionWatchPath = "c:\001_dev\notifier\state\completion-watch.json",
  [string]$CustomPromptPath = "c:\001_dev\notifier\state\custom-prompt.txt",
  [string]$CustomAwaitPath = "c:\001_dev\notifier\state\custom-await.flag",
  [string]$ControllerLogPath = "c:\001_dev\notifier\logs\controller.log",
  [string]$OneShotAction = "",
  [string]$OneShotPrompt = "",
  [int]$CliSendTimeoutSec = 45,
  [int]$ActionCooldownSec = 8,
  [int]$CompletionPollSec = 2,
  [int]$PollSeconds = 1,
  [int]$TelegramTimeoutSec = 4
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
if (-not (Test-Path $CommandsPath)) { throw "Commands file not found: $CommandsPath" }

. $ConfigPath

$bot = $env:TG_BOT_TOKEN
$chat = $env:TG_CHAT_ID
if (-not $bot -or -not $chat) { throw "Missing TG_BOT_TOKEN or TG_CHAT_ID." }

$stateDir = Split-Path -Parent $StatePath
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }

$commands = Get-Content $CommandsPath -Raw | ConvertFrom-Json
$runScript = "c:\001_dev\notifier\scripts\run-with-notify.ps1"
$sender = "c:\001_dev\notifier\scripts\send-telegram.ps1"
$bridge = "c:\001_dev\notifier\scripts\codex-bridge.ps1"
$codexCli = "codex"
$codexCliLastMessagePath = "c:\001_dev\notifier\state\cli-last-message.txt"
$codexSessionsRoot = Join-Path $env:USERPROFILE ".codex\sessions"
$codexSessionIdPath = "c:\001_dev\notifier\state\codex-session-id.txt"
$ccBridge = "c:\001_dev\notifier\scripts\cc-bridge.ps1"
$ccSessionsRoot = Join-Path $env:USERPROFILE ".claude\projects"
$ccCompletionWatchPath = "c:\001_dev\notifier\state\cc-completion-watch.json"
$menu = '{"keyboard":[[{"text":"Status"},{"text":"Continue"},{"text":"CC: Continue"}],[{"text":"Fix+Retest"},{"text":"CC: Fix+Retest"},{"text":"Stop"}],[{"text":"Set Custom"},{"text":"Send Custom"},{"text":"CC: Custom"}],[{"text":"Show Custom"},{"text":"Clear Custom"}],[{"text":"Last Text"},{"text":"CC: Last Text"},{"text":"Bind Point"},{"text":"CC: Bind"}]],"resize_keyboard":true,"is_persistent":true}'

$script:watchInitialized = $false
$script:lastCompletionKey = ""
$script:lastCompletionCheck = [DateTime]::MinValue
$script:pendingCompletion = $false
$script:pendingSinceUtc = [DateTime]::MinValue
$script:pendingLabel = ""

# CC watcher state
$script:ccWatchInitialized = $false
$script:ccLastCompletionKey = ""
$script:ccLastCompletionCheck = [DateTime]::MinValue

$ActionAText = "If everything is clear and you know what to do next, continue working and testing in this thread. Provide brief status updates."
$ActionCText = "Continue testing. If you find errors, fix them, then run tests again. Keep working until all bugs for this task are fixed. Provide brief status updates."

function Send-Tg([string]$text) {
  & $sender -BotToken $bot -ChatId $chat -Text $text -ReplyMarkup $menu
  return ($LASTEXITCODE -eq 0)
}

function Write-CtrlLog([string]$msg) {
  try {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    Add-Content -Path $ControllerLogPath -Value "$ts | $msg" -Encoding UTF8
  } catch {}
}

function Get-LatestCodexSessionId {
  if (-not (Test-Path $codexSessionsRoot)) { return "" }
  try {
    $latest = Get-ChildItem $codexSessionsRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return "" }
    if ($latest.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') {
      return $matches[1]
    }
    return ""
  } catch {
    return ""
  }
}

function Get-PinnedCodexSessionId {
  if (-not (Test-Path $codexSessionIdPath)) { return "" }
  try {
    $sid = (Get-Content $codexSessionIdPath -Raw).Trim()
    if ($sid -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
      return $sid
    }
    return ""
  } catch {
    return ""
  }
}

function Pin-CodexSessionId([string]$sid) {
  if ([string]::IsNullOrWhiteSpace($sid)) { return }
  try { Set-Content -Path $codexSessionIdPath -Value $sid -Encoding ASCII } catch {}
}

function Invoke-CodexCliSend([string]$prompt) {
  $sid = Get-PinnedCodexSessionId
  if ([string]::IsNullOrWhiteSpace($sid)) {
    $sid = Get-LatestCodexSessionId
    if (-not [string]::IsNullOrWhiteSpace($sid)) {
      Pin-CodexSessionId -sid $sid
      Write-CtrlLog "Pinned Codex session id: $sid"
    }
  }
  if ([string]::IsNullOrWhiteSpace($sid)) {
    return [PSCustomObject]@{
      success = $false
      session_id = ""
      exit_code = -1
      out = "NO_SESSION_ID"
    }
  }

  $args = @(
    "exec","resume",$sid,$prompt,
    "--skip-git-repo-check",
    "--json",
    "-o",$codexCliLastMessagePath
  )
  $job = Start-Job -ScriptBlock {
    param($cli, $argv)
    $ErrorActionPreference = "Continue"
    $out = & $cli @argv 2>&1
    $exitCode = $LASTEXITCODE
    $outText = (($out | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
    }) -join " ").Trim()
    return [PSCustomObject]@{
      exit_code = $exitCode
      out = $outText
    }
  } -ArgumentList $codexCli, $args
  $done = Wait-Job -Job $job -Timeout $CliSendTimeoutSec
  if (-not $done) {
    try { Stop-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    return [PSCustomObject]@{
      success = $false
      session_id = $sid
      exit_code = -2
      out = "CLI_TIMEOUT"
    }
  }
  $jr = $null
  try { $jr = Receive-Job -Job $job -ErrorAction SilentlyContinue } catch {}
  try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
  $exitCode = [int]$jr.exit_code
  $outText = [string]$jr.out
  $completed = ($outText -match '"turn.completed"')
  $success = ($exitCode -eq 0 -and $completed)
  return [PSCustomObject]@{
    success = $success
    session_id = $sid
    exit_code = $exitCode
    out = $outText
  }
}

function Send-Help {
  $msg = @"
<b>Codex + Claude Code Notifier</b>

<b>Codex Desktop buttons:</b>
- Continue / Fix+Retest: send prompt to active Codex thread
- Bind Point: save mouse pos over Codex input

<b>Claude Code (CC) buttons:</b>
- CC: Continue / CC: Fix+Retest: send prompt to Claude Code
- CC: Custom: send saved custom prompt to Claude Code
- CC: Last Text: show last CC assistant reply
- CC: Bind: save mouse pos over Claude Code input

<b>Common:</b>
- Set Custom -&gt; Send Custom: save and send custom prompt (Codex)
- Last Text: last assistant text from Codex
- Status: show local state
- Stop: stop local wrapper PID

<b>Completion notifications</b> arrive automatically from both Codex (JSONL watcher) and Claude Code (hook + JSONL watcher).
Codex messages have no prefix; Claude Code messages are prefixed <b>[CC]</b>.
"@
  Send-Tg $msg
}

function Send-TgChunked([string]$prefix, [string]$text) {
  $max = 3200
  if ([string]::IsNullOrWhiteSpace($text)) {
    return (Send-Tg $prefix)
  }
  $remaining = $text
  $part = 1
  while ($remaining.Length -gt $max) {
    $chunk = $remaining.Substring(0, $max)
    $remaining = $remaining.Substring($max)
    $safe = [System.Web.HttpUtility]::HtmlEncode($chunk)
    $ok = Send-Tg "$prefix (part $part)`n<pre>$safe</pre>"
    if (-not $ok) { return $false }
    $part++
    Start-Sleep -Milliseconds 150
  }
  $safeLast = [System.Web.HttpUtility]::HtmlEncode($remaining)
  return (Send-Tg "$prefix (part $part)`n<pre>$safeLast</pre>")
}

function Get-Offset() {
  if (Test-Path $OffsetPath) { return [int](Get-Content $OffsetPath -Raw) }
  return 0
}

function Save-Offset([int]$offset) {
  Set-Content -Path $OffsetPath -Value ([string]$offset) -Encoding ASCII
}

function Get-Updates([int]$offset) {
  $uri = "https://api.telegram.org/bot$bot/getUpdates?timeout=$TelegramTimeoutSec&offset=$offset"
  return Invoke-RestMethod -Method Get -Uri $uri
}

function Start-TemplateTask([string]$key, [string]$title) {
  $cfg = $commands.$key
  if (-not $cfg) {
    Send-Tg "Template not found: $key"
    return
  }

  $args = @(
    "-ExecutionPolicy","Bypass","-File",$runScript,
    "-TaskName",$cfg.task_name,
    "-Command",$cfg.command,
    "-HeartbeatMinutes",[string]$cfg.heartbeat_minutes,
    "-TimeoutMinutes",[string]$cfg.timeout_minutes,
    "-LogPath",$cfg.log_path
  )

  Start-Process -FilePath "powershell" -ArgumentList $args -WindowStyle Hidden | Out-Null
  Send-Tg "Accepted: $title`nTask: $($cfg.task_name)"
}

function Can-RunAction {
  if (-not (Test-Path $ActionStampPath)) { return $true }
  try {
    $last = [DateTime]::Parse((Get-Content $ActionStampPath -Raw))
    $delta = (Get-Date) - $last
    if ($delta.TotalSeconds -lt $ActionCooldownSec) { return $false }
    return $true
  } catch {
    return $true
  }
}

function Mark-ActionRun {
  Set-Content -Path $ActionStampPath -Value ((Get-Date).ToString("o")) -Encoding ASCII
}

function Get-LastAssistantText {
  $txt = & $bridge -Action last_text
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($txt -join ""))) { return "" }
  return (($txt -join "`n").Trim())
}

function Send-LastText {
  $raw = Get-LastAssistantText
  if ([string]::IsNullOrWhiteSpace($raw)) {
    Send-Tg "Could not read last assistant text from Codex session yet."
    return
  }
  Send-TgChunked -prefix "Last assistant text:" -text $raw
}

function Load-CustomPrompt {
  if (-not (Test-Path $CustomPromptPath)) { return "" }
  return (Get-Content $CustomPromptPath -Raw -Encoding UTF8).Trim()
}

function Save-CustomPrompt([string]$text) {
  Set-Content -Path $CustomPromptPath -Value $text -Encoding UTF8
}

function Send-Status {
  if (-not (Test-Path $StatePath)) {
    Send-Tg "Status: no local task state yet."
    return
  }

  try {
    $s = Get-Content $StatePath -Raw | ConvertFrom-Json
    $task = [string]$s.task
    $status = [string]$s.status
    $started = [string]$s.started_at
    $updated = [string]$s.updated_at
    $pid = [string]$s.pid
    $duration = [string]$s.duration_minutes
    $exitCode = [string]$s.exit_code

    if ([string]::IsNullOrWhiteSpace($task)) { $task = "-" }
    if ([string]::IsNullOrWhiteSpace($status)) { $status = "-" }
    if ([string]::IsNullOrWhiteSpace($started)) { $started = "-" }
    if ([string]::IsNullOrWhiteSpace($updated)) { $updated = "-" }
    if ([string]::IsNullOrWhiteSpace($pid)) { $pid = "-" }
    if ([string]::IsNullOrWhiteSpace($duration)) { $duration = "-" }
    if ([string]::IsNullOrWhiteSpace($exitCode)) { $exitCode = "-" }

    $statusText = @"
Status:
Task: $task
State: $status
PID: $pid
Duration (min): $duration
Exit code: $exitCode
Started: $started
Updated: $updated
"@
    Send-Tg $statusText
  } catch {
    Send-Tg "Status read error: $($_.Exception.Message)"
  }
}

function Set-CustomAwaitMode([bool]$enabled) {
  if ($enabled) {
    Set-Content -Path $CustomAwaitPath -Value "1" -Encoding ASCII
  } else {
    Remove-Item $CustomAwaitPath -ErrorAction SilentlyContinue
  }
}

function Is-CustomAwaitMode {
  return (Test-Path $CustomAwaitPath)
}

function Stop-CurrentTask() {
  $stoppedPid = ""
  if (Test-Path $PidPath) {
    $taskPid = [int](Get-Content $PidPath -Raw)
    try {
      Stop-Process -Id $taskPid -Force
      $stoppedPid = "$taskPid"
    }
    catch {}
    Remove-Item $PidPath -ErrorAction SilentlyContinue
  }

  Set-CustomAwaitMode -enabled $false

  if ([string]::IsNullOrWhiteSpace($stoppedPid)) {
    Send-Tg "Stop: no local task process was running."
  } else {
    Send-Tg "Stop: local task PID $stoppedPid stopped."
  }
}

function Get-LatestFinalAssistant {
  $rawMeta = & $bridge -Action last_meta
  if ($LASTEXITCODE -eq 0) {
    $metaText = (($rawMeta -join "`n").Trim())
    if (-not [string]::IsNullOrWhiteSpace($metaText)) {
      try {
        $m = $metaText | ConvertFrom-Json -ErrorAction Stop
        if ($m.key -and $m.timestamp_utc) {
          return [PSCustomObject]@{
            timestamp = [DateTime]::Parse([string]$m.timestamp_utc).ToUniversalTime()
            text = [string]$m.text
            key = [string]$m.key
          }
        }
      } catch {}
    }
  }

  $raw = & $bridge -Action last_text
  if ($LASTEXITCODE -ne 0) { return $null }
  $text = (($raw -join "`n").Trim())
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  return [PSCustomObject]@{
    timestamp = (Get-Date).ToUniversalTime()
    text = $text
    key = "fallback|$([Math]::Abs($text.GetHashCode()))"
  }
}

function Load-CompletionWatchState {
  if (Test-Path $CompletionWatchPath) {
    try {
      $s = Get-Content $CompletionWatchPath -Raw | ConvertFrom-Json
      $script:watchInitialized = [bool]$s.initialized
      $script:lastCompletionKey = [string]$s.last_key
      $script:pendingCompletion = [bool]$s.pending
      $script:pendingLabel = [string]$s.pending_label
      if ($s.pending_since_utc) {
        $script:pendingSinceUtc = [DateTime]::Parse([string]$s.pending_since_utc).ToUniversalTime()
      }
    } catch {
      $script:watchInitialized = $false
      $script:lastCompletionKey = ""
      $script:pendingCompletion = $false
      $script:pendingLabel = ""
      $script:pendingSinceUtc = [DateTime]::MinValue
    }
  }
}

function Save-CompletionWatchState {
  $obj = [ordered]@{
    initialized = $script:watchInitialized
    last_key = $script:lastCompletionKey
    pending = $script:pendingCompletion
    pending_label = $script:pendingLabel
    pending_since_utc = $(if ($script:pendingCompletion) { $script:pendingSinceUtc.ToString('o') } else { "" })
    updated_at = (Get-Date).ToString('o')
  }
  $obj | ConvertTo-Json | Set-Content -Path $CompletionWatchPath -Encoding UTF8
}

function Set-PendingCompletion([string]$label) {
  $script:pendingCompletion = $true
  $script:pendingLabel = $label
  $script:pendingSinceUtc = (Get-Date).ToUniversalTime()
  Save-CompletionWatchState
}

function Clear-PendingCompletion {
  $script:pendingCompletion = $false
  $script:pendingLabel = ""
  $script:pendingSinceUtc = [DateTime]::MinValue
  Save-CompletionWatchState
}

function Check-CompletionWatcher {
  $now = Get-Date
  if (($now - $script:lastCompletionCheck).TotalSeconds -lt $CompletionPollSec) { return }
  $script:lastCompletionCheck = $now

  $latest = Get-LatestFinalAssistant
  if ($null -eq $latest) { return }

  if (-not $script:watchInitialized) {
    $script:watchInitialized = $true
    $script:lastCompletionKey = $latest.key
    Save-CompletionWatchState
    Write-CtrlLog "Watcher initialized with key=$($latest.key)"
    return
  }

  if ($latest.key -eq $script:lastCompletionKey) { return }

  Write-CtrlLog "New completion candidate key=$($latest.key)"
  $completionText = [string]$latest.text
  if ([string]::IsNullOrWhiteSpace($completionText)) {
    $completionText = Get-LastAssistantText
  }
  if ([string]::IsNullOrWhiteSpace($completionText)) {
    $completionText = "(last assistant text is not available yet)"
  }
  $ok1 = Send-Tg "Completion detected at $($latest.timestamp.ToString('yyyy-MM-dd HH:mm:ss')) UTC."
  $ok2 = Send-TgChunked -prefix "Completion last assistant text:" -text $completionText

  if ($ok1 -and $ok2) {
    $script:lastCompletionKey = $latest.key
    Save-CompletionWatchState
    Write-CtrlLog "Completion notification sent; key committed=$($latest.key)"
  } else {
    Write-CtrlLog "Completion notification send failed; will retry key=$($latest.key)"
  }
}

function Send-ActionText([string]$label, [string]$prompt) {
  Write-CtrlLog "Action requested: $label"
  if (-not (Can-RunAction)) {
    Write-CtrlLog "Action rejected by cooldown: $label"
    Send-Tg "$label ignored (cooldown). Try again in ~$ActionCooldownSec s."
    return
  }
  Send-Tg "$label sending..."
  try {
    $cli = Invoke-CodexCliSend -prompt $prompt
    if ($cli.success) {
      Mark-ActionRun
      Write-CtrlLog "Action delivered (cli): $label | session=$($cli.session_id)"
      Send-Tg "$label delivered."
      return
    }

    $cliOutShort = $cli.out
    if ($cliOutShort.Length -gt 300) { $cliOutShort = $cliOutShort.Substring(0,300) + " ..." }
    Write-CtrlLog "Action CLI fallback to bridge: $label | exit=$($cli.exit_code) | session=$($cli.session_id) | out=$cliOutShort"

    $out = & $bridge -Action send_continue -ContinueText $prompt -UseNonce:$false
    $exitCode = $LASTEXITCODE
    $outText = ($out -join ' ')
    $delivered = ($outText -match 'delivered=1')

    if ($exitCode -eq 0 -and $delivered) {
      Mark-ActionRun
      Write-CtrlLog "Action delivered (bridge): $label | bridge_out=$outText"
      Send-Tg "$label delivered."
      return
    }

    Write-CtrlLog "Action failed: $label | exit=$exitCode | bridge_out=$outText"
    if ($outText.Contains('SEND_BUSY')) {
      Send-Tg "$label failed: bridge is busy (previous send is still running). Try again in a few seconds."
    } elseif ($outText.Contains('WINDOW_NOT_FOCUSED')) {
      Send-Tg "$label failed: could not activate Codex window from background. Try Bind Point once, then Continue again."
    } elseif ($outText.Contains('SEND_UNCONFIRMED') -or $outText.Contains('delivered=0')) {
      Send-Tg "$label not delivered (unconfirmed). Try once more."
    } else {
      Send-Tg "$label failed: $outText"
    }
  } catch {
    $err = $_.Exception.Message
    Write-CtrlLog "Action exception: $label | $err"
    Send-Tg "$label failed: internal bridge exception. Retry once."
  }
}

function Bind-InputPoint {
  Send-Tg "Bind Point: place mouse cursor over Codex input area and press the button once."
  try {
    $out = & $bridge -Action bind_here
    $exitCode = $LASTEXITCODE
    $outText = ($out -join ' ')
    if ($exitCode -eq 0) {
      Write-CtrlLog "Bind success: $outText"
      Send-Tg "Bind saved: $outText"
    } else {
      Write-CtrlLog "Bind failed: exit=$exitCode out=$outText"
      Send-Tg "Bind failed: $outText"
    }
  } catch {
    $err = $_.Exception.Message
    Write-CtrlLog "Bind exception: $err"
    Send-Tg "Bind failed: internal bridge exception. Retry once."
  }
}

# ─── CC (Claude Code) functions ───────────────────────────────────────────────

function Send-CcActionText([string]$label, [string]$prompt) {
  Write-CtrlLog "CC Action: $label"
  if (-not (Can-RunAction)) {
    Write-CtrlLog "CC Action cooldown: $label"
    Send-Tg "$label ignored (cooldown ~$ActionCooldownSec s)."
    return
  }
  Send-Tg "$label sending..."
  try {
    $out = & $ccBridge -Action send_continue -ContinueText $prompt
    $exitCode = $LASTEXITCODE
    $outText = ($out -join ' ')
    $delivered = ($outText -match 'delivered=1')
    if ($exitCode -eq 0 -and $delivered) {
      Mark-ActionRun
      Write-CtrlLog "CC Action delivered: $label | $outText"
      Send-Tg "$label delivered."
    } elseif ($outText.Contains('SEND_BUSY')) {
      Send-Tg "$label failed: CC bridge busy. Try again in a few seconds."
    } elseif ($outText.Contains('NO_CLAUDE_WINDOW')) {
      Send-Tg "$label failed: no Claude window found. Is Claude Code open?"
    } elseif ($outText.Contains('WINDOW_NOT_FOCUSED')) {
      Send-Tg "$label failed: could not focus Claude window. Try CC: Bind once."
    } else {
      Send-Tg "$label not delivered. $outText"
    }
  } catch {
    $err = $_.Exception.Message
    Write-CtrlLog "CC Action exception: $label | $err"
    Send-Tg "$label failed: $err"
  }
}

function Send-CcLastText {
  $out = & $ccBridge -Action last_text
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($out -join ""))) {
    Send-Tg "[CC] Could not read last text from Claude Code session."
    return
  }
  $raw = ($out -join "`n").Trim()
  Send-TgChunked -prefix "[CC] Last text:" -text $raw
}

function Bind-CcInputPoint {
  Send-Tg "[CC] Bind: place cursor over Claude Code input area and press the button."
  try {
    $out = & $ccBridge -Action bind_here
    $exitCode = $LASTEXITCODE
    $outText = ($out -join ' ')
    if ($exitCode -eq 0) {
      Write-CtrlLog "CC Bind success: $outText"
      Send-Tg "[CC] Bind saved: $outText"
    } else {
      Send-Tg "[CC] Bind failed: $outText"
    }
  } catch {
    Send-Tg "[CC] Bind failed: $($_.Exception.Message)"
  }
}

# CC JSONL completion watcher (backup for when hook is not running)
function Get-LatestCCFinalAssistant {
  if (-not (Test-Path $ccSessionsRoot)) { return $null }
  try {
    $latestFile = Get-ChildItem $ccSessionsRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latestFile) { return $null }

    $tailCandidates = @(60, 120)
    foreach ($tailSize in $tailCandidates) {
      $lines = Get-Content $latestFile.FullName -Tail $tailSize -Encoding UTF8 -ErrorAction SilentlyContinue
      for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 100000) { continue }
        if (-not $line.Contains('"type":"assistant"')) { continue }
        try {
          $obj = $line | ConvertFrom-Json
          if ([string]$obj.type -ne 'assistant') { continue }
          $sr = [string]$obj.message.stop_reason
          if ($sr -ne 'end_turn' -and $sr -ne 'max_tokens') { continue }
          $ts = [DateTime]::Parse([string]$obj.timestamp).ToUniversalTime()
          $msgId = [string]$obj.message.id
          $text = ($obj.message.content | Where-Object { $_.type -eq 'text' } |
            ForEach-Object { [string]$_.text }) -join ""
          $key = "$($ts.ToString('o'))|$msgId"
          return [PSCustomObject]@{ timestamp = $ts; text = $text; key = $key }
        } catch {}
      }
    }
  } catch {
    Write-CtrlLog "CC JSONL read error: $($_.Exception.Message)"
  }
  return $null
}

function Load-CcCompletionWatchState {
  if (Test-Path $ccCompletionWatchPath) {
    try {
      $s = Get-Content $ccCompletionWatchPath -Raw | ConvertFrom-Json
      $script:ccWatchInitialized = [bool]$s.initialized
      $script:ccLastCompletionKey = [string]$s.last_key
    } catch {
      $script:ccWatchInitialized = $false
      $script:ccLastCompletionKey = ""
    }
  }
}

function Save-CcCompletionWatchState {
  @{
    initialized = $script:ccWatchInitialized
    last_key = $script:ccLastCompletionKey
    updated_at = (Get-Date).ToString('o')
  } | ConvertTo-Json | Set-Content -Path $ccCompletionWatchPath -Encoding UTF8
}

function Check-CcCompletionWatcher {
  $now = Get-Date
  if (($now - $script:ccLastCompletionCheck).TotalSeconds -lt $CompletionPollSec) { return }
  $script:ccLastCompletionCheck = $now

  $latest = Get-LatestCCFinalAssistant
  if ($null -eq $latest) { return }

  if (-not $script:ccWatchInitialized) {
    $script:ccWatchInitialized = $true
    $script:ccLastCompletionKey = $latest.key
    Save-CcCompletionWatchState
    Write-CtrlLog "CC watcher initialized key=$($latest.key)"
    return
  }

  if ($latest.key -eq $script:ccLastCompletionKey) { return }

  # Commit key FIRST to prevent duplicate sends on second watcher call
  $script:ccLastCompletionKey = $latest.key
  Save-CcCompletionWatchState
  Write-CtrlLog "CC new completion key=$($latest.key)"

  $completionText = [string]$latest.text
  if ([string]::IsNullOrWhiteSpace($completionText)) { $completionText = "(text unavailable)" }

  $ok1 = Send-Tg "[CC] Ответ готов $($latest.timestamp.ToString('HH:mm:ss')) UTC."
  $ok2 = Send-TgChunked -prefix "[CC] Last text:" -text $completionText

  if ($ok1 -and $ok2) {
    Write-CtrlLog "CC notification sent; key=$($latest.key)"
  } else {
    Write-CtrlLog "CC notification send failed (key already committed)"
  }
}

Load-CompletionWatchState
Load-CcCompletionWatchState
Write-CtrlLog "Controller started pid=$PID"
if ([string]::IsNullOrWhiteSpace($OneShotAction)) {
  Send-Tg "Notifier ready. Send /start for quick help."
} else {
  $act = $OneShotAction.Trim().ToLowerInvariant()
  Write-CtrlLog "OneShot requested: $act"
  switch ($act) {
    "continue" {
      $prompt = $(if ([string]::IsNullOrWhiteSpace($OneShotPrompt)) { $ActionAText } else { $OneShotPrompt })
      Send-ActionText -label "Continue" -prompt $prompt
      exit 0
    }
    "fix+retest" {
      $prompt = $(if ([string]::IsNullOrWhiteSpace($OneShotPrompt)) { $ActionCText } else { $OneShotPrompt })
      Send-ActionText -label "Fix+Retest" -prompt $prompt
      exit 0
    }
    "custom" {
      if ([string]::IsNullOrWhiteSpace($OneShotPrompt)) {
        Write-CtrlLog "OneShot custom failed: empty prompt"
        exit 2
      }
      Send-ActionText -label "Custom Send" -prompt $OneShotPrompt
      exit 0
    }
    default {
      Write-CtrlLog "OneShot unsupported action: $act"
      exit 2
    }
  }
}

$offset = Get-Offset
while ($true) {
  try {
    Check-CompletionWatcher
  } catch {
    Write-CtrlLog "Watcher error (pre-poll): $($_.Exception.Message)"
  }
  try {
    $res = Get-Updates -offset $offset
    if ($res.ok -and $res.result.Count -gt 0) {
      foreach ($u in $res.result) {
        $offset = [int]$u.update_id + 1
        Save-Offset -offset $offset

        $msgObj = $u.message
        if (-not $msgObj) { continue }
        if ([string]$msgObj.chat.id -ne [string]$chat) { continue }

        $rawText = [string]$msgObj.text
        $text = $rawText.Trim()
        $textLower = $text.ToLowerInvariant()
        Write-CtrlLog "TG message received: [$textLower]"

        if (Is-CustomAwaitMode) {
          $reserved = @("status","continue","fix+retest","fix+test","action a","action b","action c","set custom","send custom","show custom","clear custom","last text","bind point","stop","/status","/c_continue","/c_retest","/c_fix","/lastlog","/stop")
          if ($textLower -eq "cancel" -or $textLower -eq "/cancel") {
            Set-CustomAwaitMode -enabled $false
            Send-Tg "Set Custom cancelled."
            continue
          }
          if (-not ($reserved -contains $textLower)) {
            Save-CustomPrompt -text $text
            Set-CustomAwaitMode -enabled $false
            Send-Tg "Custom prompt saved."
            continue
          }
        }

        switch ($textLower) {
          "/start" { Send-Help; continue }
          "start" { Send-Help; continue }
          "/help" { Send-Help; continue }
          "help" { Send-Help; continue }
          "status" {
            Send-Status
            continue
          }
          "/status" { Send-Status; continue }
          "action a" { Send-ActionText -label "Continue" -prompt $ActionAText; continue }
          "continue" { Send-ActionText -label "Continue" -prompt $ActionAText; continue }
          "/c_continue" { Send-ActionText -label "Continue" -prompt $ActionAText; continue }
          "action b" {
            $custom = Load-CustomPrompt
            if ([string]::IsNullOrWhiteSpace($custom)) {
              Send-Tg "Custom prompt is empty. Press Set Custom first."
            } else {
              Send-ActionText -label "Custom Send" -prompt $custom
            }
            continue
          }
          "send custom" {
            $custom = Load-CustomPrompt
            if ([string]::IsNullOrWhiteSpace($custom)) {
              Send-Tg "Custom prompt is empty. Press Set Custom first."
            } else {
              Send-ActionText -label "Custom Send" -prompt $custom
            }
            continue
          }
          "set custom" {
            Set-CustomAwaitMode -enabled $true
            Send-Tg "Set Custom mode enabled. Send your next message to save custom prompt. Send 'cancel' to cancel."
            continue
          }
          "show custom" {
            $custom = Load-CustomPrompt
            if ([string]::IsNullOrWhiteSpace($custom)) {
              Send-Tg "Custom prompt is empty."
            } else {
              Send-TgChunked -prefix "Custom prompt:" -text $custom
            }
            continue
          }
          "clear custom" {
            Remove-Item $CustomPromptPath -ErrorAction SilentlyContinue
            Set-CustomAwaitMode -enabled $false
            Send-Tg "Custom prompt cleared."
            continue
          }
          "action c" {
            Send-ActionText -label "Fix+Retest" -prompt $ActionCText
            continue
          }
          "fix+retest" {
            Send-ActionText -label "Fix+Retest" -prompt $ActionCText
            continue
          }
          "fix+test" {
            Send-ActionText -label "Fix+Retest" -prompt $ActionCText
            continue
          }
          "/c_fix" { Send-ActionText -label "Fix+Retest" -prompt $ActionCText; continue }
          "action c run task" { Start-TemplateTask -key "codex_fixandtest" -title "Action C task"; continue }
          "last text" { Send-LastText; continue }
          "last log" { Send-LastText; continue }
          "bind point" { Bind-InputPoint; continue }
          "/lastlog" { Send-LastText; continue }
          "stop" { Stop-CurrentTask; continue }
          "/stop" { Stop-CurrentTask; continue }
          # ── CC (Claude Code) commands ──────────────────────────
          "cc: continue" { Send-CcActionText -label "CC: Continue" -prompt $ActionAText; continue }
          "cc:continue"  { Send-CcActionText -label "CC: Continue" -prompt $ActionAText; continue }
          "/cc_continue" { Send-CcActionText -label "CC: Continue" -prompt $ActionAText; continue }
          "cc: fix+retest" { Send-CcActionText -label "CC: Fix+Retest" -prompt $ActionCText; continue }
          "cc:fix+retest"  { Send-CcActionText -label "CC: Fix+Retest" -prompt $ActionCText; continue }
          "cc: custom" {
            $custom = Load-CustomPrompt
            if ([string]::IsNullOrWhiteSpace($custom)) {
              Send-Tg "Custom prompt is empty. Press Set Custom first."
            } else {
              Send-CcActionText -label "CC: Custom" -prompt $custom
            }
            continue
          }
          "cc:custom" {
            $custom = Load-CustomPrompt
            if ([string]::IsNullOrWhiteSpace($custom)) {
              Send-Tg "Custom prompt is empty. Press Set Custom first."
            } else {
              Send-CcActionText -label "CC: Custom" -prompt $custom
            }
            continue
          }
          "cc: last text" { Send-CcLastText; continue }
          "cc:last text"  { Send-CcLastText; continue }
          "cc: bind" { Bind-CcInputPoint; continue }
          "cc:bind"  { Bind-CcInputPoint; continue }
          default { Send-Tg "Use buttons or /help: Status, Continue, Fix+Retest, Set/Send/Show/Clear Custom, Last Text, Bind Point, Stop | CC: Continue, CC: Fix+Retest, CC: Custom, CC: Last Text, CC: Bind"; continue }
        }
      }
    }

  }
  catch {
    Write-CtrlLog "Loop error: $($_.Exception.Message)"
    Start-Sleep -Milliseconds 800
  }
  try {
    Check-CompletionWatcher
  } catch {
    Write-CtrlLog "Watcher error (post-poll): $($_.Exception.Message)"
  }
  Start-Sleep -Seconds $PollSeconds
}
