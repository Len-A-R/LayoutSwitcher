unit uMain;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Grids, uProgramList, uAiExplain, uExplainWindow,
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
    tsLayout: TTabSheet;
    tsCorrections: TTabSheet;
    tsSnippets: TTabSheet;
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
    lblPrograms: TLabel;
    edProgramFilter: TEdit;
    chkProgramsCheckedOnly: TCheckBox;
    sgPrograms: TStringGrid;
    btnAddProgram: TButton;
    btnRemoveProgram: TButton;
    btnDefaultPrograms: TButton;
    lblStorage: TLabel;
    btnExport: TButton;
    btnImport: TButton;
    lblTranslate: TLabel;
    cbTranslate: TComboBox;
    lblWebSearch: TLabel;
    cbWebSearch: TComboBox;
    lblTranslateReplace: TLabel;
    cbTranslateReplace: TComboBox;
    lblExplain: TLabel;
    cbExplain: TComboBox;
    tsServices: TTabSheet;
    lblAiHeader: TLabel;
    lblAiService: TLabel;
    cbAiService: TComboBox;
    lblAiKey: TLabel;
    edAiKey: TEdit;
    lblAiUrl: TLabel;
    edAiUrl: TEdit;
    lblAiModel: TLabel;
    edAiModel: TEdit;
    lblAiNote: TLabel;
    btnAiTest: TButton;
    lblDeepLKey: TLabel;
    edDeepLKey: TEdit;
    lblTranslator: TLabel;
    cbTranslator: TComboBox;
    lblSearchEngine: TLabel;
    cbSearchEngine: TComboBox;
    chkFixCapsLock: TCheckBox;
    chkFixTwoCapitals: TCheckBox;
    lblTwoCapsExceptions: TLabel;
    memTwoCapsExceptions: TMemo;
    chkSnippets: TCheckBox;
    lblSnippetsHint: TLabel;
    memSnippets: TMemo;
    chkAutoReplace: TCheckBox;
    lblAutoReplaceHint: TLabel;
    memAutoReplace: TMemo;
    lblCorrectionsNote: TLabel;
    chkSound: TCheckBox;
    cbSound: TComboBox;
    btnSoundTest: TButton;
    chkAutoSwitch: TCheckBox;
    lblAutoSwitchHint: TLabel;
    chkFixTypos: TCheckBox;
    lblAutoSwitchExceptions: TLabel;
    memAutoSwitchExceptions: TMemo;
    chkInWordSwitch: TCheckBox;
    chkLearnManual: TCheckBox;
    lblAutoSwitchLearned: TLabel;
    memAutoSwitchLearned: TMemo;
    lblLayoutNote: TLabel;
    chkFixTyposExtended: TCheckBox;
    chkCapitalize: TCheckBox;
    chkDoubleSpace: TCheckBox;
    mniClipboard: TMenuItem;
    mniClipConvert: TMenuItem;
    mniClipUpper: TMenuItem;
    mniClipLower: TMenuItem;
    mniClipTranslit: TMenuItem;
    mniSeparator3: TMenuItem;
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
    procedure edProgramFilterChange(Sender: TObject);
    procedure chkProgramsCheckedOnlyClick(Sender: TObject);
    procedure sgProgramsDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect;
      State: TGridDrawState);
    procedure sgProgramsMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure sgProgramsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure sgProgramsSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure btnAddProgramClick(Sender: TObject);
    procedure btnRemoveProgramClick(Sender: TObject);
    procedure btnDefaultProgramsClick(Sender: TObject);
    procedure chkAutorunClick(Sender: TObject);
    procedure cbSoundChange(Sender: TObject);
    procedure cbAiServiceChange(Sender: TObject);
    procedure btnAiTestClick(Sender: TObject);
    procedure btnSoundTestClick(Sender: TObject);
    procedure chkAutorunElevatedClick(Sender: TObject);
    procedure chkDiagnosticsClick(Sender: TObject);
    procedure cbGestureChange(Sender: TObject);
    procedure edIntervalChange(Sender: TObject);
    procedure edIntervalExit(Sender: TObject);
    procedure chkBehaviorClick(Sender: TObject);
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
    // EN, RU and their grey copies for the paused state (ICON_*).
    FTrayIcons: array[0..3] of TIcon;

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
    FAutoReplace: TArray<TAutoReplace>;
    // Caps Lock state tracked from Raw Input: GetKeyState in this thread does
    // not see key messages of other applications.
    FCapsOn: Boolean;
    FCapsShiftLock: Boolean;
    FPendingAutomatic: Boolean;
    FSettleFocusNext: Boolean;
    // Process of the focused window (rules for programs).
    FLastProcessName: string;
    FAutoCorrectSkipLogged: string;
    // Word changed by the last automatic layout switch; an immediate undo
    // adds it to the exceptions.
    FAutoSwitchOriginal: string;
    FAutoSwitchResult: string;
    // The last automatic switch or typo fix, for the tray menu.
    FLastAutoWord: string;
    FLastAutoResult: string;
    // Manual conversion counted for learning; rolled back if the user widens
    // or reverts it right away.
    FLastLearnWord: string;
    FLastLearnPromoted: Boolean;
    // Options of the next QueueRequest.
    FCapitalizeNext: Boolean;
    FInWordNext: Boolean;
    FCaretBackNext: Integer;
    FPendingStamp: Integer;
    // The buffer was dropped in the middle of a word: the next space ends a
    // fragment, which must not be corrected.
    FPartialWord: Boolean;
    // Buffer right after a removed double space; one more space then means
    // the user wants the spaces.
    FDoubleSpaceNext: Boolean;
    FPendingDoubleSpace: Boolean;
    FDoubleSpaceFixed: string;
    // Automatic corrections off until then (tray menu), 0 when on.
    FAutoCorrectPausedUntil: TDateTime;
    FMenuQuickSeparator: TMenuItem;
    FMenuAutoCorrectOff: TMenuItem;
    FMenuNeverFixLast: TMenuItem;
    FMenuProgramRule: TMenuItem;
    // Exclusions table: programs found on the computer (read when the tab
    // is opened for the first time), all rows and the rows shown.
    FInstalledPrograms: TArray<TProgramEntry>;
    FProgramsLoaded: Boolean;
    FProgramScan: TProgramScanThread;
    // AI explanation window and the answer it waits for.
    FExplainWindow: TExplainWindow;
    FExplainSequence: Cardinal;
    FPrograms: TArray<TProgramEntry>;
    FVisiblePrograms: TArray<Integer>;
    FUpdateNotes: string;
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
    procedure CreateTrayIcons;

    procedure LoadControlsFromSettings;
    procedure ApplySettings;
    procedure EnsureProgramsLoaded;
    procedure RefreshProgramGrid;
    procedure SetupProgramGrid;
    procedure ToggleProgram(Row, Col: Integer);
    function ProgramAtRow(Row: Integer; out Entry: TProgramEntry): Boolean;
    procedure UpdateProgramButtons;
    procedure pcMainChange(Sender: TObject);
    procedure ProgramScanDone(Sender: TObject);
    function CurrentAiConfig: TAiConfig;
    procedure LoadAiControls;
    procedure ApplyAiFromEdit;
    procedure StartExplain(const Text: string);
    procedure ExplainDone(Sender: TObject);
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
    procedure OfferUpdate;
    procedure LearnAutoSwitchException(const Word, Converted: string);
    procedure CheckInWordSwitch;
    procedure CommitPendingEdits;
    procedure TrackManualConversion(Res: TOperationResult);
    function AutoCorrectionsPaused: Boolean;
    procedure CreateQuickMenu;
    procedure PopupMenuPopup(Sender: TObject);
    procedure QuickAutoCorrectOffClick(Sender: TObject);
    procedure QuickNeverFixLastClick(Sender: TObject);
    procedure QuickProgramRuleClick(Sender: TObject);
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
  Vcl.Imaging.pngimage, uTrayIconData,
  System.StrUtils,
  uDiagnostics, uWinUtils, uTaskAutorun, uLocale, uSettingsStore, uClipboardSnapshot,
  uSpellCheck, uInWordSwitch, Vcl.Themes, uSounds;

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
  // A word converted manually this many times is switched automatically.
  LEARN_AFTER_CONVERSIONS = 2;
  AUTO_CORRECT_OFF_MINUTES = 60;

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
  ICON_PAUSED = 2;  // + ICON_EN / ICON_RU
  LANG_EN = $0409;
  LANG_RU = $0419;

  ShortGestureNames: array[TLSGesture] of string = (
    '', 'Shift×2', 'LCtrl×2', 'RCtrl×2', 'Ctrl+Ctrl', 'Shift+Shift', 'Caps×2',
    'RAlt×2', 'LAlt×2', 'RCtrl+RAlt', 'Pause');
  AI_PROVIDER_FREE = 0;
  AI_PROVIDER_CLAUDE = 1;
  AI_PROVIDER_OPENAI = 2;

function ShortActionName(Action: TLSAction): string; forward;
function ContainsDigit(const Text: string): Boolean; forward;
function RemoveWord(const List: TArray<string>; const Word: string): TArray<string>; forward;

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
  FAutoReplace := ParseAutoReplace(FSettings.AutoReplace);
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

  CreateTrayIcons;
  CreateQuickMenu;
  SetupProgramGrid;
  pcMain.OnChange := pcMainChange;

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
  I: Integer;
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
  for I := Low(FTrayIcons) to High(FTrayIcons) do
    FreeAndNil(FTrayIcons[I]);
  // AI requests still running finish on their own; their results are ignored.
  FExplainSequence := 0;
  if Assigned(FProgramScan) then
  begin
    FProgramScan.OnTerminate := nil;
    FProgramScan.WaitFor;
    FreeAndNil(FProgramScan);
  end;
  FreeAndNil(FIndicator);
  FreeAndNil(FCatalog);
  FreeAndNil(FDetector);
  FreeAndNil(FChain);
  FreeAndNil(FNotificationTimes);
  DiagnosticsLog('form.destroy end');
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
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
    FSettleFocusNext := Gesture in [lgDoubleRAlt, lgDoubleLAlt, lgRCtrlRAlt];
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
  FLastProcessName := GetWindowProcessFileName(GetForegroundWindow);
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
    // Lock keys and Pause/Break (a gesture key) do not change the text.
    VK_CAPITAL, VK_NUMLOCK, VK_SCROLL, VK_PAUSE:
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
      CheckAutoCorrections
    else
      CheckInWordSwitch;
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
  FAutoSwitchOriginal := '';
  FLastLearnWord := '';
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
  FAutoSwitchOriginal := '';
  FLastLearnWord := '';
  if not FBufferOverflowed and (FBuffer <> '') then
    SetLength(FBuffer, Length(FBuffer) - 1);
end;

procedure TFormMain.ClearBuffer;
begin
  FBuffer := '';
  FBufferOverflowed := False;
  FPartialWord := False;
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
  if FBufferOverflowed or FFocusIsPassword then
    Plan := FChain.Plan(laNone, '')
  else if Action = laTranslateReplace then
    // A translation needs the whole phrase, not only the last word.
    Plan := TConversionChain.PlanPhrase(FBuffer)
  else
    Plan := FChain.Plan(Action, FBuffer);
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
  Request.AutoSwitchExceptions := FSettings.AutoSwitchExceptions;
  Request.AllowLayoutSwitch := FSettings.AutoSwitchEnabled;
  // The start of a word being typed is only ever switched, never "fixed".
  Request.AllowTypoFix := FSettings.FixTypos and not FInWordNext;
  Request.TypoExtended := Request.AllowTypoFix and FSettings.FixTyposExtended;
  Request.AutoSwitchLearned := FSettings.AutoSwitchLearned;
  Request.InWord := FInWordNext;
  Request.Capitalize := FCapitalizeNext and not FInWordNext;
  Request.CaretBack := FCaretBackNext;
  Request.DeepLApiKey := FSettings.DeepLApiKey;
  FPendingStamp := Request.KeystrokeStamp;
  FPendingDoubleSpace := FDoubleSpaceNext;
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

    if Res.Action in [laTranslate, laWebSearch, laExplain] then
    begin
      if Res.Success and (Res.Action = laExplain) then
        StartExplain(Res.LookupText)
      else if Res.Success then
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

    // Undoing an automatic layout switch right away teaches an exception.
    if Res.Success and (FAutoSwitchOriginal <> '') and
       (FPendingPlan.Mode in [bmUndo, bmRevert]) then
      LearnAutoSwitchException(FAutoSwitchOriginal, FAutoSwitchResult);
    if Res.Action <> laAutoSwitch then
      FAutoSwitchOriginal := '';
    if FSettings.SoundEnabled and Res.Success and (Res.BufferAction = baSet) then
      PlayFeedbackSound(FSettings.SoundKind, FSettings.SoundFile);

    if (Res.BufferAction = baSet) and FPendingAutomatic and
       (AtomicCmpExchange(GKeystrokeCount, 0, 0) <> FPendingStamp) then
    begin
      // Keys typed while the correction was applied follow the corrected
      // text (the buffer has them as they appeared on the screen).
      if StartsStr(FPendingPlan.Text, FBuffer) then
      begin
        SetBufferText(Res.NewBufferText + Copy(FBuffer, Length(FPendingPlan.Text) + 1, MaxInt));
        DiagnosticsLog('buffer.extended reason=typed_during_correction');
      end
      else
      begin
        ClearBuffer;
        FPartialWord := True;
        DiagnosticsLog('buffer.cleared reason=typed_during_correction');
      end;
    end
    else
      case Res.BufferAction of
        baClear: ClearBuffer;
        baSet: SetBufferText(Res.NewBufferText);
      end;
    if Res.Success and FPendingDoubleSpace then
      FDoubleSpaceFixed := FBuffer;
    // The last automatic change of a word, for "Never change" in the tray.
    if Res.Success and Res.UsedBuffer and (Res.Action = laAutoSwitch) and
       not Res.CapitalOnly then
    begin
      FLastAutoWord := FPendingPlan.Region;
      FLastAutoResult := Res.FixedWord;
    end;
    // Remember the step so that repeating the action widens it.
    if not Res.Success or (FBuffer = '') then
      FChain.Reset
    else if Res.UsedBuffer and (Res.TypoFixed or Res.CapitalOnly) then
    begin
      // Undo-able like the other corrections; double Shift converts as usual.
      FChain.Completed(FPendingPlan, laNone, FBuffer, 0, 0);
      if Res.TypoFixed then
      begin
        FAutoSwitchOriginal := FPendingPlan.Region;
        FAutoSwitchResult := Res.FixedWord;
        DiagnosticsLog('typo.applied');
      end
      else
        DiagnosticsLog('autocorrect.capitalized');
    end
    else if Res.UsedBuffer and (Res.Action = laAutoSwitch) then
    begin
      FChain.CompletedAutoSwitch(FPendingPlan, FBuffer, Res.SourceLayout,
        Res.TargetLayout);
      FAutoSwitchOriginal := FPendingPlan.Region;
      FAutoSwitchResult := Res.FixedWord;
      DiagnosticsLogFmt('autoswitch.applied learned=%s',
        [BoolToStr(Res.LearnedSwitch, True)]);
    end
    else if Res.UsedBuffer then
      FChain.Completed(FPendingPlan, Res.Action, FBuffer, Res.SourceLayout,
        Res.TargetLayout)
    else
      FChain.CompletedWhole(Res.Action, FBuffer, Res.OriginalText,
        Res.SourceLayout, Res.TargetLayout);
    if Res.Success and (Res.SourceLayout <> 0) then
      FPreviousLayout := Res.SourceLayout;
    if Res.Success and Res.UsedBuffer and not FPendingAutomatic then
      TrackManualConversion(Res);
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

function IconFromPng(Png: TPngImage): TIcon;
var
  Stream: TMemoryStream;
  Handle: HICON;
begin
  // Windows builds an icon directly from PNG data (Vista and later).
  Result := nil;
  Stream := TMemoryStream.Create;
  try
    Png.SaveToStream(Stream);
    Handle := CreateIconFromResourceEx(Stream.Memory, Stream.Size, True, $00030000,
      0, 0, LR_DEFAULTCOLOR);
    if Handle = 0 then
      Exit;
    Result := TIcon.Create;
    Result.Handle := Handle;
  finally
    Stream.Free;
  end;
end;

procedure MakePausedImage(Png: TPngImage);
type
  TRGB = packed record
    B, G, R: Byte;
  end;
  PRGBLine = ^TRGBLine;
  TRGBLine = array[0..32767] of TRGB;
  PAlphaLine = ^TAlphaLine;
  TAlphaLine = array[0..32767] of Byte;
var
  X, Y: Integer;
  Line: PRGBLine;
  Alpha: PAlphaLine;
  Gray: Byte;
begin
  // Grey and partly transparent (the PNG is 8-bit RGBA).
  for Y := 0 to Png.Height - 1 do
  begin
    Line := Png.Scanline[Y];
    Alpha := PAlphaLine(Png.AlphaScanline[Y]);
    for X := 0 to Png.Width - 1 do
    begin
      Gray := (Line[X].R * 30 + Line[X].G * 59 + Line[X].B * 11) div 100;
      Line[X].R := Gray;
      Line[X].G := Gray;
      Line[X].B := Gray;
      if Alpha <> nil then
        Alpha[X] := Alpha[X] * 160 div 255;
    end;
  end;
end;

procedure TFormMain.CreateTrayIcons;

  function LoadPng(const Data: array of Byte): TPngImage;
  var
    Stream: TMemoryStream;
  begin
    Result := TPngImage.Create;
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(Data[0], Length(Data));
      Stream.Position := 0;
      Result.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
  end;

var
  I: Integer;
  Png: TPngImage;
begin
  for I := ICON_EN to ICON_RU do
  try
    if I = ICON_EN then
      Png := LoadPng(TrayIconEnPng)
    else
      Png := LoadPng(TrayIconRuPng);
    try
      FTrayIcons[I] := IconFromPng(Png);
      MakePausedImage(Png);
      FTrayIcons[ICON_PAUSED + I] := IconFromPng(Png);
    finally
      Png.Free;
    end;
  except
    on E: Exception do
      DiagnosticsLogException('tray.icons', E);
  end;
end;

procedure TFormMain.UpdateTrayIcon(Force: Boolean);
var
  Target: HWND;
  Layout: HKL;
  LangID: Word;
  Index: Integer;
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
  if FPaused then
  begin
    if Index < 0 then
      Index := ICON_EN;
    Inc(Index, ICON_PAUSED);
  end;

  if (Index < 0) or (FTrayIcons[Index] = nil) then
  begin
    TrayIcon.Icon := Application.Icon;
    Exit;
  end;
  TrayIcon.Icon := FTrayIcons[Index];
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
  RefreshProgramGrid;
  LoadAiControls;
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
    cbTranslateReplace.ItemIndex := Ord(FSettings.GestureForAction(laTranslateReplace));
    cbExplain.ItemIndex := Ord(FSettings.GestureForAction(laExplain));
    edDeepLKey.Text := FSettings.DeepLApiKey;
    cbTranslator.ItemIndex := FSettings.Translator;
    cbSearchEngine.ItemIndex := FSettings.SearchEngine;
    chkFixCapsLock.Checked := FSettings.FixCapsLock;
    chkFixTwoCapitals.Checked := FSettings.FixTwoCapitals;
    memTwoCapsExceptions.Text := string.Join(sLineBreak, FSettings.TwoCapitalsExceptions);
    chkSnippets.Checked := FSettings.SnippetsEnabled;
    chkAutoReplace.Checked := FSettings.AutoReplaceEnabled;
    memAutoReplace.Text := FSettings.AutoReplace;
    chkSound.Checked := FSettings.SoundEnabled;
    cbSound.ItemIndex := FSettings.SoundKind;
    cbSound.Enabled := FSettings.SoundEnabled;
    btnSoundTest.Enabled := FSettings.SoundEnabled;
    chkAutoSwitch.Checked := FSettings.AutoSwitchEnabled;
    chkFixTypos.Checked := FSettings.FixTypos;
    chkFixTyposExtended.Checked := FSettings.FixTyposExtended;
    chkInWordSwitch.Checked := FSettings.InWordSwitch;
    chkLearnManual.Checked := FSettings.LearnManualConversions;
    memAutoSwitchLearned.Text := string.Join(sLineBreak, FSettings.AutoSwitchLearned);
    chkCapitalize.Checked := FSettings.CapitalizeSentences;
    chkDoubleSpace.Checked := FSettings.FixDoubleSpace;
    memAutoSwitchExceptions.Text := string.Join(sLineBreak, FSettings.AutoSwitchExceptions);
    memSnippets.Text := FSettings.Snippets;
    udInterval.Position := Integer(FSettings.DoubleTapInterval);
    edInterval.Text := IntToStr(FSettings.DoubleTapInterval);
    chkPauseFullscreen.Checked := FSettings.PauseInFullscreen;
    chkNotifications.Checked := FSettings.ShowNotifications;
    chkDisableStickyKeys.Checked := FSettings.DisableStickyKeysHotkey;
    chkLayoutIndicator.Checked := FSettings.ShowLayoutIndicator;
    chkCheckUpdates.Checked := FSettings.CheckForUpdates;
    cbLanguage.ItemIndex := Ord(FSettings.Language);
  finally
    FUpdatingControls := False;
  end;
end;

procedure TFormMain.ApplySettings;
begin
  FDetector.Interval := FSettings.DoubleTapInterval;
  FSnippets := ParseSnippets(FSettings.Snippets);
  FAutoReplace := ParseAutoReplace(FSettings.AutoReplace);
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
  FSettings.AutoReplaceEnabled := chkAutoReplace.Checked;
  FSettings.SoundEnabled := chkSound.Checked;
  cbSound.Enabled := FSettings.SoundEnabled;
  btnSoundTest.Enabled := FSettings.SoundEnabled;
  FSettings.AutoSwitchEnabled := chkAutoSwitch.Checked;
  FSettings.FixTypos := chkFixTypos.Checked;
  FSettings.FixTyposExtended := chkFixTyposExtended.Checked;
  FSettings.InWordSwitch := chkInWordSwitch.Checked;
  FSettings.LearnManualConversions := chkLearnManual.Checked;
  FSettings.CapitalizeSentences := chkCapitalize.Checked;
  FSettings.FixDoubleSpace := chkDoubleSpace.Checked;
  if not FSettings.ShowLayoutIndicator then
    FIndicator.HideNow;
  ApplySettings;
  ApplyStickyKeysSetting;
end;

{ Exclusions table }

const
  PROGRAM_COL_NAME = 0;
  PROGRAM_COL_EXE = 1;
  PROGRAM_COL_OFF = 2;
  PROGRAM_COL_NO_AUTO = 3;

procedure TFormMain.SetupProgramGrid;
var
  Fixed: Integer;
begin
  sgPrograms.ColCount := 4;
  sgPrograms.FixedCols := 0;
  sgPrograms.FixedRows := 1;
  sgPrograms.ColWidths[PROGRAM_COL_NAME] := MulDiv(196, CurrentPPI, 96);
  sgPrograms.ColWidths[PROGRAM_COL_EXE] := MulDiv(130, CurrentPPI, 96);
  sgPrograms.ColWidths[PROGRAM_COL_OFF] := MulDiv(70, CurrentPPI, 96);
  Fixed := sgPrograms.ColWidths[PROGRAM_COL_NAME] + sgPrograms.ColWidths[PROGRAM_COL_EXE] +
    sgPrograms.ColWidths[PROGRAM_COL_OFF] + 4 * sgPrograms.GridLineWidth +
    GetSystemMetrics(SM_CXVSCROLL);
  sgPrograms.ColWidths[PROGRAM_COL_NO_AUTO] := sgPrograms.ClientWidth - Fixed;
end;

procedure TFormMain.pcMainChange(Sender: TObject);
begin
  if pcMain.ActivePage = tsExclusions then
    EnsureProgramsLoaded;
end;

procedure TFormMain.EnsureProgramsLoaded;
begin
  if FProgramsLoaded then
    Exit;
  // The table shows the programs of the settings right away; the ones found
  // on the computer are added when the search (a few seconds) is done.
  FProgramsLoaded := True;
  edProgramFilter.TextHint := T('Идёт поиск программ на компьютере...',
    'Looking for programs on this computer...');
  FProgramScan := TProgramScanThread.Create(True);
  FProgramScan.OnTerminate := ProgramScanDone;
  FProgramScan.Start;
  RefreshProgramGrid;
end;

procedure TFormMain.ProgramScanDone(Sender: TObject);
begin
  // OnTerminate runs in the main thread.
  FInstalledPrograms := TProgramScanThread(Sender).Programs;
  DiagnosticsLogFmt('programs.loaded count=%d', [Length(FInstalledPrograms)]);
  edProgramFilter.TextHint := T('Поиск программы', 'Find a program');
  RefreshProgramGrid;
end;

function TFormMain.ProgramAtRow(Row: Integer; out Entry: TProgramEntry): Boolean;
begin
  Result := (Row >= 1) and (Row - 1 < Length(FVisiblePrograms));
  if Result then
    Entry := FPrograms[FVisiblePrograms[Row - 1]];
end;

procedure TFormMain.RefreshProgramGrid;
var
  Selected: string;
  Entry: TProgramEntry;
  I, Row: Integer;
begin
  if not FProgramsLoaded then
    Exit;
  Selected := '';
  if ProgramAtRow(sgPrograms.Row, Entry) then
    Selected := Entry.ExeName;
  FPrograms := MergePrograms(FInstalledPrograms, [FSettings.ExcludedProcesses,
    FSettings.NoAutoCorrectProcesses, FSettings.CustomPrograms]);
  FVisiblePrograms := nil;
  for I := 0 to High(FPrograms) do
    if ProgramMatches(FPrograms[I], edProgramFilter.Text) and
       (not chkProgramsCheckedOnly.Checked or
        FSettings.IsProcessExcluded(FPrograms[I].ExeName) or
        FSettings.IsAutoCorrectDisabledFor(FPrograms[I].ExeName)) then
      FVisiblePrograms := FVisiblePrograms + [I];
  // A grid with a fixed row needs at least one more row.
  if Length(FVisiblePrograms) = 0 then
    sgPrograms.RowCount := 2
  else
    sgPrograms.RowCount := Length(FVisiblePrograms) + 1;
  for Row := 1 to sgPrograms.RowCount - 1 do
    if ProgramAtRow(Row, Entry) then
    begin
      sgPrograms.Cells[PROGRAM_COL_NAME, Row] := Entry.DisplayName;
      sgPrograms.Cells[PROGRAM_COL_EXE, Row] := Entry.ExeName;
      if SameText(Entry.ExeName, Selected) then
        sgPrograms.Row := Row;
    end
    else
    begin
      sgPrograms.Cells[PROGRAM_COL_NAME, Row] := '';
      sgPrograms.Cells[PROGRAM_COL_EXE, Row] := '';
    end;
  sgPrograms.Invalidate;
  UpdateProgramButtons;
end;

procedure TFormMain.UpdateProgramButtons;
var
  Entry: TProgramEntry;
begin
  // Programs found on the computer stay in the table; only names added by
  // hand or coming from the settings can be removed.
  btnRemoveProgram.Enabled := ProgramAtRow(sgPrograms.Row, Entry) and not Entry.Installed;
end;

procedure TFormMain.sgProgramsDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect;
  State: TGridDrawState);
var
  Entry: TProgramEntry;
  Checked, Enabled: Boolean;
  Element: TThemedButton;
  Size: Integer;
  Box: TRect;
begin
  if (ARow = 0) or (ACol < PROGRAM_COL_OFF) or not ProgramAtRow(ARow, Entry) then
    Exit;
  if ACol = PROGRAM_COL_OFF then
  begin
    Checked := FSettings.IsProcessExcluded(Entry.ExeName);
    Enabled := True;
  end
  else
  begin
    Checked := FSettings.IsAutoCorrectDisabledFor(Entry.ExeName);
    // Nothing works in a program that is turned off completely.
    Enabled := not FSettings.IsProcessExcluded(Entry.ExeName);
  end;
  if Checked and Enabled then
    Element := tbCheckBoxCheckedNormal
  else if Checked then
    Element := tbCheckBoxCheckedDisabled
  else if Enabled then
    Element := tbCheckBoxUncheckedNormal
  else
    Element := tbCheckBoxUncheckedDisabled;
  Size := MulDiv(13, CurrentPPI, 96);
  Box := Bounds(Rect.Left + (Rect.Width - Size) div 2, Rect.Top + (Rect.Height - Size) div 2,
    Size, Size);
  StyleServices.DrawElement(sgPrograms.Canvas.Handle,
    StyleServices.GetElementDetails(Element), Box);
end;

procedure TFormMain.ToggleProgram(Row, Col: Integer);
var
  Entry: TProgramEntry;
begin
  if not ProgramAtRow(Row, Entry) then
    Exit;
  if Col = PROGRAM_COL_OFF then
  begin
    if FSettings.IsProcessExcluded(Entry.ExeName) then
      FSettings.ExcludedProcesses := RemoveWord(FSettings.ExcludedProcesses, Entry.ExeName)
    else
      FSettings.ExcludedProcesses := FSettings.ExcludedProcesses + [Entry.ExeName];
  end
  else if Col = PROGRAM_COL_NO_AUTO then
  begin
    if FSettings.IsAutoCorrectDisabledFor(Entry.ExeName) then
      FSettings.NoAutoCorrectProcesses :=
        RemoveWord(FSettings.NoAutoCorrectProcesses, Entry.ExeName)
    else
      FSettings.NoAutoCorrectProcesses := FSettings.NoAutoCorrectProcesses + [Entry.ExeName];
  end
  else
    Exit;
  ApplySettings;
  // The row stays visible even with "only checked": it disappears when the
  // filter is applied again, not under the mouse.
  sgPrograms.Invalidate;
end;

procedure TFormMain.sgProgramsMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Col, Row: Integer;
begin
  if Button <> mbLeft then
    Exit;
  sgPrograms.MouseToCell(X, Y, Col, Row);
  if (Row > 0) and (Col >= PROGRAM_COL_OFF) then
    ToggleProgram(Row, Col);
end;

procedure TFormMain.sgProgramsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (sgPrograms.Col >= PROGRAM_COL_OFF) then
  begin
    ToggleProgram(sgPrograms.Row, sgPrograms.Col);
    Key := 0;
  end;
end;

procedure TFormMain.sgProgramsSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
var
  Entry: TProgramEntry;
begin
  btnRemoveProgram.Enabled := ProgramAtRow(ARow, Entry) and not Entry.Installed;
end;

procedure TFormMain.edProgramFilterChange(Sender: TObject);
begin
  RefreshProgramGrid;
end;

procedure TFormMain.chkProgramsCheckedOnlyClick(Sender: TObject);
begin
  RefreshProgramGrid;
end;

procedure TFormMain.btnAddProgramClick(Sender: TObject);
var
  Dialog: TOpenDialog;
  Exe: string;
  Entry: TProgramEntry;
  Row: Integer;
begin
  EnsureProgramsLoaded;
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := T('Выберите программу или введите имя её exe-файла',
      'Choose a program or type the name of its exe file');
    Dialog.Filter := T('Программы', 'Programs') + ' (*.exe)|*.exe|' +
      T('Все файлы', 'All files') + ' (*.*)|*.*';
    // A name typed for a program that is not on this computer is accepted.
    Dialog.Options := [ofHideReadOnly, ofEnableSizing, ofNoValidate];
    if not Dialog.Execute(Handle) then
      Exit;
    Exe := Trim(ExtractFileName(Dialog.FileName));
  finally
    Dialog.Free;
  end;
  if Exe = '' then
    Exit;
  if ExtractFileExt(Exe) = '' then
    Exe := Exe + '.exe';
  if not SameText(ExtractFileExt(Exe), '.exe') then
  begin
    MessageBox(Handle, PChar(T('Укажите exe-файл программы.', 'Choose the exe file of a program.')),
      'LayoutSwitcher', MB_OK or MB_ICONWARNING);
    Exit;
  end;
  if not (FSettings.IsProcessExcluded(Exe) or FSettings.IsAutoCorrectDisabledFor(Exe)) then
  begin
    FSettings.CustomPrograms := RemoveWord(FSettings.CustomPrograms, Exe) + [Exe];
    ApplySettings;
  end;
  DiagnosticsLogFmt('programs.added process="%s"', [Exe]);
  edProgramFilter.Text := '';
  chkProgramsCheckedOnly.Checked := False;
  RefreshProgramGrid;
  for Row := 1 to sgPrograms.RowCount - 1 do
    if ProgramAtRow(Row, Entry) and SameText(Entry.ExeName, Exe) then
    begin
      sgPrograms.Row := Row;
      sgPrograms.Col := PROGRAM_COL_OFF;
      Break;
    end;
  UpdateProgramButtons;
  sgPrograms.SetFocus;
end;

procedure TFormMain.btnRemoveProgramClick(Sender: TObject);
var
  Entry: TProgramEntry;
begin
  if not ProgramAtRow(sgPrograms.Row, Entry) or Entry.Installed then
    Exit;
  FSettings.CustomPrograms := RemoveWord(FSettings.CustomPrograms, Entry.ExeName);
  FSettings.ExcludedProcesses := RemoveWord(FSettings.ExcludedProcesses, Entry.ExeName);
  FSettings.NoAutoCorrectProcesses := RemoveWord(FSettings.NoAutoCorrectProcesses,
    Entry.ExeName);
  DiagnosticsLogFmt('programs.removed process="%s"', [Entry.ExeName]);
  ApplySettings;
  RefreshProgramGrid;
end;

procedure TFormMain.btnDefaultProgramsClick(Sender: TObject);
begin
  if MessageBox(Handle, PChar(T(
       'Вернуть исходные отметки «Отключить» и «Без автоисправлений»? Отметки, сделанные вручную, будут сброшены.',
       'Restore the default "Turn off" and "No automatic corrections" marks? Marks made by hand are reset.')),
       'LayoutSwitcher', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  FSettings.ExcludedProcesses := TLSSettings.Defaults.ExcludedProcesses;
  FSettings.NoAutoCorrectProcesses := TLSSettings.Defaults.NoAutoCorrectProcesses;
  ApplySettings;
  RefreshProgramGrid;
end;

procedure TFormMain.cbSoundChange(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if FUpdatingControls or (cbSound.ItemIndex < 0) then
    Exit;
  if cbSound.ItemIndex = SOUND_FILE then
  begin
    Dialog := TOpenDialog.Create(nil);
    try
      Dialog.Title := T('Звук при исправлении текста', 'Sound when text is corrected');
      Dialog.Filter := T('Звуки WAV', 'WAV sounds') + ' (*.wav)|*.wav';
      Dialog.Options := [ofHideReadOnly, ofEnableSizing, ofFileMustExist];
      if FSettings.SoundFile <> '' then
        Dialog.FileName := FSettings.SoundFile
      else
        Dialog.InitialDir := GetEnvironmentVariable('WINDIR') + '\Media';
      if not Dialog.Execute(Handle) then
      begin
        // Cancelled: back to the previous choice.
        if FSettings.SoundFile = '' then
          cbSound.ItemIndex := SOUND_CLICK
        else if FSettings.SoundKind <> SOUND_FILE then
          cbSound.ItemIndex := FSettings.SoundKind;
        Exit;
      end;
      FSettings.SoundFile := Dialog.FileName;
    finally
      Dialog.Free;
    end;
  end;
  FSettings.SoundKind := cbSound.ItemIndex;
  ApplySettings;
  // The combo shows the file name of the own sound.
  ApplyLanguage;
  LoadControlsFromSettings;
  PlayFeedbackSound(FSettings.SoundKind, FSettings.SoundFile);
end;

procedure TFormMain.btnSoundTestClick(Sender: TObject);
begin
  PlayFeedbackSound(FSettings.SoundKind, FSettings.SoundFile);
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
  if pcMain.ActivePage = tsExclusions then
    EnsureProgramsLoaded;
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
    laTranslateReplace: Result := T('Замена переводом', 'Translate in place');
    laExplain: Result := T('ИИ', 'AI');
    laTransliterate: Result := T('Транслит', 'Translit');
    laUndo: Result := T('Отмена', 'Undo');
  else
    Result := '';
  end;
end;

function TFormMain.GestureCombos: TArray<TComboBox>;
begin
  Result := [cbConvert, cbUpper, cbLower, cbInvert, cbTranslit, cbUndo, cbTranslate,
    cbWebSearch, cbTranslateReplace, cbExplain];
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
    tsLayout.Caption := T('Раскладка', 'Layout');
    tsCorrections.Caption := T('Исправления', 'Corrections');
    tsSnippets.Caption := T('Замены', 'Replacements');
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
    chkSound.Caption := T('Звук при исправлении текста:', 'Sound when text is corrected:');
    if FSettings.SoundFile <> '' then
      FillCombo(cbSound, [T('Щелчок', 'Click'), T('Тук', 'Knock'), T('Капля', 'Drop'),
        T('Колокольчик', 'Bell'), T('Пузырёк', 'Bubble'),
        T('Свой: ', 'Own: ') + ExtractFileName(FSettings.SoundFile)])
    else
      FillCombo(cbSound, [T('Щелчок', 'Click'), T('Тук', 'Knock'), T('Капля', 'Drop'),
        T('Колокольчик', 'Bell'), T('Пузырёк', 'Bubble'), T('Свой WAV-файл...', 'Own WAV file...')]);
    btnSoundTest.Hint := T('Прослушать', 'Listen');
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
    lblTranslateReplace.Caption := ActionName(laTranslateReplace);
    lblExplain.Caption := ActionName(laExplain);
    tsServices.Caption := T('Сервисы', 'Services');
    lblAiHeader.Caption := T('Объяснение выделенного текста с помощью ИИ', 'Explaining the selection with AI');
    lblAiService.Caption := T('Сервис ИИ:', 'AI service:');
    FillCombo(cbAiService, [T('Pollinations.ai — бесплатно, без регистрации',
      'Pollinations.ai - free, no registration'), T('Anthropic Claude (ключ API)',
      'Anthropic Claude (API key)'), T('Совместимый с OpenAI (OpenAI, OpenRouter, Ollama...)',
      'OpenAI-compatible (OpenAI, OpenRouter, Ollama...)')]);
    lblAiKey.Caption := T('Ключ API:', 'API key:');
    lblAiUrl.Caption := T('Адрес API:', 'API address:');
    lblAiModel.Caption := T('Модель:', 'Model:');
    btnAiTest.Caption := T('Проверить', 'Test');
    lblDeepLKey.Caption := T('Ключ DeepL API для замены переводом:', 'DeepL API key for translating in place:');
    edDeepLKey.TextHint := T('необязательно; без ключа — Google Переводчик',
      'optional; Google Translate without a key');
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

    chkAutoSwitch.Caption := T(
      'Автоматически переключать раскладку для слов, набранных не в той раскладке',
      'Automatically fix words typed in the wrong keyboard layout');
    lblAutoSwitchHint.Caption := T('Решает проверка орфографии Windows.',
      'The Windows spell checker decides.');
    chkInWordSwitch.Caption := T(
      'Переключать уже во время набора — по невозможному началу слова (ghb → при)',
      'Switch while typing - when the start of a word is impossible (рудд → hell)');
    chkLearnManual.Caption := T(
      'Запоминать слова, дважды исправленные вручную, и дальше переключать их сами',
      'Remember words fixed manually twice and switch them automatically');
    lblAutoSwitchLearned.Caption := T('Всегда переключать (слово в строке):',
      'Always switch (one word per line):');
    lblAutoSwitchExceptions.Caption := T('Не исправлять (слово в строке):',
      'Never change (one word per line):');
    lblLayoutNote.Caption := T(
      'Ошибочное переключение отменяется двойным Shift или двойным Caps Lock — слово' +
      sLineBreak + 'попадает в список «Не исправлять». «Не исправлять» действует и на опечатки.',
      'Undo a wrong switch with a double Shift or a double Caps Lock: the word is added' +
      sLineBreak + 'to "Never change". "Never change" also applies to typo fixes.');
    chkFixTypos.Caption := T(
      'Исправлять опечатки: переставленные соседние буквы (пирвет → привет)',
      'Fix typos: swapped neighbouring letters (teh → the)');
    chkFixTyposExtended.Caption := T(
      'А также пропущенную, лишнюю или заменённую букву (превет → привет)',
      'Also a missing, extra or replaced letter (wrold → world)');
    chkCapitalize.Caption := T('Заглавная буква в начале предложения (. привет → . Привет)',
      'Capital letter at the start of a sentence (. hello → . Hello)');
    chkDoubleSpace.Caption := T('Убирать случайный двойной пробел',
      'Remove an accidental double space');
    chkFixCapsLock.Caption := T(
      'Исправлять слова, набранные с включённым Caps Lock (пРИВЕТ → Привет)',
      'Fix words typed with Caps Lock on (hELLO → Hello)');
    chkFixTwoCapitals.Caption := T(
      'Исправлять две заглавные буквы в начале слова (ПРивет → Привет)',
      'Fix two capitals at the start of a word (HEllo → Hello)');
    lblTwoCapsExceptions.Caption := T('Исключения для двух заглавных (слово в строке):',
      'Exceptions for two capitals (one word per line):');
    chkAutoReplace.Caption := T(
      'Автоцензура: заменять слова по справочнику (грубые — на мягкие или на смайлики)',
      'Auto-censor: replace words from a list (rude ones with milder words or emoji)');
    lblAutoReplaceHint.Caption := T(
      'Каждая строка: слово=замена. * в конце слова — любое окончание (чёрт*=ой).' + sLineBreak +
      'Регистр не важен и сохраняется: Чёрт! → Ой!',
      'One per line: word=replacement. * at the end - any ending (heck*=oh).' + sLineBreak +
      'Case does not matter and is kept: Heck! -> Oh!');
    chkSnippets.Caption := T('Заменять шаблоны: сокращение и пробел',
      'Expand templates: abbreviation followed by a space');
    lblSnippetsHint.Caption := T(
      'Каждая строка: сокращение=текст. Подстановки: {date}, {time}, {datetime},' + sLineBreak +
      '{clipboard} — текст из буфера обмена, {cursor} — где оставить курсор.' + sLineBreak +
      '\n — новая строка, \t — табуляция, \\ — обратная косая черта.',
      'One per line: abbreviation=text. Placeholders: {date}, {time}, {datetime},' + sLineBreak +
      '{clipboard} - the clipboard text, {cursor} - where to leave the caret.' + sLineBreak +
      '\n - new line, \t - tab, \\ - backslash.');
    lblCorrectionsNote.Caption := T(
      'Исправления выполняются после пробела. Отменить последнее — двойной Caps Lock.' +
      sLineBreak + 'Не работают в программах из списка «Без автоисправлений» на вкладке «Исключения».',
      'Corrections are made after a space. Undo the last one with a double Caps Lock.' +
      sLineBreak + 'They are off in the programs listed on the Exclusions tab.');

    lblPrograms.Caption := T(
      '«Отключить» — LayoutSwitcher не делает в программе ничего. «Без автоисправлений» —' +
      sLineBreak + 'работают только ручные действия (двойной Shift и другие жесты).',
      '"Turn off": LayoutSwitcher does nothing in the program. "No auto": only the' +
      sLineBreak + 'manual actions (double Shift and the other gestures) work.');
    if not Assigned(FProgramScan) or FProgramScan.Finished then
      edProgramFilter.TextHint := T('Поиск программы', 'Find a program');
    chkProgramsCheckedOnly.Caption := T('Только отмеченные', 'Only checked');
    sgPrograms.Cells[PROGRAM_COL_NAME, 0] := T('Программа', 'Program');
    sgPrograms.Cells[PROGRAM_COL_EXE, 0] := T('Файл', 'File');
    sgPrograms.Cells[PROGRAM_COL_OFF, 0] := T('Отключить', 'Turn off');
    sgPrograms.Cells[PROGRAM_COL_NO_AUTO, 0] := T('Без автоиспр.', 'No auto');
    btnAddProgram.Caption := T('Добавить программу...', 'Add a program...');
    btnRemoveProgram.Caption := T('Убрать из списка', 'Remove');
    btnDefaultPrograms.Caption := T('По умолчанию', 'Defaults');
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
      FUpdateNotes := Res.ReleaseNotes;
      // One-click installation only for a copy put there by the installer;
      // a copy run from elsewhere would be duplicated, not updated.
      FUpdateInstallable := (FInstallerUrl <> '') and IsInstalledCopy(PerMachine);
      UpdateDownloadMenuCaption;
      mniDownloadUpdate.Visible := True;
      // A click shows what is new and then installs or opens the page.
      FBalloonInstall := True;
      FBalloonUrl := '';
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

procedure TFormMain.OfferUpdate;
begin
  if DownloadRunning then
  begin
    FProgress.ShowWindow;
    Exit;
  end;
  if FUpdateVersion = '' then
    Exit;
  if not ShowReleaseNotes(FUpdateVersion, FUpdateNotes, FUpdateInstallable) then
    Exit;
  if FUpdateInstallable then
    StartUpdateInstall
  else if FUpdateUrl <> '' then
    ShellExecute(0, 'open', PChar(FUpdateUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TFormMain.mniDownloadUpdateClick(Sender: TObject);
begin
  OfferUpdate;
end;

procedure TFormMain.TrayIconBalloonClick(Sender: TObject);
begin
  if FBalloonInstall then
    OfferUpdate
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

function TFormMain.AutoCorrectionsPaused: Boolean;
begin
  Result := (FAutoCorrectPausedUntil <> 0) and (Now < FAutoCorrectPausedUntil);
end;

procedure TFormMain.CheckAutoCorrections;
var
  WordStart, WordLength, CaretBack: Integer;
  Word, Template, Replacement, Fixed, Clip: string;
  ToggleCaps, Capital, IsTemplate, IsAutoReplace: Boolean;
begin
  // The word before this space was typed partly before the buffer was
  // dropped: only its end is known.
  if FPartialWord then
  begin
    FPartialWord := False;
    Exit;
  end;
  if FPaused or FBufferOverflowed or FFocusIsPassword or FOperationBusy then
    Exit;
  if AutoCorrectionsPaused then
    Exit;
  if not (FSettings.FixCapsLock or FSettings.FixTwoCapitals or FSettings.AutoSwitchEnabled or
          FSettings.FixTypos or FSettings.CapitalizeSentences or FSettings.FixDoubleSpace or
          (FSettings.SnippetsEnabled and (Length(FSnippets) > 0)) or
          (FSettings.AutoReplaceEnabled and (Length(FAutoReplace) > 0))) then
    Exit;
  // Code editors, terminals, password managers: manual actions only.
  if FSettings.IsAutoCorrectDisabledFor(FLastProcessName) then
  begin
    // Logged once per program, so that "nothing happens" can be explained.
    if not SameText(FAutoCorrectSkipLogged, FLastProcessName) then
    begin
      FAutoCorrectSkipLogged := FLastProcessName;
      DiagnosticsLogFmt('autocorrect.skipped reason=program_rule process="%s"',
        [FLastProcessName]);
    end;
    Exit;
  end;

  // "word  ": the second space was typed by accident.
  if FSettings.FixDoubleSpace and EndsWithDoubleSpace(FBuffer) then
  begin
    // A space typed again right after the fix: the spaces are wanted.
    if (FDoubleSpaceFixed <> '') and (FBuffer = FDoubleSpaceFixed + ' ') then
    begin
      FDoubleSpaceFixed := '';
      Exit;
    end;
    DiagnosticsLog('autocorrect.queue kind=double_space');
    FDoubleSpaceNext := True;
    try
      QueueRequest(laNone, TConversionChain.PlanReplacement(FBuffer, Length(FBuffer) - 1,
        2, ' '), True, False);
    finally
      FDoubleSpaceNext := False;
    end;
    Exit;
  end;

  // Exactly one space has just been typed after the word.
  if not FindLastWord(FBuffer, WordStart, WordLength) or
     (WordStart + WordLength <> Length(FBuffer)) then
    Exit;
  Word := Copy(FBuffer, WordStart, WordLength);
  Capital := FSettings.CapitalizeSentences and
    IsSentenceStart(Copy(FBuffer, 1, WordStart - 1));

  Replacement := '';
  Template := '';
  ToggleCaps := False;
  CaretBack := 0;
  IsAutoReplace := False;
  IsTemplate := FSettings.SnippetsEnabled and FindSnippet(FSnippets, Word, Template);
  if IsTemplate then
  begin
    Clip := '';
    if SnippetUsesClipboard(Template) then
      Clip := ReadClipboardText(Handle);
    Replacement := ExpandSnippet(Template, Now, Clip, CaretBack);
    if Replacement = '' then
      Exit;
    // A template is inserted exactly as written.
    Capital := False;
  end
  else if FSettings.AutoReplaceEnabled and ApplyAutoReplace(FAutoReplace, Word, Fixed) then
  begin
    Replacement := Fixed;
    IsAutoReplace := True;
  end
  else if FSettings.FixCapsLock and FCapsOn and IsCapsLockMistake(Word) then
  begin
    Replacement := FixCapsLockMistake(Word);
    ToggleCaps := True;
  end
  else if FSettings.FixTwoCapitals and
     FixTwoCapitals(Word, FSettings.TwoCapitalsExceptions, Fixed) then
    Replacement := Fixed;

  if Replacement = '' then
  begin
    // Nothing else to fix: the spell checker decides about the layout and
    // typos; the worker also capitalises the first word of a sentence.
    if (FSettings.AutoSwitchEnabled or FSettings.FixTypos) and not ContainsDigit(Word) then
    begin
      FCapitalizeNext := Capital;
      try
        QueueRequest(laAutoSwitch, TConversionChain.PlanWord(FBuffer, WordStart,
          WordLength), True, False);
      finally
        FCapitalizeNext := False;
      end;
    end
    else if Capital and CanCapitalize(Word) then
    begin
      DiagnosticsLog('autocorrect.queue kind=capital');
      QueueRequest(laNone, TConversionChain.PlanReplacement(FBuffer, WordStart,
        WordLength, CapitalizeFirst(Word)), True, False);
    end;
    Exit;
  end;
  if Capital and CanCapitalize(Replacement) then
    Replacement := CapitalizeFirst(Replacement);
  if Replacement = Word then
    Exit;

  DiagnosticsLogFmt('autocorrect.queue kind=%s length=%d caret_back=%d',
    [IfThen(ToggleCaps, 'caps_lock', IfThen(IsTemplate, 'template',
       IfThen(IsAutoReplace, 'auto_replace', 'two_capitals'))),
     Length(Word), CaretBack]);
  FCaretBackNext := CaretBack;
  try
    QueueRequest(laNone, TConversionChain.PlanReplacement(FBuffer, WordStart,
      WordLength, Replacement), True, ToggleCaps);
  finally
    FCaretBackNext := 0;
  end;
end;

procedure TFormMain.CheckInWordSwitch;
var
  WordStart, Len: Integer;
  Typed, Converted, Item: string;
  Focus: HWND;
  Layout: HKL;
  Pair: TLayoutPair;
  Plan: TBufferPlan;
begin
  if not (FSettings.AutoSwitchEnabled and FSettings.InWordSwitch) then
    Exit;
  if FPaused or FBufferOverflowed or FFocusIsPassword or FOperationBusy or FPartialWord or
     AutoCorrectionsPaused or FSettings.IsAutoCorrectDisabledFor(FLastProcessName) then
    Exit;
  // The word being typed: from the last space to the end of the buffer.
  WordStart := Length(FBuffer);
  while (WordStart > 1) and not CharInSet(FBuffer[WordStart - 1], [' ', #9, #$00A0]) do
    Dec(WordStart);
  Len := Length(FBuffer) - WordStart + 1;
  if (Len < 3) or (Len > 4) then
    Exit;
  Typed := Copy(FBuffer, WordStart, Len);

  Focus := GetFocusedWindow;
  if Focus = 0 then
    Exit;
  Layout := GetKeyboardLayout(GetWindowThreadProcessId(Focus, nil));
  if not FCatalog.ChoosePair(Typed, Layout, FPreviousLayout, Pair) or
     (Pair.Source <> Layout) then
    Exit;
  Converted := ConvertTextBetweenLayouts(Typed, FCatalog.KeyChars(Pair.Source),
    FCatalog.KeyChars(Pair.Target));
  if not ShouldSwitchInWord(WordStartLanguage(LayoutLanguageTag(Pair.Source)),
       WordStartLanguage(LayoutLanguageTag(Pair.Target)), Typed, Converted) then
    Exit;
  // "ghbdtn" in "Never change" keeps every word typed as "ghb..." intact;
  // an undone in-word switch adds the prefix itself.
  for Item in FSettings.AutoSwitchExceptions do
    if StartsText(Typed, Item) or StartsText(Item, Typed) then
      Exit;

  Plan := TConversionChain.PlanWord(FBuffer, WordStart, Len);
  Plan.ForcedSource := Pair.Source;
  Plan.ForcedTarget := Pair.Target;
  DiagnosticsLogFmt('autoswitch.in_word_queue length=%d', [Len]);
  FInWordNext := True;
  try
    QueueRequest(laAutoSwitch, Plan, True, False);
  finally
    FInWordNext := False;
  end;
end;

procedure TFormMain.TrackManualConversion(Res: TOperationResult);
var
  Word: string;
  Count: Integer;
begin
  // Reverting or undoing right after a counted conversion: it was not what
  // the user wanted.  Widening to the phrase keeps it (the word was right).
  if (FLastLearnWord <> '') and (FPendingPlan.Mode in [bmRevert, bmUndo]) then
  begin
    if FLastLearnPromoted then
    begin
      CommitPendingEdits;
      FSettings.AutoSwitchLearned := RemoveWord(FSettings.AutoSwitchLearned, FLastLearnWord);
      // Back to the count before the conversion that taught it.
      BumpLearnCount(FSettings.AutoSwitchLearnCounts, FLastLearnWord,
        LEARN_AFTER_CONVERSIONS - 1);
    end
    else
      BumpLearnCount(FSettings.AutoSwitchLearnCounts, FLastLearnWord, -1);
    DiagnosticsLog('learn.rolled_back');
    ApplySettings;
    if FLastLearnPromoted then
      LoadControlsFromSettings;
    FLastLearnWord := '';
    FLastLearnPromoted := False;
    Exit;
  end;
  if FPendingPlan.Mode = bmPhrase then
    Exit;
  FLastLearnWord := '';
  FLastLearnPromoted := False;
  if (Res.Action <> laConvert) or (FPendingPlan.Mode <> bmWord) or
     not FSettings.AutoSwitchEnabled or not FSettings.LearnManualConversions then
    Exit;
  // The word as it reads now ("привет"), the same length as the typed one.
  Word := Copy(FBuffer, FPendingPlan.RegionStart, FPendingPlan.RegionLength);
  if not IsAutoSwitchCandidate(Word) or FSettings.IsAutoSwitchException(Word) or
     FSettings.IsAutoSwitchLearned(Word) then
    Exit;
  Count := BumpLearnCount(FSettings.AutoSwitchLearnCounts, Word, 1);
  FLastLearnWord := Word;
  if Count >= LEARN_AFTER_CONVERSIONS then
  begin
    CommitPendingEdits;
    BumpLearnCount(FSettings.AutoSwitchLearnCounts, Word, -Count);
    FSettings.AutoSwitchLearned := FSettings.AutoSwitchLearned + [AnsiLowerCase(Word)];
    FLastLearnPromoted := True;
    DiagnosticsLog('learn.word_learned');
    FBalloonUrl := '';
    FBalloonInstall := False;
    FNotificationTimes.Remove('learned');
    ShowNotification('learned', Format(T(
      'Слово «%s» теперь будет переключаться автоматически. Список — «Всегда переключать» на вкладке «Раскладка».',
      'The word "%s" will now be switched automatically. See "Always switch" on the Layout tab.'),
      [AnsiLowerCase(Word)]));
  end;
  ApplySettings;
  // Only the "Always switch" list is visible; the counts are not.
  if FLastLearnPromoted then
    LoadControlsFromSettings;
end;

function ContainsDigit(const Text: string): Boolean;
var
  Ch: Char;
begin
  for Ch in Text do
    if CharInSet(Ch, ['0'..'9']) then
      Exit(True);
  Result := False;
end;

function RemoveWord(const List: TArray<string>; const Word: string): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in List do
    if not AnsiSameText(Item, Word) then
      Result := Result + [Item];
end;

procedure TFormMain.CommitPendingEdits;
begin
  // Edits are saved on leaving the field; switching to another program does
  // not leave it.  Save them before the lists are reloaded from FSettings.
  if not Visible then
    Exit;
  ApplyCorrectionsFromEdit;
end;

procedure TFormMain.LearnAutoSwitchException(const Word, Converted: string);
begin
  if Word = '' then
    Exit;
  CommitPendingEdits;
  // A learned word that turns out unwanted is forgotten as well.
  if (Converted <> '') and FSettings.IsAutoSwitchLearned(Converted) then
    FSettings.AutoSwitchLearned := RemoveWord(FSettings.AutoSwitchLearned, Converted);
  if not FSettings.IsAutoSwitchException(Word) then
    FSettings.AutoSwitchExceptions := FSettings.AutoSwitchExceptions + [Word];
  ApplySettings;
  LoadControlsFromSettings;
  DiagnosticsLog('autoswitch.exception_learned');
  FBalloonUrl := '';
  FBalloonInstall := False;
  FNotificationTimes.Remove('autoswitch_learned');
  ShowNotification('autoswitch_learned', Format(T(
    'Слово «%s» больше не будет исправляться автоматически.',
    'The word "%s" will no longer be changed automatically.'), [Word]));
end;

{ Quick actions in the tray menu }

procedure TFormMain.CreateQuickMenu;
var
  Index: Integer;

  function AddItem(Handler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(PopupMenu);
    Result.OnClick := Handler;
    PopupMenu.Items.Insert(Index, Result);
    Inc(Index);
  end;

begin
  // After the pause items, before the update items.
  Index := PopupMenu.Items.IndexOf(mniSeparator2);
  if Index < 0 then
    Index := PopupMenu.Items.Count;
  FMenuQuickSeparator := AddItem(nil);
  FMenuQuickSeparator.Caption := '-';
  FMenuAutoCorrectOff := AddItem(QuickAutoCorrectOffClick);
  FMenuNeverFixLast := AddItem(QuickNeverFixLastClick);
  FMenuProgramRule := AddItem(QuickProgramRuleClick);
  PopupMenu.OnPopup := PopupMenuPopup;
end;

procedure TFormMain.PopupMenuPopup(Sender: TObject);
var
  Program_: string;
begin
  if AutoCorrectionsPaused then
    FMenuAutoCorrectOff.Caption := Format(T('Включить автоисправления (выключены до %s)',
      'Turn automatic corrections on (off until %s)'),
      [FormatDateTime('hh:nn', FAutoCorrectPausedUntil)])
  else
    FMenuAutoCorrectOff.Caption := T('Выключить автоисправления на 1 час',
      'Turn automatic corrections off for 1 hour');

  FMenuNeverFixLast.Visible := FLastAutoWord <> '';
  if FLastAutoResult <> '' then
    FMenuNeverFixLast.Caption := Format(T('Не исправлять «%s» (→ %s)',
      'Never change "%s" (-> %s)'), [FLastAutoWord, FLastAutoResult])
  else
    FMenuNeverFixLast.Caption := Format(T('Не исправлять «%s»', 'Never change "%s"'),
      [FLastAutoWord]);

  // The program the user typed in last; the tray itself has the focus now.
  Program_ := FLastProcessName;
  FMenuProgramRule.Visible := (Program_ <> '') and
    not SameText(Program_, ExtractFileName(ParamStr(0)));
  FMenuProgramRule.Checked := FSettings.IsAutoCorrectDisabledFor(Program_);
  FMenuProgramRule.Caption := Format(T('Без автоисправлений в %s',
    'No automatic corrections in %s'), [Program_]);
end;

procedure TFormMain.QuickAutoCorrectOffClick(Sender: TObject);
begin
  if AutoCorrectionsPaused then
    FAutoCorrectPausedUntil := 0
  else
    FAutoCorrectPausedUntil := IncMinute(Now, AUTO_CORRECT_OFF_MINUTES);
  DiagnosticsLogFmt('autocorrect.paused until=%s',
    [IfThen(FAutoCorrectPausedUntil = 0, 'none',
      FormatDateTime('hh:nn', FAutoCorrectPausedUntil))]);
end;

procedure TFormMain.QuickNeverFixLastClick(Sender: TObject);
begin
  if FLastAutoWord = '' then
    Exit;
  LearnAutoSwitchException(FLastAutoWord, FLastAutoResult);
  FLastAutoWord := '';
  FLastAutoResult := '';
end;

procedure TFormMain.QuickProgramRuleClick(Sender: TObject);
var
  Program_: string;
begin
  Program_ := FLastProcessName;
  if Program_ = '' then
    Exit;
  CommitPendingEdits;
  if FSettings.IsAutoCorrectDisabledFor(Program_) then
    FSettings.NoAutoCorrectProcesses := RemoveWord(FSettings.NoAutoCorrectProcesses, Program_)
  else
    FSettings.NoAutoCorrectProcesses := FSettings.NoAutoCorrectProcesses + [Program_];
  DiagnosticsLogFmt('program_rule.toggled process="%s" no_autocorrect=%s',
    [Program_, BoolToStr(FSettings.IsAutoCorrectDisabledFor(Program_), True)]);
  ApplySettings;
  LoadControlsFromSettings;
end;

procedure TFormMain.edCorrectionsExit(Sender: TObject);
begin
  ApplyCorrectionsFromEdit;
end;

procedure TFormMain.ApplyCorrectionsFromEdit;
var
  Exceptions, SwitchExceptions, Learned: TArray<string>;
  Snippets: string;
begin
  ApplyAiFromEdit;
  if Trim(edDeepLKey.Text) <> FSettings.DeepLApiKey then
  begin
    FSettings.DeepLApiKey := Trim(edDeepLKey.Text);
    DiagnosticsLogFmt('settings.deepl_key set=%s',
      [BoolToStr(FSettings.DeepLApiKey <> '', True)]);
    ApplySettings;
  end;
  Exceptions := ParseWordList(memTwoCapsExceptions.Text);
  SwitchExceptions := ParseWordList(memAutoSwitchExceptions.Text);
  Learned := ParseWordList(memAutoSwitchLearned.Text);
  Snippets := TrimRight(memSnippets.Text);
  if TrimRight(memAutoReplace.Text) <> FSettings.AutoReplace then
  begin
    FSettings.AutoReplace := TrimRight(memAutoReplace.Text);
    ApplySettings;
  end;
  if (string.Join('; ', Exceptions) <> string.Join('; ', FSettings.TwoCapitalsExceptions)) or
     (string.Join('; ', SwitchExceptions) <> string.Join('; ', FSettings.AutoSwitchExceptions)) or
     (string.Join('; ', Learned) <> string.Join('; ', FSettings.AutoSwitchLearned)) or
     (Snippets <> FSettings.Snippets) then
  begin
    FSettings.TwoCapitalsExceptions := Exceptions;
    FSettings.AutoSwitchExceptions := SwitchExceptions;
    FSettings.AutoSwitchLearned := Learned;
    FSettings.Snippets := Snippets;
    ApplySettings;
  end;
end;

{ AI explanation }

function TFormMain.CurrentAiConfig: TAiConfig;
begin
  Result.Provider := AiProviderFromInteger(FSettings.AiProvider);
  case Result.Provider of
    apClaude:
      begin
        Result.ApiKey := FSettings.AiClaudeKey;
        Result.Model := FSettings.AiClaudeModel;
      end;
    apOpenAI:
      begin
        Result.ApiKey := FSettings.AiOpenAIKey;
        Result.BaseUrl := FSettings.AiOpenAIUrl;
        Result.Model := FSettings.AiOpenAIModel;
      end;
  else
    Result.ApiKey := '';
    Result.Model := '';
  end;
end;

procedure TFormMain.LoadAiControls;
var
  Provider: TAiProvider;
begin
  FUpdatingControls := True;
  try
    Provider := AiProviderFromInteger(FSettings.AiProvider);
    cbAiService.ItemIndex := Ord(Provider);
    edAiKey.Enabled := Provider <> apFree;
    lblAiKey.Enabled := edAiKey.Enabled;
    edAiUrl.Enabled := Provider = apOpenAI;
    lblAiUrl.Enabled := edAiUrl.Enabled;
    edAiModel.Enabled := Provider <> apFree;
    lblAiModel.Enabled := edAiModel.Enabled;
    edAiModel.TextHint := DefaultAiModel(Provider);
    case Provider of
      apClaude:
        begin
          edAiKey.Text := FSettings.AiClaudeKey;
          edAiUrl.Text := 'https://api.anthropic.com';
          edAiModel.Text := FSettings.AiClaudeModel;
          lblAiNote.Caption := T(
            'Ключ API создаётся в консоли Anthropic (platform.claude.com). По умолчанию ' +
            'модель claude-opus-5-5; дешевле — claude-sonnet-5-5 или claude-haiku-5-5.',
            'Create the API key in the Anthropic Console (platform.claude.com). The default ' +
            'model is claude-opus-5-5; cheaper: claude-sonnet-5-5 or claude-haiku-5-5.');
        end;
      apOpenAI:
        begin
          edAiKey.Text := FSettings.AiOpenAIKey;
          edAiUrl.Text := FSettings.AiOpenAIUrl;
          edAiModel.Text := FSettings.AiOpenAIModel;
          lblAiNote.Caption := T(
            'Адрес — до /chat/completions: https://api.openai.com/v1, https://openrouter.ai/api/v1, ' +
            'https://api.deepseek.com/v1; локально Ollama — http://localhost:11434/v1 (ключ не нужен, ' +
            'текст не уходит в интернет).',
            'The address up to /chat/completions: https://api.openai.com/v1, ' +
            'https://openrouter.ai/api/v1, https://api.deepseek.com/v1; a local Ollama - ' +
            'http://localhost:11434/v1 (no key, the text stays on the computer).');
        end;
    else
      edAiKey.Text := '';
      edAiUrl.Text := POLLINATIONS_URL;
      edAiModel.Text := '';
      lblAiNote.Caption := T(
        'Бесплатный открытый сервис без регистрации: не чаще одного ответа в 45 секунд, ' +
        'качество скромнее платных моделей. Для лучших ответов подключите Claude или другой ИИ.',
        'A free open service without registration: at most one answer every 45 seconds, ' +
        'more modest quality than paid models. Connect Claude or another AI for better answers.');
    end;
    lblAiNote.Caption := lblAiNote.Caption + sLineBreak + T(
      'Выделенный текст отправляется выбранному сервису только по жесту.',
      'The selected text is sent to the chosen service only on the gesture.');
  finally
    FUpdatingControls := False;
  end;
end;

procedure TFormMain.ApplyAiFromEdit;
var
  Changed: Boolean;

  procedure Put(var Field: string; const Value: string);
  begin
    if Trim(Value) <> Field then
    begin
      Field := Trim(Value);
      Changed := True;
    end;
  end;

begin
  Changed := False;
  case AiProviderFromInteger(FSettings.AiProvider) of
    apClaude:
      begin
        Put(FSettings.AiClaudeKey, edAiKey.Text);
        Put(FSettings.AiClaudeModel, edAiModel.Text);
      end;
    apOpenAI:
      begin
        Put(FSettings.AiOpenAIKey, edAiKey.Text);
        Put(FSettings.AiOpenAIUrl, edAiUrl.Text);
        Put(FSettings.AiOpenAIModel, edAiModel.Text);
      end;
  end;
  if Changed then
  begin
    DiagnosticsLogFmt('settings.ai provider=%d key_set=%s', [FSettings.AiProvider,
      BoolToStr(CurrentAiConfig.ApiKey <> '', True)]);
    ApplySettings;
  end;
end;

procedure TFormMain.cbAiServiceChange(Sender: TObject);
begin
  if FUpdatingControls or (cbAiService.ItemIndex < 0) then
    Exit;
  // Fields of the previous service first.
  ApplyAiFromEdit;
  FSettings.AiProvider := cbAiService.ItemIndex;
  ApplySettings;
  LoadAiControls;
end;

procedure TFormMain.btnAiTestClick(Sender: TObject);
var
  Answer, Code, Error: string;
begin
  ApplyAiFromEdit;
  Screen.Cursor := crHourGlass;
  try
    // A tiny request: is the service reachable and does it accept the key?
    if AskAi(CurrentAiConfig, 'Answer with one word.', 'Say "OK".', Answer, Code, Error) then
      MessageBox(Handle, PChar(T('Сервис ИИ отвечает: ', 'The AI service answers: ') + Answer),
        'LayoutSwitcher', MB_OK or MB_ICONINFORMATION)
    else
      MessageBox(Handle, PChar(Error), 'LayoutSwitcher', MB_OK or MB_ICONWARNING);
  finally
    Screen.Cursor := crDefault;
  end;
  DiagnosticsLogFmt('ai.test provider=%d ok=%s error=%s',
    [FSettings.AiProvider, BoolToStr(Code = '', True), Code]);
end;

procedure TFormMain.StartExplain(const Text: string);
const
  Services: array[TAiProvider] of string = ('Pollinations.ai', 'Anthropic Claude', '');
var
  Config: TAiConfig;
  Thread: TAiExplainThread;
  Service, Host: string;
begin
  Config := CurrentAiConfig;
  Service := Services[Config.Provider];
  if Config.Provider = apOpenAI then
  begin
    Host := Config.BaseUrl;
    if Pos('://', Host) > 0 then
      Host := Copy(Host, Pos('://', Host) + 3, MaxInt);
    if Pos('/', Host) > 0 then
      Host := Copy(Host, 1, Pos('/', Host) - 1);
    Service := Host;
  end;
  // Once: the selected text leaves the computer.
  if not FSettings.AiConsent and (Pos('localhost', LowerCase(Service)) = 0) and
     (Pos('127.0.0.1', Service) = 0) then
  begin
    if MessageBox(0, PChar(Format(T(
         'Выделенный текст будет отправлен сервису ИИ «%s», чтобы получить объяснение. ' +
         'Он передаётся только когда вы сами вызываете объяснение. Сервис выбирается на ' +
         'вкладке «Сервисы».' + sLineBreak + sLineBreak + 'Продолжить?',
         'The selected text will be sent to the AI service "%s" to get an explanation. ' +
         'It is sent only when you ask for an explanation. The service is chosen on the ' +
         'Services tab.' + sLineBreak + sLineBreak + 'Continue?'), [Service])),
         'LayoutSwitcher', MB_YESNO or MB_ICONQUESTION or MB_TOPMOST or MB_SETFOREGROUND) <> IDYES then
      Exit;
    FSettings.AiConsent := True;
    ApplySettings;
  end;
  if FExplainWindow = nil then
    FExplainWindow := TExplainWindow.Create(Self);
  FExplainWindow.StartQuestion(Text, Service + ' · ' + EffectiveAiModel(Config));
  Inc(FExplainSequence);
  if FExplainSequence = 0 then
    FExplainSequence := 1;
  Thread := TAiExplainThread.Create(Config, ExplainSystemPrompt(T('ru', 'en') = 'ru'),
    ExplainUserMessage(Text), FExplainSequence);
  Thread.FreeOnTerminate := True;
  Thread.OnTerminate := ExplainDone;
  Thread.Start;
  DiagnosticsLogFmt('ai.explain_start provider=%d length=%d', [Ord(Config.Provider),
    Length(Text)]);
end;

procedure TFormMain.ExplainDone(Sender: TObject);
var
  Thread: TAiExplainThread;
begin
  // OnTerminate runs in the main thread.  A newer question or a closed
  // window makes the answer obsolete.
  Thread := TAiExplainThread(Sender);
  DiagnosticsLogFmt('ai.explain_done ok=%s ms=%d error=%s',
    [BoolToStr(Thread.Success, True), Thread.ElapsedMS, Thread.ErrorCode]);
  if (Thread.Sequence <> FExplainSequence) or (FExplainWindow = nil) or
     not FExplainWindow.Visible then
    Exit;
  if Thread.Success then
    FExplainWindow.ShowAnswer(Thread.Answer, Thread.ElapsedMS)
  else
    FExplainWindow.ShowError(Thread.ErrorText);
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
  // Exported files carry no API key: keep the current one.
  if Imported.DeepLApiKey = '' then
    Imported.DeepLApiKey := FSettings.DeepLApiKey;
  if Imported.AiClaudeKey = '' then
    Imported.AiClaudeKey := FSettings.AiClaudeKey;
  if Imported.AiOpenAIKey = '' then
    Imported.AiOpenAIKey := FSettings.AiOpenAIKey;
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
    DiagnosticsLogFmt('update.download_done success=%s cancelled=%s signature=%s error="%s"',
      [BoolToStr(Res.Success, True), BoolToStr(Res.Cancelled, True), Res.SignatureNote,
       Res.ErrorText]);
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
    FBalloonInstall := False;
    if Res.ErrorText.StartsWith('signature:') then
      ShowNotification('update_download', T(
        'Установщик подписан другим издателем или его подпись повреждена, поэтому ' +
        'он не запущен. Щёлкните, чтобы открыть страницу загрузки.',
        'The installer is signed by a different publisher or its signature is ' +
        'broken, so it was not started. Click to open the download page.'))
    else
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
