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
    FLastLCtrlTime: DWORD;      // Время последнего нажатия ЛЕВОГО Ctrl
    FLCtrlPressed: Boolean;     // Флаг ожидания второго ЛЕВОГО Ctrl
    FLastRCtrlTime: DWORD;      // Время последнего нажатия ПРАВОГО Ctrl
    FRCtrlPressed: Boolean;     // Флаг ожидания второго ПРАВОГО Ctrl
    procedure WndProc(var Message: TMessage); override;
    procedure DoConvertSelected;
    procedure DoChangeCase(ToUpper: Boolean);
    procedure DoInvertCase;
    procedure DoConvert;          // Универсальная конвертация (слово или выделение)
    procedure SwitchGlobalLayout(ToLangID: Word);
    function HasSelectionInActiveWindow: Boolean;
    procedure SimulateCopy;
    procedure SimulatePaste;
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
begin
  if nCode = HC_ACTION then
  begin
    pkbhs := PMyKBDLLHOOKSTRUCT(lParam);

    if (pkbhs^.flags and LLKHF_INJECTED) <> 0 then
    begin
      Result := CallNextHookEx(hKeyHook, nCode, wParam, lParam);
      Exit;
    end;

    if Assigned(FormMain) then FormMain.CheckWindowChanged;

    // --- ОБРАБОТКА ДВОЙНОГО SHIFT ---
    if wParam = WM_KEYDOWN then
    begin
      if (pkbhs^.vkCode = VK_SHIFT) or (pkbhs^.vkCode = VK_LSHIFT) or (pkbhs^.vkCode = VK_RSHIFT) then
      begin
        CurrentTime := GetTickCount;
        if FormMain.FShiftPressed and (CurrentTime - FormMain.FLastShiftTime <= DOUBLE_SHIFT_INTERVAL) then
        begin
          // Двойное нажатие Shift!
          FormMain.FShiftPressed := False;
          if not IsConverting then
          begin
            IsConverting := True;
            PostMessage(FormMain.Handle, WM_DO_CONVERT, 0, 0);
          end;
          Result := 1;
          Exit;
        end
        else
        begin
          FormMain.FShiftPressed := True;
          FormMain.FLastShiftTime := CurrentTime;
        end;
      end
      else if (pkbhs^.vkCode <> VK_CONTROL) and (pkbhs^.vkCode <> VK_MENU) then
      begin
        // Любая другая клавиша сбрасывает ожидание двойного Shift
        FormMain.FShiftPressed := False;
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
          // nothing
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

//    // --- Горячие клавиши регистра (Ctrl+Shift+Up/Down) ---
//    if wParam = WM_KEYDOWN then
//    begin
//      if (pkbhs^.vkCode = ord('U')) and
//         (GetAsyncKeyState(VK_CONTROL) < 0) and
//         (GetAsyncKeyState(VK_MENU) < 0) and
//         (GetAsyncKeyState(VK_SHIFT) < 0) then
//      begin
//        if not IsConverting then
//        begin
//          IsConverting := True;
//          PostMessage(FormMain.Handle, WM_DO_UPPERCASE, 0, 0);
//        end;
//        Result := 1;
//        Exit;
//      end;
//
//      if (pkbhs^.vkCode = ord('L')) and
//         (GetAsyncKeyState(VK_CONTROL) < 0) and
//         (GetAsyncKeyState(VK_MENU) < 0) and
//         (GetAsyncKeyState(VK_SHIFT) < 0) then
//      begin
//        if not IsConverting then
//        begin
//          IsConverting := True;
//          PostMessage(FormMain.Handle, WM_DO_LOWERCASE, 0, 0);
//        end;
//        Result := 1;
//        Exit;
//      end;
//    end;

    // --- ОБРАБОТКА ДВОЙНОГО CTRL (регистр) ---
    if wParam = WM_KEYDOWN then
    begin
      // LCtrl + RCtrl (одновременно) — инвертирование регистра
      if (pkbhs^.vkCode = VK_LCONTROL) and (GetAsyncKeyState(VK_RCONTROL) < 0) then
      begin
        if not IsConverting then
        begin
          IsConverting := True;
          PostMessage(FormMain.Handle, WM_DO_INVERT_CASE, 0, 0);
        end;
        Result := 1;
        Exit;
      end;
      if (pkbhs^.vkCode = VK_RCONTROL) and (GetAsyncKeyState(VK_LCONTROL) < 0) then
      begin
        if not IsConverting then
        begin
          IsConverting := True;
          PostMessage(FormMain.Handle, WM_DO_INVERT_CASE, 0, 0);
        end;
        Result := 1;
        Exit;
      end;
      // Двойной ЛЕВЫЙ Ctrl — ВЕРХНИЙ регистр
      if (pkbhs^.vkCode = VK_LCONTROL) then
      begin
        CurrentTime := GetTickCount;
        if FormMain.FLCtrlPressed and (CurrentTime - FormMain.FLastLCtrlTime <= DOUBLE_CTRL_INTERVAL) then
        begin
          FormMain.FLCtrlPressed := False;
          if not IsConverting then
          begin
            IsConverting := True;
            PostMessage(FormMain.Handle, WM_DO_UPPERCASE, 0, 0);
          end;
          Result := 1;
          Exit;
        end
        else
        begin
          FormMain.FLCtrlPressed := True;
          FormMain.FLastLCtrlTime := CurrentTime;
        end;
      end
      // Двойной ПРАВЫЙ Ctrl — нижний регистр
      else if (pkbhs^.vkCode = VK_RCONTROL) then
      begin
        CurrentTime := GetTickCount;
        if FormMain.FRCtrlPressed and (CurrentTime - FormMain.FLastRCtrlTime <= DOUBLE_CTRL_INTERVAL) then
        begin
          FormMain.FRCtrlPressed := False;
          if not IsConverting then
          begin
            IsConverting := True;
            PostMessage(FormMain.Handle, WM_DO_LOWERCASE, 0, 0);
          end;
          Result := 1;
          Exit;
        end
        else
        begin
          FormMain.FRCtrlPressed := True;
          FormMain.FLastRCtrlTime := CurrentTime;
        end;
      end
      // Любая другая клавиша сбрасывает ожидание двойного Ctrl
      else if (pkbhs^.vkCode <> VK_SHIFT) and (pkbhs^.vkCode <> VK_LSHIFT) and
              (pkbhs^.vkCode <> VK_RSHIFT) and (pkbhs^.vkCode <> VK_MENU) then
      begin
        FormMain.FLCtrlPressed := False;
        FormMain.FRCtrlPressed := False;
      end;
    end;

  end;

  Result := CallNextHookEx(hKeyHook, nCode, wParam, lParam);
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
  FLastLCtrlTime := 0;
  FLCtrlPressed := False;
  FLastRCtrlTime := 0;
  FRCtrlPressed := False;
  //Проверяем находимся ли в автозапуске
  chkAutorun.Checked := IsInStartup('LayoutSwitcher');
  ShowInTaskBar := False;

  SetWindowLong(Application.Handle, GWL_EXSTYLE,
  GetWindowLong(Application.Handle, GWL_EXSTYLE) and not WS_EX_APPWINDOW);

  hKeyHook := SetWindowsHookEx(WH_KEYBOARD_LL, @KeyboardHookProc, HInstance, 0);
  if hKeyHook = 0 then
    MessageBox(0, 'Cannot install keyboard hook!', 'LayoutSwitcher', MB_OK or MB_ICONERROR);

  hMouseHook := SetWindowsHookEx(WH_MOUSE_LL, @MouseHookProc, HInstance, 0);
  if hMouseHook = 0 then
    MessageBox(0, 'Cannot install mouse hook!', 'LayoutSwitcher', MB_OK or MB_ICONERROR);

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
// Проверка наличия выделения в активном окне
//------------------------------------------------------------------------------
function TFormMain.HasSelectionInActiveWindow: Boolean;
var
  hWnd: Windows.HWND;
  startSel, endSel: DWORD;
  className: array[0..255] of Char;
begin
  Result := False;
  hWnd := GetForegroundWindow;
  if hWnd = 0 then Exit;

  // Для стандартных Edit/RichEdit пробуем EM_GETSEL
  GetClassName(hWnd, @className, 256);
  if (Pos('Edit', className) > 0) or (Pos('RichEdit', className) > 0) or
     (Pos('TMemo', className) > 0) or (Pos('TEdit', className) > 0) then
  begin
    SendMessage(hWnd, EM_GETSEL, WPARAM(@startSel), LPARAM(@endSel));
    Result := startSel <> endSel;
  end;
end;

//------------------------------------------------------------------------------
// Clipboard
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
  fmtExclude: UINT;  // ← Добавить
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
// Конвертация раскладки и регистра
//------------------------------------------------------------------------------
//function TFormMain.ConvertLayout(const S: WideString): WideString;
//var
//  i, j: Integer;
//  Ch: WideChar;
//  Found: Boolean;
//begin
//  Result := '';
//  for i := 1 to Length(S) do
//  begin
//    Ch := S[i];
//    Found := False;
//
//    for j := 1 to Length(EnChars) do
//      if EnChars[j] = Ch then
//      begin
//        Result := Result + RuChars[j];
//        Found := True;
//        Break;
//      end;
//
//    if not Found then
//      for j := 1 to Length(RuChars) do
//        if RuChars[j] = Ch then
//        begin
//          Result := Result + EnChars[j];
//          Found := True;
//          Break;
//        end;
//
//    if not Found then
//      Result := Result + Ch;
//  end;
//end;

// Конвертация с АВТООПРЕДЕЛЕНИЕМ направления по содержимому текста
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
  HasSelection: Boolean;
  ClipboardText: WideString;
  OldClipboardText: WideString;   // ← ДОПОЛНИТЕЛЬНАЯ ПЕРЕМЕННАЯ
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
  ClipboardSaved: Boolean;       // ← ФЛАГ: был ли вызван SaveClipboard
begin
  hForeground := GetForegroundWindow;
  if hForeground = 0 then Exit;

  HasSelection := HasSelectionInActiveWindow;
  ClipboardText := '';
  ClipboardSaved := False;

  // --- Fallback: проверяем через clipboard, сравнивая ДО и ПОСЛЕ ---
  if not HasSelection then
  begin
    OldClipboardText := GetClipboardTextW;  // Запоминаем что было ДО операции
    SaveClipboard;                          // Сохраняем оригинал для восстановления
    ClipboardSaved := True;
    SimulateCopy;
    ClipboardText := GetClipboardTextW;     // Смотрим что стало ПОСЛЕ

    // Буфер реально изменился — значит Ctrl+C скопировал выделение
    if (ClipboardText <> OldClipboardText) and
       (ClipboardText <> '') and
       (Length(ClipboardText) < 1000) then
    begin
      HasSelection := True;
      // Не восстанавливаем буфер здесь — пусть основной блок работает с актуальным выделением
    end
    else
    begin
      // Выделения не было — обязательно восстанавливаем буфер и идём в ветку последнего слова
      RestoreClipboard;
      ClipboardSaved := False;
      ClipboardText := '';
    end;
  end;

  // --- Конвертация выделенного текста ---
  if HasSelection then
  begin
    // Если выделение определено через HasSelectionInActiveWindow — нужно скопировать
    if ClipboardText = '' then
    begin
      SaveClipboard;
      ClipboardSaved := True;
      SimulateCopy;
      ClipboardText := GetClipboardTextW;
    end;

    try
      if ClipboardText <> '' then
      begin
        ConvertedText := ConvertLayout(ClipboardText);
        SetClipboardTextW(ConvertedText);
        SimulatePaste;

        if IsCyrillicText(ClipboardText) then
          TargetLangID := $0409   // Было Ru → переключаем на En
        else
          TargetLangID := $0419;  // Было En → переключаем на Ru

        SwitchGlobalLayout(TargetLangID);
      end;
    finally
      // Восстанавливаем исходный буфер в любом случае, даже если вставка не удалась
      if ClipboardSaved then
        RestoreClipboard;
    end;
    Exit;
  end;

  // --- Конвертация последнего слова (clipboard не трогаем) ---
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


// Конвертация выделенного текста через clipboard
procedure TFormMain.DoConvertSelected;
var
  Text: WideString;
begin
  SaveClipboard;
  try
    SimulateCopy;
    Text := GetClipboardTextW;
    if Text <> '' then
    begin
      SetClipboardTextW(ConvertLayout(Text));
      SimulatePaste;
    end;
  finally
    RestoreClipboard;
  end;
end;

// Инвертирование регистра выделенного текста
procedure TFormMain.DoInvertCase;
var
  Text, ResultText: WideString;
  i: Integer;
  Ch: WideChar;
  OldClipboardText: WideString;
  HasSelection: Boolean;
  ClipboardSaved: Boolean;
begin
  HasSelection := HasSelectionInActiveWindow;
  ClipboardSaved := False;

  // Fallback-проверка: сравниваем clipboard до и после Ctrl+C
  if not HasSelection then
  begin
    OldClipboardText := GetClipboardTextW;
    SaveClipboard;
    ClipboardSaved := True;
    SimulateCopy;
    Text := GetClipboardTextW;

    // Буфер не изменился — значит выделения не было
    if (Text = OldClipboardText) or (Text = '') then
    begin
      RestoreClipboard;
      Exit;  // Ничего не делаем
    end;

    HasSelection := True;
  end
  else
  begin
    // Выделение определено через HasSelectionInActiveWindow
    SaveClipboard;
    ClipboardSaved := True;
    SimulateCopy;
    Text := GetClipboardTextW;
  end;

  try
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

    SetClipboardTextW(ResultText);
    SimulatePaste;
  finally
    if ClipboardSaved then
      RestoreClipboard;
  end;
end;

// Регистр выделенного текста
procedure TFormMain.DoChangeCase(ToUpper: Boolean);
var
  Text: WideString;
  OldClipboardText: WideString;
  HasSelection: Boolean;
  ClipboardSaved: Boolean;
begin
  HasSelection := HasSelectionInActiveWindow;
  ClipboardSaved := False;

  // Fallback-проверка: сравниваем clipboard до и после Ctrl+C
  if not HasSelection then
  begin
    OldClipboardText := GetClipboardTextW;
    SaveClipboard;
    ClipboardSaved := True;
    SimulateCopy;
    Text := GetClipboardTextW;

    // Буфер не изменился — значит выделения не было
    if (Text = OldClipboardText) or (Text = '') then
    begin
      RestoreClipboard;
      Exit;  // Ничего не делаем
    end;

    HasSelection := True;
  end
  else
  begin
    // Выделение определено через HasSelectionInActiveWindow
    SaveClipboard;
    ClipboardSaved := True;
    SimulateCopy;
    Text := GetClipboardTextW;
  end;

  try
    if Text <> '' then
    begin
      SetClipboardTextW(ChangeStringCase(Text, ToUpper));
      SimulatePaste;
    end;
  finally
    if ClipboardSaved then
      RestoreClipboard;
  end;
end;


//------------------------------------------------------------------------------
procedure TFormMain.mniExitClick(Sender: TObject);
begin
  Application.Terminate;
end;

end.
