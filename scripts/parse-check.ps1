param([string]$File = 'c:\001_dev\notifier\scripts\telegram-controller.ps1')
$err = $null
$tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content $File -Raw), [ref]$err)
if ($err.Count -gt 0) { $err | ForEach-Object { Write-Host "ERROR: $($_.Message) line=$($_.Token.StartLine)" } }
else { Write-Host "Parse OK tokens=$($tokens.Count) file=$File" }
