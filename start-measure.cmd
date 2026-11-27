@echo off
rem Double-click start for testers: checks for the build tools and Rust (offers to install
rem them), then runs measure-gta6.ps1, which asks whether the speed switches go on and offers
rem a test report when the game closes. Arguments are passed on to measure-gta6.ps1.
setlocal
cd /d "%~dp0"
rem rustup installed by check-tools.ps1 is not on this window's PATH yet.
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check-tools.ps1"
if errorlevel 1 (
    echo.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0measure-gta6.ps1" -SpeedSwitches ask %*
echo.
pause
