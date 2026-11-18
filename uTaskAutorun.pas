unit uTaskAutorun;

// Autorun with administrator rights through Task Scheduler.
//
// Windows (UIPI) blocks SendInput from a normal process into windows of an
// elevated one.  A logon task with RunLevel=HighestAvailable starts the
// program elevated without a UAC prompt on every logon; the Run registry key
// cannot do that.  Creating or deleting the task needs elevation once, so
// schtasks.exe is started through ShellExecuteEx("runas").

interface

const
  AUTORUN_TASK_NAME = 'LayoutSwitcher';

function IsProcessElevated: Boolean;
// True if the task exists; ExePath receives its command.
function QueryAutorunTask(out ExePath: string): Boolean;
function InstallAutorunTask(const ExePath: string; out ErrorText: string): Boolean;
function RemoveAutorunTask(out ErrorText: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI,
  System.SysUtils, System.Classes,
  uLocale;

const
  SCHTASKS_TIMEOUT = 30000;
  TOKEN_ELEVATION_CLASS = 20; // TokenElevation
  NAME_SAM_COMPATIBLE = 2;

function LSGetUserNameEx(NameFormat: Integer; NameBuffer: PWideChar;
  var Size: ULONG): BOOL; stdcall;
  external 'secur32.dll' name 'GetUserNameExW';

function IsProcessElevated: Boolean;
var
  Token: THandle;
  Elevation: DWORD;
  Size: DWORD;
begin
  Result := False;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    Elevation := 0;
    if GetTokenInformation(Token, TTokenInformationClass(TOKEN_ELEVATION_CLASS),
         @Elevation, SizeOf(Elevation), Size) then
      Result := Elevation <> 0;
  finally
    CloseHandle(Token);
  end;
end;

function SchtasksPath: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetSystemDirectory(Buffer, Length(Buffer));
  Result := IncludeTrailingPathDelimiter(Buffer) + 'schtasks.exe';
end;

function CurrentUserId: string;
var
  Size: ULONG;
  Buffer: array[0..511] of WideChar;
begin
  Size := Length(Buffer);
  if LSGetUserNameEx(NAME_SAM_COMPATIBLE, @Buffer[0], Size) then
    SetString(Result, PWideChar(@Buffer[0]), Size)
  else
    Result := GetEnvironmentVariable('USERDOMAIN') + '\' +
      GetEnvironmentVariable('USERNAME');
end;

function XmlEscape(const Value: string): string;
begin
  Result := Value.Replace('&', '&amp;').Replace('<', '&lt;')
    .Replace('>', '&gt;').Replace('"', '&quot;');
end;

function XmlUnescape(const Value: string): string;
begin
  Result := Value.Replace('&lt;', '<').Replace('&gt;', '>')
    .Replace('&quot;', '"').Replace('&amp;', '&');
end;

// Runs a console program hidden and captures its standard output.
function RunHidden(const CommandLine: string; out Output: string;
  out ExitCode: DWORD): Boolean;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  Bytes: TBytesStream;
  MutableCommand: string;
  Encoding: TEncoding;
begin
  Result := False;
  Output := '';
  ExitCode := DWORD(-1);
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
    Exit;
  Bytes := TBytesStream.Create;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdOutput := WritePipe;
    StartupInfo.hStdError := WritePipe;
    MutableCommand := CommandLine;
    UniqueString(MutableCommand);
    if not CreateProcess(nil, PChar(MutableCommand), nil, nil, True,
         CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo) then
    begin
      CloseHandle(WritePipe);
      CloseHandle(ReadPipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    try
      while ReadFile(ReadPipe, Buffer, SizeOf(Buffer), BytesRead, nil) and
            (BytesRead > 0) do
        Bytes.WriteBuffer(Buffer, BytesRead);
      WaitForSingleObject(ProcessInfo.hProcess, SCHTASKS_TIMEOUT);
      GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
    finally
      CloseHandle(ReadPipe);
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
    // Redirected console output uses the OEM code page.
    Encoding := TEncoding.GetEncoding(GetOEMCP);
    try
      Output := Encoding.GetString(Bytes.Bytes, 0, Bytes.Size);
    finally
      Encoding.Free;
    end;
    Result := True;
  finally
    Bytes.Free;
  end;
end;

// Runs schtasks.exe elevated (UAC prompt unless already elevated).
function RunSchtasksElevated(const Parameters: string;
  out ErrorText: string): Boolean;
var
  Info: TShellExecuteInfo;
  ExitCode: DWORD;
begin
  Result := False;
  ErrorText := '';
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_NOASYNC;
  if IsProcessElevated then
    Info.lpVerb := 'open'
  else
    Info.lpVerb := 'runas';
  Info.lpFile := PChar(SchtasksPath);
  Info.lpParameters := PChar(Parameters);
  Info.nShow := SW_HIDE;
  if not ShellExecuteEx(@Info) then
  begin
    if GetLastError = ERROR_CANCELLED then
      ErrorText := T('Запрос прав администратора отклонён.',
        'The administrator rights request was declined.')
    else
      ErrorText := SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    if WaitForSingleObject(Info.hProcess, SCHTASKS_TIMEOUT) <> WAIT_OBJECT_0 then
    begin
      ErrorText := T('Планировщик заданий не ответил вовремя.',
        'Task Scheduler did not respond in time.');
      Exit;
    end;
    GetExitCodeProcess(Info.hProcess, ExitCode);
    Result := ExitCode = 0;
    if not Result then
      ErrorText := Format(T('Планировщик заданий завершился с кодом %d.',
        'Task Scheduler exited with code %d.'), [ExitCode]);
  finally
    CloseHandle(Info.hProcess);
  end;
end;

function QueryAutorunTask(out ExePath: string): Boolean;
var
  Output: string;
  ExitCode: DWORD;
  StartPos, EndPos: Integer;
begin
  ExePath := '';
  Result := RunHidden(Format('"%s" /Query /TN "%s" /XML ONE',
    [SchtasksPath, AUTORUN_TASK_NAME]), Output, ExitCode) and (ExitCode = 0);
  if not Result then
    Exit;
  StartPos := Pos('<Command>', Output);
  EndPos := Pos('</Command>', Output);
  if (StartPos > 0) and (EndPos > StartPos) then
  begin
    Inc(StartPos, Length('<Command>'));
    ExePath := XmlUnescape(Trim(Copy(Output, StartPos, EndPos - StartPos)));
    ExePath := ExePath.DeQuotedString('"');
  end;
end;

function BuildTaskXml(const ExePath: string): string;
var
  UserId: string;
begin
  UserId := XmlEscape(CurrentUserId);
  // Settings that differ from the schtasks defaults: normal priority instead
  // of "below normal" (7), no 72-hour execution limit, runs on battery.
  Result :=
    '<?xml version="1.0" encoding="UTF-16"?>' + sLineBreak +
    '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' + sLineBreak +
    '  <RegistrationInfo>' + sLineBreak +
    '    <Description>LayoutSwitcher: autorun with administrator rights</Description>' + sLineBreak +
    '  </RegistrationInfo>' + sLineBreak +
    '  <Triggers>' + sLineBreak +
    '    <LogonTrigger>' + sLineBreak +
    '      <Enabled>true</Enabled>' + sLineBreak +
    '      <UserId>' + UserId + '</UserId>' + sLineBreak +
    '    </LogonTrigger>' + sLineBreak +
    '  </Triggers>' + sLineBreak +
    '  <Principals>' + sLineBreak +
    '    <Principal id="Author">' + sLineBreak +
    '      <UserId>' + UserId + '</UserId>' + sLineBreak +
    '      <LogonType>InteractiveToken</LogonType>' + sLineBreak +
    '      <RunLevel>HighestAvailable</RunLevel>' + sLineBreak +
    '    </Principal>' + sLineBreak +
    '  </Principals>' + sLineBreak +
    '  <Settings>' + sLineBreak +
    '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' + sLineBreak +
    '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' + sLineBreak +
    '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' + sLineBreak +
    '    <AllowHardTerminate>true</AllowHardTerminate>' + sLineBreak +
    '    <StartWhenAvailable>false</StartWhenAvailable>' + sLineBreak +
    '    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>' + sLineBreak +
    '    <IdleSettings>' + sLineBreak +
    '      <StopOnIdleEnd>false</StopOnIdleEnd>' + sLineBreak +
    '      <RestartOnIdle>false</RestartOnIdle>' + sLineBreak +
    '    </IdleSettings>' + sLineBreak +
    '    <AllowStartOnDemand>true</AllowStartOnDemand>' + sLineBreak +
    '    <Enabled>true</Enabled>' + sLineBreak +
    '    <Hidden>false</Hidden>' + sLineBreak +
    '    <RunOnlyIfIdle>false</RunOnlyIfIdle>' + sLineBreak +
    '    <WakeToRun>false</WakeToRun>' + sLineBreak +
    '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' + sLineBreak +
    '    <Priority>4</Priority>' + sLineBreak +
    '  </Settings>' + sLineBreak +
    '  <Actions Context="Author">' + sLineBreak +
    '    <Exec>' + sLineBreak +
    '      <Command>"' + XmlEscape(ExePath) + '"</Command>' + sLineBreak +
    '    </Exec>' + sLineBreak +
    '  </Actions>' + sLineBreak +
    '</Task>' + sLineBreak;
end;

function InstallAutorunTask(const ExePath: string; out ErrorText: string): Boolean;
var
  XmlFile: string;
  Stream: TFileStream;
  Bytes, Preamble: TBytes;
begin
  XmlFile := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    Format('LayoutSwitcher-task-%d.xml', [GetCurrentProcessId]);
  try
    Preamble := TEncoding.Unicode.GetPreamble;
    Bytes := TEncoding.Unicode.GetBytes(BuildTaskXml(ExePath));
    Stream := TFileStream.Create(XmlFile, fmCreate);
    try
      Stream.WriteBuffer(Preamble[0], Length(Preamble));
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
    Result := RunSchtasksElevated(Format('/Create /TN "%s" /XML "%s" /F',
      [AUTORUN_TASK_NAME, XmlFile]), ErrorText);
  except
    on E: Exception do
    begin
      ErrorText := E.Message;
      Result := False;
    end;
  end;
  System.SysUtils.DeleteFile(XmlFile);
end;

function RemoveAutorunTask(out ErrorText: string): Boolean;
begin
  Result := RunSchtasksElevated(Format('/Delete /TN "%s" /F',
    [AUTORUN_TASK_NAME]), ErrorText);
end;

end.
