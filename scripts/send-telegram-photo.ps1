param(
  [Parameter(Mandatory=$true)][string]$BotToken,
  [Parameter(Mandatory=$true)][string]$ChatId,
  [Parameter(Mandatory=$true)][string]$PhotoPath,
  [string]$Caption = "",
  [string]$ReplyMarkup = ""
)

if (-not (Test-Path $PhotoPath)) {
  Write-Error "Photo file not found: $PhotoPath"
  exit 1
}

$uri = "https://api.telegram.org/bot$BotToken/sendPhoto"
$fileName = [System.IO.Path]::GetFileName($PhotoPath)
$fs = $null
$http = $null
$content = $null

try {
  Add-Type -AssemblyName System.Net.Http

  $http = New-Object System.Net.Http.HttpClient
  $content = New-Object System.Net.Http.MultipartFormDataContent

  $content.Add((New-Object System.Net.Http.StringContent($ChatId)), "chat_id")

  if (-not [string]::IsNullOrWhiteSpace($Caption)) {
    $content.Add((New-Object System.Net.Http.StringContent($Caption, [System.Text.Encoding]::UTF8)), "caption")
    $content.Add((New-Object System.Net.Http.StringContent("HTML")), "parse_mode")
  }

  if (-not [string]::IsNullOrWhiteSpace($ReplyMarkup)) {
    $replyJson = $ReplyMarkup
    try {
      $replyJson = (($ReplyMarkup | ConvertFrom-Json) | ConvertTo-Json -Depth 5 -Compress)
    } catch {}
    $content.Add((New-Object System.Net.Http.StringContent($replyJson, [System.Text.Encoding]::UTF8)), "reply_markup")
  }

  $fs = [System.IO.File]::OpenRead($PhotoPath)
  $fileContent = New-Object System.Net.Http.StreamContent($fs)
  $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
  $content.Add($fileContent, "photo", $fileName)

  $resp = $http.PostAsync($uri, $content).GetAwaiter().GetResult()
  $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if (-not $resp.IsSuccessStatusCode) {
    throw "HTTP $([int]$resp.StatusCode): $body"
  }
  try {
    $obj = $body | ConvertFrom-Json -ErrorAction Stop
    if (-not $obj.ok) {
      $desc = [string]$obj.description
      if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "unknown Telegram error" }
      throw "Telegram API rejected sendPhoto: $desc"
    }
  } catch {
    if ($_.Exception.Message -like "Telegram API rejected sendPhoto*") { throw }
    throw "Invalid Telegram sendPhoto response payload."
  }
  exit 0
}
catch {
  Write-Error "Telegram sendPhoto failed: $($_.Exception.Message)"
  exit 1
}
finally {
  if ($fs) { $fs.Dispose() }
  if ($content) { $content.Dispose() }
  if ($http) { $http.Dispose() }
}
