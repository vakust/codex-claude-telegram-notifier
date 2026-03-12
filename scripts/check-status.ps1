Write-Host '=== Controller log (last 10) ==='
Get-Content 'c:\001_dev\notifier\logs\controller.log' -Tail 10

Write-Host ''
Write-Host '=== Codex sessions ==='
$root = Join-Path $env:USERPROFILE '.codex\sessions'
if (Test-Path $root) {
  Get-ChildItem $root -Recurse -Filter '*.jsonl' | Sort-Object LastWriteTime -Desc |
    Select-Object -First 3 | ForEach-Object { Write-Host "$($_.LastWriteTime.ToString('HH:mm:ss')) $($_.FullName)" }
} else { Write-Host "No Codex sessions dir at $root" }

Write-Host ''
Write-Host '=== Codex process ==='
Get-Process -Name 'Codex' -ErrorAction SilentlyContinue |
  Select-Object Id, @{N='HWnd';E={$_.MainWindowHandle}}, @{N='MB';E={[int]($_.WorkingSet64/1MB)}} |
  Format-Table -AutoSize

Write-Host '=== CC watcher state ==='
Get-Content 'c:\001_dev\notifier\state\cc-completion-watch.json' -Raw -ErrorAction SilentlyContinue

Write-Host '=== Codex watcher state ==='
Get-Content 'c:\001_dev\notifier\state\completion-watch.json' -Raw -ErrorAction SilentlyContinue
