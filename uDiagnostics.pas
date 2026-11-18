unit uDiagnostics;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

interface

uses
  System.SysUtils;

procedure InitializeDiagnostics;
procedure ShutdownDiagnostics;
procedure DiagnosticsMarkAbnormal;
procedure DiagnosticsLog(const MessageText: string);
procedure DiagnosticsLogFmt(const FormatText: string; const Args: array of const);
procedure DiagnosticsLogException(const Context: string; E: Exception;
  ExceptionAddress: Pointer = nil);
procedure DiagnosticsCaptureException(const Context: string; E: Exception;
  ExceptionAddress: Pointer = nil);
procedure DiagnosticsBeginOperation(const OperationName, Details: string);
procedure DiagnosticsEndOperation(const OperationName: string; Success: Boolean);
function DiagnosticsEnabled: Boolean;
function SetDiagnosticsEnabled(Value: Boolean): Boolean;
function DiagnosticsDirectory: string;
function DiagnosticsLogFile: string;
procedure OpenDiagnosticsDirectory;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI,
  System.Classes, System.Win.Registry, System.IOUtils, System.Types,
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Forms,
  uWinUtils;

const
  DIAGNOSTICS_FOLDER_NAME = 'LayoutSwitcher\Diagnostics';
  SETTINGS_REGISTRY_KEY = 'Software\LayoutSwitcher';
  DIAGNOSTICS_ENABLED_VALUE = 'EnableDiagnostics';
  SESSION_MARKER_NAME = 'last-session.running';
  // Rotation limits: a single log file is split when it grows past
  // MAX_LOG_FILE_SIZE; the folder keeps at most MAX_LOG_FILES logs and
  // MAX_LOG_TOTAL_SIZE bytes, plus MAX_DUMP_FILES minidumps.
  MAX_LOG_FILE_SIZE = 2 * 1024 * 1024;
  MAX_LOG_FILES = 10;
  MAX_LOG_TOTAL_SIZE = 5 * 1024 * 1024;
  MAX_DUMP_FILES = 3;
  MINIDUMP_WITH_DATA_SEGS = $00000001;
  MINIDUMP_WITH_INDIRECTLY_REFERENCED_MEMORY = $00000040;
  MINIDUMP_WITH_THREAD_INFO = $00001000;
  DIAGNOSTIC_STACK_GUARANTEE = 128 * 1024;
  EXCEPTION_CONTINUE_SEARCH_VALUE = 0;
  DIAGNOSTIC_DUMP_TYPE = MINIDUMP_WITH_DATA_SEGS or
    MINIDUMP_WITH_INDIRECTLY_REFERENCED_MEMORY or MINIDUMP_WITH_THREAD_INFO;

type
  TExceptProc = procedure(Obj: TObject; Addr: Pointer);
  TTopLevelExceptionFilter = function(ExceptionInfo: PExceptionPointers): Longint; stdcall;

  TMiniDumpExceptionInformation = record
    ThreadId: DWORD;
    ExceptionPointers: PExceptionPointers;
    ClientPointers: BOOL;
  end;

  TMiniDumpWriteDump = function(ProcessHandle: THandle; ProcessId: DWORD;
    FileHandle: THandle; DumpType: DWORD; ExceptionParam, UserStreamParam,
    CallbackParam: Pointer): BOOL; stdcall;

  TDiagnosticsExceptionSink = class
  public
    procedure ApplicationException(Sender: TObject; E: Exception);
  end;

var
  GInitialized: Boolean;
  GAbnormalShutdown: Boolean;
  GDiagnosticsDirectory: string;
  GLogFile: string;
  GDumpFile: string;
  GSessionMarker: string;
  GSessionName: string;
  GLogPart: Integer;
  GLogSize: Int64;
  GLogLock: TRTLCriticalSection;
  GOldExceptProc: Pointer;
  GOldUnhandledFilter: TFNTopLevelExceptionFilter;
  GOldApplicationException: TExceptionEvent;
  GExceptionSink: TDiagnosticsExceptionSink;
  GCrashCaptured: LongInt;

threadvar
  GCurrentOperation: string;

function SanitizeLogText(const Value: string): string;
begin
  Result := StringReplace(Value, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function AddressDescription(Address: Pointer): string;
var
  MemoryInfo: TMemoryBasicInformation;
  ModulePath: array[0..MAX_PATH - 1] of Char;
  ModuleBase: Pointer;
  ModuleName: string;
begin
  Result := Format('address=%p', [Address]);
  if Address = nil then
    Exit;

  FillChar(MemoryInfo, SizeOf(MemoryInfo), 0);
  if VirtualQuery(Address, MemoryInfo, SizeOf(MemoryInfo)) = 0 then
    Exit;
  ModuleBase := MemoryInfo.AllocationBase;
  if ModuleBase = nil then
    Exit;

  FillChar(ModulePath, SizeOf(ModulePath), 0);
  if GetModuleFileName(THandle(ModuleBase), ModulePath, Length(ModulePath)) > 0 then
    ModuleName := ExtractFileName(string(ModulePath))
  else
    ModuleName := '';
  Result := Format('address=%p module="%s" module_base=%p module_offset=0x%s',
    [Address, ModuleName, ModuleBase,
     IntToHex(NativeUInt(Address) - NativeUInt(ModuleBase), SizeOf(Pointer) * 2)]);
end;

procedure AppendTextToFile(const FileName, Value: string);
var
  FileHandle: THandle;
  Bytes: TBytes;
  Written: DWORD;
begin
  if FileName = '' then
    Exit;

  Bytes := TEncoding.UTF8.GetBytes(Value);
  if Length(Bytes) = 0 then
    Exit;

  FileHandle := CreateFile(PChar(FileName), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    WriteFile(FileHandle, Bytes[0], Length(Bytes), Written, nil);
  finally
    CloseHandle(FileHandle);
  end;
end;

procedure WriteTextFile(const FileName, Value: string);
var
  FileHandle: THandle;
  Bytes: TBytes;
  Written: DWORD;
begin
  Bytes := TEncoding.UTF8.GetBytes(Value);
  FileHandle := CreateFile(PChar(FileName), GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_DELETE, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    if Length(Bytes) > 0 then
      WriteFile(FileHandle, Bytes[0], Length(Bytes), Written, nil);
  finally
    CloseHandle(FileHandle);
  end;
end;

function ReadTextFile(const FileName: string): string;
var
  Strings: TStringList;
begin
  Result := '';
  if (FileName = '') or not FileExists(FileName) then
    Exit;
  Strings := TStringList.Create;
  try
    try
      Strings.LoadFromFile(FileName, TEncoding.UTF8);
      Result := Trim(Strings.Text);
    except
      Result := '';
    end;
  finally
    Strings.Free;
  end;
end;

procedure CleanupDiagnosticsDirectory; forward;

procedure StartNextLogPart;
begin
  // Called with GLogLock held.
  Inc(GLogPart);
  GLogFile := IncludeTrailingPathDelimiter(GDiagnosticsDirectory) +
    Format('%s-part%d.log', [GSessionName, GLogPart]);
  GLogSize := 0;
  WriteTextFile(GSessionMarker, GLogFile);
  CleanupDiagnosticsDirectory;
end;

procedure DiagnosticsLog(const MessageText: string);
var
  Line: string;
begin
  if not GInitialized then
    Exit;

  try
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
      Format(' pid=%d tid=%d ', [GetCurrentProcessId, GetCurrentThreadId]) +
      SanitizeLogText(MessageText);
    OutputDebugString(PChar(Line));
    Line := Line + sLineBreak;
    EnterCriticalSection(GLogLock);
    try
      if not GInitialized or (GLogFile = '') then
        Exit;
      if GLogSize > MAX_LOG_FILE_SIZE then
        StartNextLogPart;
      AppendTextToFile(GLogFile, Line);
      Inc(GLogSize, TEncoding.UTF8.GetByteCount(Line));
    finally
      LeaveCriticalSection(GLogLock);
    end;
  except
    // Diagnostics must never become another failure source.
  end;
end;

function SortedByAge(const Files: TStringDynArray): TArray<string>;
begin
  // File names start with a sortable timestamp, oldest first.
  Result := TArray<string>(Files);
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

procedure DeleteQuietly(const FileName: string);
begin
  try
    System.SysUtils.DeleteFile(FileName);
  except
  end;
end;

procedure CleanupDiagnosticsDirectory;
var
  Logs, Dumps: TArray<string>;
  I, Remaining: Integer;
  TotalSize: Int64;
  Sizes: TArray<Int64>;
begin
  if (GDiagnosticsDirectory = '') or not DirectoryExists(GDiagnosticsDirectory) then
    Exit;
  try
    Logs := SortedByAge(TDirectory.GetFiles(GDiagnosticsDirectory,
      'LayoutSwitcher-*.log'));
    SetLength(Sizes, Length(Logs));
    TotalSize := 0;
    for I := 0 to High(Logs) do
    begin
      try
        Sizes[I] := TFile.GetSize(Logs[I]);
      except
        Sizes[I] := 0;
      end;
      Inc(TotalSize, Sizes[I]);
    end;
    Remaining := Length(Logs);
    for I := 0 to High(Logs) do
    begin
      if (Remaining <= MAX_LOG_FILES) and (TotalSize <= MAX_LOG_TOTAL_SIZE) then
        Break;
      if SameText(Logs[I], GLogFile) then
        Continue;
      DeleteQuietly(Logs[I]);
      Dec(TotalSize, Sizes[I]);
      Dec(Remaining);
    end;

    Dumps := SortedByAge(TDirectory.GetFiles(GDiagnosticsDirectory,
      'LayoutSwitcher-*.dmp'));
    for I := 0 to High(Dumps) - MAX_DUMP_FILES do
      DeleteQuietly(Dumps[I]);
  except
    // Cleanup is best effort.
  end;
end;


procedure DiagnosticsLogFmt(const FormatText: string; const Args: array of const);
begin
  if not GInitialized then
    Exit;

  try
    DiagnosticsLog(Format(FormatText, Args));
  except
    // A malformed diagnostic format must not affect the application.
  end;
end;

function ExecutableSize: Int64;
var
  Stream: TFileStream;
begin
  try
    Stream := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
    try
      Result := Stream.Size;
    finally
      Stream.Free;
    end;
  except
    Result := -1;
  end;
end;

function WriteMiniDump(ExceptionPointers: PExceptionPointers): Boolean;
var
  DbgHelpModule: HMODULE;
  DumpWriter: TMiniDumpWriteDump;
  DumpHandle: THandle;
  ExceptionInfo: TMiniDumpExceptionInformation;
  ExceptionParam: Pointer;
begin
  Result := False;
  if not GInitialized then
    Exit;
  if InterlockedCompareExchange(GCrashCaptured, 1, 0) <> 0 then
    Exit;

  DbgHelpModule := LoadLibrary('dbghelp.dll');
  if DbgHelpModule = 0 then
  begin
    DiagnosticsLogFmt('minidump.load_failed error=%d', [GetLastError]);
    Exit;
  end;
  try
    DumpWriter := TMiniDumpWriteDump(GetProcAddress(DbgHelpModule,
      PChar('MiniDumpWriteDump')));
    if not Assigned(DumpWriter) then
    begin
      DiagnosticsLogFmt('minidump.proc_missing error=%d', [GetLastError]);
      Exit;
    end;

    DumpHandle := CreateFile(PChar(GDumpFile), GENERIC_WRITE, FILE_SHARE_READ,
      nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if DumpHandle = INVALID_HANDLE_VALUE then
    begin
      DiagnosticsLogFmt('minidump.create_failed error=%d', [GetLastError]);
      Exit;
    end;
    try
      ExceptionParam := nil;
      if Assigned(ExceptionPointers) then
      begin
        FillChar(ExceptionInfo, SizeOf(ExceptionInfo), 0);
        ExceptionInfo.ThreadId := GetCurrentThreadId;
        ExceptionInfo.ExceptionPointers := ExceptionPointers;
        ExceptionInfo.ClientPointers := False;
        ExceptionParam := @ExceptionInfo;
      end;

      Result := DumpWriter(GetCurrentProcess, GetCurrentProcessId, DumpHandle,
        DIAGNOSTIC_DUMP_TYPE, ExceptionParam, nil, nil);
      if not Result then
        DiagnosticsLogFmt('minidump.write_failed error=%d', [GetLastError]);
    finally
      CloseHandle(DumpHandle);
    end;

    if Result then
      DiagnosticsLogFmt('minidump.created path="%s"', [GDumpFile])
    else
      System.SysUtils.DeleteFile(GDumpFile);
  finally
    FreeLibrary(DbgHelpModule);
  end;
end;

procedure DiagnosticsLogException(const Context: string; E: Exception;
  ExceptionAddress: Pointer);
var
  Address: Pointer;
  StackText: string;
begin
  if not GInitialized then
    Exit;

  try
    Address := ExceptionAddress;
    if Address = nil then
      Address := ExceptAddr;
    DiagnosticsLogFmt('exception context="%s" operation="%s" class=%s message="%s" %s',
      [Context, GCurrentOperation, E.ClassName, SanitizeLogText(E.Message),
       AddressDescription(Address)]);
    StackText := E.StackTrace;
    if StackText <> '' then
      DiagnosticsLog('stack=' + StackText);
  except
    DiagnosticsLog('exception logging failed');
  end;
end;

procedure DiagnosticsCaptureException(const Context: string; E: Exception;
  ExceptionAddress: Pointer);
begin
  if not GInitialized then
    Exit;
  DiagnosticsLogException(Context, E, ExceptionAddress);
  if not (E is EAbort) then
    WriteMiniDump(nil);
end;

procedure DiagnosticsBeginOperation(const OperationName, Details: string);
begin
  if not GInitialized then
    Exit;
  GCurrentOperation := OperationName;
  DiagnosticsLogFmt('operation.begin name=%s %s', [OperationName, Details]);
end;

procedure DiagnosticsEndOperation(const OperationName: string; Success: Boolean);
begin
  if not GInitialized then
    Exit;
  DiagnosticsLogFmt('operation.end name=%s success=%s',
    [OperationName, BoolToStr(Success, True)]);
  GCurrentOperation := '';
end;

procedure DiagnosticsMarkAbnormal;
begin
  if GInitialized then
    GAbnormalShutdown := True;
end;

function DiagnosticsEnabled: Boolean;
var
  Registry: TRegistry;
begin
  Result := True;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      if Registry.OpenKeyReadOnly(SETTINGS_REGISTRY_KEY) and
         Registry.ValueExists(DIAGNOSTICS_ENABLED_VALUE) then
        Result := Registry.ReadBool(DIAGNOSTICS_ENABLED_VALUE);
    except
      // Keep diagnostics enabled when the preference cannot be read.
      Result := True;
    end;
  finally
    Registry.Free;
  end;
end;

function SetDiagnosticsEnabled(Value: Boolean): Boolean;
var
  Registry: TRegistry;
begin
  Result := False;
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      if Registry.OpenKey(SETTINGS_REGISTRY_KEY, True) then
      begin
        Registry.WriteBool(DIAGNOSTICS_ENABLED_VALUE, Value);
        Result := True;
      end;
    except
      Result := False;
    end;
  finally
    Registry.Free;
  end;
end;

procedure DelphiUnhandledException(Obj: TObject; Addr: Pointer);
begin
  GAbnormalShutdown := True;
  try
    if Obj is Exception then
      DiagnosticsLogException('delphi.unhandled', Exception(Obj), Addr)
    else if Assigned(Obj) then
      DiagnosticsLogFmt('delphi.unhandled class=%s address=%p operation="%s"',
        [Obj.ClassName, Addr, GCurrentOperation])
    else
      DiagnosticsLogFmt('delphi.unhandled object=nil address=%p operation="%s"',
        [Addr, GCurrentOperation]);
    WriteMiniDump(nil);
  except
    // Preserve the original RTL failure path even if diagnostics fail.
  end;

  if Assigned(GOldExceptProc) then
    TExceptProc(GOldExceptProc)(Obj, Addr)
  else
    Halt(1);
end;

function WindowsUnhandledException(ExceptionInfo: PExceptionPointers): Longint; stdcall;
var
  Code: DWORD;
  Address: Pointer;
begin
  GAbnormalShutdown := True;
  Code := 0;
  Address := nil;
  try
    if Assigned(ExceptionInfo) and Assigned(ExceptionInfo^.ExceptionRecord) then
    begin
      Code := ExceptionInfo^.ExceptionRecord^.ExceptionCode;
      Address := ExceptionInfo^.ExceptionRecord^.ExceptionAddress;
    end;
    DiagnosticsLogFmt('windows.unhandled code=0x%.8x %s operation="%s"',
      [Code, AddressDescription(Address), GCurrentOperation]);
    WriteMiniDump(ExceptionInfo);
  except
    // A top-level filter has to remain exception-safe.
  end;

  if Assigned(GOldUnhandledFilter) then
    Result := TTopLevelExceptionFilter(GOldUnhandledFilter)(ExceptionInfo)
  else
    Result := EXCEPTION_CONTINUE_SEARCH_VALUE;
end;

procedure TDiagnosticsExceptionSink.ApplicationException(Sender: TObject;
  E: Exception);
begin
  DiagnosticsCaptureException('vcl.application', E, ExceptAddr);

  if Assigned(GOldApplicationException) then
    GOldApplicationException(Sender, E)
  else
  try
    Application.ShowException(E);
  except
    // The log and dump are more important than an error dialog.
  end;
end;

function DiagnosticsDirectory: string;
begin
  Result := GDiagnosticsDirectory;
end;

function DiagnosticsLogFile: string;
begin
  Result := GLogFile;
end;

procedure OpenDiagnosticsDirectory;
begin
  try
    if (GDiagnosticsDirectory <> '') and
       (ShellExecute(0, 'open', PChar(GDiagnosticsDirectory), nil, nil,
          SW_SHOWNORMAL) <= 32) then
      DiagnosticsLogFmt('diagnostics.open_folder_failed error=%d', [GetLastError]);
  except
    // Opening the folder is optional and must not affect the application.
  end;
end;

procedure InitializeDiagnostics;
var
  RootDirectory, SessionName, PreviousLogFile: string;
  PreviousSessionWasAbnormal: Boolean;
  BuildKind: string;
  PreviousStackGuarantee: UInt64;
begin
  if GInitialized then
    Exit;

  RootDirectory := GetEnvironmentVariable('LOCALAPPDATA');
  if RootDirectory = '' then
    RootDirectory := GetEnvironmentVariable('TEMP');
  if RootDirectory = '' then
    RootDirectory := ExtractFilePath(ParamStr(0));

  GDiagnosticsDirectory := IncludeTrailingPathDelimiter(RootDirectory) +
    DIAGNOSTICS_FOLDER_NAME;
  if not DiagnosticsEnabled then
    Exit;

  try
    ForceDirectories(GDiagnosticsDirectory);
  except
    GDiagnosticsDirectory := ExtractFilePath(ParamStr(0)) + 'Diagnostics';
    try
      ForceDirectories(GDiagnosticsDirectory);
    except
      GDiagnosticsDirectory := '';
    end;
  end;

  SessionName := 'LayoutSwitcher-' +
    FormatDateTime('yyyymmdd-hhnnss-zzz', Now) + '-' +
    IntToStr(GetCurrentProcessId);
  GSessionName := SessionName;
  GLogPart := 1;
  GLogSize := 0;
  if GDiagnosticsDirectory <> '' then
  begin
    GLogFile := IncludeTrailingPathDelimiter(GDiagnosticsDirectory) +
      SessionName + '.log';
    GDumpFile := IncludeTrailingPathDelimiter(GDiagnosticsDirectory) +
      SessionName + '.dmp';
    GSessionMarker := IncludeTrailingPathDelimiter(GDiagnosticsDirectory) +
      SESSION_MARKER_NAME;
  end
  else
  begin
    GLogFile := '';
    GDumpFile := '';
    GSessionMarker := '';
  end;
  PreviousSessionWasAbnormal := FileExists(GSessionMarker);
  if PreviousSessionWasAbnormal then
    PreviousLogFile := ReadTextFile(GSessionMarker)
  else
    PreviousLogFile := '';

  GInitialized := True;
  GAbnormalShutdown := False;
  GCrashCaptured := 0;
  GCurrentOperation := '';

  WriteTextFile(GSessionMarker, GLogFile);
  CleanupDiagnosticsDirectory;
  {$IFDEF DEBUG}
  BuildKind := 'Debug';
  {$ELSE}
  BuildKind := 'Release';
  {$ENDIF}
  DiagnosticsLogFmt('session.start version=%s build=%s bits=%d os="%s" exe="%s" exe_size=%d module_base=%p',
    [uWinUtils.GetExecutableVersion, BuildKind, SizeOf(Pointer) * 8, TOSVersion.ToString,
     ParamStr(0), ExecutableSize, Pointer(HInstance)]);
  DiagnosticsLogFmt('diagnostics.directory path="%s"', [GDiagnosticsDirectory]);
  if PreviousSessionWasAbnormal then
    DiagnosticsLogFmt('session.previous_abnormal marker_found=true previous_log="%s"',
      [PreviousLogFile]);

  PreviousStackGuarantee := DIAGNOSTIC_STACK_GUARANTEE;
  if SetThreadStackGuarantee(PreviousStackGuarantee) then
    DiagnosticsLogFmt(
      'diagnostics.stack_guarantee success=true requested=%d previous=%d',
      [DIAGNOSTIC_STACK_GUARANTEE, PreviousStackGuarantee])
  else
    DiagnosticsLogFmt(
      'diagnostics.stack_guarantee success=false requested=%d error=%d',
      [DIAGNOSTIC_STACK_GUARANTEE, GetLastError]);

  GOldExceptProc := ExceptProc;
  ExceptProc := @DelphiUnhandledException;
  GOldUnhandledFilter := SetUnhandledExceptionFilter(@WindowsUnhandledException);

  GExceptionSink := TDiagnosticsExceptionSink.Create;
  GOldApplicationException := Application.OnException;
  Application.OnException := GExceptionSink.ApplicationException;
end;

procedure ShutdownDiagnostics;
begin
  if not GInitialized then
    Exit;

  if GAbnormalShutdown then
    DiagnosticsLog('session.end abnormal=true')
  else
    DiagnosticsLog('session.end normal=true');

  Application.OnException := GOldApplicationException;
  FreeAndNil(GExceptionSink);
  ExceptProc := GOldExceptProc;
  SetUnhandledExceptionFilter(GOldUnhandledFilter);

  if not GAbnormalShutdown then
    System.SysUtils.DeleteFile(GSessionMarker);
  EnterCriticalSection(GLogLock);
  try
    GInitialized := False;
  finally
    LeaveCriticalSection(GLogLock);
  end;
end;

initialization
  InitializeCriticalSection(GLogLock);

finalization
  DeleteCriticalSection(GLogLock);

end.
