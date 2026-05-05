@echo off
setlocal

cd /d "%~dp0"

set "LOCAL_OMX=%~dp0..\.omx"
if not exist "%LOCAL_OMX%\manual_packages\args" (
  if exist "%~dp0..\..\..\.omx\manual_packages\args" (
    if not exist "%LOCAL_OMX%" mkdir "%LOCAL_OMX%" >nul
    if not exist "%LOCAL_OMX%\manual_packages" mklink /J "%LOCAL_OMX%\manual_packages" "%~dp0..\..\..\.omx\manual_packages" >nul
  )
)

if not exist ".dart_tool\package_config.json" (
  echo [0/3] Resolving Flutter packages...
  call flutter pub get
  if errorlevel 1 goto failed
  echo.
)

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
