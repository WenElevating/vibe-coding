@echo off
setlocal
cd /d "%~dp0"

if "%PORT%"=="" set PORT=4317
if "%DAEMON_HOST%"=="" set DAEMON_HOST=0.0.0.0
if "%DAEMON_MODE%"=="" set DAEMON_MODE=dev
if "%CODEX_ENABLED%"=="" set CODEX_ENABLED=1
if "%DEV_ADAPTERS%"=="" set DEV_ADAPTERS=1

echo [daemon] starting on http://%DAEMON_HOST%:%PORT%
echo [daemon] workspace=%CD%
echo [daemon] press Ctrl+C to stop
if "%DAEMON_WATCHDOG%"=="" set DAEMON_WATCHDOG=1

:start_daemon
node daemon\src\main.js
set "DAEMON_EXIT=%ERRORLEVEL%"

if "%DAEMON_WATCHDOG%"=="0" exit /b %DAEMON_EXIT%
if "%DAEMON_EXIT%"=="0" exit /b 0
if "%DAEMON_EXIT%"=="130" exit /b 130
if "%DAEMON_EXIT%"=="143" exit /b 143

echo [daemon] process exited with code %DAEMON_EXIT%; restarting in 2 seconds...
timeout /t 2 /nobreak >nul
goto start_daemon
