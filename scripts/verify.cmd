@echo off
rem Run the four smoke suites in ..\package\test. All must pass.
rem Usage: scripts\verify.cmd
setlocal
set "PKG=%~dp0..\package"
where node >nul 2>nul
if errorlevel 1 (
  echo [X] node not found in PATH. Install Node.js 20+ first.
  pause
  exit /b 1
)

if not exist "%PKG%\test" (
  echo [X] test directory not found: %PKG%\test
  pause
  exit /b 1
)

pushd "%PKG%"
set "FAILED=0"
for %%t in (smoke-host.mjs smoke-splash.mjs smoke-client.mjs smoke-desktop-boot.mjs) do (
  echo.
  echo ================ test\%%t ================
  call node "test\%%t"
  if errorlevel 1 set "FAILED=1"
)
popd

echo.
if "%FAILED%"=="1" (
  echo [X] SOME SUITES FAILED - do not ship
  pause
  exit /b 1
)
echo [OK] all four suites passed
pause
