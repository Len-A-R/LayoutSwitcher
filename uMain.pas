unit uMain;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  System.ImageList, Vcl.ImgList, PngImageList, Vcl.StdCtrls, Vcl.ComCtrls,
  uSettings, uGestureDetector, uOperationWorker;

const
  INSTANCE_WINDOW_PROP = 'LayoutSwitcher.Instance.v2';

type
  TFormMain = class(TForm)
    TrayIcon: TTrayIcon;
    PopupMenu: TPopupMenu;
    mniSettings: TMenuItem;
    mniSeparator1: TMenuItem;
    mniPause15: TMenuItem;
    mniPause60: TMenuItem;
    mniPauseIndefinite: TMenuItem;
    mniResume: TMenuItem;
    mniSeparator2: TMenuItem;
    mniDiagnostics: TMenuItem;
    mniSeparator: TMenuItem;
    mniExit: TMenuItem;
    TrayIcons: TPngImageList;
    TimerLayout: TTimer;
    TimerPause: TTimer;
    lblVersion: TLabel;
    lblAuthor: TLabel;
    chkAutorun: TCheckBox;
    chkDiagnostics: TCheckBox;
    grpHotkeys: TGroupBox;
    lblConvert: TLabel;
    cbConvert: TComboBox;
    lblUpper: TLabel;
    cbUpper: TComboBox;
    lblLower: TLabel;
    cbLower: TComboBox;
    lblInvert: TLabel;
    cbInvert: TComboBox;
    lblInterval: TLabel;
    edInterval: TEdit;
    udInterval: TUpDown;
    lblIntervalUnit: TLabel;
    grpBehavior: TGroupBox;
    chkPauseFullscreen: TCheckBox;
    chkNotifications: TCheckBox;
    lblExcluded: TLabel;
    edExcluded: TEdit;
    btnDefaultExcluded: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TimerLayoutTimer(Sender: TObject);
    procedure TimerPauseTimer(Sender: TObject);
    procedure TrayIconDblClick(Sender: TObject);
    procedure chkAutorunClick(Sender: TObject);
    procedure chkDiagnosticsClick(Sender: TObject);
    procedure cbGestureChange(Sender: TObject);
    procedure edIntervalChange(Sender: TObject);
    procedure edIntervalExit(Sender: TObject);
    procedure chkBehaviorClick(Sender: TObject);
    procedure edExcludedExit(Sender: TObject);
    procedure btnDefaultExcludedClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure mniSettingsClick(Sender: TObject);
    procedure mniPauseClick(Sender: TObject);
    procedure mniResumeClick(Sender: TObject);
    procedure mniDiagnosticsClick(Sender: TObject);
    procedure mniExitClick(Sender: TObject);
  private
    FSettings: TLSSettings;
    FDetector: TGestureDetector;
    FWorker: TOperationWorker;
    FVersion: string;

    FBuffer: string;
    FBufferOverflowed: Boolean;
    FLastWindow: HWND;
    FFocusIsPassword: Boolean;
    FLastLayout: HKL;
    FPreviousLayout: HKL;

    FRawInputRegistered: Boolean;
    FUpdatingControls: Boolean;

    FPaused: Boolean;
    FPauseUntil: TDateTime;
    FPausedIconBase: Integer;

    FOperationBusy: Boolean;
    FOperationStarted: DWORD;
    FOperationSequence: Cardinal;
    FNotificationTimes: TDictionary<string, DWORD>;

    function RegisterRawInput: Boolean;
    procedure UnregisterRawInput;
    procedure ResetInputState(const Reason: string; Reregister: Boolean);
    procedure HandleRawInput(RawInputHandle: THandle; EventTime: DWORD);
    procedure ProcessKeyboardEvent(EventTime: DWORD; VK, ScanCode: UINT;
      IsKeyUp: Boolean);
    procedure ProcessPointerActivity;
    procedure ProcessBufferKey(VK, ScanCode: UINT);
    procedure CheckWindowChanged;
    function TryTranslateKey(VK, ScanCode: UINT; out Ch: Char): Boolean;

    procedure AddChar(Ch: Char);
    procedure BufferBackspace;
    procedure ClearBuffer;
    procedure SetBufferText(const Value: string);

    procedure QueueAction(Action: TLSAction);
    procedure HandleOperationResult(Res: TOperationResult);
    procedure ShowNotification(const Key, Text: string);

    procedure PauseFor(Minutes: Integer);
    procedure Resume;
    procedure UpdatePauseState;
    procedure CreatePausedIcons;

    procedure LoadControlsFromSettings;
    procedure ApplySettings;
    procedure ApplyExcludedFromEdit;
    procedure SyncAutorunPath;
    procedure ShowSettingsWindow;

    procedure UpdateTrayIcon(Force: Boolean);
    procedure UpdateTrayHint;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure WndProc(var Message: TMessage); override;
  end;

var
  FormMain: TFormMain;

// Registered message used by a second launch to open the settings window of
// the running instance.
function ShowSettingsMessage: UINT;

implementation

{$R *.dfm}

uses
  System.DateUtils,
  PngImage, PngFunctions,
  uDiagnostics, uWinUtils;

const
  WM_LS_OPERATION_DONE = WM_APP + 10;
  MAX_WORD_LEN = 50;
  TO_UNICODE_NO_STATE_CHANGE = 4;
  OPERATION_WATCHDOG_MS = 30000;
  NOTIFICATION_THROTTLE_MS = 60000;
  MSGFLT_ALLOW = 1;
  // Keys tracked as held longer than this are checked against the physical
  // keyboard state before each key press.
  STALE_KEY_MIN_AGE_MS = 250;

  WM_WTSSESSION_CHANGE = $02B1;
  NOTIFY_FOR_THIS_SESSION = 0;
  WTS_CONSOLE_CONNECT = $1;
  WTS_REMOTE_CONNECT = $3;
  WTS_SESSION_LOCK = $7;
  WTS_SESSION_UNLOCK = $8;
  PBT_APMRESUMESUSPEND = $7;
  PBT_APMRESUMEAUTOMATIC = $12;

  HID_USAGE_PAGE_GENERIC = $01;
  HID_USAGE_GENERIC_MOUSE = $02;
  HID_USAGE_GENERIC_KEYBOARD = $06;
  RIDEV_REMOVE = $00000001;
  RIDEV_INPUTSINK = $00000100;
  RID_INPUT = $10000003;
  RIM_TYPEMOUSE = 0;
  RIM_TYPEKEYBOARD = 1;
  RI_KEY_BREAK = $0001;
  RI_KEY_E0 = $0002;
  RI_MOUSE_LEFT_BUTTON_DOWN = $0001;
  RI_MOUSE_RIGHT_BUTTON_DOWN = $0004;
  RI_MOUSE_MIDDLE_BUTTON_DOWN = $0010;
  RI_MOUSE_BUTTON_4_DOWN = $0040;
  RI_MOUSE_BUTTON_5_DOWN = $0100;
  RI_MOUSE_WHEEL = $0400;
  RI_MOUSE_HWHEEL = $0800;
  MOUSE_ACTIVITY_MASK = RI_MOUSE_LEFT_BUTTON_DOWN or
    RI_MOUSE_RIGHT_BUTTON_DOWN or RI_MOUSE_MIDDLE_BUTTON_DOWN or
    RI_MOUSE_BUTTON_4_DOWN or RI_MOUSE_BUTTON_5_DOWN or
    RI_MOUSE_WHEEL or RI_MOUSE_HWHEEL;

  ICON_EN = 0;
  ICON_RU = 1;
  LANG_EN = $0409;
  LANG_RU = $0419;

  ShortGestureNames: array[TLSGesture] of string = (
    '', 'Dbl Shift', 'Dbl LCtrl', 'Dbl RCtrl', 'LCtrl+RCtrl');
  ShortActionNames: array[TLSAction] of string = (
    '', 'Конвертация', 'ВЕРХНИЙ регистр', 'нижний регистр', 'Инверсия регистра');

type
  TLSRawInputDevice = record
    UsagePage: Word;
    Usage: Word;
    Flags: DWORD;
    Target: HWND;
  end;
  PLSRawInputDevice = ^TLSRawInputDevice;

  TLSRawInputHeader = record
    DataType: DWORD;
    Size: DWORD;
    Device: THandle;
    Param: NativeUInt;
  end;

  TLSRawKeyboard = record
    MakeCode: Word;
    Flags: Word;
    Reserved: Word;
    VKey: Word;
    MessageID: UINT;
    ExtraInformation: ULONG;
  end;

  TLSRawMouse = record
    Flags: Word;
    ButtonFlags: Word;
    ButtonData: Word;
    RawButtons: ULONG;
    LastX: LongInt;
    LastY: LongInt;
    ExtraInformation: ULONG;
  end;

  TLSRawInput = record
    Header: TLSRawInputHeader;
    case Integer of
      0: (Mouse: TLSRawMouse);
      1: (Keyboard: TLSRawKeyboard);
  end;
  PLSRawInput = ^TLSRawInput;

var
  GShowSettingsMessage: UINT;

function RegisterRawInputDevices(Devices: PLSRawInputDevice; DeviceCount,
  DeviceSize: UINT): BOOL; stdcall; external user32 name 'RegisterRawInputDevices';
function GetRawInputData(RawInput: THandle; Command: UINT; Data: Pointer;
  var DataSize: UINT; HeaderSize: UINT): UINT; stdcall;
  external user32 name 'GetRawInputData';
function LSWTSRegisterSessionNotification(Wnd: HWND; Flags: DWORD): BOOL;
  stdcall; external 'wtsapi32.dll' name 'WTSRegisterSessionNotification';
function LSWTSUnRegisterSessionNotification(Wnd: HWND): BOOL;
  stdcall; external 'wtsapi32.dll' name 'WTSUnRegisterSessionNotification';
function LSChangeWindowMessageFilterEx(Wnd: HWND; Msg: UINT; Action: DWORD;
  ChangeFilterStruct: Pointer): BOOL; stdcall;
  external user32 name 'ChangeWindowMessageFilterEx';

function ShowSettingsMessage: UINT;
begin
  Result := GShowSettingsMessage;
end;

{ Window lifetime }

procedure TFormMain.CreateWnd;
begin
  inherited;
  // Lets a second launch find this instance and allows the message through
  // UIPI when this instance runs elevated.
  SetProp(Handle, INSTANCE_WINDOW_PROP, 1);
  if GShowSettingsMessage <> 0 then
    LSChangeWindowMessageFilterEx(Handle, GShowSettingsMessage, MSGFLT_ALLOW, nil);
end;

procedure TFormMain.DestroyWnd;
begin
  RemoveProp(Handle, INSTANCE_WINDOW_PROP);
  inherited;
end;

procedure TFormMain.FormCreate(Sender: TObject);
var
  Gesture: TLSGesture;
  Combo: TComboBox;
  Combos: array[0..3] of TComboBox;
begin
  FSettings := LoadSettings;
  FDetector := TGestureDetector.Create;
  FDetector.Interval := FSettings.DoubleTapInterval;
  FNotificationTimes := TDictionary<string, DWORD>.Create;
  FVersion := GetExecutableVersion;
  lblVersion.Caption := 'Версия ' + FVersion;
  lblAuthor.Left := ClientWidth - lblAuthor.Width - btnClose.Width - 24;

  Combos[0] := cbConvert;
  Combos[1] := cbUpper;
  Combos[2] := cbLower;
  Combos[3] := cbInvert;
  for Combo in Combos do
  begin
    Combo.Items.Clear;
    for Gesture := Low(TLSGesture) to High(TLSGesture) do
      Combo.Items.Add(GestureNames[Gesture]);
  end;

  // Assigning Checked raises OnClick; the guard keeps FormCreate from
  // rewriting the Run key or the diagnostics preference.
  FUpdatingControls := True;
  try
    chkAutorun.Checked := IsInStartup(STARTUP_VALUE_NAME);
    chkDiagnostics.Checked := DiagnosticsEnabled;
  finally
    FUpdatingControls := False;
  end;
  LoadControlsFromSettings;
  SyncAutorunPath;
  mniDiagnostics.Enabled := DirectoryExists(DiagnosticsDirectory);

  ShowInTaskBar := False;
  SetWindowLong(Application.Handle, GWL_EXSTYLE,
    GetWindowLong(Application.Handle, GWL_EXSTYLE) and not WS_EX_APPWINDOW);

  CreatePausedIcons;

  FWorker := TOperationWorker.Create(Handle, WM_LS_OPERATION_DONE);
  if not FWorker.WaitUntilReady(5000) then
    DiagnosticsLog('worker.start_timeout');

  if not RegisterRawInput then
  begin
    DiagnosticsLogFmt('raw_input.register_failed error=%d', [GetLastError]);
    MessageBox(0, 'Не удалось зарегистрировать Raw Input.', 'LayoutSwitcher',
      MB_OK or MB_ICONERROR);
  end
  else
    DiagnosticsLog('raw_input.registered keyboard=true mouse=true');

  // Lock/unlock notifications: key releases on the secure desktop are lost.
  if not LSWTSRegisterSessionNotification(Handle, NOTIFY_FOR_THIS_SESSION) then
    DiagnosticsLogFmt('session.notification_register_failed error=%d', [GetLastError]);

  UpdatePauseState;
  WindowState := wsMinimized;
  Hide;
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
var
  Msg: TMsg;
begin
  DiagnosticsLog('form.destroy begin');
  LSWTSUnRegisterSessionNotification(Handle);
  UnregisterRawInput;
  if Assigned(FWorker) then
  begin
    FWorker.Shutdown;
    FreeAndNil(FWorker);
  end;
  // Results posted after the last message loop iteration.
  while PeekMessage(Msg, Handle, WM_LS_OPERATION_DONE, WM_LS_OPERATION_DONE,
          PM_REMOVE) do
    TOperationResult(Msg.lParam).Free;
  FreeAndNil(FDetector);
  FreeAndNil(FNotificationTimes);
  DiagnosticsLog('form.destroy end');
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  ApplyExcludedFromEdit;
  CanClose := False;
  Hide;
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TFormMain.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_INPUT then
  begin
    try
      try
        HandleRawInput(THandle(Message.LParam), DWORD(GetMessageTime));
      except
        on E: Exception do
        begin
          ClearBuffer;
          FDetector.ResetAll;
          DiagnosticsCaptureException('raw_input.message', E, ExceptAddr);
        end;
      end;
    finally
      inherited WndProc(Message);
    end;
    Exit;
  end;

  case Message.Msg of
    WM_WTSSESSION_CHANGE:
      case Message.WParam of
        WTS_SESSION_LOCK:
          ResetInputState('session_lock', False);
        WTS_SESSION_UNLOCK, WTS_CONSOLE_CONNECT, WTS_REMOTE_CONNECT:
          ResetInputState('session_unlock', True);
      end;
    WM_POWERBROADCAST:
      if (Message.WParam = PBT_APMRESUMEAUTOMATIC) or
         (Message.WParam = PBT_APMRESUMESUSPEND) then
        ResetInputState('power_resume', True);
  end;

  if Message.Msg = WM_LS_OPERATION_DONE then
  begin
    HandleOperationResult(TOperationResult(Message.LParam));
    Exit;
  end;

  if (GShowSettingsMessage <> 0) and (Message.Msg = GShowSettingsMessage) then
  begin
    ShowSettingsWindow;
    Exit;
  end;

  inherited WndProc(Message);
end;

{ Raw Input }

function TFormMain.RegisterRawInput: Boolean;
var
  Devices: array[0..1] of TLSRawInputDevice;
begin
  FillChar(Devices, SizeOf(Devices), 0);
  Devices[0].UsagePage := HID_USAGE_PAGE_GENERIC;
  Devices[0].Usage := HID_USAGE_GENERIC_KEYBOARD;
  Devices[0].Flags := RIDEV_INPUTSINK;
  Devices[0].Target := Handle;
  Devices[1].UsagePage := HID_USAGE_PAGE_GENERIC;
  Devices[1].Usage := HID_USAGE_GENERIC_MOUSE;
  Devices[1].Flags := RIDEV_INPUTSINK;
  Devices[1].Target := Handle;
  Result := RegisterRawInputDevices(@Devices[0], Length(Devices),
    SizeOf(TLSRawInputDevice));
  FRawInputRegistered := Result;
end;

procedure TFormMain.UnregisterRawInput;
var
  Devices: array[0..1] of TLSRawInputDevice;
begin
  if not FRawInputRegistered then
    Exit;
  FillChar(Devices, SizeOf(Devices), 0);
  Devices[0].UsagePage := HID_USAGE_PAGE_GENERIC;
  Devices[0].Usage := HID_USAGE_GENERIC_KEYBOARD;
  Devices[0].Flags := RIDEV_REMOVE;
  Devices[1].UsagePage := HID_USAGE_PAGE_GENERIC;
  Devices[1].Usage := HID_USAGE_GENERIC_MOUSE;
  Devices[1].Flags := RIDEV_REMOVE;
  if not RegisterRawInputDevices(@Devices[0], Length(Devices),
       SizeOf(TLSRawInputDevice)) then
    DiagnosticsLogFmt('raw_input.unregister_failed error=%d', [GetLastError]);
  FRawInputRegistered := False;
end;

procedure TFormMain.HandleRawInput(RawInputHandle: THandle; EventTime: DWORD);
var
  // Keyboard and mouse RAWINPUT fit easily; UInt64 keeps 8-byte alignment.
  Buffer: array[0..31] of UInt64;
  DataSize, BytesRead: UINT;
  Raw: PLSRawInput;
  VK, ScanCode: UINT;
begin
  // Every mouse move arrives here, so this path must not allocate.
  DataSize := SizeOf(Buffer);
  BytesRead := GetRawInputData(RawInputHandle, RID_INPUT, @Buffer[0], DataSize,
    SizeOf(TLSRawInputHeader));
  if (BytesRead = UINT(-1)) or (BytesRead < SizeOf(TLSRawInputHeader)) then
    Exit;

  Raw := PLSRawInput(@Buffer[0]);
  case Raw^.Header.DataType of
    RIM_TYPEMOUSE:
      if (Raw^.Mouse.ButtonFlags and MOUSE_ACTIVITY_MASK) <> 0 then
        ProcessPointerActivity;
    RIM_TYPEKEYBOARD:
      begin
        if Raw^.Keyboard.ExtraInformation = LS_INPUT_TAG then
          Exit;
        VK := Raw^.Keyboard.VKey;
        if (VK = 0) or (VK >= $FF) then
          Exit;
        ScanCode := Raw^.Keyboard.MakeCode;
        if VK = VK_SHIFT then
          VK := MapVirtualKey(ScanCode, MAPVK_VSC_TO_VK_EX)
        else if VK = VK_CONTROL then
        begin
          if (Raw^.Keyboard.Flags and RI_KEY_E0) <> 0 then
            VK := VK_RCONTROL
          else
            VK := VK_LCONTROL;
        end
        else if VK = VK_MENU then
        begin
          if (Raw^.Keyboard.Flags and RI_KEY_E0) <> 0 then
            VK := VK_RMENU
          else
            VK := VK_LMENU;
        end;
        ProcessKeyboardEvent(EventTime, VK, ScanCode,
          (Raw^.Keyboard.Flags and RI_KEY_BREAK) <> 0);
      end;
  end;
end;

procedure TFormMain.ResetInputState(const Reason: string; Reregister: Boolean);
begin
  DiagnosticsLogFmt('input.reset reason=%s held_keys=%d busy=%s',
    [Reason, FDetector.HeldKeyCount, BoolToStr(FOperationBusy, True)]);
  FDetector.ResetAll;
  ClearBuffer;
  FLastWindow := 0;
  // A request interrupted by sleep must not block the next gesture; a late
  // result is discarded by its sequence number.
  FOperationBusy := False;
  if Reregister then
  begin
    // Registration normally survives sleep; re-registering is harmless and
    // covers keyboards re-enumerated on resume.
    if not RegisterRawInput then
      DiagnosticsLogFmt('raw_input.reregister_failed error=%d', [GetLastError]);
  end;
end;

procedure TFormMain.ProcessKeyboardEvent(EventTime: DWORD; VK, ScanCode: UINT;
  IsKeyUp: Boolean);
var
  Gesture: TLSGesture;
  Released: Integer;
begin
  if VK > 255 then
    Exit;
  if not FPaused then
    CheckWindowChanged;

  // Releases lost on the secure desktop would otherwise block every tap.
  if not IsKeyUp then
  begin
    Released := FDetector.ReleaseStaleKeys(
      function(Key: Cardinal): Boolean
      begin
        Result := GetAsyncKeyState(Integer(Key)) < 0;
      end, EventTime, STALE_KEY_MIN_AGE_MS);
    if Released > 0 then
      DiagnosticsLogFmt('input.stale_keys_released count=%d', [Released]);
  end;

  // The detector always tracks key states, even while paused, so that a
  // modifier held across a pause/resume does not leave stale state.
  Gesture := FDetector.KeyEvent(VK, IsKeyUp, EventTime);
  if FPaused then
    Exit;
  if Gesture <> lgNone then
    QueueAction(FSettings.ActionForGesture(Gesture));

  if IsKeyUp or IsModifierKey(VK) then
    Exit;
  ProcessBufferKey(VK, ScanCode);
end;

procedure TFormMain.ProcessPointerActivity;
begin
  ClearBuffer;
  FDetector.ResetTaps;
end;

procedure TFormMain.CheckWindowChanged;
var
  CurrentWindow: HWND;
begin
  CurrentWindow := GetFocusedWindow;
  if CurrentWindow = FLastWindow then
    Exit;
  FLastWindow := CurrentWindow;
  ClearBuffer;
  FDetector.ResetTaps;
  FFocusIsPassword := IsNativePasswordEdit(CurrentWindow);
end;

procedure TFormMain.ProcessBufferKey(VK, ScanCode: UINT);
var
  Ch: Char;
begin
  // Never keep keystrokes typed into a password field.
  if FFocusIsPassword then
  begin
    ClearBuffer;
    Exit;
  end;

  case VK of
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT,
    VK_ESCAPE, VK_DELETE, VK_INSERT, VK_RETURN, VK_TAB, VK_SPACE:
      begin
        ClearBuffer;
        Exit;
      end;
    VK_BACK:
      begin
        if FDetector.CtrlDown then
          ClearBuffer
        else
          BufferBackspace;
        Exit;
      end;
    VK_CAPITAL, VK_NUMLOCK, VK_SCROLL:
      Exit;
  end;

  if FDetector.CtrlDown or FDetector.AltDown or FDetector.WinDown then
  begin
    ClearBuffer;
    Exit;
  end;

  if TryTranslateKey(VK, ScanCode, Ch) then
    AddChar(Ch)
  else
    ClearBuffer;
end;

function TFormMain.TryTranslateKey(VK, ScanCode: UINT; out Ch: Char): Boolean;
var
  KeyState: TKeyboardState;
  Buffer: array[0..3] of WideChar;
  FocusedWindow: HWND;
  Layout: HKL;
  CharCount: Integer;
  TranslationVK, MappedVK: UINT;
begin
  Result := False;
  Ch := #0;
  FocusedWindow := GetFocusedWindow;
  if FocusedWindow = 0 then
    Exit;
  Layout := GetKeyboardLayout(GetWindowThreadProcessId(FocusedWindow, nil));
  if Layout = 0 then
    Exit;

  FillChar(KeyState, SizeOf(KeyState), 0);
  if FDetector.ShiftDown then
    KeyState[VK_SHIFT] := $80;
  if (GetKeyState(VK_CAPITAL) and 1) <> 0 then
    KeyState[VK_CAPITAL] := 1;
  if (GetKeyState(VK_NUMLOCK) and 1) <> 0 then
    KeyState[VK_NUMLOCK] := 1;

  // Raw Input reports the VK of the system layout; the scan code identifies
  // the physical key in the layout of the focused window.
  TranslationVK := VK;
  if ScanCode <> 0 then
  begin
    MappedVK := MapVirtualKeyEx(ScanCode, MAPVK_VSC_TO_VK_EX, Layout);
    if MappedVK <> 0 then
      TranslationVK := MappedVK;
  end
  else
    ScanCode := MapVirtualKeyEx(TranslationVK, MAPVK_VK_TO_VSC, Layout);
  if TranslationVK <= High(KeyState) then
    KeyState[TranslationVK] := $80;
  FillChar(Buffer, SizeOf(Buffer), 0);
  CharCount := ToUnicodeEx(TranslationVK, ScanCode, KeyState, Buffer,
    Length(Buffer), TO_UNICODE_NO_STATE_CHANGE, Layout);
  if (CharCount = 1) and (Ord(Buffer[0]) >= 32) then
  begin
    Ch := Buffer[0];
    Result := True;
  end;
end;

{ Word buffer }

procedure TFormMain.AddChar(Ch: Char);
begin
  if FBufferOverflowed then
    Exit;
  if Length(FBuffer) >= MAX_WORD_LEN then
  begin
    FBuffer := '';
    FBufferOverflowed := True;
    Exit;
  end;
  FBuffer := FBuffer + Ch;
end;

procedure TFormMain.BufferBackspace;
begin
  if not FBufferOverflowed and (FBuffer <> '') then
    SetLength(FBuffer, Length(FBuffer) - 1);
end;

procedure TFormMain.ClearBuffer;
begin
  FBuffer := '';
  FBufferOverflowed := False;
end;

procedure TFormMain.SetBufferText(const Value: string);
var
  Ch: Char;
begin
  ClearBuffer;
  if (Value = '') or (Length(Value) > MAX_WORD_LEN) then
    Exit;
  for Ch in Value do
    if Ord(Ch) <= 32 then
      Exit;
  FBuffer := Value;
end;

{ Operations }

procedure TFormMain.QueueAction(Action: TLSAction);
var
  Foreground, Focus: HWND;
  ProcessName: string;
  Request: TOperationRequest;
begin
  if (Action = laNone) or FPaused then
    Exit;

  if FOperationBusy then
  begin
    if GetTickCount - FOperationStarted < OPERATION_WATCHDOG_MS then
    begin
      DiagnosticsLogFmt('operation.ignored action=%s reason=busy', [ActionKeys[Action]]);
      Exit;
    end;
    DiagnosticsLogFmt('operation.watchdog_reset seq=%d', [FOperationSequence]);
    FOperationBusy := False;
  end;

  Foreground := GetForegroundWindow;
  Focus := GetFocusedWindow;
  if (Foreground = 0) or (Focus = 0) then
    Exit;

  // Screenshot tools: their capture overlay uses Shift/Ctrl itself and a
  // synthetic Ctrl+C makes them copy the image.
  ProcessName := GetWindowProcessFileName(Foreground);
  if FSettings.IsProcessExcluded(ProcessName) then
  begin
    ClearBuffer;
    DiagnosticsLogFmt('operation.skipped action=%s reason=excluded_process process="%s"',
      [ActionKeys[Action], ProcessName]);
    Exit;
  end;
  if FSettings.PauseInFullscreen and IsFullscreenAppActive then
  begin
    DiagnosticsLogFmt('operation.skipped action=%s reason=fullscreen process="%s"',
      [ActionKeys[Action], ProcessName]);
    Exit;
  end;
  if IsWindowProcessElevatedAboveUs(Focus) then
  begin
    DiagnosticsLogFmt('operation.skipped action=%s reason=elevated_target process="%s"',
      [ActionKeys[Action], ProcessName]);
    ShowNotification('elevated', Format(
      '%s запущен от имени администратора, поэтому Windows не позволяет ' +
      'изменить в нём текст. Запустите LayoutSwitcher от имени администратора.',
      [ProcessName]));
    Exit;
  end;

  Request := TOperationRequest.Create;
  Inc(FOperationSequence);
  Request.Sequence := FOperationSequence;
  Request.Action := Action;
  if not FBufferOverflowed and not FFocusIsPassword then
    Request.BufferText := FBuffer;
  Request.FocusWnd := Focus;
  Request.WindowLayout := GetKeyboardLayout(GetWindowThreadProcessId(Focus, nil));
  Request.PreviousLayout := FPreviousLayout;
  Request.ExcludedProcesses := FSettings.ExcludedProcesses;

  FOperationBusy := True;
  FOperationStarted := GetTickCount;
  if not FWorker.Post(Request) then
  begin
    FOperationBusy := False;
    DiagnosticsLogFmt('operation.queue_failed error=%d', [GetLastError]);
  end;
end;

procedure TFormMain.HandleOperationResult(Res: TOperationResult);
begin
  try
    if Res.Sequence <> FOperationSequence then
    begin
      DiagnosticsLogFmt('operation.result_stale seq=%d current=%d',
        [Res.Sequence, FOperationSequence]);
      Exit;
    end;
    FOperationBusy := False;

    if Res.FocusIsPassword and (GetFocusedWindow = FLastWindow) then
      FFocusIsPassword := True;
    case Res.BufferAction of
      baClear: ClearBuffer;
      baSet: SetBufferText(Res.NewBufferText);
    end;
    if Res.Success and (Res.SourceLayout <> 0) then
      FPreviousLayout := Res.SourceLayout;
    if Res.Notification <> '' then
      ShowNotification(Res.NotificationKey, Res.Notification);
  finally
    Res.Free;
  end;
end;

procedure TFormMain.ShowNotification(const Key, Text: string);
var
  LastShown: DWORD;
begin
  DiagnosticsLogFmt('notification key=%s shown=%s', [Key,
    BoolToStr(FSettings.ShowNotifications, True)]);
  if not FSettings.ShowNotifications then
    Exit;
  if FNotificationTimes.TryGetValue(Key, LastShown) and
     (GetTickCount - LastShown < NOTIFICATION_THROTTLE_MS) then
    Exit;
  FNotificationTimes.AddOrSetValue(Key, GetTickCount);
  TrayIcon.BalloonTitle := 'LayoutSwitcher';
  TrayIcon.BalloonHint := Text;
  TrayIcon.BalloonFlags := bfInfo;
  TrayIcon.ShowBalloonHint;
end;

{ Pause }

procedure TFormMain.PauseFor(Minutes: Integer);
begin
  FPaused := True;
  ClearBuffer;
  FDetector.ResetTaps;
  TimerPause.Enabled := False;
  if Minutes > 0 then
  begin
    FPauseUntil := IncMinute(Now, Minutes);
    TimerPause.Interval := 15000;
    TimerPause.Enabled := True;
  end
  else
    FPauseUntil := 0;
  DiagnosticsLogFmt('pause.start minutes=%d', [Minutes]);
  UpdatePauseState;
end;

procedure TFormMain.Resume;
begin
  if not FPaused then
    Exit;
  FPaused := False;
  TimerPause.Enabled := False;
  FPauseUntil := 0;
  FLastWindow := 0;
  DiagnosticsLog('pause.end');
  UpdatePauseState;
end;

procedure TFormMain.TimerPauseTimer(Sender: TObject);
begin
  // Polling keeps the pause correct across sleep/hibernation.
  if FPaused and (FPauseUntil <> 0) and (Now >= FPauseUntil) then
    Resume;
end;

procedure TFormMain.UpdatePauseState;
begin
  mniResume.Visible := FPaused;
  mniPause15.Enabled := not FPaused;
  mniPause60.Enabled := not FPaused;
  mniPauseIndefinite.Enabled := not FPaused;
  UpdateTrayHint;
  UpdateTrayIcon(True);
end;

procedure TFormMain.CreatePausedIcons;
var
  I: Integer;
  Png: TPngImage;
begin
  // Grey, half-transparent copies of the EN/RU icons for the paused state.
  FPausedIconBase := -1;
  try
    FPausedIconBase := TrayIcons.Count;
    for I := ICON_EN to ICON_RU do
    begin
      Png := TPngImage.Create;
      try
        Png.Assign(TrayIcons.PngImages[I].PngImage);
        MakeImageGrayscale(Png);
        MakeImageBlended(Png, 160);
        TrayIcons.AddPng(Png);
      finally
        Png.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      FPausedIconBase := -1;
      DiagnosticsLogException('tray.paused_icons', E);
    end;
  end;
end;

procedure TFormMain.UpdateTrayIcon(Force: Boolean);
var
  Target: HWND;
  Layout: HKL;
  LangID: Word;
  Index: Integer;
  Icon: TIcon;
begin
  Target := GetFocusedWindow;
  Layout := 0;
  if Target <> 0 then
    Layout := GetKeyboardLayout(GetWindowThreadProcessId(Target, nil));
  if (Layout <> 0) and (Layout <> FLastLayout) then
  begin
    if FLastLayout <> 0 then
      FPreviousLayout := FLastLayout;
    FLastLayout := Layout;
    Force := True;
  end;
  if not Force then
    Exit;

  LangID := LoWord(NativeUInt(FLastLayout));
  case LangID of
    LANG_EN: Index := ICON_EN;
    LANG_RU: Index := ICON_RU;
  else
    Index := -1;
  end;
  if FPaused and (FPausedIconBase >= 0) then
  begin
    if Index < 0 then
      Index := ICON_EN;
    Index := FPausedIconBase + Index;
  end;

  if Index < 0 then
  begin
    TrayIcon.Icon := Application.Icon;
    Exit;
  end;
  Icon := TIcon.Create;
  try
    TrayIcons.GetIcon(Index, Icon);
    TrayIcon.Icon := Icon;
  finally
    Icon.Free;
  end;
end;

procedure TFormMain.UpdateTrayHint;
const
  MAX_TIP = 127;
var
  Hint: string;
  Action: TLSAction;
  Gesture: TLSGesture;
begin
  Hint := 'LayoutSwitcher';
  if FPaused then
  begin
    if FPauseUntil <> 0 then
      Hint := Hint + ' — пауза до ' + FormatDateTime('hh:nn', FPauseUntil)
    else
      Hint := Hint + ' — пауза';
  end
  else
    for Action := laConvert to laInvertCase do
    begin
      Gesture := FSettings.GestureForAction(Action);
      if Gesture <> lgNone then
        Hint := Hint + sLineBreak + ShortGestureNames[Gesture] + ' = ' +
          ShortActionNames[Action];
    end;
  if Length(Hint) > MAX_TIP then
    SetLength(Hint, MAX_TIP);
  TrayIcon.Hint := Hint;
end;

procedure TFormMain.TimerLayoutTimer(Sender: TObject);
begin
  UpdateTrayIcon(False);
end;

{ Settings UI }

procedure TFormMain.LoadControlsFromSettings;
begin
  FUpdatingControls := True;
  try
    cbConvert.ItemIndex := Ord(FSettings.GestureForAction(laConvert));
    cbUpper.ItemIndex := Ord(FSettings.GestureForAction(laUpperCase));
    cbLower.ItemIndex := Ord(FSettings.GestureForAction(laLowerCase));
    cbInvert.ItemIndex := Ord(FSettings.GestureForAction(laInvertCase));
    udInterval.Position := Integer(FSettings.DoubleTapInterval);
    edInterval.Text := IntToStr(FSettings.DoubleTapInterval);
    chkPauseFullscreen.Checked := FSettings.PauseInFullscreen;
    chkNotifications.Checked := FSettings.ShowNotifications;
    edExcluded.Text := ProcessListToText(FSettings.ExcludedProcesses);
  finally
    FUpdatingControls := False;
  end;
end;

procedure TFormMain.ApplySettings;
begin
  FDetector.Interval := FSettings.DoubleTapInterval;
  if not SaveSettings(FSettings) then
    DiagnosticsLog('settings.save_failed');
  UpdateTrayHint;
  DiagnosticsLogFmt('settings.applied convert=%d upper=%d lower=%d invert=%d interval=%d fullscreen=%s notifications=%s excluded="%s"',
    [Ord(FSettings.ActionGestures[laConvert]), Ord(FSettings.ActionGestures[laUpperCase]),
     Ord(FSettings.ActionGestures[laLowerCase]), Ord(FSettings.ActionGestures[laInvertCase]),
     FSettings.DoubleTapInterval, BoolToStr(FSettings.PauseInFullscreen, True),
     BoolToStr(FSettings.ShowNotifications, True),
     ProcessListToText(FSettings.ExcludedProcesses)]);
end;

procedure TFormMain.cbGestureChange(Sender: TObject);
var
  Combo: TComboBox;
begin
  if FUpdatingControls then
    Exit;
  Combo := Sender as TComboBox;
  if Combo.ItemIndex < 0 then
    Exit;
  // A gesture can drive only one action; the previous owner is disabled.
  FSettings.AssignGesture(TLSAction(Combo.Tag), TLSGesture(Combo.ItemIndex));
  LoadControlsFromSettings;
  ApplySettings;
end;

procedure TFormMain.edIntervalChange(Sender: TObject);
var
  Value: Integer;
begin
  if FUpdatingControls then
    Exit;
  if TryStrToInt(edInterval.Text, Value) and
     (Value >= MIN_DOUBLE_TAP_INTERVAL) and (Value <= MAX_DOUBLE_TAP_INTERVAL) and
     (Cardinal(Value) <> FSettings.DoubleTapInterval) then
  begin
    FSettings.DoubleTapInterval := Cardinal(Value);
    ApplySettings;
  end;
end;

procedure TFormMain.edIntervalExit(Sender: TObject);
begin
  FSettings.DoubleTapInterval :=
    ClampDoubleTapInterval(StrToIntDef(edInterval.Text, DEFAULT_DOUBLE_TAP_INTERVAL));
  LoadControlsFromSettings;
  ApplySettings;
end;

procedure TFormMain.chkBehaviorClick(Sender: TObject);
begin
  if FUpdatingControls then
    Exit;
  FSettings.PauseInFullscreen := chkPauseFullscreen.Checked;
  FSettings.ShowNotifications := chkNotifications.Checked;
  ApplySettings;
end;

procedure TFormMain.ApplyExcludedFromEdit;
var
  List: TArray<string>;
begin
  List := ParseProcessList(edExcluded.Text);
  if ProcessListToText(List) <> ProcessListToText(FSettings.ExcludedProcesses) then
  begin
    FSettings.ExcludedProcesses := List;
    ApplySettings;
  end;
  LoadControlsFromSettings;
end;

procedure TFormMain.edExcludedExit(Sender: TObject);
begin
  ApplyExcludedFromEdit;
end;

procedure TFormMain.btnDefaultExcludedClick(Sender: TObject);
begin
  FSettings.ExcludedProcesses := TLSSettings.Defaults.ExcludedProcesses;
  LoadControlsFromSettings;
  ApplySettings;
end;

procedure TFormMain.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TFormMain.chkAutorunClick(Sender: TObject);
begin
  if FUpdatingControls then
    Exit;
  if chkAutorun.Checked then
    AddToStartup(STARTUP_VALUE_NAME, Application.ExeName)
  else
    RemoveFromStartup(STARTUP_VALUE_NAME);
  DiagnosticsLogFmt('ui.autorun_changed enabled=%s path="%s"',
    [BoolToStr(chkAutorun.Checked, True), Application.ExeName]);
end;

procedure TFormMain.SyncAutorunPath;
var
  Registered: string;
begin
  if not chkAutorun.Checked then
    Exit;
  Registered := StartupCommandToPath(GetStartupCommand(STARTUP_VALUE_NAME));
  if SameText(ExpandFileName(Registered), Application.ExeName) then
    Exit;
  {$IFDEF DEBUG}
  // Debug builds started from the IDE must not hijack the user's autorun.
  DiagnosticsLogFmt('autorun.path_mismatch registered="%s" current="%s" updated=false',
    [Registered, Application.ExeName]);
  {$ELSE}
  AddToStartup(STARTUP_VALUE_NAME, Application.ExeName);
  DiagnosticsLogFmt('autorun.path_mismatch registered="%s" current="%s" updated=true',
    [Registered, Application.ExeName]);
  {$ENDIF}
end;

procedure TFormMain.chkDiagnosticsClick(Sender: TObject);
var
  Enabled: Boolean;
begin
  if FUpdatingControls then
    Exit;
  Enabled := chkDiagnostics.Checked;
  if not SetDiagnosticsEnabled(Enabled) then
  begin
    FUpdatingControls := True;
    try
      chkDiagnostics.Checked := DiagnosticsEnabled;
    finally
      FUpdatingControls := False;
    end;
    MessageBox(Handle, 'Не удалось сохранить настройку диагностики в реестре.',
      'LayoutSwitcher', MB_OK or MB_ICONERROR);
    Exit;
  end;
  if Enabled then
  begin
    InitializeDiagnostics;
    DiagnosticsLog('ui.diagnostics_changed enabled=true');
  end
  else
  begin
    DiagnosticsLog('ui.diagnostics_changed enabled=false');
    ShutdownDiagnostics;
  end;
  mniDiagnostics.Enabled := DirectoryExists(DiagnosticsDirectory);
end;

procedure TFormMain.ShowSettingsWindow;
begin
  DiagnosticsLog('ui.settings_open');
  LoadControlsFromSettings;
  Show;
  WindowState := wsNormal;
  ShowWindow(Application.Handle, SW_SHOW);
  Application.BringToFront;
  SetForegroundWindow(Handle);
end;

procedure TFormMain.TrayIconDblClick(Sender: TObject);
begin
  ShowSettingsWindow;
end;

procedure TFormMain.mniSettingsClick(Sender: TObject);
begin
  ShowSettingsWindow;
end;

procedure TFormMain.mniPauseClick(Sender: TObject);
begin
  PauseFor((Sender as TMenuItem).Tag);
end;

procedure TFormMain.mniResumeClick(Sender: TObject);
begin
  Resume;
end;

procedure TFormMain.mniDiagnosticsClick(Sender: TObject);
begin
  DiagnosticsLog('ui.open_diagnostics');
  OpenDiagnosticsDirectory;
end;

procedure TFormMain.mniExitClick(Sender: TObject);
begin
  DiagnosticsLog('ui.exit_requested');
  Application.Terminate;
end;

initialization
  GShowSettingsMessage := RegisterWindowMessage('LayoutSwitcher.ShowSettings.v2');

end.
