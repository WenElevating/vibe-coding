@echo off
setlocal

cd /d "%~dp0"

echo [0/3] Resolving Flutter packages...
call flutter pub get
if errorlevel 1 goto failed
echo.

echo [1/3] Formatting Dart files...
call dart format lib test
if errorlevel 1 goto failed

echo.
echo [2/3] Running Flutter analyze...
call flutter analyze --no-pub
if errorlevel 1 goto failed

echo.
echo [3/3] Running Flutter tests...
call flutter test --no-pub
if errorlevel 1 goto failed

echo.
echo All checks passed.
exit /b 0

:failed
echo.
echo Checks failed.
exit /b 1
