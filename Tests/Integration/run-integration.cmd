@echo off
rem Builds and runs the scenario tests against real edit boxes.
rem The test window takes the focus and types into itself for about ten
rem seconds: do not touch the keyboard or the mouse while it runs.
setlocal
set BDS_DIR=C:\Program Files (x86)\Embarcadero\Studio\23.0
call "%BDS_DIR%\bin\rsvars.bat" || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out

dcc64 -B -Q -NSSystem;Winapi;System.Win;Vcl -U..\.. -Eout -NUout -$Q+ -$R+ LSIntegration.dpr || exit /b 1

echo.
echo The test window will take the focus and type for about ten seconds.
echo Do not touch the keyboard or the mouse.
pause
out\LSIntegration.exe || exit /b 1
