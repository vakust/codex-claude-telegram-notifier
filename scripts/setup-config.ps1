param(
  [Parameter(Mandatory=$true)][string]$BotToken,
  [Parameter(Mandatory=$true)][string]$ChatId
)

$content = @"
`$env:TG_BOT_TOKEN = "$BotToken"
`$env:TG_CHAT_ID = "$ChatId"
"@

Set-Content -Path 'c:\001_dev\notifier\.env.ps1' -Value $content -Encoding UTF8
Write-Host 'Saved: c:\001_dev\notifier\.env.ps1'
