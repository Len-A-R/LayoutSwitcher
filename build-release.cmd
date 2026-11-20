@echo off
rem Release build: both platforms, unit tests, integration tests, optional
rem code signing and the installer.  Results go to dist\.
rem
rem   build-release.cmd                 everything (local release)
rem   build-release.cmd /dry            only print what would be done
rem   build-release.cmd /nointegration  skip the integration tests
rem   build-release.cmd /binaries       CI stage 1: build + unit tests only
rem   build-release.cmd /package        CI stage 2: installer from the
rem                                     (already signed) Win32/Win64 exes,
rem                                     no build, no signing, no manifests
rem
rem The GitHub workflow (.github\workflows\release.yml) runs /binaries, has
rem the executables signed by SignPath, runs /package, signs the installer
rem and creates the winget manifests from the signed installer.
rem
rem Local code signing (optional), set one of:
rem   LS_SIGN_PFX=path\to\cert.pfx  and  LS_SIGN_PASSWORD=...
rem   LS_SIGN_THUMBPRINT=<SHA1 thumbprint of a certificate in the user store>
rem   LS_SIGN_TIMESTAMP=http://timestamp.digicert.com   (default)
rem Installer: Inno Setup 7 or 6 (ISCC.exe) in the default location or LS_ISCC.
setlocal EnableDelayedExpansion
set DRY=
set DO_BUILD=1
set DO_PACKAGE=1
set DO_SIGN=1
set DO_MANIFESTS=1
set DO_INTEGRATION=1
for %%a in (%*) do (
  if /i "%%~a"=="/dry" set DRY=echo [dry]
  if /i "%%~a"=="/nointegration" set DO_INTEGRATION=
  if /i "%%~a"=="/binaries" (
    set DO_PACKAGE=
    set DO_SIGN=
    set DO_MANIFESTS=
    set DO_INTEGRATION=
  )
  if /i "%%~a"=="/package" (
    set DO_BUILD=
    set DO_SIGN=
    set DO_MANIFESTS=
    set DO_INTEGRATION=
  )
)
set ROOT=%~dp0
set BDS_DIR=C:\Program Files (x86)\Embarcadero\Studio\23.0
if not defined LS_SIGN_TIMESTAMP set LS_SIGN_TIMESTAMP=http://timestamp.digicert.com
cd /d "%ROOT%"

call "%BDS_DIR%\bin\rsvars.bat" || exit /b 1

if defined DO_BUILD (
  echo === Build ===
  %DRY% msbuild LS.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal /nologo || exit /b 1
  %DRY% msbuild LS.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal /nologo || exit /b 1

  echo === Unit tests ===
  %DRY% call Tests\run-tests.cmd || exit /b 1
)

if defined DO_INTEGRATION (
  echo === Integration tests ===
  if exist "%windir%\System32\WindowsSandbox.exe" (
    %DRY% powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-integration.ps1 || exit /b 1
  ) else (
    echo Windows Sandbox is not installed: run tools\run-integration.ps1 -Local
    echo before publishing, or install Windows Sandbox to run them here.
  )
)

if not defined DO_PACKAGE (
  echo === Done: Win32\Release\LS.exe, Win64\Release\LS.exe ===
  exit /b 0
)

set SIGNTOOL=
set SIGNARGS=
if defined DO_SIGN (
  echo === Signing ===
  for /f "delims=" %%i in ('where /r "%ProgramFiles(x86)%\Windows Kits\10\bin" signtool.exe 2^>nul ^| findstr /i "\\x64\\"') do set SIGNTOOL=%%i
  if defined LS_SIGN_PFX set SIGNARGS=/f "%LS_SIGN_PFX%" /p "%LS_SIGN_PASSWORD%"
  if defined LS_SIGN_THUMBPRINT set SIGNARGS=/sha1 %LS_SIGN_THUMBPRINT%
  if not defined SIGNARGS (
    echo No certificate configured: executables stay unsigned.
  ) else if not defined SIGNTOOL (
    echo signtool.exe not found: executables stay unsigned.
    set SIGNARGS=
  ) else (
    for %%f in (Win32\Release\LS.exe Win64\Release\LS.exe) do (
      %DRY% "!SIGNTOOL!" sign !SIGNARGS! /fd SHA256 /tr "%LS_SIGN_TIMESTAMP%" /td SHA256 /d LayoutSwitcher "%%f" || exit /b 1
    )
  )
)

echo === Package ===
for /f "delims=" %%v in ('powershell -NoProfile -Command "(Get-Item 'Win64\Release\LS.exe').VersionInfo.FileVersion"') do set VERSION=%%v
if not defined VERSION set VERSION=unknown
echo Version %VERSION%
if not exist dist mkdir dist
%DRY% copy /y Win64\Release\LS.exe dist\LayoutSwitcher-%VERSION%-x64.exe || exit /b 1
%DRY% copy /y Win32\Release\LS.exe dist\LayoutSwitcher-%VERSION%-x86.exe || exit /b 1

set ISCC=%LS_ISCC%
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 7\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 7\ISCC.exe
if not defined ISCC if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if not defined ISCC (
  echo Inno Setup not found: installer skipped.
) else (
  %DRY% "%ISCC%" /Q installer\LayoutSwitcher.iss || exit /b 1
  if defined SIGNARGS (
    %DRY% "!SIGNTOOL!" sign !SIGNARGS! /fd SHA256 /tr "%LS_SIGN_TIMESTAMP%" /td SHA256 /d LayoutSwitcher "dist\LayoutSwitcher-Setup-%VERSION%.exe" || exit /b 1
  )
)

if defined DO_MANIFESTS (
  echo === winget manifests ===
  if exist "dist\LayoutSwitcher-Setup-%VERSION%.exe" (
    %DRY% powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-winget.ps1 -Version %VERSION% -InstallerPath "dist\LayoutSwitcher-Setup-%VERSION%.exe" -OutDir dist\winget || exit /b 1
  ) else (
    echo No installer: winget manifests skipped.
  )
)

echo === Done: dist\ ===
dir /b dist
