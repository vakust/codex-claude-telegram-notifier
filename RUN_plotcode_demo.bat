@echo off
powershell -ExecutionPolicy Bypass -File "c:\001_dev\notifier\scripts\run-with-notify.ps1" -TaskName "PlotCode Long Task" -Command "& 'c:\001_dev\notifier\scripts\demo-plotcode-task.ps1'" -HeartbeatMinutes 1 -TimeoutMinutes 30 -LogPath "c:\001_dev\notifier\logs\plotcode-task.log"
pause
