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
  uSettings, uGestureDetector, uOperationWorker, uConversionChain,
  uLayoutIndicator, uUpdateCheck, uUpdateProgress, uLayoutConverter, uTextTools;

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
    mniDownloadUpdate: TMenuItem;
    mniCheckUpdates: TMenuItem;
    mniReport: TMenuItem;
    mniDiagnostics: TMenuItem;
    mniSeparator: TMenuItem;
    mniExit: TMenuItem;
    TrayIcons: TPngImageList;
    TimerLayout: TTimer;
    TimerPause: TTimer;
    TimerUpdate: TTimer;
    lblVersion: TLabel;
    lblAuthor: TLabel;
    chkAutorun: TCheckBox;
    chkDiagnostics: TCheckBox;
    chkAutorunElevated: TCheckBox;
    pcMain: TPageControl;
    tsGeneral: TTabSheet;
    tsHotkeys: TTabSheet;
    tsCorrections: TTabSheet;
    tsExclusions: TTabSheet;
    lblConvert: TLabel;
    cbConvert: TComboBox;
    lblUpper: TLabel;
    cbUpper: TComboBox;
    lblLower: TLabel;
    cbLower: TComboBox;
    lblInvert: TLabel;
    cbInvert: TComboBox;
    lblTranslit: TLabel;
    cbTranslit: TComboBox;
    lblUndo: TLabel;
    cbUndo: TComboBox;
    lblInterval: TLabel;
    edInterval: TEdit;
    udInterval: TUpDown;
    lblIntervalUnit: TLabel;
    chkPauseFullscreen: TCheckBox;
    chkNotifications: TCheckBox;
    chkDisableStickyKeys: TCheckBox;
    chkLayoutIndicator: TCheckBox;
    chkCheckUpdates: TCheckBox;
    lblLanguage: TLabel;
    cbLanguage: TComboBox;
    lblExcluded: TLabel;
    edExcluded: TMemo;
    lblStorage: TLabel;
    btnExport: TButton;
    btnImport: TButton;
    lblTranslate: TLabel;
    cbTranslate: TComboBox;
    lblWebSearch: TLabel;
    cbWebSearch: TComboBox;
    lblTranslator: TLabel;
    cbTranslator: TComboBox;
    lblSearchEngine: TLabel;
    cbSearchEngine: TComboBox;
    chkFixCapsLock: TCheckBox;
    chkFixTwoCapitals: TCheckBox;
    lblTwoCapsExceptions: TLabel;
    edTwoCapsExceptions: TEdit;
    chkSnippets: TCheckBox;
    lblSnippetsHint: TLabel;
    memSnippets: TMemo;
    lblCorrectionsNote: TLabel;
    mniClipboard: TMenuItem;
    mniClipConvert: TMenuItem;
    mniClipUpper: TMenuItem;
    mniClipLower: TMenuItem;
    mniClipTranslit: TMenuItem;
    mniSeparator3: TMenuItem;
    btnDefaultExcluded: TButton;
    btnReport: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TimerLayoutTimer(Sender: TObject);
    procedure TimerPauseTimer(Sender: TObject);
    procedure TrayIconDblClick(Sender: TObject);
    procedure TrayIconBalloonClick(Sender: TObject);
    procedure TimerUpdateTimer(Sender: TObject);
    procedure cbLanguageChange(Sender: TObject);
    procedure mniCheckUpdatesClick(Sender: TObject);
    procedure mniDownloadUpdateClick(Sender: TObject);
    procedure mniReportClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
    procedure cbServiceChange(Sender: TObject);
    procedure edCorrectionsExit(Sender: TObject);
    procedure mniClipboardClick(Sender: TObject);
    procedure chkAutorunClick(Sender: TObject);
    procedure chkAutorunElevatedClick(Sender: TObject);
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
    FChain: TConversionChain;
    FPendingPlan: TBufferPlan;
    // Sticky Keys hotkey bits this instance turned off and must restore.
    FStickyHotkeyRemoved: DWORD;
    // Logon task with administrator rights (uTaskAutorun).
    FTaskInstalled: Boolean;
    FTaskPath: string;
    FIndicator: TLayoutIndicator;
    FIndicatorWindow: HWND;
    FUpdateThread: TUpdateCheckThread;
    FUpdateVersion: string;
    FUpdateUrl: string;
    FBalloonUrl: string;      // Opened when the current balloon is clicked.
    FBalloonInstall: Boolean; // A balloon click installs the update.
    FUpdateInstallable: Boolean;
    FInstallerUrl: string;
    FInstallerName: string;
    FInstallerSha256: string;
    FDownloadThread: TUpdateDownloadThread;
    FProgress: TUpdateProgressWindow;
    FCatalog: TKeyboardLayoutCatalog;
    FSnippets: TArray<TSnippet>;
    // Caps Lock state tracked from Raw Input: GetKeyState in this thread does
    // not see key messages of other applications.
    FCapsOn: Boolean;
    FCapsShiftLock: Boolean;
    FPendingAutomatic: Boolean;
    FSettleFocusNext: Boolean;
    FPendingToggleCaps: Boolean;

    function RegisterRawInput: Boolean;
    procedure UnregisterRawInput;
    procedure ResetInputState(const Reason: string; Reregister: Boolean);
    procedure ApplyStickyKeysSetting;
    procedure RestoreStickyKeysHotkey;
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
    procedure UpdateAutorunControls;
    procedure ShowSettingsWindow;

    procedure UpdateTrayIcon(Force: Boolean);
    procedure UpdateTrayHint;
    function GestureCombos: TArray<TComboBox>;
    procedure ApplyLanguage;
    procedure StartUpdateCheck(Manual: Boolean);
    procedure HandleUpdateResult(Res: TUpdateCheckResult);
    function BuildSystemInfo: string;
    procedure QueueRequest(Action: TLSAction; const Plan: TBufferPlan;
      Automatic, ToggleCaps: Boolean);
    procedure CheckAutoCorrections;
    procedure ApplyCorrectionsFromEdit;
    procedure UpdateDownloadMenuCaption;
    procedure StartUpdateInstall;
    procedure HandleDownloadResult(Res: TUpdateDownloadResult);
    procedure HandleDownloadProgress(ReceivedKB, TotalKB: Int64);
    procedure DownloadCancel(Sender: TObject);
    function DownloadRunning: Boolean;
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
  Winapi.ShellAPI, Winapi.ShlObj,
  PngImage, PngFunctions,
  System.StrUtils,
  uDiagnostics, uWinUtils, uTaskAutorun, uLocale, uSettingsStore, uClipboardSnapshot;

const
  WM_LS_OPERATION_DONE = WM_APP + 10;
  WM_LS_UPDATE_RESULT = WM_APP + 11;
  WM_LS_UPDATE_DOWNLOADED = WM_APP + 12;
  WM_LS_UPDATE_PROGRESS = WM_APP + 13;
  // The phrase typed since the last caret jump (spaces included).
  MAX_PHRASE_LEN = 300;
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
    '', 'Shift×2', 'LCtrl×2', 'RCtrl×2', 'Ctrl+Ctrl', 'Shift+Shift', 'Caps×2',
    'RAlt×2', 'LAlt×2');

function ShortActionName(Action: TLSAction): string; forward;

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
begin
  FSettings := LoadSettings;
  SetUILanguage(FSettings.Language);
  FDetector := TGestureDetector.Create;
  FChain := TConversionChain.Create;
  FDetector.Interval := FSettings.DoubleTapInterval;
  FNotificationTimes := TDictionary<string, DWORD>.Create;
  FVersion := GetExecutableVersion;
  FIndicator := TLayoutIndicator.Create;
  FCatalog := TKeyboardLayoutCatalog.Create;
  FSnippets := ParseSnippets(FSettings.Snippets);
  FCapsShiftLock := IsCapsLockOffByShift;
  FCapsOn := (GetKeyState(VK_CAPITAL) and 1) <> 0;
  ApplyLanguage;

  // Assigning Checked raises OnClick; the guard keeps FormCreate from
  // rewriting the Run key or the diagnostics preference.
  FUpdatingControls := True;
  try
    chkDiagnostics.Checked := DiagnosticsEnabled;
  finally
    FUpdatingControls := False;
  end;
  LoadControlsFromSettings;
  FTaskInstalled := QueryAutorunTask(FTaskPath);
  UpdateAutorunControls;
  SyncAutorunPath;
  ApplyStickyKeysSetting;
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
    MessageBox(0, PChar(T('Не удалось зарегистрировать Raw Input.',
      'Could not register Raw Input.')), 'LayoutSwitcher',
      MB_OK or MB_ICONERROR);
  end
  else
    DiagnosticsLog('raw_input.registered keyboard=true mouse=true');

  // Lock/unlock notifications: key releases on the secure desktop are lost.
  if not LSWTSRegisterSessionNotification(Handle, NOTIFY_FOR_THIS_SESSION) then
    DiagnosticsLogFmt('session.notification_register_failed error=%d', [GetLastError]);

  UpdatePauseState;
  TimerUpdate.Enabled := True;
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
  RestoreStickyKeysHotkey;
  if Assigned(FWorker) then
  begin
    FWorker.Shutdown;
    FreeAndNil(FWorker);
  end;
  // Results posted after the last message loop iteration.
  while PeekMessage(Msg, Handle, WM_LS_OPERATION_DONE, WM_LS_OPERATION_DONE,
          PM_REMOVE) do
    TOperationResult(Msg.lParam).Free;
  if Assigned(FUpdateThread) then
  begin
    // Bounded by the HTTP timeouts.
    FUpdateThread.WaitFor;
    FreeAndNil(FUpdateThread);
  end;
  while PeekMessage(Msg, Handle, WM_LS_UPDATE_RESULT, WM_LS_UPDATE_RESULT,
          PM_REMOVE) do
    TUpdateCheckResult(Msg.lParam).Free;
  if Assigned(FDownloadThread) then
  begin
    // Cancels the download at the next received block.
    FDownloadThread.Terminate;
    FDownloadThread.WaitFor;
    FreeAndNil(FDownloadThread);
  end;
  FreeAndNil(FProgress);
  while PeekMessage(Msg, Handle, WM_LS_UPDATE_DOWNLOADED, WM_LS_UPDATE_DOWNLOADED,
          PM_REMOVE) do
    TUpdateDownloadResult(Msg.lParam).Free;
  FreeAndNil(FIndicator);
  FreeAndNil(FCatalog);
  FreeAndNil(FDetector);
  FreeAndNil(FChain);
  FreeAndNil(FNotificationTimes);
  DiagnosticsLog('form.destroy end');
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  ApplyExcludedFromEdit;
  ApplyCorrectionsFromEdit;
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

  if Message.Msg = WM_LS_UPDATE_PROGRESS then
  begin
    HandleDownloadProgress(Int64(Message.WParam), Int64(Message.LParam));
    Exit;
  end;

  if Message.Msg = WM_LS_UPDATE_DOWNLOADED then
  begin
    HandleDownloadResult(TUpdateDownloadResult(Message.LParam));
    Exit;
  end;

  if Message.Msg = WM_LS_UPDATE_RESULT then
  begin
    HandleUpdateResult(TUpdateCheckResult(Message.LParam));
    Exit;
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
  FChain.Reset;
  FCapsOn := (GetKeyState(VK_CAPITAL) and 1) <> 0;
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
    // The accessibility settings may have been changed meanwhile.
    ApplyStickyKeysSetting;
  end;
end;

procedure TFormMain.ApplyStickyKeysSetting;
var
  Flags, Bits: DWORD;
begin
  if not FSettings.DisableStickyKeysHotkey then
  begin
    RestoreStickyKeysHotkey;
    Exit;
  end;
  if not ReadStickyKeysFlags(Flags) then
  begin
    DiagnosticsLogFmt('sticky_keys.read_failed error=%d', [GetLastError]);
    Exit;
  end;
  Bits := Flags and STICKY_KEYS_HOTKEY_FLAGS;
  if Bits = 0 then
    Exit; // Already off: nothing to change and nothing to restore later.
  if WriteStickyKeysFlags(Flags and not STICKY_KEYS_HOTKEY_FLAGS) then
  begin
    FStickyHotkeyRemoved := FStickyHotkeyRemoved or Bits;
    DiagnosticsLogFmt('sticky_keys.hotkey_disabled flags=0x%.8x', [Flags]);
  end
  else
    DiagnosticsLogFmt('sticky_keys.write_failed error=%d', [GetLastError]);
end;

procedure TFormMain.RestoreStickyKeysHotkey;
var
  Flags: DWORD;
begin
  if FStickyHotkeyRemoved = 0 then
    Exit;
  // Only the bits removed by us are put back; other Sticky Keys options the
  // user may have changed meanwhile are preserved.
  if ReadStickyKeysFlags(Flags) and
     WriteStickyKeysFlags(Flags or FStickyHotkeyRemoved) then
    DiagnosticsLog('sticky_keys.hotkey_restored')
  else
    DiagnosticsLogFmt('sticky_keys.restore_failed error=%d', [GetLastError]);
  FStickyHotkeyRemoved := 0;
end;

procedure TFormMain.ProcessKeyboardEvent(EventTime: DWORD; VK, ScanCode: UINT;
  IsKeyUp: Boolean);
var
  Gesture: TLSGesture;
  Released: Integer;
begin
  if VK > 255 then
    Exit;
  if IsModifierKey(VK) then
    DiagnosticsLogFmt('input.modifier vk=0x%.2x up=%s focus=%p',
      [VK, BoolToStr(IsKeyUp, True), Pointer(GetFocusedWindow)]);
  // Alt moves the focus into the menu bar of many applications (Windows 11
  // Notepad, Office): that is not a window change and must neither reset a
  // pending double Alt nor drop the text typed so far.
  if not FPaused and not IsAltKey(VK) then
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

  if not IsKeyUp and not FDetector.IsDown(VK) then
  begin
    // Caps Lock state, following the "press Shift to turn it off" option.
    if VK = VK_CAPITAL then
    begin
      if FCapsShiftLock then
        FCapsOn := True
      else
        FCapsOn := not FCapsOn;
    end
    else if FCapsShiftLock and IsShiftKey(VK) then
      FCapsOn := False;
    // Automatic corrections are dropped once the user types on.
    if not IsModifierKey(VK) then
      AtomicIncrement(GKeystrokeCount);
  end;

  // The detector always tracks key states, even while paused, so that a
  // modifier held across a pause/resume does not leave stale state.
  Gesture := FDetector.KeyEvent(VK, IsKeyUp, EventTime);
  if FPaused then
    Exit;
  if Gesture <> lgNone then
  begin
    DiagnosticsLogFmt('gesture.detected gesture=%d action=%s',
      [Ord(Gesture), ActionKeys[FSettings.ActionForGesture(Gesture)]]);
    if (Gesture = lgDoubleCapsLock) and
       (FSettings.ActionForGesture(Gesture) <> laNone) and IsCapsLockOffByShift then
    begin
      FBalloonUrl := '';
      FBalloonInstall := False;
      ShowNotification('caps_shiftlock', T(
        'В Windows включено «Отключать Caps Lock клавишей Shift», поэтому после ' +
        'двойного Caps Lock он остаётся включённым. Нажмите Shift или назначьте ' +
        'действию другой жест.',
        'Windows is set to turn off Caps Lock with Shift, so Caps Lock stays on ' +
        'after a double Caps Lock. Press Shift or assign another gesture.'));
    end;
    // After a double Alt the application still has to leave its menu mode.
    FSettleFocusNext := Gesture in [lgDoubleRAlt, lgDoubleLAlt];
    QueueAction(FSettings.ActionForGesture(Gesture));
    FSettleFocusNext := False;
  end;

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
    VK_ESCAPE, VK_DELETE, VK_INSERT, VK_RETURN, VK_TAB:
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
  begin
    AddChar(Ch);
    if Ch = ' ' then
      CheckAutoCorrections;
  end
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
  if FCapsOn then
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
  // Any manual edit ends the word -> phrase -> revert chain.
  FChain.Reset;
  if FBufferOverflowed then
    Exit;
  if Length(FBuffer) >= MAX_PHRASE_LEN then
  begin
    FBuffer := '';
    FBufferOverflowed := True;
    Exit;
  end;
  FBuffer := FBuffer + Ch;
end;

procedure TFormMain.BufferBackspace;
begin
  FChain.Reset;
  if not FBufferOverflowed and (FBuffer <> '') then
    SetLength(FBuffer, Length(FBuffer) - 1);
end;

procedure TFormMain.ClearBuffer;
begin
  FBuffer := '';
  FBufferOverflowed := False;
  if Assigned(FChain) then
    FChain.Reset;
end;

procedure TFormMain.SetBufferText(const Value: string);
var
  Ch: Char;
begin
  ClearBuffer;
  if (Value = '') or (Length(Value) > MAX_PHRASE_LEN) then
    Exit;
  for Ch in Value do
    if Ord(Ch) < 32 then
      Exit;
  FBuffer := Value;
end;

{ Operations }

procedure TFormMain.QueueAction(Action: TLSAction);
var
  Plan: TBufferPlan;
begin
  if (Action = laNone) or FPaused then
    Exit;
  if not FBufferOverflowed and not FFocusIsPassword then
    Plan := FChain.Plan(Action, FBuffer)
  else
    Plan := FChain.Plan(laNone, '');
  if (Action = laUndo) and (Plan.Mode <> bmUndo) then
  begin
    DiagnosticsLog('operation.skipped action=undo reason=nothing_to_undo');
    Exit;
  end;
  QueueRequest(Action, Plan, False, False);
end;

procedure TFormMain.QueueRequest(Action: TLSAction; const Plan: TBufferPlan;
  Automatic, ToggleCaps: Boolean);
var
  Foreground, Focus: HWND;
  ProcessName: string;
  Request: TOperationRequest;
begin
  if FPaused then
    Exit;
  if FOperationBusy then
  begin
    if Automatic or (GetTickCount - FOperationStarted < OPERATION_WATCHDOG_MS) then
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
    if not Automatic then
    begin
      FBalloonUrl := '';
      FBalloonInstall := False;
      ShowNotification('elevated', Format(T(
        '%s запущен от имени администратора, поэтому Windows не позволяет ' +
        'изменить в нём текст. Включите в настройках запуск LayoutSwitcher ' +
        'с правами администратора.',
        '%s runs as administrator, so Windows does not allow changing its text. ' +
        'Turn on "Run as administrator" in the LayoutSwitcher settings.'),
        [ProcessName]));
    end;
    Exit;
  end;

  Request := TOperationRequest.Create;
  Inc(FOperationSequence);
  Request.Sequence := FOperationSequence;
  Request.Action := Action;
  Request.Plan := Plan;
  Request.Automatic := Automatic;
  Request.KeystrokeStamp := AtomicCmpExchange(GKeystrokeCount, 0, 0);
  Request.ToggleCapsLock := ToggleCaps;
  Request.SettleFocus := FSettleFocusNext;
  if FCapsShiftLock then
    Request.CapsOffKey := VK_SHIFT
  else
    Request.CapsOffKey := VK_CAPITAL;
  Request.FocusWnd := Focus;
  Request.WindowLayout := GetKeyboardLayout(GetWindowThreadProcessId(Focus, nil));
  Request.PreviousLayout := FPreviousLayout;
  Request.ExcludedProcesses := FSettings.ExcludedProcesses;
  FPendingPlan := Plan;
  FPendingAutomatic := Automatic;
  FPendingToggleCaps := ToggleCaps;

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

    if Res.Action in [laTranslate, laWebSearch] then
    begin
      if Res.Success then
      begin
        if Res.Action = laTranslate then
          ShellExecute(0, 'open', PChar(BuildTranslateUrl(FSettings.Translator,
            Res.LookupText)), nil, nil, SW_SHOWNORMAL)
        else
          ShellExecute(0, 'open', PChar(BuildSearchUrl(FSettings.SearchEngine,
            Res.LookupText)), nil, nil, SW_SHOWNORMAL);
      end
      else if Res.Notification <> '' then
      begin
        FBalloonUrl := '';
        FBalloonInstall := False;
        ShowNotification(Res.NotificationKey, Res.Notification);
      end;
      Exit;
    end;
    if Res.Success and FPendingToggleCaps then
      FCapsOn := False;

    if Res.FocusIsPassword and (GetFocusedWindow = FLastWindow) then
      FFocusIsPassword := True;
    case Res.BufferAction of
      baClear: ClearBuffer;
      baSet: SetBufferText(Res.NewBufferText);
    end;
    // Remember the step so that repeating the action widens it.
    if not Res.Success or (FBuffer = '') then
      FChain.Reset
    else if Res.UsedBuffer then
      FChain.Completed(FPendingPlan, Res.Action, FBuffer, Res.SourceLayout,
        Res.TargetLayout)
    else
      FChain.CompletedWhole(Res.Action, FBuffer, Res.OriginalText,
        Res.SourceLayout, Res.TargetLayout);
    if Res.Success and (Res.SourceLayout <> 0) then
      FPreviousLayout := Res.SourceLayout;
    // Automatic corrections never bother the user with notifications.
    if (Res.Notification <> '') and not FPendingAutomatic then
    begin
      FBalloonUrl := '';
      FBalloonInstall := False;
      ShowNotification(Res.NotificationKey, Res.Notification);
    end;
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
    // The badge is shown only when the layout of the same window changes,
    // not when the user merely switches to a window with another layout.
    if FSettings.ShowLayoutIndicator and not FPaused and (FLastLayout <> 0) and
       (Target = FIndicatorWindow) then
      FIndicator.ShowLayout(Layout);
    FLastLayout := Layout;
    Force := True;
  end;
  FIndicatorWindow := Target;
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
  Hint, Line: string;
  Action: TLSAction;
  Gesture: TLSGesture;
begin
  Hint := 'LayoutSwitcher';
  if FPaused then
  begin
    if FPauseUntil <> 0 then
      Hint := Hint + T(' — пауза до ', ' - paused until ') +
        FormatDateTime('hh:nn', FPauseUntil)
    else
      Hint := Hint + T(' — пауза', ' - paused');
  end
  else
    for Action := Low(FSettings.ActionGestures) to High(FSettings.ActionGestures) do
    begin
      Gesture := FSettings.GestureForAction(Action);
      if Gesture = lgNone then
        Continue;
      // #10 instead of CRLF and no spaces: the tray tip holds 127 chars.
      // Lines that do not fit are replaced by an ellipsis; the settings
      // window lists everything.
      Line := #10 + ShortGestureNames[Gesture] + '=' + ShortActionName(Action);
      if Length(Hint) + Length(Line) > MAX_TIP - 2 then
      begin
        Hint := Hint + #10'…';
        Break;
      end;
      Hint := Hint + Line;
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
    cbTranslit.ItemIndex := Ord(FSettings.GestureForAction(laTransliterate));
    cbUndo.ItemIndex := Ord(FSettings.GestureForAction(laUndo));
    cbTranslate.ItemIndex := Ord(FSettings.GestureForAction(laTranslate));
    cbWebSearch.ItemIndex := Ord(FSettings.GestureForAction(laWebSearch));
    cbTranslator.ItemIndex := FSettings.Translator;
    cbSearchEngine.ItemIndex := FSettings.SearchEngine;
    chkFixCapsLock.Checked := FSettings.FixCapsLock;
    chkFixTwoCapitals.Checked := FSettings.FixTwoCapitals;
    edTwoCapsExceptions.Text := string.Join('; ', FSettings.TwoCapitalsExceptions);
    chkSnippets.Checked := FSettings.SnippetsEnabled;
    memSnippets.Text := FSettings.Snippets;
    udInterval.Position := Integer(FSettings.DoubleTapInterval);
    edInterval.Text := IntToStr(FSettings.DoubleTapInterval);
    chkPauseFullscreen.Checked := FSettings.PauseInFullscreen;
    chkNotifications.Checked := FSettings.ShowNotifications;
    chkDisableStickyKeys.Checked := FSettings.DisableStickyKeysHotkey;
    chkLayoutIndicator.Checked := FSettings.ShowLayoutIndicator;
    chkCheckUpdates.Checked := FSettings.CheckForUpdates;
    cbLanguage.ItemIndex := Ord(FSettings.Language);
    edExcluded.Text := string.Join(sLineBreak, FSettings.ExcludedProcesses);
  finally
    FUpdatingControls := False;
  end;
end;

procedure TFormMain.ApplySettings;
begin
  FDetector.Interval := FSettings.DoubleTapInterval;
  FSnippets := ParseSnippets(FSettings.Snippets);
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
  FSettings.DisableStickyKeysHotkey := chkDisableStickyKeys.Checked;
  FSettings.ShowLayoutIndicator := chkLayoutIndicator.Checked;
  FSettings.CheckForUpdates := chkCheckUpdates.Checked;
  FSettings.FixCapsLock := chkFixCapsLock.Checked;
  FSettings.FixTwoCapitals := chkFixTwoCapitals.Checked;
  FSettings.SnippetsEnabled := chkSnippets.Checked;
  if not FSettings.ShowLayoutIndicator then
    FIndicator.HideNow;
  ApplySettings;
  ApplyStickyKeysSetting;
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

procedure TFormMain.UpdateAutorunControls;
begin
  FUpdatingControls := True;
  try
    chkAutorun.Checked := FTaskInstalled or IsInStartup(STARTUP_VALUE_NAME);
    chkAutorunElevated.Checked := FTaskInstalled;
    chkAutorunElevated.Enabled := chkAutorun.Checked;
  finally
    FUpdatingControls := False;
  end;
end;

procedure TFormMain.chkAutorunClick(Sender: TObject);
var
  ErrorText: string;
begin
  if FUpdatingControls then
    Exit;
  if chkAutorun.Checked then
    AddToStartup(STARTUP_VALUE_NAME, Application.ExeName)
  else
  begin
    if FTaskInstalled then
    begin
      if not RemoveAutorunTask(ErrorText) then
      begin
        DiagnosticsLogFmt('autorun.task_remove_failed error="%s"', [ErrorText]);
        UpdateAutorunControls;
        MessageBox(Handle, PChar(T('Не удалось отключить автозапуск с правами ' +
          'администратора.', 'Could not turn off running as administrator.') +
          sLineBreak + ErrorText), 'LayoutSwitcher',
          MB_OK or MB_ICONERROR);
        Exit;
      end;
      FTaskInstalled := False;
    end;
    RemoveFromStartup(STARTUP_VALUE_NAME);
  end;
  UpdateAutorunControls;
  DiagnosticsLogFmt('ui.autorun_changed enabled=%s path="%s"',
    [BoolToStr(chkAutorun.Checked, True), Application.ExeName]);
end;

procedure TFormMain.chkAutorunElevatedClick(Sender: TObject);
var
  ErrorText: string;
begin
  if FUpdatingControls then
    Exit;
  if chkAutorunElevated.Checked then
  begin
    if not InstallAutorunTask(Application.ExeName, ErrorText) then
    begin
      DiagnosticsLogFmt('autorun.task_install_failed error="%s"', [ErrorText]);
      UpdateAutorunControls;
      MessageBox(Handle, PChar(T('Не удалось включить автозапуск с правами ' +
        'администратора.', 'Could not turn on running as administrator.') +
        sLineBreak + ErrorText), 'LayoutSwitcher',
        MB_OK or MB_ICONERROR);
      Exit;
    end;
    FTaskInstalled := True;
    // The task replaces the Run key; both would start two copies.
    RemoveFromStartup(STARTUP_VALUE_NAME);
    DiagnosticsLog('autorun.task_installed');
    if not IsProcessElevated then
      MessageBox(Handle, PChar(T('С правами администратора программа будет запускаться ' +
        'со следующего входа в Windows. Чтобы работать в окнах администратора ' +
        'уже сейчас, закройте LayoutSwitcher и запустите его от имени администратора.',
        'LayoutSwitcher will run as administrator from the next sign-in. To work ' +
        'in administrator windows right now, exit LayoutSwitcher and start it ' +
        'as administrator.')),
        'LayoutSwitcher', MB_OK or MB_ICONINFORMATION);
  end
  else
  begin
    if not RemoveAutorunTask(ErrorText) then
    begin
      DiagnosticsLogFmt('autorun.task_remove_failed error="%s"', [ErrorText]);
      UpdateAutorunControls;
      MessageBox(Handle, PChar(T('Не удалось отключить автозапуск с правами ' +
        'администратора.', 'Could not turn off running as administrator.') +
        sLineBreak + ErrorText), 'LayoutSwitcher',
        MB_OK or MB_ICONERROR);
      Exit;
    end;
    FTaskInstalled := False;
    AddToStartup(STARTUP_VALUE_NAME, Application.ExeName);
    DiagnosticsLog('autorun.task_removed');
  end;
  UpdateAutorunControls;
end;

procedure TFormMain.SyncAutorunPath;
var
  Registered: string;
begin
  if FTaskInstalled then
  begin
    // A leftover Run entry would start a second, non-elevated copy.
    if IsInStartup(STARTUP_VALUE_NAME) then
    begin
      RemoveFromStartup(STARTUP_VALUE_NAME);
      DiagnosticsLog('autorun.run_key_removed reason=task_installed');
    end;
    if (FTaskPath = '') or SameText(ExpandFileName(FTaskPath), Application.ExeName) then
      Exit;
    {$IFDEF DEBUG}
    DiagnosticsLogFmt('autorun.task_path_mismatch registered="%s" current="%s" updated=false',
      [FTaskPath, Application.ExeName]);
    {$ELSE}
    // Updating the task needs elevation; do it silently only when we have it.
    var ErrorText: string;
    if IsProcessElevated and InstallAutorunTask(Application.ExeName, ErrorText) then
      DiagnosticsLogFmt('autorun.task_path_mismatch registered="%s" current="%s" updated=true',
        [FTaskPath, Application.ExeName])
    else
      DiagnosticsLogFmt('autorun.task_path_mismatch registered="%s" current="%s" updated=false',
        [FTaskPath, Application.ExeName]);
    {$ENDIF}
    Exit;
  end;

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
    MessageBox(Handle, PChar(T('Не удалось сохранить настройку диагностики в реестре.',
      'Could not save the diagnostics setting to the registry.')),
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

function ShortActionName(Action: TLSAction): string;
begin
  case Action of
    laConvert: Result := T('Раскладка', 'Layout');
    laUpperCase: Result := T('ВЕРХНИЙ', 'UPPER');
    laLowerCase: Result := T('нижний', 'lower');
    laInvertCase: Result := T('иНВЕРСИЯ', 'iNVERT');
    laTranslate: Result := T('Перевод', 'Translate');
    laWebSearch: Result := T('Поиск', 'Search');
    laTransliterate: Result := T('Транслит', 'Translit');
    laUndo: Result := T('Отмена', 'Undo');
  else
    Result := '';
  end;
end;

function TFormMain.GestureCombos: TArray<TComboBox>;
begin
  Result := [cbConvert, cbUpper, cbLower, cbInvert, cbTranslit, cbUndo, cbTranslate,
    cbWebSearch];
end;

procedure TFormMain.ApplyLanguage;
var
  Combo: TComboBox;
  Gesture: TLSGesture;
  Index: Integer;

  procedure FillCombo(Box: TComboBox; const Items: array of string);
  var
    Saved: Integer;
    Item: string;
  begin
    Saved := Box.ItemIndex;
    Box.Items.Clear;
    for Item in Items do
      Box.Items.Add(Item);
    Box.ItemIndex := Saved;
  end;

begin
  FUpdatingControls := True;
  try
    Caption := T('LayoutSwitcher - Переключатель раскладок клавиатуры',
      'LayoutSwitcher - Keyboard layout switcher');
    tsGeneral.Caption := T('Основные', 'General');
    tsHotkeys.Caption := T('Сочетания', 'Shortcuts');
    tsCorrections.Caption := T('Исправления', 'Corrections');
    tsExclusions.Caption := T('Исключения', 'Exclusions');

    chkAutorun.Caption := T('Автозапуск при старте системы', 'Start with Windows');
    chkAutorunElevated.Caption := T(
      'Запускать с правами администратора (для окон, открытых от имени администратора)',
      'Run as administrator (to work in windows opened as administrator)');
    chkDiagnostics.Caption := T('Вести диагностический журнал', 'Keep a diagnostic log');
    chkCheckUpdates.Caption := T('Проверять наличие новой версии раз в день',
      'Check for a new version once a day');
    chkPauseFullscreen.Caption := T('Не работать в полноэкранных приложениях и играх',
      'Do not work in full-screen applications and games');
    chkNotifications.Caption := T('Показывать уведомление, если действие невозможно',
      'Show a notification when an action is not possible');
    chkDisableStickyKeys.Caption := T(
      'Отключить вызов залипания клавиш пятикратным нажатием Shift',
      'Turn off the Sticky Keys prompt on pressing Shift five times');
    chkLayoutIndicator.Caption := T('Показывать раскладку рядом с курсором при переключении',
      'Show the layout next to the caret when it changes');
    lblLanguage.Caption := T('Язык интерфейса / Language:', 'Language / Язык интерфейса:');
    FillCombo(cbLanguage, [T('Как в Windows', 'As in Windows'), 'Русский', 'English']);
    if IsPortableMode then
      lblStorage.Caption := T('Переносной режим: настройки хранятся в файле ',
        'Portable mode: settings are stored in ') + PortableIniFile
    else
      lblStorage.Caption := T('Настройки хранятся в реестре Windows.',
        'Settings are stored in the Windows registry.');
    btnExport.Caption := T('Экспорт настроек...', 'Export settings...');
    btnImport.Caption := T('Импорт настроек...', 'Import settings...');

    lblConvert.Caption := ActionName(laConvert);
    lblUpper.Caption := ActionName(laUpperCase);
    lblLower.Caption := ActionName(laLowerCase);
    lblInvert.Caption := ActionName(laInvertCase);
    lblTranslit.Caption := ActionName(laTransliterate);
    lblUndo.Caption := ActionName(laUndo);
    lblTranslate.Caption := ActionName(laTranslate);
    lblWebSearch.Caption := ActionName(laWebSearch);
    lblInterval.Caption := T('Интервал двойного нажатия:', 'Double-tap interval:');
    lblIntervalUnit.Caption := T('мс', 'ms');
    for Combo in GestureCombos do
    begin
      Index := Combo.ItemIndex;
      Combo.Items.BeginUpdate;
      try
        Combo.Items.Clear;
        for Gesture := Low(TLSGesture) to High(TLSGesture) do
          Combo.Items.Add(GestureName(Gesture));
      finally
        Combo.Items.EndUpdate;
      end;
      Combo.ItemIndex := Index;
    end;
    lblTranslator.Caption := T('Переводчик:', 'Translator:');
    FillCombo(cbTranslator, [T('Яндекс Переводчик', 'Yandex Translate'),
      'Google Translate', 'DeepL']);
    lblSearchEngine.Caption := T('Поиск:', 'Search engine:');
    FillCombo(cbSearchEngine, [T('Яндекс', 'Yandex'), 'Google', 'Bing', 'DuckDuckGo']);

    chkFixCapsLock.Caption := T(
      'Исправлять слова, набранные с включённым Caps Lock (пРИВЕТ → Привет)',
      'Fix words typed with Caps Lock on (hELLO → Hello)');
    chkFixTwoCapitals.Caption := T(
      'Исправлять две заглавные буквы в начале слова (ПРивет → Привет)',
      'Fix two capitals at the start of a word (HEllo → Hello)');
    lblTwoCapsExceptions.Caption := T('Исключения:', 'Exceptions:');
    chkSnippets.Caption := T('Заменять шаблоны: сокращение и пробел',
      'Expand templates: abbreviation followed by a space');
    lblSnippetsHint.Caption := T(
      'Каждая строка: сокращение=текст. Подстановки: {date}, {time}, {datetime}.',
      'One per line: abbreviation=text. Placeholders: {date}, {time}, {datetime}.');
    lblCorrectionsNote.Caption := T(
      'Исправления выполняются после пробела. Отменить последнее — двойной Caps Lock.',
      'Corrections are made after a space. Undo the last one with a double Caps Lock.');

    lblExcluded.Caption := T('Не работать в программах (имя exe в строке):',
      'Do not work in these programs (one exe name per line):');
    btnDefaultExcluded.Caption := T('По умолчанию', 'Defaults');
    btnReport.Caption := T('Собрать отчёт...', 'Create report...');
    btnClose.Caption := T('Закрыть', 'Close');
    lblVersion.Caption := T('Версия ', 'Version ') + FVersion;
    lblAuthor.Left := lblVersion.Left + lblVersion.Width + 12;

    mniSettings.Caption := T('Настройки...', 'Settings...');
    mniClipboard.Caption := T('Текст в буфере обмена', 'Text in the clipboard');
    mniClipConvert.Caption := T('Исправить раскладку', 'Fix keyboard layout');
    mniClipUpper.Caption := T('ВЕРХНИЙ регистр', 'UPPER case');
    mniClipLower.Caption := T('нижний регистр', 'lower case');
    mniClipTranslit.Caption := T('Транслитерация', 'Transliterate');
    mniPause15.Caption := T('Приостановить на 15 минут', 'Pause for 15 minutes');
    mniPause60.Caption := T('Приостановить на 1 час', 'Pause for 1 hour');
    mniPauseIndefinite.Caption := T('Приостановить до возобновления', 'Pause until resumed');
    mniResume.Caption := T('Возобновить работу', 'Resume');
    mniCheckUpdates.Caption := T('Проверить обновления', 'Check for updates');
    UpdateDownloadMenuCaption;
    mniReport.Caption := T('Собрать отчёт...', 'Create report...');
    mniDiagnostics.Caption := T('Открыть папку диагностики', 'Open diagnostics folder');
    mniExit.Caption := T('Выход', 'Exit');
  finally
    FUpdatingControls := False;
  end;
  UpdateTrayHint;
end;

procedure TFormMain.cbLanguageChange(Sender: TObject);
begin
  if FUpdatingControls or (cbLanguage.ItemIndex < 0) then
    Exit;
  FSettings.Language := TLSLanguage(cbLanguage.ItemIndex);
  SetUILanguage(FSettings.Language);
  ApplyLanguage;
  ApplySettings;
end;

{ Updates }

procedure TFormMain.StartUpdateCheck(Manual: Boolean);
begin
  if Assigned(FUpdateThread) then
  begin
    if not FUpdateThread.Finished then
      Exit;
    FreeAndNil(FUpdateThread);
  end;
  DiagnosticsLogFmt('update.check_start manual=%s', [BoolToStr(Manual, True)]);
  FUpdateThread := TUpdateCheckThread.Create(Handle, WM_LS_UPDATE_RESULT, FVersion,
    Manual);
end;

procedure TFormMain.TimerUpdateTimer(Sender: TObject);
begin
  // First tick a minute after start, then hourly; a check runs once a day.
  TimerUpdate.Interval := 60 * 60 * 1000;
  if FSettings.CheckForUpdates and (Now - FSettings.LastUpdateCheck >= 1) then
    StartUpdateCheck(False);
end;

procedure TFormMain.HandleUpdateResult(Res: TUpdateCheckResult);
var
  PerMachine: Boolean;
begin
  try
    DiagnosticsLogFmt('update.check_done success=%s latest=%s newer=%s error="%s"',
      [BoolToStr(Res.Success, True), Res.LatestVersion,
       BoolToStr(Res.IsNewer, True), Res.ErrorText]);
    if Res.Success then
    begin
      FSettings.LastUpdateCheck := Now;
      SaveSettings(FSettings);
    end;

    if Res.Success and Res.IsNewer then
    begin
      FUpdateVersion := Res.LatestVersion;
      FUpdateUrl := Res.ReleaseUrl;
      FInstallerUrl := Res.InstallerUrl;
      FInstallerName := Res.InstallerName;
      FInstallerSha256 := Res.InstallerSha256;
      // One-click installation only for a copy put there by the installer;
      // a copy run from elsewhere would be duplicated, not updated.
      FUpdateInstallable := (FInstallerUrl <> '') and IsInstalledCopy(PerMachine);
      UpdateDownloadMenuCaption;
      mniDownloadUpdate.Visible := True;
      FBalloonInstall := FUpdateInstallable;
      if FUpdateInstallable then
        FBalloonUrl := ''
      else
        FBalloonUrl := FUpdateUrl;
      if Res.Manual then
        FNotificationTimes.Remove('update');
      if FUpdateInstallable then
        ShowNotification('update', Format(T(
          'Доступна новая версия LayoutSwitcher %s. Щёлкните, чтобы установить её.',
          'LayoutSwitcher %s is available. Click to install it.'), [FUpdateVersion]))
      else
        ShowNotification('update', Format(T(
          'Доступна новая версия LayoutSwitcher %s. Щёлкните, чтобы открыть страницу загрузки.',
          'LayoutSwitcher %s is available. Click to open the download page.'),
          [FUpdateVersion]));
    end
    else if Res.Manual then
    begin
      FNotificationTimes.Remove('update_status');
      FBalloonUrl := '';
      FBalloonInstall := False;
      if Res.Success then
        ShowNotification('update_status', Format(T(
          'Установлена последняя версия (%s).', 'You have the latest version (%s).'),
          [FVersion]))
      else
        ShowNotification('update_status', T(
          'Не удалось проверить обновления: ', 'Could not check for updates: ') +
          Res.ErrorText);
    end;
  finally
    Res.Free;
  end;
end;

procedure TFormMain.mniCheckUpdatesClick(Sender: TObject);
begin
  StartUpdateCheck(True);
end;

procedure TFormMain.mniDownloadUpdateClick(Sender: TObject);
begin
  if FUpdateInstallable then
    StartUpdateInstall
  else if FUpdateUrl <> '' then
    ShellExecute(0, 'open', PChar(FUpdateUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TFormMain.TrayIconBalloonClick(Sender: TObject);
begin
  if FBalloonInstall then
    StartUpdateInstall
  else if FBalloonUrl <> '' then
    ShellExecute(0, 'open', PChar(FBalloonUrl), nil, nil, SW_SHOWNORMAL);
end;

{ Report }

function TFormMain.BuildSystemInfo: string;
var
  Lines: TStringList;
  Layout: HKL;
  Action: TLSAction;
  NameBuffer: array[0..KL_NAMELENGTH] of Char;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('LayoutSwitcher ' + FVersion);
    Lines.Add('Created: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    Lines.Add('Executable: ' + Application.ExeName);
    Lines.Add(Format('Bits: %d', [SizeOf(Pointer) * 8]));
    Lines.Add('OS: ' + TOSVersion.ToString);
    Lines.Add('Elevated: ' + BoolToStr(IsProcessElevated, True));
    Lines.Add('UI language: ' + T('ru', 'en'));
    Lines.Add('');
    Lines.Add('[Keyboard layouts]');
    for Layout in TKeyboardLayoutCatalog.InstalledLayouts do
      Lines.Add(Format('%.8x %s', [NativeUInt(Layout), LayoutShortName(Layout)]));
    if GetKeyboardLayoutName(NameBuffer) then
      Lines.Add('Active layout name: ' + string(NameBuffer));
    Lines.Add('');
    Lines.Add('[Settings]');
    for Action := Low(FSettings.ActionGestures) to High(FSettings.ActionGestures) do
      Lines.Add(Format('%s = %s', [ActionKeys[Action],
        GestureName(FSettings.ActionGestures[Action])]));
    Lines.Add(Format('DoubleTapInterval = %d', [FSettings.DoubleTapInterval]));
    Lines.Add('PauseInFullscreen = ' + BoolToStr(FSettings.PauseInFullscreen, True));
    Lines.Add('ShowNotifications = ' + BoolToStr(FSettings.ShowNotifications, True));
    Lines.Add('DisableStickyKeysHotkey = ' + BoolToStr(FSettings.DisableStickyKeysHotkey, True));
    Lines.Add('ShowLayoutIndicator = ' + BoolToStr(FSettings.ShowLayoutIndicator, True));
    Lines.Add('CheckForUpdates = ' + BoolToStr(FSettings.CheckForUpdates, True));
    Lines.Add('ExcludedProcesses = ' + ProcessListToText(FSettings.ExcludedProcesses));
    Lines.Add('Diagnostics = ' + BoolToStr(DiagnosticsEnabled, True));
    Lines.Add('Paused = ' + BoolToStr(FPaused, True));
    Lines.Add('');
    Lines.Add('[Autorun]');
    Lines.Add('Run key = ' + GetStartupCommand(STARTUP_VALUE_NAME));
    Lines.Add('Elevated task = ' + BoolToStr(FTaskInstalled, True) + ' ' + FTaskPath);
    if not DiagnosticsEnabled then
    begin
      Lines.Add('');
      Lines.Add('Diagnostics are disabled: the report contains only older logs, if any.');
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

procedure TFormMain.mniReportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  DesktopPath: array[0..MAX_PATH] of Char;
  ErrorText: string;
begin
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Title := T('Сохранить отчёт LayoutSwitcher', 'Save LayoutSwitcher report');
    Dialog.Filter := T('Архив ZIP', 'ZIP archive') + ' (*.zip)|*.zip';
    Dialog.DefaultExt := 'zip';
    Dialog.FileName := 'LayoutSwitcher-report-' +
      FormatDateTime('yyyymmdd-hhnn', Now) + '.zip';
    if SHGetFolderPath(0, CSIDL_DESKTOPDIRECTORY, 0, 0, DesktopPath) = S_OK then
      Dialog.InitialDir := DesktopPath;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if not Dialog.Execute then
      Exit;
    if CreateDiagnosticsReport(Dialog.FileName, BuildSystemInfo, ErrorText) then
      ShellExecute(0, 'open', 'explorer.exe',
        PChar('/select,"' + Dialog.FileName + '"'), nil, SW_SHOWNORMAL)
    else
      MessageBox(Handle, PChar(T('Не удалось создать отчёт: ',
        'Could not create the report: ') + ErrorText), 'LayoutSwitcher',
        MB_OK or MB_ICONERROR);
  finally
    Dialog.Free;
  end;
end;

{ Automatic corrections }

procedure TFormMain.CheckAutoCorrections;
var
  WordStart, WordLength: Integer;
  Word, Template, Replacement, Fixed: string;
  ToggleCaps: Boolean;
begin
  if FPaused or FBufferOverflowed or FFocusIsPassword or FOperationBusy then
    Exit;
  if not (FSettings.FixCapsLock or FSettings.FixTwoCapitals or
          (FSettings.SnippetsEnabled and (Length(FSnippets) > 0))) then
    Exit;
  // Exactly one space has just been typed after the word.
  if not FindLastWord(FBuffer, WordStart, WordLength) or
     (WordStart + WordLength <> Length(FBuffer)) then
    Exit;
  Word := Copy(FBuffer, WordStart, WordLength);

  Replacement := '';
  Template := '';
  ToggleCaps := False;
  if FSettings.SnippetsEnabled and FindSnippet(FSnippets, Word, Template) then
    Replacement := ExpandSnippet(Template, Now)
  else if FSettings.FixCapsLock and FCapsOn and IsCapsLockMistake(Word) then
  begin
    Replacement := FixCapsLockMistake(Word);
    ToggleCaps := True;
  end
  else if FSettings.FixTwoCapitals and
     FixTwoCapitals(Word, FSettings.TwoCapitalsExceptions, Fixed) then
    Replacement := Fixed;
  if (Replacement = '') or (Replacement = Word) then
    Exit;

  DiagnosticsLogFmt('autocorrect.queue kind=%s length=%d',
    [IfThen(ToggleCaps, 'caps_lock', IfThen(Template <> '', 'template', 'two_capitals')),
     Length(Word)]);
  QueueRequest(laNone, TConversionChain.PlanReplacement(FBuffer, WordStart,
    WordLength, Replacement), True, ToggleCaps);
end;

procedure TFormMain.edCorrectionsExit(Sender: TObject);
begin
  ApplyCorrectionsFromEdit;
end;

procedure TFormMain.ApplyCorrectionsFromEdit;
var
  Exceptions: TArray<string>;
  Snippets: string;
begin
  Exceptions := ParseWordList(edTwoCapsExceptions.Text);
  Snippets := TrimRight(memSnippets.Text);
  if (string.Join('; ', Exceptions) <> string.Join('; ', FSettings.TwoCapitalsExceptions)) or
     (Snippets <> FSettings.Snippets) then
  begin
    FSettings.TwoCapitalsExceptions := Exceptions;
    FSettings.Snippets := Snippets;
    ApplySettings;
  end;
end;

procedure TFormMain.cbServiceChange(Sender: TObject);
begin
  if FUpdatingControls then
    Exit;
  FSettings.Translator := cbTranslator.ItemIndex;
  FSettings.SearchEngine := cbSearchEngine.ItemIndex;
  ApplySettings;
end;

{ Clipboard }

procedure TFormMain.mniClipboardClick(Sender: TObject);
var
  Action: TLSAction;
  Text, Converted: string;
  Pair: TLayoutPair;
begin
  Action := TLSAction((Sender as TMenuItem).Tag);
  Text := ReadClipboardText(Handle);
  FBalloonUrl := '';
  FBalloonInstall := False;
  FNotificationTimes.Remove('clipboard');
  if Text = '' then
  begin
    ShowNotification('clipboard', T('В буфере обмена нет текста.',
      'There is no text in the clipboard.'));
    Exit;
  end;
  case Action of
    laConvert:
      if FCatalog.ChoosePair(Text, FLastLayout, FPreviousLayout, Pair) then
        Converted := ConvertTextBetweenLayouts(Text, FCatalog.KeyChars(Pair.Source),
          FCatalog.KeyChars(Pair.Target))
      else
        Converted := Text;
    laUpperCase: Converted := ChangeTextCase(Text, True);
    laLowerCase: Converted := ChangeTextCase(Text, False);
    laTransliterate: Converted := TransliterateText(Text);
  else
    Exit;
  end;
  if Converted = Text then
  begin
    ShowNotification('clipboard', T('Текст в буфере обмена уже в нужном виде.',
      'The clipboard text needs no change.'));
    Exit;
  end;
  if WriteClipboardText(Handle, Converted) then
    ShowNotification('clipboard', T('Текст в буфере обмена изменён — его можно вставить.',
      'The clipboard text has been changed and can be pasted.'))
  else
    ShowNotification('clipboard', T('Буфер обмена занят другой программой.',
      'The clipboard is busy.'));
  DiagnosticsLogFmt('clipboard.convert action=%s length=%d', [ActionKeys[Action],
    Length(Text)]);
end;

{ Export / import }

procedure TFormMain.btnExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  ApplyExcludedFromEdit;
  ApplyCorrectionsFromEdit;
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Title := T('Экспорт настроек LayoutSwitcher', 'Export LayoutSwitcher settings');
    Dialog.Filter := T('Файл настроек', 'Settings file') + ' (*.ini)|*.ini';
    Dialog.DefaultExt := 'ini';
    Dialog.FileName := PORTABLE_INI_NAME;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if not Dialog.Execute then
      Exit;
    if ExportSettings(FSettings, Dialog.FileName, DiagnosticsEnabled) then
      MessageBox(Handle, PChar(T('Настройки сохранены. Чтобы программа работала в ' +
        'переносном режиме, положите файл LayoutSwitcher.ini рядом с LS.exe.',
        'Settings saved. To run the program in portable mode, put ' +
        'LayoutSwitcher.ini next to LS.exe.')), 'LayoutSwitcher',
        MB_OK or MB_ICONINFORMATION)
    else
      MessageBox(Handle, PChar(T('Не удалось сохранить файл.', 'Could not save the file.')),
        'LayoutSwitcher', MB_OK or MB_ICONERROR);
  finally
    Dialog.Free;
  end;
end;

procedure TFormMain.btnImportClick(Sender: TObject);
var
  Dialog: TOpenDialog;
  Imported: TLSSettings;
  Diagnostics: Boolean;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := T('Импорт настроек LayoutSwitcher', 'Import LayoutSwitcher settings');
    Dialog.Filter := T('Файл настроек', 'Settings file') + ' (*.ini)|*.ini';
    if not Dialog.Execute then
      Exit;
    if not ImportSettings(Dialog.FileName, Imported, Diagnostics) then
    begin
      MessageBox(Handle, PChar(T('Файл не похож на настройки LayoutSwitcher.',
        'The file does not contain LayoutSwitcher settings.')), 'LayoutSwitcher',
        MB_OK or MB_ICONERROR);
      Exit;
    end;
  finally
    Dialog.Free;
  end;

  // Autorun and the elevated task belong to this computer and stay as they are.
  FSettings := Imported;
  SetUILanguage(FSettings.Language);
  ApplySettings;
  if Diagnostics <> DiagnosticsEnabled then
  begin
    SetDiagnosticsEnabled(Diagnostics);
    if Diagnostics then
      InitializeDiagnostics
    else
      ShutdownDiagnostics;
    FUpdatingControls := True;
    try
      chkDiagnostics.Checked := Diagnostics;
    finally
      FUpdatingControls := False;
    end;
  end;
  LoadControlsFromSettings;
  ApplyLanguage;
  ApplyStickyKeysSetting;
  DiagnosticsLog('settings.imported');
  MessageBox(Handle, PChar(T('Настройки импортированы.', 'Settings imported.')),
    'LayoutSwitcher', MB_OK or MB_ICONINFORMATION);
end;

{ Update installation }

procedure TFormMain.UpdateDownloadMenuCaption;
begin
  if FUpdateVersion = '' then
    Exit;
  if FUpdateInstallable then
    mniDownloadUpdate.Caption := Format(T('Установить версию %s', 'Install version %s'),
      [FUpdateVersion])
  else
    mniDownloadUpdate.Caption := Format(T('Скачать версию %s', 'Download version %s'),
      [FUpdateVersion]);
end;

function TFormMain.DownloadRunning: Boolean;
begin
  Result := Assigned(FDownloadThread) and not FDownloadThread.Finished;
end;

procedure TFormMain.StartUpdateInstall;
begin
  if DownloadRunning then
  begin
    // A second click just brings the progress window back.
    FProgress.ShowWindow;
    Exit;
  end;
  FreeAndNil(FDownloadThread);
  if not Assigned(FProgress) then
  begin
    FProgress := TUpdateProgressWindow.Create;
    FProgress.OnCancel := DownloadCancel;
  end;
  FProgress.Start(FUpdateVersion);
  mniDownloadUpdate.Caption := Format(T('Загрузка версии %s...',
    'Downloading version %s...'), [FUpdateVersion]);
  DiagnosticsLogFmt('update.download_start version=%s', [FUpdateVersion]);
  FDownloadThread := TUpdateDownloadThread.Create(Handle, WM_LS_UPDATE_DOWNLOADED,
    WM_LS_UPDATE_PROGRESS, FInstallerUrl, IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    FInstallerName, FInstallerSha256, FVersion);
end;

procedure TFormMain.HandleDownloadProgress(ReceivedKB, TotalKB: Int64);
begin
  if not Assigned(FProgress) or not DownloadRunning then
    Exit;
  FProgress.SetProgress(ReceivedKB, TotalKB);
  if FProgress.Percent >= 0 then
    mniDownloadUpdate.Caption := Format(T('Загрузка версии %s: %d%%',
      'Downloading version %s: %d%%'), [FUpdateVersion, FProgress.Percent]);
end;

procedure TFormMain.DownloadCancel(Sender: TObject);
begin
  DiagnosticsLog('update.download_cancel_requested');
  if DownloadRunning then
    FDownloadThread.Terminate;
end;

procedure TFormMain.HandleDownloadResult(Res: TUpdateDownloadResult);
var
  PerMachine: Boolean;
begin
  try
    DiagnosticsLogFmt('update.download_done success=%s cancelled=%s error="%s"',
      [BoolToStr(Res.Success, True), BoolToStr(Res.Cancelled, True), Res.ErrorText]);
    FNotificationTimes.Remove('update_download');
    UpdateDownloadMenuCaption;
    if Res.Cancelled then
    begin
      if Assigned(FProgress) then
        FProgress.Close;
      FBalloonUrl := '';
      FBalloonInstall := False;
      ShowNotification('update_download', T('Загрузка обновления отменена.',
        'The update download was cancelled.'));
      Exit;
    end;
    if Res.Success and IsInstalledCopy(PerMachine) then
    begin
      if Assigned(FProgress) then
        FProgress.ShowInstalling;
    end;
    if Res.Success and IsInstalledCopy(PerMachine) and
       StartSilentInstaller(Res.FileName, PerMachine) then
    begin
      // The installer waits for this process to exit and then starts the
      // new version.
      DiagnosticsLog('update.installer_started');
      Application.Terminate;
      Exit;
    end;
    if Assigned(FProgress) then
      FProgress.Close;
    FBalloonUrl := FUpdateUrl;
    ShowNotification('update_download', T(
      'Не удалось установить обновление автоматически. Щёлкните, чтобы открыть ' +
      'страницу загрузки.',
      'Could not install the update automatically. Click to open the download page.'));
  finally
    Res.Free;
  end;
end;

initialization
  GShowSettingsMessage := RegisterWindowMessage('LayoutSwitcher.ShowSettings.v2');

end.
