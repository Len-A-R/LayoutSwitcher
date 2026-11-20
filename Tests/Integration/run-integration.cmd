@echo off
rem Builds and runs the scenario tests against real edit boxes.
rem The test window takes the focus and types into itself for about fifteen
rem seconds: do not touch the keyboard or the mouse while it runs.
rem
rem   run-integration.cmd           build, warn, run on this desktop
rem   run-integration.cmd /build    only build out\LSIntegration.exe
rem   run-integration.cmd /nopause  build and run without the prompt
rem
rem tools\run-integration.ps1 runs them in Windows Sandbox instead, so the
rem desktop stays free.
setlocal
set BDS_DIR=C:\Program Files (x86)\Embarcadero\Studio\23.0
call "%BDS_DIR%\bin\rsvars.bat" || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out

dcc64 -B -Q -NSSystem;Winapi;System.Win;Vcl -U..\.. -Eout -NUout -$Q+ -$R+ LSIntegration.dpr || exit /b 1
if /i "%~1"=="/build" exit /b 0

if /i not "%~1"=="/nopause" (
  echo.
  echo The test window will take the focus and type for about fifteen seconds.
  echo Do not touch the keyboard or the mouse.
  pause
)
out\LSIntegration.exe || exit /b 1
