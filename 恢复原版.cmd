@echo off
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Blip-zh-CN.ps1" -Mode Restore
echo.
pause
