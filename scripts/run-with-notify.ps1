param(
  [Parameter(Mandatory=$true)][string]$TaskName,
  [Parameter(Mandatory=$true)][string]$Command,
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1",
  [int]$HeartbeatMinutes = 10,
  [int]$TimeoutMinutes = 0,
  [string]$LogPath = "",
  [string]$StatePath = "c:\001_dev\notifier\state\current-task.json",
  [string]$PidPath = "c:\001_dev\notifier\state\current-task.pid"
)

if (-not (Test-Path $ConfigPath)) {
  Write-Error "Config not found: $ConfigPath"
  exit 1
}

. $ConfigPath

if (-not $env:TG_BOT_TOKEN -or -not $env:TG_CHAT_ID) {
  Write-Error "TG_BOT_TOKEN or TG_CHAT_ID is missing in config."
  exit 1
}

$bot = $env:TG_BOT_TOKEN
$chat = $env:TG_CHAT_ID
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sender = Join-Path $scriptRoot 'send-telegram.ps1'
$startAt = Get-Date

function Send-Tg([string]$msg) {
  & $sender -BotToken $bot -ChatId $chat -Text $msg
}

function Save-State([string]$status, [int]$processId, [int]$exitCode, [double]$durationMinutes) {
  $state = [ordered]@{
    task = $TaskName
    status = $status
    started_at = $startAt.ToString('s')
    updated_at = (Get-Date).ToString('s')
    pid = $processId
    log_path = $LogPath
    exit_code = $exitCode
    duration_minutes = $durationMinutes
  } | ConvertTo-Json
  Set-Content -Path $StatePath -Value $state -Encoding UTF8
}

$stateDir = Split-Path -Parent $StatePath
if (-not (Test-Path $stateDir)) {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
}

$hostName = $env:COMPUTERNAME
Send-Tg "<b>START</b> | $TaskName`nHost: $hostName`nStarted: $($startAt.ToString('yyyy-MM-dd HH:mm:ss'))"

$wrapped = if ([string]::IsNullOrWhiteSpace($LogPath)) {
  $Command
} else {
  "& { $Command } *>&1 | Tee-Object -FilePath '$LogPath'"
}

$exitCode = 1
$timedOut = $false
$proc = $null
$job = $null

try {
  $proc = Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$wrapped -PassThru -WindowStyle Hidden
  Set-Content -Path $PidPath -Value ([string]$proc.Id) -Encoding ASCII
  Save-State -status 'running' -processId $proc.Id -exitCode -1 -durationMinutes 0

  $job = Start-Job -ScriptBlock {
    param($sender,$bot,$chat,$taskName,$minutes,$statePath,$startedAt,$pid,$logPath)
    while ($true) {
      Start-Sleep -Seconds ($minutes * 60)
      $duration = [math]::Round(((Get-Date) - $startedAt).TotalMinutes, 2)
      $state = [ordered]@{
        task = $taskName
        status = 'running'
        started_at = $startedAt.ToString('s')
        updated_at = (Get-Date).ToString('s')
        pid = $pid
        log_path = $logPath
        exit_code = -1
        duration_minutes = $duration
      } | ConvertTo-Json
      Set-Content -Path $statePath -Value $state -Encoding UTF8
      & $sender -BotToken $bot -ChatId $chat -Text "<b>PROGRESS</b> | $taskName`nStill running at $((Get-Date).ToString('HH:mm:ss'))`nDuration: ${duration}m"
    }
  } -ArgumentList $sender,$bot,$chat,$TaskName,$HeartbeatMinutes,$StatePath,$startAt,$proc.Id,$LogPath

  if ($TimeoutMinutes -gt 0) {
    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
      $timedOut = $true
      Stop-Process -Id $proc.Id -Force
      $exitCode = 124
    } else {
      $exitCode = $proc.ExitCode
    }
  } else {
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
  }
}
catch {
  $err = $_.Exception.Message
  Save-State -status 'failed' -processId 0 -exitCode 1 -durationMinutes ([math]::Round(((Get-Date) - $startAt).TotalMinutes, 2))
  Send-Tg "<b>FAIL</b> | $TaskName`nException: $err"
  exit 1
}
finally {
  if ($null -ne $job) {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
  }
  Remove-Item $PidPath -ErrorAction SilentlyContinue
}

$endedAt = Get-Date
$duration = [math]::Round(($endedAt - $startAt).TotalMinutes, 2)

if ($timedOut) {
  Save-State -status 'timeout' -processId 0 -exitCode 124 -durationMinutes $duration
  Send-Tg "<b>TIMEOUT</b> | $TaskName`nAfter: ${duration}m"
  exit 124
}

if ($exitCode -eq 0) {
  Save-State -status 'done' -processId 0 -exitCode 0 -durationMinutes $duration
  $msg = "<b>DONE</b> | $TaskName`nDuration: ${duration}m"
  if ($LogPath -and (Test-Path $LogPath)) {
    $tail = (Get-Content $LogPath -Tail 15) -join "`n"
    if ($tail.Length -gt 0) {
      $safeTail = [System.Web.HttpUtility]::HtmlEncode($tail)
      $msg += "`nLast log lines:`n<pre>$safeTail</pre>"
    }
  }
  Send-Tg $msg
  exit 0
}

$msg = "<b>FAIL</b> | $TaskName`nExit code: $exitCode`nDuration: ${duration}m"
Save-State -status 'failed' -processId 0 -exitCode $exitCode -durationMinutes $duration
if ($LogPath -and (Test-Path $LogPath)) {
  $tail = (Get-Content $LogPath -Tail 20) -join "`n"
  if ($tail.Length -gt 0) {
    $safeTail = [System.Web.HttpUtility]::HtmlEncode($tail)
    $msg += "`nLast log lines:`n<pre>$safeTail</pre>"
  }
}
Send-Tg $msg
exit $exitCode
