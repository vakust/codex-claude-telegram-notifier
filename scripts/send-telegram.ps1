param(
  [Parameter(Mandatory=$true)][string]$BotToken,
  [Parameter(Mandatory=$true)][string]$ChatId,
  [Parameter(Mandatory=$true)][string]$Text,
  [string]$ReplyMarkup = ""
)

$uri = "https://api.telegram.org/bot$BotToken/sendMessage"

try {
  $body = @{
    chat_id = $ChatId
    text = $Text
    parse_mode = 'HTML'
    disable_web_page_preview = 'true'
  }
  if (-not [string]::IsNullOrWhiteSpace($ReplyMarkup)) {
    $body.reply_markup = $ReplyMarkup
  }
  Invoke-RestMethod -Method Post -Uri $uri -Body $body | Out-Null
  exit 0
}
catch {
  Write-Error "Telegram send failed: $($_.Exception.Message)"
  exit 1
}
