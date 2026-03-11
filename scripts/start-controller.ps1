param([switch]$Force)

$pidPath = "c:\001_dev\notifier\state\controller.pid"
$script = "c:\001_dev\notifier\scripts\telegram-controller.ps1"

if (-not $Force -and (Test-Path $pidPath)) {
  $old = (Get-Content $pidPath -Raw).Trim()
  if ($old -match '^\d+$') {
    $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
    if ($p) {
      Write-Host "Controller already running pid=$old"
      exit 0
    }
  }
}

$proc = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$script -PassThru -WindowStyle Hidden
"$($proc.Id)" | Set-Content -Path $pidPath -Encoding ASCII
Write-Host "Controller started pid=$($proc.Id)"
