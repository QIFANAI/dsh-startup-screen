@echo off
rem Emergency re-install of dsh-startup-screen into the DSH "desktop" profile.
rem Run this only when the "Startup animation" section is missing from DSH
rem Settings after a restart. Fully quit DeepSeek Harness Desktop first.
rem Bump the version below when a newer tarball is added to ..\releases.
setlocal
set "TGZ=%~dp0..\releases\dsh-startup-screen-1.6.0.tgz"
set "DSHCLI=dsh"

if not exist "%TGZ%" (
  echo [X] tarball not found: %TGZ%
  echo     edit the version in this script after running scripts\build.cmd
  pause
  exit /b 1
)
where dsh >nul 2>nul
if errorlevel 1 (
  echo [X] dsh CLI not found in PATH. Install dsh or edit DSHCLI in this script.
  pause
  exit /b 1
)

echo Installing:
echo   %TGZ%
echo   into profile "desktop"
echo.
call "%DSHCLI%" plugin --profile desktop add "%TGZ%"
if errorlevel 1 (
  echo [X] install failed - see the output above.
  pause
  exit /b 1
)

echo.
echo [OK] Installed. Fully quit DeepSeek Harness Desktop, then start it again.
pause
