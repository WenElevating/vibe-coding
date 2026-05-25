@echo off
setlocal
cd /d "%~dp0"

if "%GRADLE_USER_HOME%"=="" set "GRADLE_USER_HOME=D:\Gradle\home"

powershell -ExecutionPolicy Bypass -File scripts\package-android-update.ps1 -VerboseBuild %*
exit /b %ERRORLEVEL%
