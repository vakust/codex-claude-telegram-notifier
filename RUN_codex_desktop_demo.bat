@echo off
powershell -ExecutionPolicy Bypass -File "c:\001_dev\notifier\scripts\run-with-notify.ps1" -TaskName "Codex Desktop Long Task" -Command "& 'c:\001_dev\notifier\scripts\demo-codex-task.ps1'" -HeartbeatMinutes 1 -TimeoutMinutes 30 -LogPath "c:\001_dev\notifier\logs\codex-desktop-task.log"
pause
