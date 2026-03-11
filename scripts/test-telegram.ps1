param(
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1"
)

if (-not (Test-Path $ConfigPath)) {
  Write-Error "Config not found: $ConfigPath"
  exit 1
}

. $ConfigPath

if (-not $env:TG_BOT_TOKEN -or -not $env:TG_CHAT_ID) {
  Write-Error "TG_BOT_TOKEN or TG_CHAT_ID is empty in $ConfigPath"
  exit 1
}

$sender = 'c:\001_dev\notifier\scripts\send-telegram.ps1'
$msg = "<b>TEST</b> | notifier is connected`nTime: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
& $sender -BotToken $env:TG_BOT_TOKEN -ChatId $env:TG_CHAT_ID -Text $msg
Write-Host 'Telegram test message sent.'
