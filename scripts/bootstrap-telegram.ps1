param(
  [Parameter(Mandatory=$true)][string]$BotToken,
  [string]$ConfigPath = "c:\001_dev\notifier\.env.ps1"
)

$ErrorActionPreference = 'Stop'

function Get-Updates([string]$token) {
  $uri = "https://api.telegram.org/bot$token/getUpdates"
  return Invoke-RestMethod -Method Get -Uri $uri
}

Write-Host "Checking bot token..."
$check = Get-Updates -token $BotToken
if (-not $check.ok) {
  throw "Invalid bot token or Telegram API error."
}

$chatId = $null
if ($check.result.Count -gt 0) {
  $last = $check.result[-1]
  if ($last.message.chat.id) { $chatId = [string]$last.message.chat.id }
  elseif ($last.channel_post.chat.id) { $chatId = [string]$last.channel_post.chat.id }
}

if (-not $chatId) {
  Write-Host "No chat_id found yet."
  Write-Host "Please open Telegram, find your bot, and send it any message (for example: hi)."
  Write-Host "Waiting up to 2 minutes for first update..."

  $deadline = (Get-Date).AddMinutes(2)
  while ((Get-Date) -lt $deadline -and -not $chatId) {
    Start-Sleep -Seconds 5
    $u = Get-Updates -token $BotToken
    if ($u.result.Count -gt 0) {
      $last = $u.result[-1]
      if ($last.message.chat.id) { $chatId = [string]$last.message.chat.id }
      elseif ($last.channel_post.chat.id) { $chatId = [string]$last.channel_post.chat.id }
    }
  }
}

if (-not $chatId) {
  throw "chat_id not found. Send a direct message to your bot, then run bootstrap again."
}

$content = @"
`$env:TG_BOT_TOKEN = "$BotToken"
`$env:TG_CHAT_ID = "$chatId"
"@
Set-Content -Path $ConfigPath -Value $content -Encoding UTF8

Write-Host "Saved config: $ConfigPath"
Write-Host "Detected chat_id: $chatId"

$sender = "c:\001_dev\notifier\scripts\send-telegram.ps1"
$testMsg = "<b>TEST</b> | bootstrap complete`nTime: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
& $sender -BotToken $BotToken -ChatId $chatId -Text $testMsg
Write-Host "Sent test message to Telegram."
