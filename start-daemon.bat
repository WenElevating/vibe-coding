@echo off
setlocal
cd /d "%~dp0"

if "%PORT%"=="" set PORT=4317
if "%DAEMON_HOST%"=="" set DAEMON_HOST=127.0.0.1
if "%DAEMON_MODE%"=="" set DAEMON_MODE=dev
if "%CODEX_ENABLED%"=="" set CODEX_ENABLED=1
if "%DEV_ADAPTERS%"=="" set DEV_ADAPTERS=1

echo [daemon] starting on http://%DAEMON_HOST%:%PORT%
echo [daemon] workspace=%CD%
echo [daemon] press Ctrl+C to stop
node daemon\src\main.js
