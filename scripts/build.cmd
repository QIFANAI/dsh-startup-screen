@echo off
rem Build a release tarball from ..\package into ..\releases
rem Usage: scripts\build.cmd
setlocal
set "PKG=%~dp0..\package"
set "OUT=%~dp0..\releases"
where npm >nul 2>nul
if errorlevel 1 (
  echo [X] npm not found in PATH. Install Node.js 20+ first.
  pause
  exit /b 1
)

if not exist "%PKG%\package.json" (
  echo [X] package not found: %PKG%
  pause
  exit /b 1
)
if not exist "%OUT%" mkdir "%OUT%"

pushd "%PKG%"
call npm pack --pack-destination "%OUT%"
set "CODE=%errorlevel%"
popd

if not "%CODE%"=="0" (
  echo [X] build failed
  pause
  exit /b %CODE%
)

echo.
echo [OK] tarball written to %OUT%
echo Next: quit DeepSeek Harness Desktop, then
echo   dsh plugin --profile desktop add "%%OUT%%\dsh-startup-screen-^<version^>.tgz"
pause
