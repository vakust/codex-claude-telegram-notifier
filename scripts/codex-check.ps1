Write-Host '=== Codex bridge debug log ==='
Get-Content 'c:\001_dev\notifier\logs\continue-debug.log' -Tail 20 -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '=== Latest Codex session (last 5 JSONL lines) ==='
$root = Join-Path $env:USERPROFILE '.codex\sessions'
$f = Get-ChildItem $root -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Desc | Select-Object -First 1
if ($f) {
  Write-Host "File: $($f.FullName) ($($f.LastWriteTime))"
  Get-Content $f.FullName -Tail 5 -Encoding UTF8 | ForEach-Object {
    if ($_.Length -gt 300) { $_.Substring(0,300) + ' ...' } else { $_ }
  }
} else { Write-Host 'No session file' }

Write-Host ''
Write-Host '=== Codex bridge: last_meta ==='
& 'c:\001_dev\notifier\scripts\codex-bridge.ps1' -Action last_meta
