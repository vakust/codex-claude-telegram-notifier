# Scan UIA elements in claude.exe or Codex.exe to find input fields
param([string]$ProcessName = "claude")

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

if (-not ("Win32ScanApi" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32ScanApi {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
}

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
  Sort-Object WorkingSet64 -Descending | Select-Object -First 1

if (-not $proc) {
  Write-Host "Process '$ProcessName' not found or no window" -ForegroundColor Red
  exit 1
}

Write-Host "Process: $ProcessName pid=$($proc.Id) hwnd=$($proc.MainWindowHandle)" -ForegroundColor Cyan
$r = New-Object Win32ScanApi+RECT
[Win32ScanApi]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
Write-Host "Window rect: ($($r.Left), $($r.Top)) -> ($($r.Right), $($r.Bottom)) size=$(($r.Right-$r.Left))x$(($r.Bottom-$r.Top))" -ForegroundColor Cyan

$root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
$scope = [System.Windows.Automation.TreeScope]::Descendants

Write-Host ""
Write-Host "=== All Edit/TextBox controls ===" -ForegroundColor Yellow
$condEdit = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Edit)
$edits = $root.FindAll($scope, $condEdit)
Write-Host "Found $($edits.Count) Edit controls"
for ($i = 0; $i -lt $edits.Count; $i++) {
  $el = $edits.Item($i)
  $b = $el.Current.BoundingRectangle
  Write-Host "  Edit[$i] name='$($el.Current.Name)' class='$($el.Current.ClassName)' bounds=($([int]$b.X),$([int]$b.Y) ${[int]$b.Width}x${[int]$b.Height})"
}

Write-Host ""
Write-Host "=== Document controls ===" -ForegroundColor Yellow
$condDoc = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Document)
$docs = $root.FindAll($scope, $condDoc)
Write-Host "Found $($docs.Count) Document controls"
for ($i = 0; $i -lt [Math]::Min($docs.Count, 5); $i++) {
  $el = $docs.Item($i)
  $b = $el.Current.BoundingRectangle
  Write-Host "  Doc[$i] name='$($el.Current.Name)' class='$($el.Current.ClassName)' bounds=($([int]$b.X),$([int]$b.Y))"
}

Write-Host ""
Write-Host "=== Pane/Custom with known CC names ===" -ForegroundColor Yellow
$names = @('Reply to Claude...','Message Claude...','Type a message...','How can Claude help?','Ask Claude anything','Plan and execute')
foreach ($n in $names) {
  $cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, $n)
  $found = $root.FindAll($scope, $cond)
  if ($found.Count -gt 0) {
    Write-Host "  FOUND name='$n' count=$($found.Count)" -ForegroundColor Green
    for ($i = 0; $i -lt $found.Count; $i++) {
      $el = $found.Item($i)
      $b = $el.Current.BoundingRectangle
      Write-Host "    [$i] class='$($el.Current.ClassName)' bounds=($([int]$b.X),$([int]$b.Y) $([int]$b.Width)x$([int]$b.Height))"
    }
  }
}

Write-Host ""
Write-Host "=== xterm elements ===" -ForegroundColor Yellow
$classCond = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'xterm-helper-textarea')
$xtermEls = $root.FindAll($scope, $classCond)
Write-Host "Found $($xtermEls.Count) xterm-helper-textarea"
for ($i = 0; $i -lt $xtermEls.Count; $i++) {
  $el = $xtermEls.Item($i)
  $b = $el.Current.BoundingRectangle
  Write-Host "  xterm[$i] bounds=($([int]$b.X),$([int]$b.Y) $([int]$b.Width)x$([int]$b.Height))"
}

Write-Host ""
Write-Host "=== Top-level children of main window ===" -ForegroundColor Yellow
$children = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
Write-Host "Found $($children.Count) direct children"
for ($i = 0; $i -lt [Math]::Min($children.Count, 10); $i++) {
  $el = $children.Item($i)
  $b = $el.Current.BoundingRectangle
  Write-Host "  child[$i] type=$($el.Current.ControlType.ProgrammaticName) name='$($el.Current.Name)' class='$($el.Current.ClassName)'"
}
