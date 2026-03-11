param(
  [string]$ProjectRoot = "c:\001_dev\notifier",
  [string]$OutputDir = "c:\001_dev\notifier\dist"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectRoot)) {
  throw "Project root not found: $ProjectRoot"
}

if (-not (Test-Path $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$zipPath = Join-Path $OutputDir "notifier-share-$stamp.zip"
$tempRoot = Join-Path $env:TEMP ("notifier-share-" + [Guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  $files = Get-ChildItem -Path $ProjectRoot -Recurse -File | Where-Object {
    $_.FullName -notlike "$ProjectRoot\logs\*" -and
    $_.FullName -notlike "$ProjectRoot\state\*" -and
    $_.Name -ne ".env.ps1" -and
    $_.Name -notlike "*.pid" -and
    $_.Name -notlike "*.log"
  }

  foreach ($file in $files) {
    $rel = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\')
    $dest = Join-Path $tempRoot $rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -Path $file.FullName -Destination $dest -Force
  }

  if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
  }

  Compress-Archive -Path (Join-Path $tempRoot "*") -DestinationPath $zipPath -Force
  Write-Host "Share package created: $zipPath"
}
finally {
  Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
