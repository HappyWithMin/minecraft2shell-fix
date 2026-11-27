@echo off
chcp 65001 >nul
rem Minecraft2Shell launcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc2shell-check.ps1"
echo.
echo ============================================
echo  自检完成, 按任意键关闭此窗口...
pause >nul