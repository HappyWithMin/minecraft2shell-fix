@echo off
chcp 65001 >nul
rem Minecraft2Shell launcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc2shell-fix.ps1"
echo.
echo ============================================
echo  已结束, 按任意键关闭此窗口...
pause >nul