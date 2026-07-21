unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  System.ImageList, Vcl.ImgList, PngImageList, Vcl.StdCtrls;

const
  DOUBLE_SHIFT_INTERVAL = 500;
  DOUBLE_CTRL_INTERVAL = 500;

type
  TBufferedChar = record
    Ch: WideChar;
  end;

  TClipboardFormatSnapshot = record
    FormatID: UINT;
    DataHandle: THandle;
    DataSize: NativeUInt;
  end;

  TFormMain = class(TForm)
    TrayIcon: TTrayIcon;
    PopupMenu: TPopupMenu;
    mniDiagnostics: TMenuItem;
    mniSeparator: TMenuItem;
    mniExit: TMenuItem;
    TrayIcons: TPngImageList;
    TimerLayout: TTimer;
    chkAutorun: TCheckBox;
    chkDiagnostics: TCheckBox;
    Label2: TLabel;
    Label4: TLabel;
    Label6: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    Label1: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure mniExitClick(Sender: TObject);
    procedure mniDiagnosticsClick(Sender: TObject);
    procedure TimerLayoutTimer(Sender: TObject);
    procedure chkAutorunClick(Sender: TObject);
    procedure chkDiagnosticsClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TrayIconDblClick(Sender: TObject);
  private
    FBuffer: array of TBufferedChar;
    FBufferOverflowed: Boolean;
    FLastWindow: HWND;
    FLastLangID: DWORD;

    FSavedClipboardFormats: array of TClipboardFormatSnapshot;
    FClipboardSnapshotValid: Boolean;
    FClipboardWasEmpty: Boolean;

    FLastShiftTime: DWORD;
    FShiftPressed: Boolean;
    FLastLCtrlTime: DWORD;
    FLCtrlPressed: Boolean;
    FLastRCtrlTime: DWORD;
    FRCtrlPressed: Boolean;
    FKeyDown: array[0..255] of Boolean;
    FShiftTapEligible: Boolean;
    FLCtrlTapEligible: Boolean;
    FRCtrlTapEligible: Boolean;
    FInvertChordActive: Boolean;

    FSelectionWindow: HWND;
    FSelectionIsNative: Boolean;
    FRawInputRegistered: Boolean;
    FUpdatingDiagnosticsSetting: Boolean;

    function RegisterRawInput: Boolean;
    procedure UnregisterRawInput;
    procedure HandleRawInput(RawInputHandle: THandle; EventTime: DWORD);
    procedure ProcessKeyboardEvent(EventTime: DWORD; VK, ScanCode: UINT;
      IsKeyUp: Boolean);
    procedure ProcessPointerActivity;
    procedure ProcessBufferKey(VK, ScanCode: UINT);
    procedure CompleteShiftTap(EventTime: DWORD);
    procedure CompleteCtrlTap(IsLeft: Boolean; EventTime: DWORD);
    procedure QueueOperation(MessageID: UINT);
    procedure ExecuteOperation(MessageID: UINT);
    procedure CheckWindowChanged;

    procedure AddChar(Ch: WideChar);
    procedure BufferBackspace;
    procedure ClearBuffer;
    procedure SetBufferText(const Value: WideString);
    procedure FinalizeWord;
    function BufferToString: WideString;
    function TryTranslateKey(VK, ScanCode: UINT; out Ch: WideChar): Boolean;

    procedure DoConvert;
    procedure DoChangeCase(ToUpper: Boolean);
    procedure DoInvertCase;
    function TryGetTargetText(out Text: WideString; out IsSelection: Boolean): Boolean;
    function GetSelectedTextInActiveWindow(out Text: WideString): Boolean;
    function GetSelectedTextByUIAutomation(out Text: WideString): Boolean;
    function GetSelectedTextByClipboardFallback(out Text: WideString): Boolean;
    function ReplaceSelection(const Value: WideString): Boolean;

    function SendChord(ModifierVK, VK: Word): Boolean;
    function SendBackspaces(Count: Integer): Boolean;
    function TypeUnicodeText(const Value: WideString): Boolean;
    function WaitForModifiersReleased(TimeoutMS: DWORD): Boolean;
    function WaitForClipboardChange(OldSequence: DWORD; TimeoutMS: DWORD): Boolean;
    function DuplicateClipboardData(FormatID: UINT; SourceHandle: THandle;
      out DataSize: NativeUInt): THandle;
    procedure FreeClipboardData(FormatID: UINT; DataHandle: THandle);
    function AddClipboardHistoryExclusion: Boolean;
    function SaveClipboard: Boolean;
    procedure DiscardClipboardSnapshot;
    procedure RestoreClipboard;
    function GetClipboardTextW: WideString;

    function GetFocusedWindow: HWND;
    function FindHKLByLangID(LangID: Word): HKL;
    procedure SwitchGlobalLayout(ToLangID: Word);
    function ConvertLayout(const S: WideString): WideString;
    function ChangeStringCase(const S: WideString; ToUpper: Boolean): WideString;
    function InvertStringCase(const S: WideString): WideString;
    procedure UpdateTrayIcon;
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

uses
  System.Win.Registry,
  uDiagnostics,
  uUIAutomation;

const
  WM_DO_CONVERT         = WM_APP + 1;
  WM_DO_UPPERCASE       = WM_APP + 2;
  WM_DO_LOWERCASE       = WM_APP + 3;
  WM_DO_INVERT_CASE     = WM_APP + 4;

  MAX_WORD_LEN = 50;
  MAX_SELECTION_LEN = 1024 * 1024;
  CLIPBOARD_COPY_TIMEOUT = 500;
  CLIPBOARD_OPEN_TIMEOUT = 1000;
  CLIPBOARD_RETRY_INTERVAL = 10;
  MODIFIER_RELEASE_TIMEOUT = 150;
  TARGET_KEYUP_SETTLE_DELAY = 30;
  WINDOW_MESSAGE_TIMEOUT = 250;
  TO_UNICODE_NO_STATE_CHANGE = 4;
  LS_INPUT_TAG = $4C535749; // "LSWI"

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

  EnChars: WideString = '''
  `1234567890-=qwertyuiop[]asdfghjkl;'\zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:"|ZXCVBNM<>?
  ''';
  RuChars: WideString = '''
  ё1234567890-=йцукенгшщзхъфывапролджэ\ячсмитьбю.Ё!"№;%:?*()_+ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭ/ЯЧСМИТЬБЮ,
  ''';

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

var
  GConversionState: LongInt;

function RegisterRawInputDevices(Devices: PLSRawInputDevice; DeviceCount,
  DeviceSize: UINT): BOOL; stdcall; external user32 name 'RegisterRawInputDevices';
function GetRawInputData(RawInput: THandle; Command: UINT; Data: Pointer;
  var DataSize: UINT; HeaderSize: UINT): UINT; stdcall;
  external user32 name 'GetRawInputData';

function IsShiftKey(VK: UINT): Boolean;
begin
  Result := (VK = VK_SHIFT) or (VK = VK_LSHIFT) or (VK = VK_RSHIFT);
end;

function IsCtrlKey(VK: UINT): Boolean;
begin
  Result := (VK = VK_CONTROL) or (VK = VK_LCONTROL) or (VK = VK_RCONTROL);
end;

function IsAltKey(VK: UINT): Boolean;
begin
  Result := (VK = VK_MENU) or (VK = VK_LMENU) or (VK = VK_RMENU);
end;

function IsWinKey(VK: UINT): Boolean;
begin
  Result := (VK = VK_LWIN) or (VK = VK_RWIN);
end;

function IsModifierKey(VK: UINT): Boolean;
begin
  Result := IsShiftKey(VK) or IsCtrlKey(VK) or IsAltKey(VK) or IsWinKey(VK);
end;

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
const
  MOUSE_ACTIVITY_MASK = RI_MOUSE_LEFT_BUTTON_DOWN or
    RI_MOUSE_RIGHT_BUTTON_DOWN or RI_MOUSE_MIDDLE_BUTTON_DOWN or
    RI_MOUSE_BUTTON_4_DOWN or RI_MOUSE_BUTTON_5_DOWN or
    RI_MOUSE_WHEEL or RI_MOUSE_HWHEEL;
var
  DataSize, BytesRead: UINT;
  Data: Pointer;
  Raw: PLSRawInput;
  VK, ScanCode: UINT;
  IsKeyUp: Boolean;
begin
  DataSize := 0;
  BytesRead := GetRawInputData(RawInputHandle, RID_INPUT, nil, DataSize,
    SizeOf(TLSRawInputHeader));
  if BytesRead <> 0 then
  begin
    DiagnosticsLogFmt('raw_input.size_failed result=%d error=%d',
      [BytesRead, GetLastError]);
    Exit;
  end;
  if DataSize < SizeOf(TLSRawInputHeader) then
  begin
    DiagnosticsLogFmt('raw_input.invalid_size size=%d header=%d',
      [DataSize, SizeOf(TLSRawInputHeader)]);
    Exit;
  end;

  GetMem(Data, DataSize);
  try
    BytesRead := GetRawInputData(RawInputHandle, RID_INPUT, Data, DataSize,
      SizeOf(TLSRawInputHeader));
    if (BytesRead = UINT(-1)) or (BytesRead < SizeOf(TLSRawInputHeader)) then
    begin
      DiagnosticsLogFmt('raw_input.read_failed result=%d size=%d error=%d',
        [BytesRead, DataSize, GetLastError]);
      Exit;
    end;

    Raw := PLSRawInput(Data);
    case Raw^.Header.DataType of
      RIM_TYPEKEYBOARD:
        begin
          if Raw^.Keyboard.ExtraInformation = LS_INPUT_TAG then
            Exit;
          VK := Raw^.Keyboard.VKey;
          if VK = $FF then
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

          IsKeyUp := (Raw^.Keyboard.Flags and RI_KEY_BREAK) <> 0;
          ProcessKeyboardEvent(EventTime, VK, ScanCode, IsKeyUp);
        end;
      RIM_TYPEMOUSE:
        if (Raw^.Mouse.ButtonFlags and MOUSE_ACTIVITY_MASK) <> 0 then
          ProcessPointerActivity;
    end;
  finally
    FreeMem(Data);
  end;
end;

procedure AddToStartup(const AppName, AppPath: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', True) then
    try
      Reg.WriteString(AppName, '"' + AppPath + '"');
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure RemoveFromStartup(const AppName: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', False) then
    try
      if Reg.ValueExists(AppName) then
        Reg.DeleteValue(AppName);
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function IsInStartup(const AppName: string): Boolean;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Result := Reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Run') and
              Reg.ValueExists(AppName);
  finally
    Reg.Free;
  end;
end;

function IsCyrillicText(const S: WideString): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    if ((S[I] >= WideChar('а')) and (S[I] <= WideChar('я'))) or
       ((S[I] >= WideChar('А')) and (S[I] <= WideChar('Я'))) or
       (S[I] = WideChar('ё')) or (S[I] = WideChar('Ё')) then
      Exit(True);
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  SetLength(FBuffer, 0);
  FBufferOverflowed := False;
  FLastWindow := 0;
  FLastLangID := 0;
  SetLength(FSavedClipboardFormats, 0);
  FClipboardSnapshotValid := False;
  FClipboardWasEmpty := False;
  FillChar(FKeyDown, SizeOf(FKeyDown), 0);
  FShiftPressed := False;
  FLCtrlPressed := False;
  FRCtrlPressed := False;
  FShiftTapEligible := False;
  FLCtrlTapEligible := False;
  FRCtrlTapEligible := False;
  FInvertChordActive := False;
  FSelectionWindow := 0;
  FSelectionIsNative := False;
  FRawInputRegistered := False;
  FUpdatingDiagnosticsSetting := True;

  try
    chkAutorun.Checked := IsInStartup('LayoutSwitcher');
    chkDiagnostics.Checked := DiagnosticsEnabled;
  finally
    FUpdatingDiagnosticsSetting := False;
  end;
  mniDiagnostics.Enabled := DirectoryExists(DiagnosticsDirectory);
  ShowInTaskBar := False;
  SetWindowLong(Application.Handle, GWL_EXSTYLE,
    GetWindowLong(Application.Handle, GWL_EXSTYLE) and not WS_EX_APPWINDOW);

  InterlockedExchange(GConversionState, 0);
  if not RegisterRawInput then
  begin
    DiagnosticsLogFmt('raw_input.register_failed error=%d', [GetLastError]);
    MessageBox(0, 'Cannot register Raw Input devices!', 'LayoutSwitcher',
      MB_OK or MB_ICONERROR);
  end
  else
    DiagnosticsLog('raw_input.registered keyboard=true mouse=true');

  TrayIcon.Hint := 'Layout Switcher' + sLineBreak +
    'Dbl Shift=Конвертация' + sLineBreak +
    'Dbl LCtrl=ВЕРХНИЙ регистр' + sLineBreak +
    'Dbl RCtrl=нижний регистр' + sLineBreak +
    'LCtrl+RCtrl=Инвертировать регистр';
  WindowState := wsMinimized;
  Hide;
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  DiagnosticsLog('form.destroy begin');
  UnregisterRawInput;
  RestoreClipboard;
  DiscardClipboardSnapshot;
  DiagnosticsLog('form.destroy end');
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
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
          FillChar(FKeyDown, SizeOf(FKeyDown), 0);
          FShiftTapEligible := False;
          FLCtrlTapEligible := False;
          FRCtrlTapEligible := False;
          FInvertChordActive := False;
          DiagnosticsCaptureException('raw_input.message', E, ExceptAddr);
          {$IFDEF DEBUG}
          raise;
          {$ENDIF}
        end;
      end;
    finally
      inherited WndProc(Message);
    end;
    Exit;
  end;

  case Message.Msg of
    WM_DO_CONVERT, WM_DO_UPPERCASE, WM_DO_LOWERCASE, WM_DO_INVERT_CASE:
      try
        ExecuteOperation(Message.Msg);
      finally
        InterlockedExchange(GConversionState, 0);
      end;
  else
    inherited WndProc(Message);
  end;
end;

procedure TFormMain.QueueOperation(MessageID: UINT);
begin
  if InterlockedCompareExchange(GConversionState, 1, 0) = 0 then
  begin
    if not PostMessage(Handle, MessageID, 0, 0) then
    begin
      DiagnosticsLogFmt('operation.queue_failed message=%d error=%d',
        [MessageID, GetLastError]);
      InterlockedExchange(GConversionState, 0);
    end;
  end
  else
    DiagnosticsLogFmt('operation.queue_ignored message=%d reason=busy',
      [MessageID]);
end;

procedure TFormMain.ExecuteOperation(MessageID: UINT);
var
  OperationName, TargetClass: string;
  Target: HWND;
  TargetProcessID: DWORD;
  ClassBuffer: array[0..255] of Char;
  Success: Boolean;
begin
  case MessageID of
    WM_DO_CONVERT: OperationName := 'convert_layout';
    WM_DO_UPPERCASE: OperationName := 'uppercase';
    WM_DO_LOWERCASE: OperationName := 'lowercase';
    WM_DO_INVERT_CASE: OperationName := 'invert_case';
  else
    OperationName := 'unknown';
  end;

  Target := GetFocusedWindow;
  TargetProcessID := 0;
  TargetClass := '';
  FillChar(ClassBuffer, SizeOf(ClassBuffer), 0);
  if Target <> 0 then
  begin
    GetWindowThreadProcessId(Target, @TargetProcessID);
    if GetClassName(Target, ClassBuffer, Length(ClassBuffer)) > 0 then
      TargetClass := string(ClassBuffer);
  end;

  DiagnosticsBeginOperation(OperationName,
    Format('buffer_len=%d overflow=%s target=%p target_pid=%d target_class="%s"',
      [Length(FBuffer), BoolToStr(FBufferOverflowed, True), Pointer(Target),
       TargetProcessID, TargetClass]));
  Success := False;
  try
    try
      case MessageID of
        WM_DO_CONVERT: DoConvert;
        WM_DO_UPPERCASE: DoChangeCase(True);
        WM_DO_LOWERCASE: DoChangeCase(False);
        WM_DO_INVERT_CASE: DoInvertCase;
      end;
      Success := True;
    except
      on E: Exception do
      begin
        DiagnosticsCaptureException('operation.execute', E, ExceptAddr);
        raise;
      end;
    end;
  finally
    DiagnosticsEndOperation(OperationName, Success);
  end;
end;

procedure TFormMain.CompleteShiftTap(EventTime: DWORD);
begin
  if FShiftPressed and
     (EventTime - FLastShiftTime <= DOUBLE_SHIFT_INTERVAL) then
  begin
    FShiftPressed := False;
    QueueOperation(WM_DO_CONVERT);
  end
  else
  begin
    FShiftPressed := True;
    FLastShiftTime := EventTime;
  end;
end;

procedure TFormMain.CompleteCtrlTap(IsLeft: Boolean; EventTime: DWORD);
begin
  if IsLeft then
  begin
    if FLCtrlPressed and
       (EventTime - FLastLCtrlTime <= DOUBLE_CTRL_INTERVAL) then
    begin
      FLCtrlPressed := False;
      QueueOperation(WM_DO_UPPERCASE);
    end
    else
    begin
      FLCtrlPressed := True;
      FLastLCtrlTime := EventTime;
    end;
  end
  else
  begin
    if FRCtrlPressed and
       (EventTime - FLastRCtrlTime <= DOUBLE_CTRL_INTERVAL) then
    begin
      FRCtrlPressed := False;
      QueueOperation(WM_DO_LOWERCASE);
    end
    else
    begin
      FRCtrlPressed := True;
      FLastRCtrlTime := EventTime;
    end;
  end;
end;

procedure TFormMain.ProcessKeyboardEvent(EventTime: DWORD; VK, ScanCode: UINT;
  IsKeyUp: Boolean);
var
  WasDown, HadShiftDown: Boolean;
begin
  if VK > High(FKeyDown) then
    Exit;

  CheckWindowChanged;
  WasDown := FKeyDown[VK];

  if IsKeyUp then
  begin
    FKeyDown[VK] := False;
    if IsShiftKey(VK) and
       not (FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT]) then
    begin
      if FShiftTapEligible then
        CompleteShiftTap(EventTime);
      FShiftTapEligible := False;
    end;

    if (VK = VK_LCONTROL) and FLCtrlTapEligible and not FInvertChordActive then
    begin
      CompleteCtrlTap(True, EventTime);
      FLCtrlTapEligible := False;
    end;
    if (VK = VK_RCONTROL) and FRCtrlTapEligible and not FInvertChordActive then
    begin
      CompleteCtrlTap(False, EventTime);
      FRCtrlTapEligible := False;
    end;

    if FInvertChordActive and
       not FKeyDown[VK_LCONTROL] and not FKeyDown[VK_RCONTROL] then
    begin
      FInvertChordActive := False;
      FLCtrlTapEligible := False;
      FRCtrlTapEligible := False;
      FLCtrlPressed := False;
      FRCtrlPressed := False;
      QueueOperation(WM_DO_INVERT_CASE);
    end;
    Exit;
  end;

  if WasDown then
  begin
    if not IsModifierKey(VK) then
      ProcessBufferKey(VK, ScanCode);
    Exit;
  end;

  HadShiftDown := FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT];
  FKeyDown[VK] := True;

  if IsShiftKey(VK) then
  begin
    if HadShiftDown then
      FShiftTapEligible := False
    else
      FShiftTapEligible := not (FKeyDown[VK_LCONTROL] or FKeyDown[VK_RCONTROL] or
        FKeyDown[VK_LMENU] or FKeyDown[VK_RMENU] or
        FKeyDown[VK_LWIN] or FKeyDown[VK_RWIN]);
    Exit;
  end;

  if VK = VK_LCONTROL then
  begin
    FLCtrlTapEligible := not (FKeyDown[VK_RCONTROL] or
      FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT] or
      FKeyDown[VK_LMENU] or FKeyDown[VK_RMENU] or
      FKeyDown[VK_LWIN] or FKeyDown[VK_RWIN]);
    if FKeyDown[VK_RCONTROL] then
    begin
      FInvertChordActive := True;
      FLCtrlTapEligible := False;
      FRCtrlTapEligible := False;
    end;
    Exit;
  end;

  if VK = VK_RCONTROL then
  begin
    FRCtrlTapEligible := not (FKeyDown[VK_LCONTROL] or
      FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT] or
      FKeyDown[VK_LMENU] or FKeyDown[VK_RMENU] or
      FKeyDown[VK_LWIN] or FKeyDown[VK_RWIN]);
    if FKeyDown[VK_LCONTROL] then
    begin
      FInvertChordActive := True;
      FLCtrlTapEligible := False;
      FRCtrlTapEligible := False;
    end;
    Exit;
  end;

  if IsAltKey(VK) or IsWinKey(VK) or (VK = VK_CONTROL) then
    Exit;

  if FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT] then
    FShiftTapEligible := False;
  if FKeyDown[VK_LCONTROL] then
    FLCtrlTapEligible := False;
  if FKeyDown[VK_RCONTROL] then
    FRCtrlTapEligible := False;
  FShiftPressed := False;
  FLCtrlPressed := False;
  FRCtrlPressed := False;
  ProcessBufferKey(VK, ScanCode);
end;

procedure TFormMain.ProcessPointerActivity;
begin
  ClearBuffer;
  FShiftPressed := False;
  FLCtrlPressed := False;
  FRCtrlPressed := False;
  FShiftTapEligible := False;
  FLCtrlTapEligible := False;
  FRCtrlTapEligible := False;
end;

procedure TFormMain.ProcessBufferKey(VK, ScanCode: UINT);
var
  Ch: WideChar;
begin
  if (VK = VK_LEFT) or (VK = VK_RIGHT) or (VK = VK_UP) or (VK = VK_DOWN) or
     (VK = VK_HOME) or (VK = VK_END) or (VK = VK_PRIOR) or (VK = VK_NEXT) or
     (VK = VK_ESCAPE) or (VK = VK_DELETE) or (VK = VK_INSERT) then
  begin
    ClearBuffer;
    Exit;
  end;

  if VK = VK_BACK then
  begin
    if FKeyDown[VK_LCONTROL] or FKeyDown[VK_RCONTROL] then
      ClearBuffer
    else
      BufferBackspace;
    Exit;
  end;

  if (VK = VK_RETURN) or (VK = VK_TAB) or (VK = VK_SPACE) then
  begin
    FinalizeWord;
    Exit;
  end;

  if IsModifierKey(VK) then
    Exit;

  if FKeyDown[VK_LCONTROL] or FKeyDown[VK_RCONTROL] or
     FKeyDown[VK_LMENU] or FKeyDown[VK_RMENU] or
     FKeyDown[VK_LWIN] or FKeyDown[VK_RWIN] then
  begin
    ClearBuffer;
    Exit;
  end;

  if TryTranslateKey(VK, ScanCode, Ch) then
    AddChar(Ch)
  else if (VK <> VK_CAPITAL) and (VK <> VK_NUMLOCK) and (VK <> VK_SCROLL) then
    ClearBuffer;
end;

procedure TFormMain.AddChar(Ch: WideChar);
begin
  if FBufferOverflowed then
    Exit;
  if Length(FBuffer) >= MAX_WORD_LEN then
  begin
    SetLength(FBuffer, 0);
    FBufferOverflowed := True;
    Exit;
  end;
  SetLength(FBuffer, Length(FBuffer) + 1);
  FBuffer[High(FBuffer)].Ch := Ch;
end;

procedure TFormMain.BufferBackspace;
begin
  if FBufferOverflowed then
    Exit;
  if Length(FBuffer) > 0 then
    SetLength(FBuffer, Length(FBuffer) - 1);
end;

procedure TFormMain.ClearBuffer;
begin
  SetLength(FBuffer, 0);
  FBufferOverflowed := False;
end;

procedure TFormMain.SetBufferText(const Value: WideString);
var
  I: Integer;
begin
  ClearBuffer;
  if (Value = '') or (Length(Value) > MAX_WORD_LEN) then
    Exit;

  for I := 1 to Length(Value) do
    if Ord(Value[I]) <= 32 then
      Exit;

  SetLength(FBuffer, Length(Value));
  for I := 1 to Length(Value) do
    FBuffer[I - 1].Ch := Value[I];
end;

procedure TFormMain.FinalizeWord;
begin
  ClearBuffer;
end;

function TFormMain.BufferToString: WideString;
var
  I: Integer;
begin
  SetLength(Result, Length(FBuffer));
  for I := 0 to High(FBuffer) do
    Result[I + 1] := FBuffer[I].Ch;
end;

function TFormMain.TryTranslateKey(VK, ScanCode: UINT; out Ch: WideChar): Boolean;
var
  KeyState: TKeyboardState;
  Buffer: array[0..3] of WideChar;
  FocusedWindow: HWND;
  ThreadID: DWORD;
  Layout: HKL;
  CharCount: Integer;
  TranslationVK, MappedVK: UINT;
begin
  Result := False;
  Ch := #0;
  FocusedWindow := GetFocusedWindow;
  if FocusedWindow = 0 then
    Exit;

  ThreadID := GetWindowThreadProcessId(FocusedWindow, nil);
  Layout := GetKeyboardLayout(ThreadID);
  if Layout = 0 then
    Exit;

  FillChar(KeyState, SizeOf(KeyState), 0);
  if FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT] then
    KeyState[VK_SHIFT] := $80;
  if (GetKeyState(VK_CAPITAL) and 1) <> 0 then
    KeyState[VK_CAPITAL] := 1;
  if (GetKeyState(VK_NUMLOCK) and 1) <> 0 then
    KeyState[VK_NUMLOCK] := 1;

  TranslationVK := VK;
  if ScanCode <> 0 then
  begin
    MappedVK := MapVirtualKeyEx(ScanCode, MAPVK_VSC_TO_VK_EX, Layout);
    if MappedVK <> 0 then
      TranslationVK := MappedVK;
  end;
  if ScanCode = 0 then
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

function TFormMain.GetFocusedWindow: HWND;
var
  Foreground: HWND;
  Info: TLSGUIThreadInfo;
begin
  Result := 0;
  Foreground := GetForegroundWindow;
  if Foreground = 0 then
    Exit;

  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetGUIThreadInfo(GetWindowThreadProcessId(Foreground, nil),
       PGUIThreadInfo(@Info)^) and (Info.hwndFocus <> 0) then
    Result := Info.hwndFocus
  else
    Result := Foreground;
end;

procedure TFormMain.CheckWindowChanged;
var
  CurrentWindow: HWND;
begin
  CurrentWindow := GetFocusedWindow;
  if CurrentWindow <> FLastWindow then
  begin
    FLastWindow := CurrentWindow;
    ClearBuffer;
    FShiftPressed := False;
    FLCtrlPressed := False;
    FRCtrlPressed := False;
    FShiftTapEligible := False;
    FLCtrlTapEligible := False;
    FRCtrlTapEligible := False;
  end;
end;

function TFormMain.GetSelectedTextInActiveWindow(out Text: WideString): Boolean;
var
  Target: HWND;
  StartSel, EndSel: DWORD;
  ClassName: array[0..255] of Char;
  ClassText: string;
  MessageResult: DWORD_PTR;
  TextLength, Copied: Integer;
  Buffer: WideString;
  Style: NativeInt;
  SelectionStart, SelectionEnd: DWORD;
begin
  Result := False;
  Text := '';
  Target := GetFocusedWindow;
  if Target = 0 then
    Exit;

  GetClassName(Target, ClassName, Length(ClassName));
  ClassText := LowerCase(string(ClassName));
  if (Pos('edit', ClassText) = 0) and (Pos('richedit', ClassText) = 0) and
     (Pos('tmemo', ClassText) = 0) and (Pos('tedit', ClassText) = 0) then
    Exit;

  Style := GetWindowLongPtr(Target, GWL_STYLE);
  if (Style and ES_PASSWORD) <> 0 then
    Exit;

  StartSel := 0;
  EndSel := 0;
  MessageResult := 0;
  if SendMessageTimeout(Target, EM_GETSEL, WPARAM(@StartSel), LPARAM(@EndSel),
       SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;

  MessageResult := 0;
  if SendMessageTimeoutW(Target, WM_GETTEXTLENGTH, 0, 0,
       SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  TextLength := Integer(MessageResult);
  if (TextLength <= 0) or (TextLength > MAX_SELECTION_LEN) or
     (EndSel > DWORD(TextLength)) or (StartSel > EndSel) then
    Exit;

  SetLength(Buffer, TextLength + 1);
  MessageResult := 0;
  if SendMessageTimeoutW(Target, WM_GETTEXT, WPARAM(TextLength + 1),
       LPARAM(PWideChar(Buffer)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
       WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  Copied := Integer(MessageResult);
  if Copied <= 0 then
    Exit;
  SetLength(Buffer, Copied);
  if EndSel > DWORD(Copied) then
    Exit;

  SelectionStart := StartSel;
  SelectionEnd := EndSel;
  if SelectionStart = SelectionEnd then
  begin
    if (SelectionStart = 0) or (SelectionStart > DWORD(Copied)) then
      Exit;

    // Standard Edit/RichEdit controls let us read the word immediately
    // before the caret directly. This is more reliable than reconstructing
    // Unicode text from global keyboard events.
    while (SelectionStart > 0) and
          (Ord(Buffer[SelectionStart]) > 32) do
      Dec(SelectionStart);
    if SelectionStart = SelectionEnd then
      Exit;

    MessageResult := 0;
    if SendMessageTimeout(Target, EM_SETSEL, SelectionStart, SelectionEnd,
         SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT,
         @MessageResult) = 0 then
      Exit;
  end;

  Text := Copy(Buffer, SelectionStart + 1, SelectionEnd - SelectionStart);
  if Text <> '' then
  begin
    FSelectionWindow := Target;
    FSelectionIsNative := True;
    Result := True;
  end;
end;

function TFormMain.GetSelectedTextByUIAutomation(
  out Text: WideString): Boolean;
var
  Target: HWND;
  FailureStage: string;
  ErrorCode: HRESULT;
begin
  Result := False;
  Text := '';
  Target := GetFocusedWindow;
  if Target = 0 then
    Exit;

  if not TryGetUIAutomationSelection(Text, FailureStage, ErrorCode) then
  begin
    DiagnosticsLogFmt('target.uia unavailable stage=%s result=0x%.8x',
      [FailureStage, Cardinal(ErrorCode)]);
    Exit;
  end;
  if (Text = '') or (GetFocusedWindow <> Target) then
  begin
    DiagnosticsLog('target.uia rejected reason=focus_changed_or_empty');
    Text := '';
    Exit;
  end;

  FSelectionWindow := Target;
  FSelectionIsNative := False;
  Result := True;
  DiagnosticsLogFmt('target.uia success=true length=%d', [Length(Text)]);
end;

function TFormMain.WaitForClipboardChange(OldSequence, TimeoutMS: DWORD): Boolean;
var
  Started: DWORD;
begin
  Started := GetTickCount;
  repeat
    if GetClipboardSequenceNumber <> OldSequence then
      Exit(True);
    Sleep(CLIPBOARD_RETRY_INTERVAL);
  until GetTickCount - Started >= TimeoutMS;
  Result := False;
end;

function TFormMain.WaitForModifiersReleased(TimeoutMS: DWORD): Boolean;
var
  Started, Elapsed: DWORD;
begin
  Started := GetTickCount;
  repeat
    if ((GetAsyncKeyState(VK_LSHIFT) and $8000) = 0) and
       ((GetAsyncKeyState(VK_RSHIFT) and $8000) = 0) and
       ((GetAsyncKeyState(VK_LCONTROL) and $8000) = 0) and
       ((GetAsyncKeyState(VK_RCONTROL) and $8000) = 0) and
       ((GetAsyncKeyState(VK_LMENU) and $8000) = 0) and
       ((GetAsyncKeyState(VK_RMENU) and $8000) = 0) and
       ((GetAsyncKeyState(VK_LWIN) and $8000) = 0) and
       ((GetAsyncKeyState(VK_RWIN) and $8000) = 0) then
    begin
      Elapsed := GetTickCount - Started;
      // Raw Input reports the physical Shift release before Electron has
      // necessarily handled the corresponding key-up message.  Without this
      // short settling interval VS Code can interpret Ctrl+C as Ctrl+Shift+C.
      Sleep(TARGET_KEYUP_SETTLE_DELAY);
      DiagnosticsLogFmt('input.modifiers released=true wait_ms=%d settle_ms=%d',
        [Elapsed, TARGET_KEYUP_SETTLE_DELAY]);
      Exit(True);
    end;
    Sleep(5);
  until GetTickCount - Started >= TimeoutMS;

  DiagnosticsLogFmt(
    'input.modifiers release_timeout shift=%d ctrl=%d alt=%d win=%d',
    [Ord((GetAsyncKeyState(VK_SHIFT) and $8000) <> 0),
     Ord((GetAsyncKeyState(VK_CONTROL) and $8000) <> 0),
     Ord((GetAsyncKeyState(VK_MENU) and $8000) <> 0),
     Ord(((GetAsyncKeyState(VK_LWIN) or GetAsyncKeyState(VK_RWIN)) and $8000) <> 0)]);
  Result := False;
end;

function TFormMain.GetSelectedTextByClipboardFallback(out Text: WideString): Boolean;
var
  OldSequence: DWORD;
  ClipboardChanged: Boolean;
begin
  Result := False;
  Text := '';
  if not WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) then
  begin
    DiagnosticsLog('target.clipboard modifiers_still_pressed');
    Exit;
  end;

  if not SaveClipboard then
  begin
    DiagnosticsLog('target.clipboard save_failed');
    Exit;
  end;

  OldSequence := GetClipboardSequenceNumber;
  ClipboardChanged := False;
  try
    if not SendChord(VK_CONTROL, Ord('C')) then
    begin
      DiagnosticsLog('target.clipboard copy_send_failed');
      Exit;
    end;
    if not WaitForClipboardChange(OldSequence, CLIPBOARD_COPY_TIMEOUT) then
    begin
      DiagnosticsLog('target.clipboard copy_timeout');
      Exit;
    end;
    ClipboardChanged := True;

    Text := GetClipboardTextW;
    if (Text = '') or (Length(Text) > MAX_SELECTION_LEN) then
    begin
      DiagnosticsLogFmt('target.clipboard invalid_text length=%d', [Length(Text)]);
      Text := '';
      Exit;
    end;

    // VS Code and some other editors copy the whole line when there is no selection.
    if (Text[Length(Text)] = #10) or (Text[Length(Text)] = #13) then
    begin
      DiagnosticsLog('target.clipboard rejected_whole_line=true');
      Text := '';
      Exit;
    end;

    FSelectionWindow := GetFocusedWindow;
    FSelectionIsNative := False;
    Result := FSelectionWindow <> 0;
    DiagnosticsLogFmt('target.clipboard success=%s length=%d',
      [BoolToStr(Result, True), Length(Text)]);
  finally
    // Do not rewrite the clipboard when Ctrl+C was ignored.  Apart from being
    // unnecessary, that used to contend with VS Code/ShareX for another second.
    ClipboardChanged := ClipboardChanged or
      (GetClipboardSequenceNumber <> OldSequence);
    if ClipboardChanged then
      RestoreClipboard
    else
    begin
      DiagnosticsLog('clipboard.restore skipped changed=false');
      DiscardClipboardSnapshot;
    end;
  end;
end;

function TFormMain.TryGetTargetText(out Text: WideString;
  out IsSelection: Boolean): Boolean;
begin
  Result := False;
  Text := '';
  IsSelection := False;
  FSelectionWindow := 0;
  FSelectionIsNative := False;

  if GetSelectedTextInActiveWindow(Text) then
  begin
    IsSelection := True;
    DiagnosticsLogFmt('target.selected source=native length=%d', [Length(Text)]);
    Exit(True);
  end;

  // The locally tracked word is reliable and does not touch the system clipboard.
  if not FBufferOverflowed and (Length(FBuffer) > 0) then
  begin
    Text := BufferToString;
    DiagnosticsLogFmt('target.selected source=buffer length=%d', [Length(Text)]);
    Exit(Text <> '');
  end;

  if GetSelectedTextByUIAutomation(Text) then
  begin
    IsSelection := True;
    DiagnosticsLogFmt('target.selected source=uia length=%d', [Length(Text)]);
    Exit(True);
  end;

  if GetSelectedTextByClipboardFallback(Text) then
  begin
    IsSelection := True;
    DiagnosticsLogFmt('target.selected source=clipboard length=%d', [Length(Text)]);
    Exit(True);
  end;
  DiagnosticsLog('target.selected source=none');
end;

function TFormMain.ReplaceSelection(const Value: WideString): Boolean;
var
  MessageResult: DWORD_PTR;
begin
  Result := False;
  if (FSelectionWindow = 0) or (GetFocusedWindow <> FSelectionWindow) then
    Exit;

  if FSelectionIsNative then
  begin
    MessageResult := 0;
    Result := SendMessageTimeoutW(FSelectionWindow, EM_REPLACESEL, 1,
      LPARAM(PWideChar(Value)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
      WINDOW_MESSAGE_TIMEOUT, @MessageResult) <> 0;
  end
  else
    Result := TypeUnicodeText(Value);
end;

function TFormMain.SendChord(ModifierVK, VK: Word): Boolean;
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
  Result := SendInput(Length(Inputs), Inputs[0], SizeOf(TInput)) = UINT(Length(Inputs));
  if not Result then
    DiagnosticsLogFmt('send_input.chord_failed modifier=%d key=%d error=%d',
      [ModifierVK, VK, GetLastError]);
end;

function TFormMain.SendBackspaces(Count: Integer): Boolean;
const
  MAX_INPUTS_PER_BATCH = 128;
var
  Inputs: array[0..MAX_INPUTS_PER_BATCH - 1] of TInput;
  BatchChars, I, InputCount, Remaining: Integer;
begin
  Result := True;
  Remaining := Count;
  while Remaining > 0 do
  begin
    BatchChars := Remaining;
    if BatchChars > MAX_INPUTS_PER_BATCH div 2 then
      BatchChars := MAX_INPUTS_PER_BATCH div 2;
    InputCount := BatchChars * 2;
    FillChar(Inputs, SizeOf(Inputs), 0);
    for I := 0 to BatchChars - 1 do
    begin
      Inputs[I * 2].Itype := INPUT_KEYBOARD;
      Inputs[I * 2].ki.wVk := VK_BACK;
      Inputs[I * 2].ki.dwExtraInfo := LS_INPUT_TAG;
      Inputs[I * 2 + 1] := Inputs[I * 2];
      Inputs[I * 2 + 1].ki.dwFlags := KEYEVENTF_KEYUP;
    end;
    if SendInput(InputCount, Inputs[0], SizeOf(TInput)) <> UINT(InputCount) then
    begin
      DiagnosticsLogFmt('send_input.backspace_failed remaining=%d batch=%d error=%d',
        [Remaining, BatchChars, GetLastError]);
      Exit(False);
    end;
    Dec(Remaining, BatchChars);
  end;
end;

function TFormMain.TypeUnicodeText(const Value: WideString): Boolean;
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
    begin
      DiagnosticsLogFmt('send_input.unicode_failed offset=%d batch=%d error=%d',
        [Offset, BatchChars, GetLastError]);
      Exit(False);
    end;
    Inc(Offset, BatchChars);
  end;
end;

function TFormMain.DuplicateClipboardData(FormatID: UINT;
  SourceHandle: THandle; out DataSize: NativeUInt): THandle;
var
  SourceData, TargetData: Pointer;
  SourcePict, TargetPict: PMetaFilePict;
  NewMetaFile: HMETAFILE;
  EntryCount: UINT;
  PaletteSize: NativeUInt;
  LogPalette: PLogPalette;
  DummyPaletteEntry: TPaletteEntry;
begin
  Result := 0;
  DataSize := 0;
  if SourceHandle = 0 then
    Exit;

  case FormatID of
    CF_BITMAP, CF_DSPBITMAP:
      begin
        Result := THandle(CopyImage(SourceHandle, IMAGE_BITMAP, 0, 0,
          LR_CREATEDIBSECTION));
        Exit;
      end;

    CF_PALETTE:
      begin
        EntryCount := GetPaletteEntries(HPALETTE(SourceHandle), 0, 0,
          DummyPaletteEntry);
        if (EntryCount = 0) or (EntryCount > High(Word)) then
          Exit;
        PaletteSize := SizeOf(TLogPalette) +
          (EntryCount - 1) * SizeOf(TPaletteEntry);
        GetMem(LogPalette, PaletteSize);
        try
          FillChar(LogPalette^, PaletteSize, 0);
          LogPalette^.palVersion := $0300;
          LogPalette^.palNumEntries := Word(EntryCount);
          if GetPaletteEntries(HPALETTE(SourceHandle), 0, EntryCount,
               LogPalette^.palPalEntry[0]) <> EntryCount then
            Exit;
          Result := THandle(CreatePalette(LogPalette^));
        finally
          FreeMem(LogPalette);
        end;
        Exit;
      end;

    CF_ENHMETAFILE, CF_DSPENHMETAFILE:
      begin
        Result := THandle(CopyEnhMetaFile(HENHMETAFILE(SourceHandle), nil));
        Exit;
      end;

    CF_METAFILEPICT, CF_DSPMETAFILEPICT:
      begin
        SourcePict := GlobalLock(HGLOBAL(SourceHandle));
        if SourcePict = nil then
          Exit;
        try
          NewMetaFile := CopyMetaFile(SourcePict^.hMF, nil);
          if NewMetaFile = 0 then
            Exit;
          Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,
            SizeOf(TMetaFilePict));
          if Result = 0 then
          begin
            DeleteMetaFile(NewMetaFile);
            Exit;
          end;
          TargetPict := GlobalLock(HGLOBAL(Result));
          if TargetPict = nil then
          begin
            GlobalFree(HGLOBAL(Result));
            DeleteMetaFile(NewMetaFile);
            Result := 0;
            Exit;
          end;
          TargetPict^ := SourcePict^;
          TargetPict^.hMF := NewMetaFile;
          GlobalUnlock(HGLOBAL(Result));
          DataSize := SizeOf(TMetaFilePict);
        finally
          GlobalUnlock(HGLOBAL(SourceHandle));
        end;
        Exit;
      end;
  end;

  // Text, HTML, RTF, PNG, DIB, file lists and nearly all registered formats
  // are movable global-memory blocks.  Copy the bytes now so the snapshot no
  // longer depends on the original clipboard owner or a delayed IDataObject.
  DataSize := GlobalSize(HGLOBAL(SourceHandle));
  if DataSize = 0 then
    Exit;
  SourceData := GlobalLock(HGLOBAL(SourceHandle));
  if SourceData = nil then
    Exit;
  try
    Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, DataSize);
    if Result = 0 then
      Exit;
    TargetData := GlobalLock(HGLOBAL(Result));
    if TargetData = nil then
    begin
      GlobalFree(HGLOBAL(Result));
      Result := 0;
      Exit;
    end;
    Move(SourceData^, TargetData^, DataSize);
    GlobalUnlock(HGLOBAL(Result));
  finally
    GlobalUnlock(HGLOBAL(SourceHandle));
  end;
end;

procedure TFormMain.FreeClipboardData(FormatID: UINT; DataHandle: THandle);
var
  MetaFilePict: PMetaFilePict;
begin
  if DataHandle = 0 then
    Exit;
  case FormatID of
    CF_BITMAP, CF_DSPBITMAP, CF_PALETTE:
      DeleteObject(HGDIOBJ(DataHandle));
    CF_ENHMETAFILE, CF_DSPENHMETAFILE:
      DeleteEnhMetaFile(HENHMETAFILE(DataHandle));
    CF_METAFILEPICT, CF_DSPMETAFILEPICT:
      begin
        MetaFilePict := GlobalLock(HGLOBAL(DataHandle));
        if MetaFilePict <> nil then
        try
          if MetaFilePict^.hMF <> 0 then
            DeleteMetaFile(MetaFilePict^.hMF);
        finally
          GlobalUnlock(HGLOBAL(DataHandle));
        end;
        GlobalFree(HGLOBAL(DataHandle));
      end;
  else
    GlobalFree(HGLOBAL(DataHandle));
  end;
end;

function TFormMain.AddClipboardHistoryExclusion: Boolean;
const
  EXCLUSION_FORMAT_NAME = 'ExcludeClipboardContentFromMonitorProcessing';
var
  FormatID: UINT;
  DataHandle: HGLOBAL;
  Data: PCardinal;
begin
  Result := False;
  FormatID := RegisterClipboardFormat(EXCLUSION_FORMAT_NAME);
  if FormatID = 0 then
  begin
    DiagnosticsLogFmt('clipboard.history_exclusion register_failed error=%d',
      [GetLastError]);
    Exit;
  end;
  if IsClipboardFormatAvailable(FormatID) then
    Exit(True);

  DataHandle := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,
    SizeOf(Cardinal));
  if DataHandle = 0 then
  begin
    DiagnosticsLogFmt('clipboard.history_exclusion alloc_failed error=%d',
      [GetLastError]);
    Exit;
  end;
  Data := GlobalLock(DataHandle);
  if Data = nil then
  begin
    GlobalFree(DataHandle);
    DiagnosticsLogFmt('clipboard.history_exclusion lock_failed error=%d',
      [GetLastError]);
    Exit;
  end;
  Data^ := 1;
  GlobalUnlock(DataHandle);

  if SetClipboardData(FormatID, DataHandle) <> 0 then
  begin
    // The system owns the handle after SetClipboardData succeeds.
    DataHandle := 0;
    Result := True;
  end
  else
    DiagnosticsLogFmt('clipboard.history_exclusion set_failed error=%d',
      [GetLastError]);
  if DataHandle <> 0 then
    GlobalFree(DataHandle);
end;

function TFormMain.SaveClipboard: Boolean;
var
  Started: DWORD;
  ClipboardOpened: Boolean;
  FormatID, NextFormat, EnumerationError: UINT;
  SourceHandle: THandle;
  Snapshot: TClipboardFormatSnapshot;
  SourceFormatCount, SkippedFormatCount: Integer;
  TotalBytes: UInt64;
begin
  Result := False;

  // A failed restore must never poison all subsequent conversions.
  if FClipboardSnapshotValid or (Length(FSavedClipboardFormats) > 0) then
  begin
    DiagnosticsLog('clipboard.save stale_snapshot_reset=true');
    DiscardClipboardSnapshot;
  end;

  ClipboardOpened := False;
  Started := GetTickCount;
  repeat
    if OpenClipboard(Handle) then
    begin
      ClipboardOpened := True;
      Break;
    end;
    Sleep(CLIPBOARD_RETRY_INTERVAL);
  until GetTickCount - Started >= CLIPBOARD_OPEN_TIMEOUT;
  if not ClipboardOpened then
  begin
    DiagnosticsLogFmt('clipboard.save open_timeout error=%d', [GetLastError]);
    Exit;
  end;

  SourceFormatCount := 0;
  SkippedFormatCount := 0;
  TotalBytes := 0;
  EnumerationError := ERROR_SUCCESS;
  try
    FClipboardWasEmpty := CountClipboardFormats = 0;
    if FClipboardWasEmpty then
    begin
      FClipboardSnapshotValid := True;
      Result := True;
    end
    else
    begin
      FormatID := 0;
      while True do
      begin
        SetLastError(ERROR_SUCCESS);
        NextFormat := EnumClipboardFormats(FormatID);
        if NextFormat = 0 then
        begin
          EnumerationError := GetLastError;
          Break;
        end;
        FormatID := NextFormat;
        Inc(SourceFormatCount);

        SetLastError(ERROR_SUCCESS);
        SourceHandle := GetClipboardData(FormatID);
        if SourceHandle = 0 then
        begin
          Inc(SkippedFormatCount);
          DiagnosticsLogFmt(
            'clipboard.save format_skipped id=%d reason=get_data error=%d',
            [FormatID, GetLastError]);
          Continue;
        end;

        FillChar(Snapshot, SizeOf(Snapshot), 0);
        Snapshot.FormatID := FormatID;
        try
          Snapshot.DataHandle := DuplicateClipboardData(FormatID, SourceHandle,
            Snapshot.DataSize);
        except
          on E: Exception do
          begin
            Snapshot.DataHandle := 0;
            DiagnosticsLogFmt(
              'clipboard.save format_exception id=%d class=%s message="%s"',
              [FormatID, E.ClassName, E.Message]);
          end;
        end;
        if Snapshot.DataHandle = 0 then
        begin
          Inc(SkippedFormatCount);
          DiagnosticsLogFmt(
            'clipboard.save format_skipped id=%d reason=duplicate error=%d',
            [FormatID, GetLastError]);
          Continue;
        end;

        SetLength(FSavedClipboardFormats,
          Length(FSavedClipboardFormats) + 1);
        FSavedClipboardFormats[High(FSavedClipboardFormats)] := Snapshot;
        Inc(TotalBytes, Snapshot.DataSize);
      end;
      FClipboardSnapshotValid := Length(FSavedClipboardFormats) > 0;
      Result := FClipboardSnapshotValid;
    end;
  finally
    CloseClipboard;
  end;

  if (EnumerationError <> ERROR_SUCCESS) then
    DiagnosticsLogFmt('clipboard.save enumeration_failed error=%d',
      [EnumerationError]);
  DiagnosticsLogFmt(
    'clipboard.save success=%s empty=%s source_formats=%d saved_formats=%d skipped_formats=%d bytes=%d',
    [BoolToStr(Result, True), BoolToStr(FClipboardWasEmpty, True),
     SourceFormatCount, Length(FSavedClipboardFormats), SkippedFormatCount,
     Int64(TotalBytes)]);

  if not Result then
    DiscardClipboardSnapshot;
end;

procedure TFormMain.DiscardClipboardSnapshot;
var
  I: Integer;
begin
  FClipboardSnapshotValid := False;
  FClipboardWasEmpty := False;
  for I := 0 to High(FSavedClipboardFormats) do
  begin
    FreeClipboardData(FSavedClipboardFormats[I].FormatID,
      FSavedClipboardFormats[I].DataHandle);
    FSavedClipboardFormats[I].DataHandle := 0;
  end;
  SetLength(FSavedClipboardFormats, 0);
end;

procedure TFormMain.RestoreClipboard;
var
  WasEmpty, ClipboardOpened, ClipboardEmptied, Restored: Boolean;
  Started, LastErrorCode: DWORD;
  I, RestoredFormatCount, FailedFormatCount: Integer;
begin
  if not FClipboardSnapshotValid then
    Exit;

  WasEmpty := FClipboardWasEmpty;
  ClipboardOpened := False;
  ClipboardEmptied := False;
  RestoredFormatCount := 0;
  FailedFormatCount := 0;
  LastErrorCode := ERROR_SUCCESS;
  DiagnosticsLogFmt('clipboard.restore begin was_empty=%s formats=%d',
    [BoolToStr(WasEmpty, True), Length(FSavedClipboardFormats)]);
  try
    Started := GetTickCount;
    repeat
      if OpenClipboard(Handle) then
      begin
        ClipboardOpened := True;
        Break;
      end;
      LastErrorCode := GetLastError;
      Sleep(CLIPBOARD_RETRY_INTERVAL);
    until GetTickCount - Started >= CLIPBOARD_OPEN_TIMEOUT;

    if ClipboardOpened then
    try
      ClipboardEmptied := EmptyClipboard;
      if not ClipboardEmptied then
        LastErrorCode := GetLastError
      else
        for I := 0 to High(FSavedClipboardFormats) do
        begin
          SetLastError(ERROR_SUCCESS);
          if SetClipboardData(FSavedClipboardFormats[I].FormatID,
               FSavedClipboardFormats[I].DataHandle) <> 0 then
          begin
            // Ownership belongs to the system after a successful call.
            FSavedClipboardFormats[I].DataHandle := 0;
            Inc(RestoredFormatCount);
          end
          else
          begin
            LastErrorCode := GetLastError;
            Inc(FailedFormatCount);
            DiagnosticsLogFmt(
              'clipboard.restore format_failed id=%d error=%d',
              [FSavedClipboardFormats[I].FormatID, LastErrorCode]);
          end;
        end;
      if ClipboardEmptied and not WasEmpty then
        DiagnosticsLogFmt('clipboard.history_exclusion success=%s',
          [BoolToStr(AddClipboardHistoryExclusion, True)]);
    finally
      CloseClipboard;
    end;

    Restored := ClipboardEmptied and
      (WasEmpty or ((RestoredFormatCount > 0) and (FailedFormatCount = 0)));
    DiagnosticsLogFmt(
      'clipboard.restore success=%s opened=%s emptied=%s restored_formats=%d failed_formats=%d error=%d',
      [BoolToStr(Restored, True), BoolToStr(ClipboardOpened, True),
       BoolToStr(ClipboardEmptied, True), RestoredFormatCount,
       FailedFormatCount, LastErrorCode]);
  finally
    DiscardClipboardSnapshot;
  end;
end;

function TFormMain.GetClipboardTextW: WideString;
var
  DataHandle: HGLOBAL;
  Data: Pointer;
  Started: DWORD;
begin
  Result := '';
  Started := GetTickCount;
  while not OpenClipboard(Handle) do
  begin
    if GetTickCount - Started >= CLIPBOARD_OPEN_TIMEOUT then
      Exit;
    Sleep(CLIPBOARD_RETRY_INTERVAL);
  end;
  try
    DataHandle := GetClipboardData(CF_UNICODETEXT);
    if DataHandle = 0 then
      Exit;
    Data := GlobalLock(DataHandle);
    if Data <> nil then
    try
      Result := WideString(PWideChar(Data));
    finally
      GlobalUnlock(DataHandle);
    end;
  finally
    CloseClipboard;
  end;
end;

function TFormMain.FindHKLByLangID(LangID: Word): HKL;
var
  Layouts: array[0..63] of HKL;
  Count, I: Integer;
begin
  Result := 0;
  Count := GetKeyboardLayoutList(Length(Layouts), Layouts[0]);
  for I := 0 to Count - 1 do
    if LOWORD(Layouts[I]) = LangID then
      Exit(Layouts[I]);
end;

procedure TFormMain.SwitchGlobalLayout(ToLangID: Word);
var
  Layout: HKL;
  Target: HWND;
begin
  Layout := FindHKLByLangID(ToLangID);
  if Layout = 0 then
    Exit;
  Target := GetFocusedWindow;
  if Target <> 0 then
    PostMessage(Target, WM_INPUTLANGCHANGEREQUEST, 0, LPARAM(Layout));
end;

function TFormMain.ConvertLayout(const S: WideString): WideString;
var
  I, J: Integer;
  Ch: WideChar;
  Found, ToRussian: Boolean;
begin
  Result := '';
  if S = '' then
    Exit;
  ToRussian := not IsCyrillicText(S);

  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    Found := False;
    if ToRussian then
    begin
      for J := 1 to Length(EnChars) do
        if EnChars[J] = Ch then
        begin
          Result := Result + RuChars[J];
          Found := True;
          Break;
        end;
    end
    else
    begin
      for J := 1 to Length(RuChars) do
        if RuChars[J] = Ch then
        begin
          Result := Result + EnChars[J];
          Found := True;
          Break;
        end;
    end;
    if not Found then
      Result := Result + Ch;
  end;
end;

function TFormMain.ChangeStringCase(const S: WideString;
  ToUpper: Boolean): WideString;
begin
  if ToUpper then
    Result := WideUpperCase(S)
  else
    Result := WideLowerCase(S);
end;

function TFormMain.InvertStringCase(const S: WideString): WideString;
var
  I: Integer;
  Ch: WideChar;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if (Ch >= WideChar('a')) and (Ch <= WideChar('z')) then
      Result := Result + WideChar(Ord(Ch) - Ord('a') + Ord('A'))
    else if (Ch >= WideChar('A')) and (Ch <= WideChar('Z')) then
      Result := Result + WideChar(Ord(Ch) - Ord('A') + Ord('a'))
    else if (Ch >= WideChar('а')) and (Ch <= WideChar('я')) then
      Result := Result + WideChar(Ord(Ch) - Ord('а') + Ord('А'))
    else if (Ch >= WideChar('А')) and (Ch <= WideChar('Я')) then
      Result := Result + WideChar(Ord(Ch) - Ord('А') + Ord('а'))
    else if Ch = WideChar('ё') then
      Result := Result + WideChar('Ё')
    else if Ch = WideChar('Ё') then
      Result := Result + WideChar('ё')
    else
      Result := Result + Ch;
  end;
end;

procedure TFormMain.DoConvert;
var
  Text, ConvertedText: WideString;
  IsSelection: Boolean;
  Count: Integer;
  TargetLangID: Word;
begin
  if not TryGetTargetText(Text, IsSelection) or (Text = '') then
  begin
    DiagnosticsLog('convert.no_target');
    Exit;
  end;

  ConvertedText := ConvertLayout(Text);
  DiagnosticsLogFmt('convert.prepared input_length=%d output_length=%d selection=%s',
    [Length(Text), Length(ConvertedText), BoolToStr(IsSelection, True)]);
  if IsCyrillicText(Text) then
    TargetLangID := $0409
  else
    TargetLangID := $0419;

  if IsSelection then
  begin
    if ReplaceSelection(ConvertedText) then
    begin
      SetBufferText(ConvertedText);
      SwitchGlobalLayout(TargetLangID);
      DiagnosticsLog('convert.replace success=true source=selection');
    end
    else
    begin
      ClearBuffer;
      DiagnosticsLog('convert.replace success=false source=selection');
    end;
    Exit;
  end;

  Count := Length(FBuffer);
  ClearBuffer;
  if (Count > 0) and SendBackspaces(Count) and TypeUnicodeText(ConvertedText) then
  begin
    SetBufferText(ConvertedText);
    SwitchGlobalLayout(TargetLangID);
    DiagnosticsLog('convert.replace success=true source=buffer');
  end
  else
    DiagnosticsLog('convert.replace success=false source=buffer');
end;

procedure TFormMain.DoChangeCase(ToUpper: Boolean);
var
  Text, ConvertedText: WideString;
  IsSelection: Boolean;
  Count: Integer;
begin
  if not TryGetTargetText(Text, IsSelection) or (Text = '') then
  begin
    DiagnosticsLog('change_case.no_target');
    Exit;
  end;
  ConvertedText := ChangeStringCase(Text, ToUpper);
  DiagnosticsLogFmt('change_case.prepared length=%d selection=%s upper=%s',
    [Length(Text), BoolToStr(IsSelection, True), BoolToStr(ToUpper, True)]);

  if IsSelection then
  begin
    if ReplaceSelection(ConvertedText) then
      SetBufferText(ConvertedText)
    else
      ClearBuffer;
    Exit;
  end;

  Count := Length(FBuffer);
  ClearBuffer;
  if Count > 0 then
    if SendBackspaces(Count) then
      if TypeUnicodeText(ConvertedText) then
        SetBufferText(ConvertedText);
end;

procedure TFormMain.DoInvertCase;
var
  Text, ConvertedText: WideString;
  IsSelection: Boolean;
  Count: Integer;
begin
  if not TryGetTargetText(Text, IsSelection) or (Text = '') then
  begin
    DiagnosticsLog('invert_case.no_target');
    Exit;
  end;
  ConvertedText := InvertStringCase(Text);
  DiagnosticsLogFmt('invert_case.prepared length=%d selection=%s',
    [Length(Text), BoolToStr(IsSelection, True)]);

  if IsSelection then
  begin
    if ReplaceSelection(ConvertedText) then
      SetBufferText(ConvertedText)
    else
      ClearBuffer;
    Exit;
  end;

  Count := Length(FBuffer);
  ClearBuffer;
  if Count > 0 then
    if SendBackspaces(Count) then
      if TypeUnicodeText(ConvertedText) then
        SetBufferText(ConvertedText);
end;

procedure TFormMain.chkAutorunClick(Sender: TObject);
begin
  if chkAutorun.Checked then
    AddToStartup('LayoutSwitcher', Application.ExeName)
  else
    RemoveFromStartup('LayoutSwitcher');
end;

procedure TFormMain.chkDiagnosticsClick(Sender: TObject);
var
  Enabled: Boolean;
begin
  if FUpdatingDiagnosticsSetting then
    Exit;

  Enabled := chkDiagnostics.Checked;
  if not SetDiagnosticsEnabled(Enabled) then
  begin
    FUpdatingDiagnosticsSetting := True;
    try
      chkDiagnostics.Checked := DiagnosticsEnabled;
    finally
      FUpdatingDiagnosticsSetting := False;
    end;
    MessageBox(Handle,
      'Не удалось сохранить настройку диагностики в реестре.',
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

procedure TFormMain.TimerLayoutTimer(Sender: TObject);
begin
  UpdateTrayIcon;
end;

procedure TFormMain.UpdateTrayIcon;
var
  Target: HWND;
  ThreadID: DWORD;
  Layout: HKL;
  LangID: Word;
begin
  Target := GetFocusedWindow;
  if Target = 0 then
    Exit;
  ThreadID := GetWindowThreadProcessId(Target, nil);
  Layout := GetKeyboardLayout(ThreadID);
  LangID := LOWORD(Layout);
  if LangID = FLastLangID then
    Exit;
  FLastLangID := LangID;

  case LangID of
    $0409: TrayIcon.IconIndex := 0;
    $0419: TrayIcon.IconIndex := 1;
  else
    TrayIcon.Icon := Application.Icon;
  end;
end;

procedure TFormMain.TrayIconDblClick(Sender: TObject);
begin
  DiagnosticsLog('ui.settings_open');
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
  ShowWindow(Application.Handle, SW_SHOW);
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

end.
