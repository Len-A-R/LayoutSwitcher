unit uMain;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  ExtCtrls, Menus, System.ImageList, Vcl.ImgList, PngImageList, Vcl.StdCtrls;

const
  LLKHF_INJECTED = $00000010;
  WM_INPUTLANGCHANGEREQUEST = $0050;
  DOUBLE_SHIFT_INTERVAL = 500; // мс между нажатиями Shift
  DOUBLE_CTRL_INTERVAL = 500;  // мс между нажатиями Ctrl
  STICKY_SHIFT_MAX_PRESSES = 4; // 5-е чистое нажатие Shift вызывает Sticky Keys
  LS_SPI_GETSTICKYKEYS = $003A;
  LS_SPI_SETSTICKYKEYS = $003B;
  LS_SKF_HOTKEYACTIVE = $00000004;
  LS_SKF_CONFIRMHOTKEY = $00000008;

type
  PHKL = ^HKL;
  TMyKBDLLHOOKSTRUCT = packed record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: DWORD;
  end;
  PMyKBDLLHOOKSTRUCT = ^TMyKBDLLHOOKSTRUCT;

  TVKRecord = record
    VK: Byte;
    Shift: Boolean;
  end;

  TLSStickyKeys = record
    cbSize: UINT;
    dwFlags: DWORD;
  end;

  TFormMain = class(TForm)
    TrayIcon: TTrayIcon;
    PopupMenu: TPopupMenu;
    mniExit: TMenuItem;
    TrayIcons: TPngImageList;
    TimerLayout: TTimer;
    chkAutorun: TCheckBox;
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
    procedure TimerLayoutTimer(Sender: TObject);
    procedure chkAutorunClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TrayIconDblClick(Sender: TObject);
  private
    FVKBuffer: array of TVKRecord;
    FLastWindow: HWND;
    FSavedClipboard: HGLOBAL;
    FClipboardHadText: Boolean;
    FLastLangID: DWORD;         // Последняя раскладка клавиатуры
    FLastShiftTime: DWORD;      // Время последнего нажатия Shift
    FShiftPressed: Boolean;     // Флаг что Shift уже был нажат (для двойного)
    FPureShiftPressCount: Integer; // Счётчик для подавления Sticky Keys
    FOriginalStickyKeys: TLSStickyKeys;
    FStickyKeysSaved: Boolean;
    FLastLCtrlTime: DWORD;      // Время последнего нажатия ЛЕВОГО Ctrl
    FLCtrlPressed: Boolean;     // Флаг ожидания второго ЛЕВОГО Ctrl
    FLastRCtrlTime: DWORD;      // Время последнего нажатия ПРАВОГО Ctrl
    FRCtrlPressed: Boolean;     // Флаг ожидания второго ПРАВОГО Ctrl
    procedure WndProc(var Message: TMessage); override;
    procedure DoConvert;
    procedure DoChangeCase(ToUpper: Boolean);
    procedure DoInvertCase;
    procedure SwitchGlobalLayout(ToLangID: Word);
    function GetSelectedTextInActiveWindow(out Text: WideString): Boolean;
    function GetSelectedTextByClipboardFallback(out Text: WideString): Boolean;
    function GetWordAtCursor(out Text: WideString): Boolean;
    function TryGetTargetText(out Text: WideString; out IsSelection: Boolean): Boolean;
    function VKBufferToString: WideString;
    procedure SimulateCopy;
    procedure SimulatePaste;
    procedure TypeUnicodeText(const Value: WideString);
    function ConvertLayout(const S: WideString): WideString;
    function ChangeStringCase(const S: WideString; ToUpper: Boolean): WideString;
    procedure SaveClipboard;
    procedure RestoreClipboard;
    function GetClipboardTextW: WideString;
    procedure SetClipboardTextW(const Value: WideString);
    procedure CheckWindowChanged;
    function FindHKLByLangID(LangID: Word): HKL;
    function IsPrintableKey(vkCode, scanCode: DWORD; hkl: HKL): Boolean;
    procedure UpdateTrayIcon;
    procedure DisableStickyKeysHotkey;
    procedure RestoreStickyKeysHotkey;
  public
    procedure AddVK(VK: Byte; Shift: Boolean);
    procedure BufferBackspace;
    procedure ClearBuffer;
    procedure FinalizeWord;
  end;

var
  FormMain: TFormMain;
  hKeyHook: HHOOK;
  hMouseHook: HHOOK;
  IsConverting: Boolean;

function MyToUnicodeEx(wVirtKey, wScanCode: UINT; lpKeyState: PByte;
  pwszBuff: PWideChar; cchBuff: Integer; wFlags: UINT; dwhkl: HKL): Integer; stdcall;
  external 'user32.dll' name 'ToUnicodeEx';

function MapVirtualKeyExW(uCode, uMapType: UINT; dwhkl: HKL): UINT; stdcall;
  external 'user32.dll' name 'MapVirtualKeyExW';

function MyGetKeyboardLayoutList(nBuff: Integer; List: PHKL): Integer; stdcall;
  external 'user32.dll' name 'GetKeyboardLayoutList';

implementation

{$R *.dfm}

uses Registry;

const
  WM_DO_CONVERT          = WM_USER + 1;  // Универсальная конвертация
  WM_DO_UPPERCASE        = WM_USER + 2;
  WM_DO_LOWERCASE        = WM_USER + 3;
  WM_DO_INVERT_CASE      = WM_USER + 4;
  MAX_WORD_LEN = 50;

  EnChars: WideString = '''
  `1234567890-=qwertyuiop[]asdfghjkl;'\zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:"|ZXCVBNM<>?
  ''';
  RuChars: WideString = '''
  ё1234567890-=йцукенгшщзхъфывапролджэ\ячсмитьбю.Ё!"№;%:?*()_+ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭ/ЯЧСМИТЬБЮ,
  ''';

type
  // Для GetGUIThreadInfo (координаты каретки)
  TMyGUIThreadInfo = record
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

function MyGetGUIThreadInfo(idThread: DWORD; var lpgui: TMyGUIThreadInfo): BOOL; stdcall;
  external 'user32.dll' name 'GetGUIThreadInfo';

procedure AddToStartup(const AppName, AppPath: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', True) then
    begin
      Reg.WriteString(AppName, AppPath);
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
    begin
      Reg.DeleteValue(AppName);
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

//------------------------------------------------------------------------------
function TFormMain.IsPrintableKey(vkCode, scanCode: DWORD; hkl: HKL): Boolean;
var
  kbState: TKeyboardState;
  buf: array[0..1] of WideChar;
  ret: Integer;
begin
  Result := False;
  if hkl = 0 then Exit;

  ZeroMemory(@kbState, SizeOf(kbState));
  if (GetAsyncKeyState(VK_SHIFT)   and $8000) <> 0 then kbState[VK_SHIFT]   := $80;
  if (GetAsyncKeyState(VK_LSHIFT)  and $8000) <> 0 then kbState[VK_LSHIFT]  := $80;
  if (GetAsyncKeyState(VK_RSHIFT)  and $8000) <> 0 then kbState[VK_RSHIFT]  := $80;
  if (GetAsyncKeyState(VK_CONTROL) and $8000) <> 0 then kbState[VK_CONTROL] := $80;
  if (GetAsyncKeyState(VK_LCONTROL)and $8000) <> 0 then kbState[VK_LCONTROL]:= $80;
  if (GetAsyncKeyState(VK_RCONTROL)and $8000) <> 0 then kbState[VK_RCONTROL]:= $80;
  if (GetAsyncKeyState(VK_MENU)    and $8000) <> 0 then kbState[VK_MENU]    := $80;
  if (GetAsyncKeyState(VK_LMENU)   and $8000) <> 0 then kbState[VK_LMENU]   := $80;
  if (GetAsyncKeyState(VK_RMENU)   and $8000) <> 0 then kbState[VK_RMENU]   := $80;
  if (GetAsyncKeyState(VK_CAPITAL) and $0001) <> 0 then kbState[VK_CAPITAL] := $01;
  if (GetAsyncKeyState(VK_NUMLOCK) and $0001) <> 0 then kbState[VK_NUMLOCK] := $01;

  ret := MyToUnicodeEx(vkCode, scanCode, @kbState, @buf, 2, 0, hkl);
  Result := (ret > 0) and ((Ord(buf[0]) >= 32) or (buf[0] = WideChar(9)));
end;

//------------------------------------------------------------------------------
function KeyboardHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  pkbhs: PMyKBDLLHOOKSTRUCT;
  hkl: Windows.HKL;
  threadId: DWORD;
  ShiftPressed: Boolean;
  CurrentTime: DWORD;
  // === ДОБАВЛЕНО: проверка чистоты нажатия ===
  IsPureShift, IsPureLCtrl, IsPureRCtrl: Boolean;
begin
  // ВСЕГДА передаём дальше, если не обрабатываем
  Result := CallNextHookEx(hKeyHook, nCode, wParam, lParam);

  if nCode <> HC_ACTION then Exit;

  pkbhs := PMyKBDLLHOOKSTRUCT(lParam);

  // Игнорируем инжектированные (наши собственные) и системные
  if (pkbhs^.flags and LLKHF_INJECTED) <> 0 then Exit;

  if Assigned(FormMain) then FormMain.CheckWindowChanged;

  // === ПРОВЕРКА: нажатие "чистое" (без других модификаторов) ===
  // Только если НЕ зажаты Ctrl, Alt, Win — считаем чистым Shift
  IsPureShift := (pkbhs^.vkCode = VK_SHIFT) or
                 (pkbhs^.vkCode = VK_LSHIFT) or
                 (pkbhs^.vkCode = VK_RSHIFT);
  if IsPureShift then
    IsPureShift := IsPureShift and
                   (GetAsyncKeyState(VK_CONTROL) >= 0) and
                   (GetAsyncKeyState(VK_MENU) >= 0) and
                   (GetAsyncKeyState(VK_LWIN) >= 0) and
                   (GetAsyncKeyState(VK_RWIN) >= 0);

  // Только если НЕ зажаты Shift, Alt, Win — считаем чистым LCtrl
  IsPureLCtrl := (pkbhs^.vkCode = VK_LCONTROL);
  if IsPureLCtrl then
    IsPureLCtrl := IsPureLCtrl and
                   (GetAsyncKeyState(VK_SHIFT) >= 0) and
                   (GetAsyncKeyState(VK_MENU) >= 0) and
                   (GetAsyncKeyState(VK_RCONTROL) >= 0) and  // RCtrl тоже не должен быть зажат
                   (GetAsyncKeyState(VK_LWIN) >= 0) and
                   (GetAsyncKeyState(VK_RWIN) >= 0);

  // Только если НЕ зажаты Shift, Alt, Win — считаем чистым RCtrl
  IsPureRCtrl := (pkbhs^.vkCode = VK_RCONTROL);
  if IsPureRCtrl then
    IsPureRCtrl := IsPureRCtrl and
                   (GetAsyncKeyState(VK_SHIFT) >= 0) and
                   (GetAsyncKeyState(VK_MENU) >= 0) and
                   (GetAsyncKeyState(VK_LCONTROL) >= 0) and  // LCtrl тоже не должен быть зажат
                   (GetAsyncKeyState(VK_LWIN) >= 0) and
                   (GetAsyncKeyState(VK_RWIN) >= 0);

  // --- ОБРАБОТКА ДВОЙНОГО SHIFT (только чистое нажатие) ---
  if (wParam = WM_KEYDOWN) and IsPureShift then
  begin
    CurrentTime := GetTickCount;
    Inc(FormMain.FPureShiftPressCount);
    if FormMain.FPureShiftPressCount > STICKY_SHIFT_MAX_PRESSES then
    begin
      FormMain.FPureShiftPressCount := 0;
      FormMain.FShiftPressed := False;
      Result := 1;
      Exit;
    end;

    if FormMain.FShiftPressed and
       (CurrentTime - FormMain.FLastShiftTime <= DOUBLE_SHIFT_INTERVAL) then
    begin
      // Двойное нажатие Shift!
      FormMain.FShiftPressed := False;
      if not IsConverting then
      begin
        IsConverting := True;
        PostMessage(FormMain.Handle, WM_DO_CONVERT, 0, 0);
        Result := 1; // Блокируем только это нажатие
      end;
      Exit;
    end
    else
    begin
      FormMain.FShiftPressed := True;
      FormMain.FLastShiftTime := CurrentTime;
    end;
  end
  else if (wParam = WM_KEYDOWN) and not IsPureShift and
          not ((pkbhs^.vkCode = VK_CONTROL) or (pkbhs^.vkCode = VK_MENU) or
               (pkbhs^.vkCode = VK_LWIN) or (pkbhs^.vkCode = VK_RWIN)) then
  begin
    // Любая другая клавиша сбрасывает ожидание двойного Shift
    // Но НЕ сбрасываем при нажатии модификаторов (чтобы Ctrl+Shift не сбрасывал)
    FormMain.FShiftPressed := False;
    FormMain.FPureShiftPressCount := 0;
  end;

  // --- ОБРАБОТКА ДВОЙНОГО CTRL (только чистое нажатие) ---
  if (wParam = WM_KEYDOWN) and (IsPureLCtrl or IsPureRCtrl) then
  begin
    CurrentTime := GetTickCount;

    // Двойной ЛЕВЫЙ Ctrl — ВЕРХНИЙ регистр
    if IsPureLCtrl then
    begin
      if FormMain.FLCtrlPressed and
         (CurrentTime - FormMain.FLastLCtrlTime <= DOUBLE_CTRL_INTERVAL) then
      begin
        FormMain.FLCtrlPressed := False;
        if not IsConverting then
        begin
          IsConverting := True;
          PostMessage(FormMain.Handle, WM_DO_UPPERCASE, 0, 0);
          Result := 1;
        end;
        Exit;
      end
      else
      begin
        FormMain.FLCtrlPressed := True;
        FormMain.FLastLCtrlTime := CurrentTime;
      end;
    end;

    // Двойной ПРАВЫЙ Ctrl — нижний регистр
    if IsPureRCtrl then
    begin
      if FormMain.FRCtrlPressed and
         (CurrentTime - FormMain.FLastRCtrlTime <= DOUBLE_CTRL_INTERVAL) then
      begin
        FormMain.FRCtrlPressed := False;
        if not IsConverting then
        begin
          IsConverting := True;
          PostMessage(FormMain.Handle, WM_DO_LOWERCASE, 0, 0);
          Result := 1;
        end;
        Exit;
      end
      else
      begin
        FormMain.FRCtrlPressed := True;
        FormMain.FLastRCtrlTime := CurrentTime;
      end;
    end;
  end
  else if (wParam = WM_KEYDOWN) and not (IsPureLCtrl or IsPureRCtrl) and
          not ((pkbhs^.vkCode = VK_SHIFT) or (pkbhs^.vkCode = VK_MENU) or
               (pkbhs^.vkCode = VK_LWIN) or (pkbhs^.vkCode = VK_RWIN)) then
  begin
    // Сбрасываем ожидание Ctrl только при "реальных" клавишах, не модификаторах
    FormMain.FLCtrlPressed := False;
    FormMain.FRCtrlPressed := False;
  end;

  // --- LCtrl + RCtrl одновременно — инвертирование регистра ---
  // Проверяем при нажатии ЛЕВОГО, если ПРАВЫЙ уже зажат (и наоборот)
  // Но только если не было "чистого" двойного нажатия выше
  if (wParam = WM_KEYDOWN) and not IsConverting then
  begin
    if (pkbhs^.vkCode = VK_LCONTROL) and (GetAsyncKeyState(VK_RCONTROL) < 0) then
    begin
      IsConverting := True;
      PostMessage(FormMain.Handle, WM_DO_INVERT_CASE, 0, 0);
      Result := 1;
      Exit;
    end;
    if (pkbhs^.vkCode = VK_RCONTROL) and (GetAsyncKeyState(VK_LCONTROL) < 0) then
    begin
      IsConverting := True;
      PostMessage(FormMain.Handle, WM_DO_INVERT_CASE, 0, 0);
      Result := 1;
      Exit;
    end;
  end;

  // --- БУФЕР ВВОДА (только если не конвертируем) ---
  if not IsConverting then
  begin
    if wParam = WM_KEYDOWN then
    begin
      if (pkbhs^.vkCode = VK_LEFT)  or (pkbhs^.vkCode = VK_RIGHT) or
         (pkbhs^.vkCode = VK_UP)    or (pkbhs^.vkCode = VK_DOWN)  or
         (pkbhs^.vkCode = VK_HOME)  or (pkbhs^.vkCode = VK_END)   or
         (pkbhs^.vkCode = VK_PRIOR) or (pkbhs^.vkCode = VK_NEXT)  or
         (pkbhs^.vkCode = VK_ESCAPE) or (pkbhs^.vkCode = VK_DELETE) then
      begin
        if Assigned(FormMain) then FormMain.ClearBuffer;
      end
      else if pkbhs^.vkCode = VK_BACK then
      begin
        if Assigned(FormMain) then FormMain.BufferBackspace;
      end
      else if (pkbhs^.vkCode = VK_RETURN) or (pkbhs^.vkCode = VK_TAB) or
              (pkbhs^.vkCode = VK_SPACE) then
      begin
        if Assigned(FormMain) then FormMain.FinalizeWord;
      end
      else if (pkbhs^.vkCode = VK_SHIFT)   or (pkbhs^.vkCode = VK_LSHIFT) or
              (pkbhs^.vkCode = VK_RSHIFT)  or (pkbhs^.vkCode = VK_CONTROL) or
              (pkbhs^.vkCode = VK_LCONTROL)or (pkbhs^.vkCode = VK_RCONTROL)or
              (pkbhs^.vkCode = VK_MENU)    or (pkbhs^.vkCode = VK_LMENU)  or
              (pkbhs^.vkCode = VK_RMENU)   or (pkbhs^.vkCode = VK_LWIN)   or
              (pkbhs^.vkCode = VK_RWIN) then
      begin
        // nothing — модификаторы не попадают в буфер
      end
      else if GetAsyncKeyState(VK_CONTROL) < 0 then
      begin
        if (pkbhs^.vkCode = Ord('C')) or (pkbhs^.vkCode = Ord('X')) or
           (pkbhs^.vkCode = Ord('V')) then
          if Assigned(FormMain) then FormMain.ClearBuffer;
      end
      else
      begin
        threadId := GetWindowThreadProcessId(GetForegroundWindow, nil);
        hkl := GetKeyboardLayout(threadId);
        if FormMain.IsPrintableKey(pkbhs^.vkCode, pkbhs^.scanCode, hkl) then
        begin
          ShiftPressed := (GetAsyncKeyState(VK_SHIFT) and $8000) <> 0;
          if Assigned(FormMain) then FormMain.AddVK(pkbhs^.vkCode, ShiftPressed);
        end;
      end;
    end;
  end;
end;

//------------------------------------------------------------------------------
function MouseHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if nCode = HC_ACTION then
  begin
    if (wParam = WM_LBUTTONDOWN) or (wParam = WM_RBUTTONDOWN) or
       (wParam = WM_MBUTTONDOWN) or (wParam = WM_MOUSEWHEEL) then
    begin
      if Assigned(FormMain) then
      begin
        FormMain.ClearBuffer;
        FormMain.FShiftPressed := False;
        FormMain.FPureShiftPressCount := 0;
        FormMain.FLCtrlPressed := False;
        FormMain.FRCtrlPressed := False;
      end;
    end;
  end;
  Result := CallNextHookEx(hMouseHook, nCode, wParam, lParam);
end;

//------------------------------------------------------------------------------
// Определяет, является ли текст кириллическим (русская раскладка)
function IsCyrillicText(const S: WideString): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to Length(S) do
    if ((S[i] >= WideChar('а')) and (S[i] <= WideChar('я'))) or
       ((S[i] >= WideChar('А')) and (S[i] <= WideChar('Я'))) or
       (S[i] = WideChar('ё')) or (S[i] = WideChar('Ё')) then
    begin
      Result := True;
      Exit;
    end;
end;

//------------------------------------------------------------------------------
procedure TFormMain.DisableStickyKeysHotkey;
var
  StickyKeys: TLSStickyKeys;
begin
  FStickyKeysSaved := False;
  ZeroMemory(@FOriginalStickyKeys, SizeOf(FOriginalStickyKeys));

  ZeroMemory(@StickyKeys, SizeOf(StickyKeys));
  StickyKeys.cbSize := SizeOf(StickyKeys);
  if not SystemParametersInfo(LS_SPI_GETSTICKYKEYS, SizeOf(StickyKeys),
                              @StickyKeys, 0) then
    Exit;

  FOriginalStickyKeys := StickyKeys;
  FStickyKeysSaved := True;

  StickyKeys.dwFlags := StickyKeys.dwFlags and
                        not (LS_SKF_HOTKEYACTIVE or LS_SKF_CONFIRMHOTKEY);
  SystemParametersInfo(LS_SPI_SETSTICKYKEYS, SizeOf(StickyKeys),
                       @StickyKeys, 0);
end;

procedure TFormMain.RestoreStickyKeysHotkey;
begin
  if not FStickyKeysSaved then Exit;

  FOriginalStickyKeys.cbSize := SizeOf(FOriginalStickyKeys);
  SystemParametersInfo(LS_SPI_SETSTICKYKEYS, SizeOf(FOriginalStickyKeys),
                       @FOriginalStickyKeys, 0);
  FStickyKeysSaved := False;
end;

//------------------------------------------------------------------------------
procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := False;
  Hide;
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  SetLength(FVKBuffer, 0);
  FLastWindow := 0;
  FSavedClipboard := 0;
  FClipboardHadText := False;
  FLastShiftTime := 0;
  FShiftPressed := False;
  FPureShiftPressCount := 0;
  FStickyKeysSaved := False;
  FLastLCtrlTime := 0;
  FLCtrlPressed := False;
  FLastRCtrlTime := 0;
  FRCtrlPressed := False;
  //Проверяем находимся ли в автозапуске
  chkAutorun.Checked := IsInStartup('LayoutSwitcher');
  ShowInTaskBar := False;

  SetWindowLong(Application.Handle, GWL_EXSTYLE,
  GetWindowLong(Application.Handle, GWL_EXSTYLE) and not WS_EX_APPWINDOW);

  DisableStickyKeysHotkey;

  hKeyHook := SetWindowsHookEx(WH_KEYBOARD_LL, @KeyboardHookProc, HInstance, 0);
  if hKeyHook = 0 then
    MessageBox(0, 'Cannot install keyboard hook!', 'LayoutSwitcher', MB_OK or MB_ICONERROR);

  hMouseHook := 0;

  TrayIcon.Hint := '''
  Layout Switcher
  Dbl Shift=Конвертация
  Dbl LCtrl=ВЕРХНИЙ регистр
  Dbl RCtrl=нижний регистр
  LCtrl+RCtrl=Инвертировать регистр
  ''';
  WindowState := wsMinimized;
  Hide;
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  if hKeyHook <> 0 then UnhookWindowsHookEx(hKeyHook);
  if hMouseHook <> 0 then UnhookWindowsHookEx(hMouseHook);
  RestoreStickyKeysHotkey;
  RestoreClipboard;
end;

procedure TFormMain.CheckWindowChanged;
var
  h: HWND;
begin
  h := GetForegroundWindow;
  if h <> FLastWindow then
  begin
    FLastWindow := h;
    ClearBuffer;
    FShiftPressed := False;
    FPureShiftPressCount := 0;
    FLCtrlPressed := False;
    FRCtrlPressed := False;
  end;
end;

procedure TFormMain.chkAutorunClick(Sender: TObject);
begin
  if chkAutorun.Checked then
    AddToStartup('LayoutSwitcher', Application.ExeName)
  else
    RemoveFromStartup('LayoutSwitcher');
end;

procedure TFormMain.WndProc(var Message: TMessage);
begin
  case Message.Msg of
    WM_DO_CONVERT:
      try
        DoConvert;
      finally
        IsConverting := False;
        FShiftPressed := False;
        FPureShiftPressCount := 0;
      end;
    WM_DO_UPPERCASE:
      try
        DoChangeCase(True);
      finally
        FLCtrlPressed := False;  // сброс на всякий случай
        IsConverting := False;
      end;
    WM_DO_LOWERCASE:
      try
        DoChangeCase(False);
      finally
        IsConverting := False;
        FRCtrlPressed := False;  // сброс на всякий случай
      end;
    WM_DO_INVERT_CASE:
      try
        DoInvertCase;
      finally
        IsConverting := False;
        FLCtrlPressed := False;
        FRCtrlPressed := False;
      end;
  else
    inherited WndProc(Message);
  end;
end;

//------------------------------------------------------------------------------
// Буфер нажатых клавиш
//------------------------------------------------------------------------------
procedure TFormMain.AddVK(VK: Byte; Shift: Boolean);
begin
  if Length(FVKBuffer) >= MAX_WORD_LEN then Exit;
  SetLength(FVKBuffer, Length(FVKBuffer) + 1);
  FVKBuffer[High(FVKBuffer)].VK := VK;
  FVKBuffer[High(FVKBuffer)].Shift := Shift;
end;

procedure TFormMain.BufferBackspace;
begin
  if Length(FVKBuffer) > 0 then
    SetLength(FVKBuffer, Length(FVKBuffer) - 1);
end;

procedure TFormMain.ClearBuffer;
begin
  SetLength(FVKBuffer, 0);
end;

procedure TFormMain.FinalizeWord;
begin
  SetLength(FVKBuffer, 0);
end;

//------------------------------------------------------------------------------
function TFormMain.FindHKLByLangID(LangID: Word): HKL;
var
  KL: array[0..63] of HKL;
  Count, i: Integer;
begin
  Result := 0;
  Count := MyGetKeyboardLayoutList(64, @KL);
  for i := 0 to Count - 1 do
    if LOWORD(KL[i]) = LangID then
    begin
      Result := KL[i];
      Exit;
    end;
end;

//------------------------------------------------------------------------------
// ГЛОБАЛЬНОЕ переключение раскладки системной клавиатуры
//------------------------------------------------------------------------------
procedure TFormMain.SwitchGlobalLayout(ToLangID: Word);
var
  hkl: Windows.HKL;
  hForeground: HWND;
  threadId: DWORD;
begin
  hkl := FindHKLByLangID(ToLangID);
  if hkl = 0 then Exit;

  // Переключаем раскладку для текущего потока (нашего)
  ActivateKeyboardLayout(hkl, 0);

  // Переключаем раскладку для активного окна
  hForeground := GetForegroundWindow;
  if hForeground <> 0 then
  begin
    threadId := GetWindowThreadProcessId(hForeground, nil);
    PostMessage(hForeground, WM_INPUTLANGCHANGEREQUEST, 0, hkl);
  end;

  // Также переключаем для всех потоков через SendMessage HWND_BROADCAST
  // (не всегда работает, но пробуем)
  PostMessage(HWND_BROADCAST, WM_INPUTLANGCHANGEREQUEST, 0, hkl);
end;

procedure TFormMain.TimerLayoutTimer(Sender: TObject);
begin
  UpdateTrayIcon;
end;

procedure TFormMain.TrayIconDblClick(Sender: TObject);
begin
  // Восстанавливаем окно
  Show;
  WindowState := wsNormal;
  Application.BringToFront;

  // Возвращаем кнопку Application, если скрывали
  ShowWindow(Application.Handle, SW_SHOW);
end;

procedure TFormMain.UpdateTrayIcon;
var
  hForeground: HWND;
  threadId: DWORD;
  hkl: Windows.HKL;
  LangID: Word;
  LangName: string;
begin
  hForeground := GetForegroundWindow;
  if hForeground = 0 then Exit;

  threadId := GetWindowThreadProcessId(hForeground, nil);
  hkl := GetKeyboardLayout(threadId);
  LangID := LOWORD(hkl);

  // Если не изменилось — выходим
  if LangID = FLastLangID then Exit;
  FLastLangID := LangID;

  // Выбираем иконку и подсказку
  case LangID of
    $0409: begin  // Английская (US)
             TrayIcon.IconIndex := 0;
             LangName := 'EN';
           end;
    $0419: begin  // Русская
             TrayIcon.IconIndex := 1;
             LangName := 'RU';
           end;
  else
    // Другие языки — стандартная иконка приложения
    TrayIcon.Icon := Application.Icon;
    LangName := Format('Lang %.4x', [LangID]);
  end;
end;

//------------------------------------------------------------------------------
// Получение выделения в стандартных Edit/RichEdit без clipboard
//------------------------------------------------------------------------------
function TFormMain.GetSelectedTextInActiveWindow(out Text: WideString): Boolean;
var
  hWnd: Windows.HWND;
  startSel, endSel: DWORD;
  className: array[0..255] of Char;
  guiInfo: TMyGUIThreadInfo;
  Len, Copied: Integer;
  Buffer: WideString;
begin
  Result := False;
  Text := '';
  hWnd := GetForegroundWindow;
  if hWnd = 0 then Exit;

  ZeroMemory(@guiInfo, SizeOf(guiInfo));
  guiInfo.cbSize := SizeOf(guiInfo);
  if MyGetGUIThreadInfo(GetWindowThreadProcessId(hWnd, nil), guiInfo) and
     (guiInfo.hwndFocus <> 0) then
    hWnd := guiInfo.hwndFocus;

  GetClassName(hWnd, @className, 256);
  if (Pos('Edit', className) > 0) or (Pos('RichEdit', className) > 0) or
     (Pos('TMemo', className) > 0) or (Pos('TEdit', className) > 0) then
  begin
    SendMessage(hWnd, EM_GETSEL, WPARAM(@startSel), LPARAM(@endSel));
    if startSel = endSel then Exit;

    Len := GetWindowTextLengthW(hWnd);
    if Len <= 0 then Exit;
    if endSel > DWORD(Len) then Exit;
    if startSel > endSel then Exit;

    SetLength(Buffer, Len + 1);
    Copied := SendMessageW(hWnd, WM_GETTEXT, WPARAM(Len + 1), LPARAM(PWideChar(Buffer)));
    if Copied <= 0 then Exit;
    SetLength(Buffer, Copied);

    Text := Copy(Buffer, startSel + 1, endSel - startSel);
    Result := Text <> '';
  end;
end;

function TFormMain.GetSelectedTextByClipboardFallback(out Text: WideString): Boolean;
begin
  Result := False;
  Text := '';

  SaveClipboard;
  try
    SimulateCopy;
    Text := GetClipboardTextW;

    if Text = '' then Exit;

    // VS Code with an empty selection may copy the whole current line including
    // a line break. Treat that as "no explicit selection" to avoid replacing a line.
    if (Text[Length(Text)] = #10) or (Text[Length(Text)] = #13) then
    begin
      Text := '';
      Exit;
    end;

    Result := True;
  finally
    RestoreClipboard;
  end;
end;

//------------------------------------------------------------------------------
// ДВОЙНОЙ КЛИК МЫШЬЮ в позиции каретки для выделения слова.
// Если каретка недоступна — fallback на Ctrl+Shift+Left.
//------------------------------------------------------------------------------
function TFormMain.GetWordAtCursor(out Text: WideString): Boolean;
label KEYBOARD_FALLBACK;
var
  OldClipboardText: WideString;
  pt: TPoint;
  hWnd: Windows.HWND;
  guiInfo: TMyGUIThreadInfo;
  cxScreen, cyScreen: Integer;
  inputs: array[0..7] of TInput;
  i: Integer;
  className: array[0..255] of Char;
  MouseRestored: Boolean;
  OriginalCursorPos: TPoint;
begin
  Result := False;
  Text := '';
  MouseRestored := False;

  hWnd := GetForegroundWindow;
  if hWnd = 0 then Exit;

  // === ЗАЩИТА: не используем мышь в окнах скриншотеров и некоторых приложениях ===
  GetClassName(hWnd, @className, 256);
  // Список классов окон, где мышиный клик опасен (скриншотеры, рисовалки и т.д.)
  if (Pos('ShareX', className) > 0) or
     (Pos('Screenshot', className) > 0) or
     (Pos('Lightshot', className) > 0) or
     (Pos('Greenshot', className) > 0) or
     (Pos('SnippingTool', className) > 0) or  // Ножницы Windows
     (Pos('Screenpresso', className) > 0) or
     (Pos('PicPick', className) > 0) or
     (Pos('Fullscreen', className) > 0) then   // Некоторые игры в полный экран
  begin
    // Переходим сразу к keyboard fallback (Ctrl+Shift+Left)
    goto KEYBOARD_FALLBACK;
  end;

  // Запоминаем текущую позицию курсора для восстановления
  GetCursorPos(OriginalCursorPos);

  // Пытаемся получить позицию каретки
  ZeroMemory(@guiInfo, SizeOf(guiInfo));
  guiInfo.cbSize := SizeOf(guiInfo);

  if MyGetGUIThreadInfo(GetWindowThreadProcessId(hWnd, nil), guiInfo) and
     (guiInfo.hwndCaret <> 0) then
  begin
    // === Есть каретка: двойной клик мышью ===
    hWnd := guiInfo.hwndCaret;
    pt.X := guiInfo.rcCaret.Left + (guiInfo.rcCaret.Right - guiInfo.rcCaret.Left) div 2;
    pt.Y := guiInfo.rcCaret.Top + (guiInfo.rcCaret.Bottom - guiInfo.rcCaret.Top) div 2;
    Windows.ClientToScreen(hWnd, pt);

    OldClipboardText := GetClipboardTextW;
    SaveClipboard;

    cxScreen := GetSystemMetrics(SM_CXSCREEN);
    cyScreen := GetSystemMetrics(SM_CYSCREEN);

    ZeroMemory(@inputs, SizeOf(inputs));

    // Перемещаем мышь абсолютно
    inputs[0].Itype := INPUT_MOUSE;
    inputs[0].mi.dx := MulDiv(pt.X, 65535, cxScreen);
    inputs[0].mi.dy := MulDiv(pt.Y, 65535, cyScreen);
    inputs[0].mi.dwFlags := MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_MOVE;

    // Первый клик
    inputs[1].Itype := INPUT_MOUSE;
    inputs[1].mi.dwFlags := MOUSEEVENTF_LEFTDOWN;
    inputs[2].Itype := INPUT_MOUSE;
    inputs[2].mi.dwFlags := MOUSEEVENTF_LEFTUP;

    // Второй клик (double-click)
    inputs[3].Itype := INPUT_MOUSE;
    inputs[3].mi.dwFlags := MOUSEEVENTF_LEFTDOWN;
    inputs[4].Itype := INPUT_MOUSE;
    inputs[4].mi.dwFlags := MOUSEEVENTF_LEFTUP;

    // Восстановление позиции мыши (перемещаем обратно)
    inputs[5].Itype := INPUT_MOUSE;
    inputs[5].mi.dx := MulDiv(OriginalCursorPos.X, 65535, cxScreen);
    inputs[5].mi.dy := MulDiv(OriginalCursorPos.Y, 65535, cyScreen);
    inputs[5].mi.dwFlags := MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_MOVE;
    inputs[5].mi.time := 0; // Сразу после кликов

    SendInput(6, @inputs[0], SizeOf(TInput));
    Sleep(200);

    SimulateCopy;
    Text := GetClipboardTextW;

    // Проверяем, что получили валидное слово
    if (Text <> OldClipboardText) and (Text <> '') and
       (Pos(' ', Text) = 0) and (Pos(#9, Text) = 0) and
       (Pos(#10, Text) = 0) and (Pos(#13, Text) = 0) and
       (Length(Text) < 100) and (Length(Text) > 0) then
    begin
      Result := True;
      // Выделение активно, clipboard содержит слово
      // Вызывающий код должен вызвать RestoreClipboard после обработки
      Exit;
    end
    else
    begin
      // Неудача — восстанавливаем clipboard и снимаем выделение
      RestoreClipboard;

      // Снимаем выделение: перемещаем курсор в конец слова (Right)
      // Это надёжнее, чем кликать мышью — мы уже знаем, где каретка
      ZeroMemory(@inputs, SizeOf(inputs));
      inputs[0].Itype := INPUT_KEYBOARD;
      inputs[0].ki.wVk := VK_RIGHT;
      inputs[1].Itype := INPUT_KEYBOARD;
      inputs[1].ki.wVk := VK_RIGHT;
      inputs[1].ki.dwFlags := KEYEVENTF_KEYUP;
      SendInput(2, @inputs[0], SizeOf(TInput));

      Text := '';
      Exit;
    end;
  end;

KEYBOARD_FALLBACK:
  // === Fallback: нет каретки — используем Ctrl+Shift+Left ===
  OldClipboardText := GetClipboardTextW;
  SaveClipboard;

  keybd_event(VK_CONTROL, 0, 0, 0);
  keybd_event(VK_SHIFT, 0, 0, 0);
  keybd_event(VK_LEFT, 0, 0, 0);
  keybd_event(VK_LEFT, 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
  Sleep(200);

  SimulateCopy;
  Text := GetClipboardTextW;

  if (Text <> OldClipboardText) and (Text <> '') and
     (Pos(' ', Text) = 0) and (Pos(#9, Text) = 0) and
     (Pos(#10, Text) = 0) and (Pos(#13, Text) = 0) and
     (Length(Text) < 100) and (Length(Text) > 0) then
  begin
    Result := True;
  end
  else
  begin
    RestoreClipboard;
    // Возвращаем каретку на место (если сдвинулись влево)
    keybd_event(VK_RIGHT, 0, 0, 0);
    keybd_event(VK_RIGHT, 0, KEYEVENTF_KEYUP, 0);
    Text := '';
  end;
end;

//------------------------------------------------------------------------------
// Сборка строки из FVKBuffer через текущую раскладку
//------------------------------------------------------------------------------
function TFormMain.VKBufferToString: WideString;
var
  i: Integer;
  VK: Byte;
  Shift: Boolean;
  kbState: TKeyboardState;
  buf: array[0..1] of WideChar;
  hkl: Windows.HKL;
  threadId: DWORD;
  scanCode: UINT;
  ret: Integer;
begin
  Result := '';
  if Length(FVKBuffer) = 0 then Exit;

  threadId := GetWindowThreadProcessId(GetForegroundWindow, nil);
  hkl := GetKeyboardLayout(threadId);

  for i := 0 to High(FVKBuffer) do
  begin
    VK := FVKBuffer[i].VK;
    Shift := FVKBuffer[i].Shift;

    ZeroMemory(@kbState, SizeOf(kbState));
    if Shift then kbState[VK_SHIFT] := $80;
    if (GetAsyncKeyState(VK_CAPITAL) and $0001) <> 0 then kbState[VK_CAPITAL] := $01;

    scanCode := MapVirtualKey(VK, 0);
    ret := MyToUnicodeEx(VK, scanCode, @kbState, @buf, 2, 0, hkl);
    if ret > 0 then
      Result := Result + buf[0];
  end;
end;

//------------------------------------------------------------------------------
// Универсальная функция получения целевого текста.
// Priority: 1) Выделение  2) FVKBuffer
// IsSelection=True  → текст уже выделен, замена прямым Unicode-вводом
// IsSelection=False → нужно использовать Backspace (только для FVKBuffer)
//------------------------------------------------------------------------------
function TFormMain.TryGetTargetText(out Text: WideString; out IsSelection: Boolean): Boolean;
begin
  Result := False;
  Text := '';
  IsSelection := False;

  // 1. Проверяем выделение: сначала стандартные Edit/RichEdit без clipboard,
  // затем обычный Ctrl+C fallback для VS Code/браузеров.
  try
    if GetSelectedTextInActiveWindow(Text) then
    begin
      IsSelection := True;
      Result := True;
      Exit;
    end;
  except
    Text := '';
  end;

  try
    if GetSelectedTextByClipboardFallback(Text) then
    begin
      IsSelection := True;
      Result := True;
      Exit;
    end;
  except
    Text := '';
  end;

  // 2. Последнее введённое слово.
  if Length(FVKBuffer) > 0 then
  begin
    Result := True;
    // IsSelection остаётся False → вызывающий код использует Backspace
    Exit;
  end;
end;

//------------------------------------------------------------------------------
procedure TFormMain.SimulateCopy;
begin
  keybd_event(VK_CONTROL, 0, 0, 0);
  keybd_event(Ord('C'), 0, 0, 0);
  keybd_event(Ord('C'), 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
  Sleep(150);
end;

procedure TFormMain.SimulatePaste;
begin
  keybd_event(VK_CONTROL, 0, 0, 0);
  keybd_event(Ord('V'), 0, 0, 0);
  keybd_event(Ord('V'), 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
  Sleep(50);
end;

procedure TFormMain.TypeUnicodeText(const Value: WideString);
var
  i: Integer;
  inputs: array[0..1] of TInput;
begin
  for i := 1 to Length(Value) do
  begin
    ZeroMemory(@inputs, SizeOf(inputs));

    inputs[0].Itype := INPUT_KEYBOARD;
    inputs[0].ki.wScan := Ord(Value[i]);
    inputs[0].ki.dwFlags := KEYEVENTF_UNICODE;

    inputs[1].Itype := INPUT_KEYBOARD;
    inputs[1].ki.wScan := Ord(Value[i]);
    inputs[1].ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;

    SendInput(2, @inputs[0], SizeOf(TInput));
    Sleep(1);
  end;
end;

function TFormMain.GetClipboardTextW: WideString;
var
  hData: HGLOBAL;
  pData: Pointer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    hData := GetClipboardData(CF_UNICODETEXT);
    if hData <> 0 then
    begin
      pData := GlobalLock(hData);
      if pData <> nil then
      begin
        Result := WideString(PWideChar(pData));
        GlobalUnlock(hData);
      end;
    end;
  finally
    CloseClipboard;
  end;
end;

procedure TFormMain.SetClipboardTextW(const Value: WideString);
var
  hData: HGLOBAL;
  pData: Pointer;
  Len: Integer;
  fmtExclude: UINT;
begin
  if not OpenClipboard(0) then Exit;
  try
    EmptyClipboard;
    Len := (Length(Value) + 1) * SizeOf(WideChar);
    hData := GlobalAlloc(GMEM_MOVEABLE, Len);
    if hData <> 0 then
    begin
      pData := GlobalLock(hData);
      if pData <> nil then
      begin
        Move(PWideChar(Value)^, pData^, Len);
        GlobalUnlock(hData);
        SetClipboardData(CF_UNICODETEXT, hData);

        // === Не сохранять в историю Cloud Clipboard (Win+V) ===
        fmtExclude := RegisterClipboardFormat('ExcludeClipboardContentFromMonitorProcessing');
        if fmtExclude <> 0 then
        begin
          hData := GlobalAlloc(GMEM_MOVEABLE, SizeOf(DWORD));
          if hData <> 0 then
          begin
            pData := GlobalLock(hData);
            if pData <> nil then
            begin
              PDWord(pData)^ := 1;
              GlobalUnlock(hData);
              SetClipboardData(fmtExclude, hData);
            end
            else
              GlobalFree(hData);
          end;
        end;

      end
      else
        GlobalFree(hData);
    end;
  finally
    CloseClipboard;
  end;
end;

procedure TFormMain.SaveClipboard;
var
  Source: HGLOBAL;
  Size: DWORD;
  PSource, PDest: Pointer;
begin
  if FSavedClipboard <> 0 then
  begin
    GlobalFree(FSavedClipboard);
    FSavedClipboard := 0;
  end;
  FClipboardHadText := False;

  if not OpenClipboard(0) then Exit;
  try
    Source := GetClipboardData(CF_UNICODETEXT);
    if Source <> 0 then
    begin
      Size := GlobalSize(Source);
      FSavedClipboard := GlobalAlloc(GMEM_MOVEABLE, Size);
      if FSavedClipboard <> 0 then
      begin
        PSource := GlobalLock(Source);
        PDest   := GlobalLock(FSavedClipboard);
        try
          Move(PSource^, PDest^, Size);
        finally
          GlobalUnlock(Source);
          GlobalUnlock(FSavedClipboard);
        end;
        FClipboardHadText := True;
      end;
    end;
  finally
    CloseClipboard;
  end;
end;

procedure TFormMain.RestoreClipboard;
var
  Mem: HGLOBAL;
  PDest: Pointer;
  Size: DWORD;
begin
  if not FClipboardHadText then
  begin
    if OpenClipboard(0) then
    try
      EmptyClipboard;
    finally
      CloseClipboard;
    end;
    if FSavedClipboard <> 0 then
    begin
      GlobalFree(FSavedClipboard);
      FSavedClipboard := 0;
    end;
    Exit;
  end;

  if FSavedClipboard = 0 then Exit;

  if not OpenClipboard(0) then Exit;
  try
    EmptyClipboard;
    Size := GlobalSize(FSavedClipboard);
    Mem  := GlobalAlloc(GMEM_MOVEABLE, Size);
    if Mem <> 0 then
    begin
      PDest := GlobalLock(Mem);
      if PDest <> nil then
      begin
        Move(GlobalLock(FSavedClipboard)^, PDest^, Size);
        GlobalUnlock(FSavedClipboard);
        GlobalUnlock(Mem);
        SetClipboardData(CF_UNICODETEXT, Mem);
      end
      else
        GlobalFree(Mem);
    end;
  finally
    CloseClipboard;
    if FSavedClipboard <> 0 then
    begin
      GlobalFree(FSavedClipboard);
      FSavedClipboard := 0;
    end;
  end;
end;

//------------------------------------------------------------------------------
function TFormMain.ConvertLayout(const S: WideString): WideString;
var
  i, j: Integer;
  Ch: WideChar;
  Found: Boolean;
  ToRu: Boolean; // True = En→Ru, False = Ru→En
begin
  Result := '';
  if S = '' then Exit;

  // Определяем направление: если есть кириллица → значит текст в Ru, конвертируем в En
  // Если только латиница/цифры/знаки → значит текст в En, конвертируем в Ru
  ToRu := not IsCyrillicText(S);

  for i := 1 to Length(S) do
  begin
    Ch := S[i];
    Found := False;

    if ToRu then
    begin
      // En → Ru
      for j := 1 to Length(EnChars) do
        if EnChars[j] = Ch then
        begin
          Result := Result + RuChars[j];
          Found := True;
          Break;
        end;
    end
    else
    begin
      // Ru → En
      for j := 1 to Length(RuChars) do
        if RuChars[j] = Ch then
        begin
          Result := Result + EnChars[j];
          Found := True;
          Break;
        end;
    end;

    // Символ не найден в таблице — оставляем как есть (цифры, пробелы и т.д.)
    if not Found then
      Result := Result + Ch;
  end;
end;

function TFormMain.ChangeStringCase(const S: WideString; ToUpper: Boolean): WideString;
begin
  if ToUpper then
    Result := WideUpperCase(S)
  else
    Result := WideLowerCase(S);
end;

//------------------------------------------------------------------------------
// УНИВЕРСАЛЬНАЯ КОНВЕРТАЦИЯ: слово или выделение
//------------------------------------------------------------------------------
procedure TFormMain.DoConvert;
var
  hForeground: HWND;
  threadId: DWORD;
  hklOriginal: HKL;
  Text: WideString;
  IsSelection: Boolean;
  i: Integer;
  VK: Byte;
  Shift: Boolean;
  scanCode: Byte;
  hklTarget: HKL;
  LangID: Word;
  LocalBuffer: array of TVKRecord;
  Count: Integer;
  ConvertedText: WideString;
  TargetLangID: Word;
begin
  hForeground := GetForegroundWindow;
  if hForeground = 0 then Exit;

  if not TryGetTargetText(Text, IsSelection) then Exit;

  // --- Сценарий 1: Выделение / слово под курсором ---
  if IsSelection then
  begin
    if Text <> '' then
    begin
      ConvertedText := ConvertLayout(Text);
      TypeUnicodeText(ConvertedText);

      if IsCyrillicText(Text) then
        TargetLangID := $0409
      else
        TargetLangID := $0419;

      SwitchGlobalLayout(TargetLangID);
    end;
    Exit;
  end;

  // --- Сценарий 2: Последнее введённое слово (FVKBuffer) ---
  Count := Length(FVKBuffer);
  if Count = 0 then Exit;

  SetLength(LocalBuffer, Count);
  for i := 0 to Count - 1 do
    LocalBuffer[i] := FVKBuffer[i];
  SetLength(FVKBuffer, 0);

  threadId := GetWindowThreadProcessId(hForeground, nil);
  hklOriginal := GetKeyboardLayout(threadId);

  if LOWORD(hklOriginal) = $0419 then
    LangID := $0409
  else
    LangID := $0419;

  hklTarget := FindHKLByLangID(LangID);
  if hklTarget = 0 then Exit;

  // Переключаем раскладку окна
  PostMessage(hForeground, WM_INPUTLANGCHANGEREQUEST, 0, hklTarget);
  Sleep(200);

  if LOWORD(GetKeyboardLayout(threadId)) <> LangID then
  begin
    if AttachThreadInput(GetCurrentThreadId, threadId, True) then
    try
      ActivateKeyboardLayout(hklTarget, 0);
      Sleep(100);
    finally
      AttachThreadInput(GetCurrentThreadId, threadId, False);
    end;
  end;

  // Стираем слово обратными Backspace
  for i := 1 to Count do
  begin
    scanCode := Byte(MapVirtualKey(VK_BACK, 0));
    keybd_event(VK_BACK, scanCode, 0, 0);
    keybd_event(VK_BACK, scanCode, KEYEVENTF_KEYUP, 0);
  end;
  Sleep(50);

  // Вводим те же клавиши, но в новой раскладке
  for i := 0 to Count - 1 do
  begin
    VK := LocalBuffer[i].VK;
    Shift := LocalBuffer[i].Shift;

    if Shift then
      keybd_event(VK_SHIFT, 0, 0, 0);

    scanCode := Byte(MapVirtualKeyExW(VK, 0, hklTarget));
    if scanCode = 0 then
      scanCode := Byte(MapVirtualKey(VK, 0));

    keybd_event(VK, scanCode, 0, 0);
    keybd_event(VK, scanCode, KEYEVENTF_KEYUP, 0);

    if Shift then
      keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0);

    Sleep(5);
  end;

  // Переключаем глобальную раскладку
  SwitchGlobalLayout(LangID);
end;

//------------------------------------------------------------------------------
// ДВОЙНОЙ LCTRL / RCTRL: смена регистра
//------------------------------------------------------------------------------
procedure TFormMain.DoChangeCase(ToUpper: Boolean);
var
  Text: WideString;
  IsSelection: Boolean;
  Count: Integer;
  i: Integer;
  scanCode: Byte;
begin
  if not TryGetTargetText(Text, IsSelection) then Exit;

  // --- Сценарий 1: Выделение / слово под курсором ---
  if IsSelection then
  begin
    if Text <> '' then
      TypeUnicodeText(ChangeStringCase(Text, ToUpper));
    Exit;
  end;

  // --- Сценарий 2: FVKBuffer ---
  Count := Length(FVKBuffer);
  if Count = 0 then Exit;

  // Собираем строку из буфера клавиш
  Text := VKBufferToString;
  if Text = '' then
  begin
    SetLength(FVKBuffer, 0);
    Exit;
  end;

  // Меняем регистр
  Text := ChangeStringCase(Text, ToUpper);

  // Стираем исходное слово
  for i := 1 to Count do
  begin
    scanCode := Byte(MapVirtualKey(VK_BACK, 0));
    keybd_event(VK_BACK, scanCode, 0, 0);
    keybd_event(VK_BACK, scanCode, KEYEVENTF_KEYUP, 0);
  end;
  Sleep(50);

  TypeUnicodeText(Text);

  SetLength(FVKBuffer, 0);
end;

//------------------------------------------------------------------------------
// LCTRL + RCTRL: инвертирование регистра
//------------------------------------------------------------------------------
procedure TFormMain.DoInvertCase;
var
  Text, ResultText: WideString;
  IsSelection: Boolean;
  i: Integer;
  Ch: WideChar;
  Count: Integer;
  scanCode: Byte;
begin
  if not TryGetTargetText(Text, IsSelection) then Exit;

  // --- Сценарий 1: Выделение / слово под курсором ---
  if IsSelection then
  begin
    if Text = '' then Exit;

    ResultText := '';
    for i := 1 to Length(Text) do
    begin
      Ch := Text[i];
      if (Ch >= WideChar('a')) and (Ch <= WideChar('z')) then
        ResultText := ResultText + WideChar(Ord(Ch) - Ord('a') + Ord('A'))
      else if (Ch >= WideChar('A')) and (Ch <= WideChar('Z')) then
        ResultText := ResultText + WideChar(Ord(Ch) - Ord('A') + Ord('a'))
      else if (Ch >= WideChar('а')) and (Ch <= WideChar('я')) then
        ResultText := ResultText + WideChar(Ord(Ch) - Ord('а') + Ord('А'))
      else if (Ch >= WideChar('А')) and (Ch <= WideChar('Я')) then
        ResultText := ResultText + WideChar(Ord(Ch) - Ord('А') + Ord('а'))
      else if Ch = WideChar('ё') then
        ResultText := ResultText + WideChar('Ё')
      else if Ch = WideChar('Ё') then
        ResultText := ResultText + WideChar('ё')
      else
        ResultText := ResultText + Ch;
    end;

    TypeUnicodeText(ResultText);
    Exit;
  end;

  // --- Сценарий 2: FVKBuffer ---
  Count := Length(FVKBuffer);
  if Count = 0 then Exit;

  // Собираем строку из буфера клавиш
  Text := VKBufferToString;
  if Text = '' then
  begin
    SetLength(FVKBuffer, 0);
    Exit;
  end;

  // Инвертируем регистр
  ResultText := '';
  for i := 1 to Length(Text) do
  begin
    Ch := Text[i];
    if (Ch >= WideChar('a')) and (Ch <= WideChar('z')) then
      ResultText := ResultText + WideChar(Ord(Ch) - Ord('a') + Ord('A'))
    else if (Ch >= WideChar('A')) and (Ch <= WideChar('Z')) then
      ResultText := ResultText + WideChar(Ord(Ch) - Ord('A') + Ord('a'))
    else if (Ch >= WideChar('а')) and (Ch <= WideChar('я')) then
      ResultText := ResultText + WideChar(Ord(Ch) - Ord('а') + Ord('А'))
    else if (Ch >= WideChar('А')) and (Ch <= WideChar('Я')) then
      ResultText := ResultText + WideChar(Ord(Ch) - Ord('А') + Ord('а'))
    else if Ch = WideChar('ё') then
      ResultText := ResultText + WideChar('Ё')
    else if Ch = WideChar('Ё') then
      ResultText := ResultText + WideChar('ё')
    else
      ResultText := ResultText + Ch;
  end;

  // Стираем и вставляем
  for i := 1 to Count do
  begin
    scanCode := Byte(MapVirtualKey(VK_BACK, 0));
    keybd_event(VK_BACK, scanCode, 0, 0);
    keybd_event(VK_BACK, scanCode, KEYEVENTF_KEYUP, 0);
  end;
  Sleep(50);

  TypeUnicodeText(ResultText);

  SetLength(FVKBuffer, 0);
end;

//------------------------------------------------------------------------------
procedure TFormMain.mniExitClick(Sender: TObject);
begin
  Application.Terminate;
end;

end.
