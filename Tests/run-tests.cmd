@echo off
rem Builds and runs the LayoutSwitcher unit tests.
rem DUnitX ships with RAD Studio 12 as precompiled Win64 units only.
setlocal
set BDS_DIR=C:\Program Files (x86)\Embarcadero\Studio\23.0
call "%BDS_DIR%\bin\rsvars.bat" || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out

dcc64 -B -Q -NSSystem;Winapi;System.Win -U.. -U"%BDS_DIR%\lib\win64\release" -Eout -NUout -$Q+ -$R+ LSTests.dpr || exit /b 1
out\LSTests.exe --exitbehavior:Continue || exit /b 1

echo All tests passed.
