@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Set-StartupMode.ps1" -Mode Normal
pause
