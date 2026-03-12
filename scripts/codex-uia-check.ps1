Remove-Item 'c:\001_dev\notifier\state\codex-input-point.json' -Force -ErrorAction SilentlyContinue
Write-Host 'Cleared stale Codex saved point'

$p = Get-Process Codex -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Host 'No Codex window'; exit }
Write-Host "Codex pid=$($p.Id) hwnd=$($p.MainWindowHandle)"

Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop

if (-not ("Win32BridgeApi2" -as [type])) {
Add-Type @"
using System.Runtime.InteropServices;
public class Win32BridgeApi2 {
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT r);
}
"@
}
$rect = New-Object Win32BridgeApi2+RECT
[Win32BridgeApi2]::GetWindowRect($p.MainWindowHandle, [ref]$rect) | Out-Null
Write-Host "Window rect: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom) W=$($rect.Right-$rect.Left) H=$($rect.Bottom-$rect.Top)"

$root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$scope = [System.Windows.Automation.TreeScope]::Descendants

# Try placeholder
$cond = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::NameProperty, 'Ask for follow-up changes')
$el = $root.FindFirst($scope, $cond)
if ($el) { Write-Host "Placeholder FOUND bounds=$($el.Current.BoundingRectangle)" }
else { Write-Host 'Placeholder NOT found (Codex may be idle/busy)' }

# List top named elements
Write-Host '--- Top named UIA elements ---'
$all = $root.FindAll($scope, [System.Windows.Automation.Condition]::TrueCondition)
$shown = 0
for ($i = 0; $i -lt $all.Count -and $shown -lt 20; $i++) {
  $e = $all.Item($i)
  $name = $e.Current.Name
  if ($name -and $name.Length -lt 100) {
    Write-Host "  '$name' type=$($e.Current.ControlType.ProgrammaticName)"
    $shown++
  }
}
