; Inno Setup 6 script for LayoutSwitcher.
; Built by build-release.cmd after both Release configurations are compiled.
;
; Installs per user (no administrator rights needed) into
; %LOCALAPPDATA%\Programs\LayoutSwitcher; the user may choose an installation
; for all users on the first page.

#define AppName "LayoutSwitcher"
#define AppExe "LS.exe"
#define AppVersion GetVersionNumbersString(AddBackslash(SourcePath) + "..\Win64\Release\LS.exe")
; Used in [Code] only, where braces need no escaping.
#define AppMutexName "Local\LayoutSwitcher.{7D419F5E-2D00-46CB-B50E-48D7F8A070C1}"

[Setup]
AppId={{6F0D1E3A-5B7C-4C0B-9E55-4A1D9E2B7C11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Len-A-R Soft
AppPublisherURL=https://github.com/Len-A-R/LayoutSwitcher
AppSupportURL=https://github.com/Len-A-R/LayoutSwitcher/issues
AppUpdatesURL=https://github.com/Len-A-R/LayoutSwitcher/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
; "commandline": winget passes /CURRENTUSER or /ALLUSERS.
PrivilegesRequiredOverridesAllowed=commandline dialog
ArchitecturesAllowed=x86compatible x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The running instance must be closed before its files are replaced; this
; is checked in InitializeSetup (see [Code]).
CloseApplications=no
OutputDir=..\dist
OutputBaseFilename=LayoutSwitcher-Setup-{#AppVersion}
SetupIconFile=..\LS.Artwork\Windows\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
russian.CloseApp=LayoutSwitcher запущен. Закройте его (значок в трее → «Выход») и нажмите «Повтор».
english.CloseApp=LayoutSwitcher is running. Close it (tray icon → Exit) and click Retry.
russian.AutostartTask=Запускать при входе в Windows
english.AutostartTask=Start with Windows
russian.RemoveSettings=Удалить также настройки и журналы диагностики LayoutSwitcher?
english.RemoveSettings=Also remove the LayoutSwitcher settings and diagnostic logs?

[Tasks]
Name: "autostart"; Description: "{cm:AutostartTask}"

[Files]
Source: "..\Win64\Release\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion; Check: Is64BitInstallMode
Source: "..\Win32\Release\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion; Check: not Is64BitInstallMode
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Registry]
; The same value the program writes itself when autorun is enabled.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Update started from the program itself (/WAITAPP=1): start the new version.
Filename: "{app}\{#AppExe}"; Flags: nowait runasoriginaluser; Check: IsUpdateRun

[UninstallDelete]
Type: dirifempty; Name: "{app}"

[Code]
function IsUpdateRun: Boolean;
begin
  Result := ExpandConstant('{param:WAITAPP|0}') = '1';
end;

function InitializeSetup: Boolean;
var
  Waited: Integer;
begin
  Result := True;
  if IsUpdateRun then
  begin
    // The program started this update and is exiting right now.
    Waited := 0;
    while CheckForMutexes('{#AppMutexName}') and (Waited < 30000) do
    begin
      Sleep(250);
      Waited := Waited + 250;
    end;
  end;
  while CheckForMutexes('{#AppMutexName}') do
    if MsgBox(CustomMessage('CloseApp'), mbError, MB_RETRYCANCEL) <> IDRETRY then
    begin
      Result := False;
      Exit;
    end;
end;

function TaskExists: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\schtasks.exe'), '/Query /TN "{#AppName}"', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Autorun with administrator rights is a scheduled task; deleting it
    // needs elevation, so UAC is shown only if the task exists.
    if TaskExists then
      ShellExec('runas', ExpandConstant('{sys}\schtasks.exe'),
        '/Delete /TN "{#AppName}" /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#AppName}');
  end;
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
    if MsgBox(CustomMessage('RemoveSettings'), mbConfirmation, MB_YESNO) = IDYES then
    begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\{#AppName}');
      DelTree(ExpandConstant('{localappdata}\{#AppName}'), True, True, True);
    end;
end;
