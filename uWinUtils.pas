unit uWinUtils;

// Thin wrappers around Win32 used by both the UI thread and the worker.

interface

uses
  Winapi.Windows;

const
  // dwExtraInfo marker for our own synthetic input.
  LS_INPUT_TAG = $4C535749; // "LSWI"

function GetFocusedWindow: HWND;
function GetWindowProcessPath(Wnd: HWND): string;
function GetWindowProcessFileName(Wnd: HWND): string;
function GetWindowClassName(Wnd: HWND): string;
function IsWindowHung(Wnd: HWND): Boolean;
function IsNativePasswordEdit(Wnd: HWND): Boolean;

// True when the window belongs to a process with a higher integrity level
// (typically "Run as administrator").  UIPI silently drops SendInput there.
function IsWindowProcessElevatedAboveUs(Wnd: HWND): Boolean;

// True for exclusive/borderless full-screen applications, games and
// presentation mode.
function IsFullscreenAppActive: Boolean;

function GetExecutableVersion: string;

function SendChord(ModifierVK, VK: Word): Boolean;
function SendBackspaces(Count: Integer): Boolean;
function TypeUnicodeText(const Value: string): Boolean;
function AreModifiersPhysicallyDown: Boolean;

implementation

uses
  Winapi.MultiMon,
  System.SysUtils;

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;
  TOKEN_INTEGRITY_LEVEL_CLASS = 25; // TokenIntegrityLevel
  QUNS_BUSY = 2;
  QUNS_RUNNING_D3D_FULL_SCREEN = 3;
  QUNS_PRESENTATION_MODE = 4;

type
  TLSGUIThreadInfo = record
    cbSize: DWORD;
    flags: DWORD;
    hwndActive: HWND;
    hwndFocus: HWND;
    hwndCapture: HWND;
    hwndMenuOwner: HWND;
    hwndMoveSize: HWND;
    hwndCaret: HWND;
    rcCaret: TRect;
  end;

  TLSTokenMandatoryLabel = record
    Sid: PSID;
    Attributes: DWORD;
  end;
  PLSTokenMandatoryLabel = ^TLSTokenMandatoryLabel;

function LSIsHungAppWindow(Wnd: HWND): BOOL; stdcall;
  external user32 name 'IsHungAppWindow';
function LSGetGUIThreadInfo(ThreadID: DWORD; var Info: TLSGUIThreadInfo): BOOL;
  stdcall; external user32 name 'GetGUIThreadInfo';
function LSQueryFullProcessImageName(Process: THandle; Flags: DWORD;
  ExeName: PWideChar; var Size: DWORD): BOOL; stdcall;
  external kernel32 name 'QueryFullProcessImageNameW';
function LSGetShellWindow: HWND; stdcall;
  external user32 name 'GetShellWindow';
function LSSHQueryUserNotificationState(out State: Integer): HRESULT; stdcall;
  external 'shell32.dll' name 'SHQueryUserNotificationState';

function GetFocusedWindow: HWND;
var
  Foreground: HWND;
  Info: TLSGUIThreadInfo;
begin
  Foreground := GetForegroundWindow;
  if Foreground = 0 then
    Exit(0);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if LSGetGUIThreadInfo(GetWindowThreadProcessId(Foreground, nil), Info) and
     (Info.hwndFocus <> 0) then
    Result := Info.hwndFocus
  else
    Result := Foreground;
end;

function OpenWindowProcess(Wnd: HWND): THandle;
var
  ProcessID: DWORD;
begin
  Result := 0;
  if Wnd = 0 then
    Exit;
  ProcessID := 0;
  GetWindowThreadProcessId(Wnd, @ProcessID);
  if ProcessID = 0 then
    Exit;
  Result := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, ProcessID);
end;

function GetWindowProcessPath(Wnd: HWND): string;
var
  Process: THandle;
  Size: DWORD;
  Buffer: array[0..MAX_PATH * 2] of WideChar;
begin
  Result := '';
  Process := OpenWindowProcess(Wnd);
  if Process = 0 then
    Exit;
  try
    Size := Length(Buffer);
    if LSQueryFullProcessImageName(Process, 0, @Buffer[0], Size) then
      SetString(Result, PWideChar(@Buffer[0]), Size);
  finally
    CloseHandle(Process);
  end;
end;

function GetWindowProcessFileName(Wnd: HWND): string;
begin
  Result := ExtractFileName(GetWindowProcessPath(Wnd));
end;

function GetWindowClassName(Wnd: HWND): string;
var
  Buffer: array[0..255] of Char;
  Len: Integer;
begin
  Result := '';
  if Wnd = 0 then
    Exit;
  Len := GetClassName(Wnd, Buffer, Length(Buffer));
  if Len > 0 then
    SetString(Result, PChar(@Buffer[0]), Len);
end;

function IsWindowHung(Wnd: HWND): Boolean;
begin
  Result := (Wnd <> 0) and LSIsHungAppWindow(Wnd);
end;

function IsNativePasswordEdit(Wnd: HWND): Boolean;
var
  ClassText: string;
begin
  Result := False;
  if Wnd = 0 then
    Exit;
  ClassText := LowerCase(GetWindowClassName(Wnd));
  if (Pos('edit', ClassText) = 0) and (Pos('tmemo', ClassText) = 0) then
    Exit;
  Result := (GetWindowLongPtr(Wnd, GWL_STYLE) and ES_PASSWORD) <> 0;
end;

function GetTokenIntegrityLevel(Token: THandle; out Level: DWORD): Boolean;
var
  Size: DWORD;
  Buffer: array of Byte;
  LabelPtr: PLSTokenMandatoryLabel;
  SubAuthorityCount: PUCHAR;
begin
  Result := False;
  Level := 0;
  Size := 0;
  GetTokenInformation(Token, TTokenInformationClass(TOKEN_INTEGRITY_LEVEL_CLASS),
    nil, 0, Size);
  if Size = 0 then
    Exit;
  SetLength(Buffer, Size);
  if not GetTokenInformation(Token,
       TTokenInformationClass(TOKEN_INTEGRITY_LEVEL_CLASS), @Buffer[0], Size,
       Size) then
    Exit;
  LabelPtr := PLSTokenMandatoryLabel(@Buffer[0]);
  SubAuthorityCount := GetSidSubAuthorityCount(LabelPtr^.Sid);
  if (SubAuthorityCount = nil) or (SubAuthorityCount^ = 0) then
    Exit;
  Level := GetSidSubAuthority(LabelPtr^.Sid, SubAuthorityCount^ - 1)^;
  Result := True;
end;

function GetOwnIntegrityLevel: DWORD;
var
  Token: THandle;
begin
  Result := 0;
  if OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
  try
    GetTokenIntegrityLevel(Token, Result);
  finally
    CloseHandle(Token);
  end;
end;

function IsWindowProcessElevatedAboveUs(Wnd: HWND): Boolean;
var
  Process, Token: THandle;
  TargetLevel: DWORD;
begin
  Result := False;
  Process := OpenWindowProcess(Wnd);
  if Process = 0 then
    Exit;
  try
    if not OpenProcessToken(Process, TOKEN_QUERY, Token) then
    begin
      // A medium-integrity process cannot open the token of an elevated one.
      Result := GetLastError = ERROR_ACCESS_DENIED;
      Exit;
    end;
    try
      if GetTokenIntegrityLevel(Token, TargetLevel) then
        Result := TargetLevel > GetOwnIntegrityLevel;
    finally
      CloseHandle(Token);
    end;
  finally
    CloseHandle(Process);
  end;
end;

function IsShellWindow(Wnd: HWND): Boolean;
var
  ClassText: string;
begin
  ClassText := GetWindowClassName(Wnd);
  Result := (Wnd = LSGetShellWindow) or (Wnd = GetDesktopWindow) or
    SameText(ClassText, 'Progman') or SameText(ClassText, 'WorkerW') or
    SameText(ClassText, 'Shell_TrayWnd');
end;

function IsFullscreenAppActive: Boolean;
var
  State: Integer;
  Foreground: HWND;
  WindowRect: TRect;
  Monitor: HMONITOR;
  MonitorInfo: TMonitorInfo;
  Style: NativeInt;
begin
  Result := False;
  if Succeeded(LSSHQueryUserNotificationState(State)) and
     ((State = QUNS_BUSY) or (State = QUNS_RUNNING_D3D_FULL_SCREEN) or
      (State = QUNS_PRESENTATION_MODE)) then
    Exit(True);

  // Fallback for borderless windows the shell does not report.
  Foreground := GetForegroundWindow;
  if (Foreground = 0) or IsShellWindow(Foreground) then
    Exit;
  // Maximised windows with a custom title bar (VS Code, browsers) cover the
  // whole monitor when the taskbar auto-hides; they are not full-screen apps.
  if IsZoomed(Foreground) then
    Exit;
  Style := GetWindowLongPtr(Foreground, GWL_STYLE);
  if (Style and WS_CAPTION) = WS_CAPTION then
    Exit;
  if not GetWindowRect(Foreground, WindowRect) then
    Exit;
  Monitor := MonitorFromWindow(Foreground, MONITOR_DEFAULTTONULL);
  if Monitor = 0 then
    Exit;
  FillChar(MonitorInfo, SizeOf(MonitorInfo), 0);
  MonitorInfo.cbSize := SizeOf(MonitorInfo);
  if not GetMonitorInfo(Monitor, @MonitorInfo) then
    Exit;
  Result := (WindowRect.Left <= MonitorInfo.rcMonitor.Left) and
    (WindowRect.Top <= MonitorInfo.rcMonitor.Top) and
    (WindowRect.Right >= MonitorInfo.rcMonitor.Right) and
    (WindowRect.Bottom >= MonitorInfo.rcMonitor.Bottom);
end;

function GetExecutableVersion: string;
var
  FileName: string;
  Handle, Size, Len: DWORD;
  Buffer: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '';
  FileName := ParamStr(0);
  Size := GetFileVersionInfoSize(PChar(FileName), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buffer, Size);
  if not GetFileVersionInfo(PChar(FileName), 0, Size, @Buffer[0]) then
    Exit;
  if not VerQueryValue(@Buffer[0], '\', Pointer(Info), Len) or (Info = nil) then
    Exit;
  Result := Format('%d.%d.%d.%d', [HiWord(Info^.dwFileVersionMS),
    LoWord(Info^.dwFileVersionMS), HiWord(Info^.dwFileVersionLS),
    LoWord(Info^.dwFileVersionLS)]);
end;

function SendChord(ModifierVK, VK: Word): Boolean;
var
  Inputs: array[0..3] of TInput;
begin
  FillChar(Inputs, SizeOf(Inputs), 0);
  Inputs[0].Itype := INPUT_KEYBOARD;
  Inputs[0].ki.wVk := ModifierVK;
  Inputs[0].ki.dwExtraInfo := LS_INPUT_TAG;
  Inputs[1].Itype := INPUT_KEYBOARD;
  Inputs[1].ki.wVk := VK;
  Inputs[1].ki.dwExtraInfo := LS_INPUT_TAG;
  Inputs[2] := Inputs[1];
  Inputs[2].ki.dwFlags := KEYEVENTF_KEYUP;
  Inputs[3] := Inputs[0];
  Inputs[3].ki.dwFlags := KEYEVENTF_KEYUP;
  Result := SendInput(Length(Inputs), Inputs[0], SizeOf(TInput)) =
    UINT(Length(Inputs));
end;

function SendBackspaces(Count: Integer): Boolean;
const
  MAX_KEYS_PER_BATCH = 64;
var
  Inputs: array[0..MAX_KEYS_PER_BATCH * 2 - 1] of TInput;
  BatchKeys, I, InputCount, Remaining: Integer;
begin
  Result := True;
  Remaining := Count;
  while Remaining > 0 do
  begin
    BatchKeys := Remaining;
    if BatchKeys > MAX_KEYS_PER_BATCH then
      BatchKeys := MAX_KEYS_PER_BATCH;
    InputCount := BatchKeys * 2;
    FillChar(Inputs, SizeOf(Inputs), 0);
    for I := 0 to BatchKeys - 1 do
    begin
      Inputs[I * 2].Itype := INPUT_KEYBOARD;
      Inputs[I * 2].ki.wVk := VK_BACK;
      Inputs[I * 2].ki.dwExtraInfo := LS_INPUT_TAG;
      Inputs[I * 2 + 1] := Inputs[I * 2];
      Inputs[I * 2 + 1].ki.dwFlags := KEYEVENTF_KEYUP;
    end;
    if SendInput(InputCount, Inputs[0], SizeOf(TInput)) <> UINT(InputCount) then
      Exit(False);
    Dec(Remaining, BatchKeys);
  end;
end;

function TypeUnicodeText(const Value: string): Boolean;
const
  MAX_CHARS_PER_BATCH = 64;
var
  Inputs: array[0..MAX_CHARS_PER_BATCH * 2 - 1] of TInput;
  Offset, BatchChars, I, InputCount: Integer;
begin
  Result := True;
  Offset := 1;
  while Offset <= Length(Value) do
  begin
    BatchChars := Length(Value) - Offset + 1;
    if BatchChars > MAX_CHARS_PER_BATCH then
      BatchChars := MAX_CHARS_PER_BATCH;
    InputCount := BatchChars * 2;
    FillChar(Inputs, SizeOf(Inputs), 0);
    for I := 0 to BatchChars - 1 do
    begin
      Inputs[I * 2].Itype := INPUT_KEYBOARD;
      Inputs[I * 2].ki.wScan := Ord(Value[Offset + I]);
      Inputs[I * 2].ki.dwFlags := KEYEVENTF_UNICODE;
      Inputs[I * 2].ki.dwExtraInfo := LS_INPUT_TAG;
      Inputs[I * 2 + 1] := Inputs[I * 2];
      Inputs[I * 2 + 1].ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
    end;
    if SendInput(InputCount, Inputs[0], SizeOf(TInput)) <> UINT(InputCount) then
      Exit(False);
    Inc(Offset, BatchChars);
  end;
end;

function AreModifiersPhysicallyDown: Boolean;
begin
  Result := ((GetAsyncKeyState(VK_LSHIFT) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_RSHIFT) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_LCONTROL) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_RCONTROL) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_LMENU) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_RMENU) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_LWIN) and $8000) <> 0) or
    ((GetAsyncKeyState(VK_RWIN) and $8000) <> 0);
end;

end.
