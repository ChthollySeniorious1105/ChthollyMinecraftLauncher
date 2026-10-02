@echo off
chcp 65001 >nul
cd /d "%~dp0"
pulse_server.exe %*
pause
