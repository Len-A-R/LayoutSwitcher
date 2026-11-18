unit uOperationWorker;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

// Background thread that performs text operations (layout conversion and
// case changes).  Everything that may block - UI Automation, the clipboard,
// waiting for modifier release, SendMessageTimeout - runs here so the UI
// thread keeps processing Raw Input, the tray icon and the settings window.
//
// The UI thread posts a TOperationRequest; the worker always answers with a
// TOperationResult posted back to the UI window, even when it fails.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.SyncObjs,
  uSettings, uLayoutConverter, uClipboardSnapshot;

type
  TBufferAction = (baKeep, baClear, baSet);

  TOperationRequest = class
  public
    Sequence: Cardinal;
    Action: TLSAction;
    BufferText: string;      // Empty when the tracked word is unavailable.
    FocusWnd: HWND;
    WindowLayout: HKL;
    PreviousLayout: HKL;
    ExcludedProcesses: TArray<string>;
  end;

  TOperationResult = class
  public
    Sequence: Cardinal;
    Action: TLSAction;
    Success: Boolean;
    BufferAction: TBufferAction;
    NewBufferText: string;
    FocusIsPassword: Boolean;
    SourceLayout: HKL;
    TargetLayout: HKL;
    NotificationKey: string;
    Notification: string;
  end;

  TOperationWorker = class(TThread)
  private
    FNotifyWnd: HWND;
    FNotifyMsg: UINT;
    FReady: TEvent;
    FWindow: HWND;
    FCatalog: TKeyboardLayoutCatalog;
    FSnapshot: TClipboardSnapshot;
    FSelectionWindow: HWND;
    FSelectionIsNative: Boolean;
    FClipboardSkipReason: string;
    procedure HandleRequest(Request: TOperationRequest);
    procedure Process(Request: TOperationRequest; Res: TOperationResult);
    function GetNativeSelection(Target: HWND; out Text: string): Boolean;
    function GetClipboardSelection(Request: TOperationRequest;
      out Text: string): Boolean;
    function ReplaceSelection(const Value: string): Boolean;
    function WaitForModifiersReleased(TimeoutMS: DWORD): Boolean;
    procedure Notify(Res: TOperationResult; const Key, Text: string);
  protected
    procedure Execute; override;
  public
    constructor Create(NotifyWnd: HWND; NotifyMsg: UINT);
    destructor Destroy; override;
    function WaitUntilReady(TimeoutMS: Cardinal): Boolean;
    // Takes ownership of Request.  Returns False if it could not be queued.
    function Post(Request: TOperationRequest): Boolean;
    procedure Shutdown;
  end;

implementation

uses
  Winapi.ActiveX,
  uDiagnostics, uWinUtils, uUIAutomation;

const
  WM_LS_EXECUTE = WM_APP + 100;

  MAX_SELECTION_LEN = 1024 * 1024;
  CLIPBOARD_COPY_TIMEOUT = 500;
  MODIFIER_RELEASE_TIMEOUT = 1000;
  TARGET_KEYUP_SETTLE_DELAY = 30;
  WINDOW_MESSAGE_TIMEOUT = 250;

{ TOperationWorker }

constructor TOperationWorker.Create(NotifyWnd: HWND; NotifyMsg: UINT);
begin
  FNotifyWnd := NotifyWnd;
  FNotifyMsg := NotifyMsg;
  FReady := TEvent.Create(nil, True, False, '');
  FCatalog := TKeyboardLayoutCatalog.Create;
  FSnapshot := TClipboardSnapshot.Create;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TOperationWorker.Destroy;
begin
  Shutdown;
  inherited;
  FSnapshot.Free;
  FCatalog.Free;
  FReady.Free;
end;

function TOperationWorker.WaitUntilReady(TimeoutMS: Cardinal): Boolean;
begin
  Result := FReady.WaitFor(TimeoutMS) = wrSignaled;
end;

function TOperationWorker.Post(Request: TOperationRequest): Boolean;
begin
  Result := PostThreadMessage(ThreadID, WM_LS_EXECUTE, 0, LPARAM(Request));
  if not Result then
    Request.Free;
end;

procedure TOperationWorker.Shutdown;
begin
  if Finished then
    Exit;
  Terminate;
  PostThreadMessage(ThreadID, WM_QUIT, 0, 0);
  WaitFor;
end;

procedure TOperationWorker.Execute;
var
  Msg: TMsg;
begin
  NameThreadForDebugging('LayoutSwitcher.OperationWorker');
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    // A message-only window owns the clipboard while we save/restore it.
    FWindow := CreateWindowEx(0, 'STATIC', 'LayoutSwitcher.Worker', 0, 0, 0, 0,
      0, HWND_MESSAGE, 0, HInstance, nil);
    PeekMessage(Msg, 0, WM_USER, WM_USER, PM_NOREMOVE); // Create the queue.
    FReady.SetEvent;
    DiagnosticsLogFmt('worker.started window=%p', [Pointer(FWindow)]);

    while GetMessage(Msg, 0, 0, 0) do
    begin
      if Msg.hwnd = 0 then
        case Msg.message of
          WM_LS_EXECUTE:
            HandleRequest(TOperationRequest(Msg.lParam));
        end
      else
      begin
        TranslateMessage(Msg);
        DispatchMessage(Msg);
      end;
    end;

    // Free requests that arrived after WM_QUIT.
    while PeekMessage(Msg, 0, WM_LS_EXECUTE, WM_LS_EXECUTE, PM_REMOVE) do
      TOperationRequest(Msg.lParam).Free;
  finally
    FSnapshot.Discard;
    if FWindow <> 0 then
      DestroyWindow(FWindow);
    FWindow := 0;
    CoUninitialize;
    DiagnosticsLog('worker.stopped');
  end;
end;

procedure TOperationWorker.Notify(Res: TOperationResult; const Key, Text: string);
begin
  Res.NotificationKey := Key;
  Res.Notification := Text;
end;

procedure TOperationWorker.HandleRequest(Request: TOperationRequest);
var
  Res: TOperationResult;
  OperationName: string;
begin
  Res := TOperationResult.Create;
  try
    Res.Sequence := Request.Sequence;
    Res.Action := Request.Action;
    Res.BufferAction := baKeep;
    OperationName := ActionKeys[Request.Action];
    DiagnosticsBeginOperation(OperationName,
      Format('seq=%d buffer_len=%d target=%p target_class="%s" target_process="%s"',
        [Request.Sequence, Length(Request.BufferText), Pointer(Request.FocusWnd),
         GetWindowClassName(Request.FocusWnd),
         GetWindowProcessFileName(Request.FocusWnd)]));
    try
      Process(Request, Res);
    except
      on E: Exception do
      begin
        Res.Success := False;
        Res.BufferAction := baClear;
        DiagnosticsCaptureException('worker.operation', E, ExceptAddr);
      end;
    end;
    DiagnosticsEndOperation(OperationName, Res.Success);
  finally
    Request.Free;
    if not PostMessage(FNotifyWnd, FNotifyMsg, 0, LPARAM(Res)) then
      Res.Free;
  end;
end;

function TOperationWorker.WaitForModifiersReleased(TimeoutMS: DWORD): Boolean;
var
  Started: DWORD;
begin
  Started := GetTickCount;
  repeat
    if not AreModifiersPhysicallyDown then
    begin
      // Raw Input reports the physical release before Electron has handled
      // the corresponding key-up; without this VS Code may see Ctrl+Shift+C.
      Sleep(TARGET_KEYUP_SETTLE_DELAY);
      Exit(True);
    end;
    Sleep(5);
  until GetTickCount - Started >= TimeoutMS;
  DiagnosticsLog('input.modifiers release_timeout');
  Result := False;
end;

function TOperationWorker.GetNativeSelection(Target: HWND;
  out Text: string): Boolean;
var
  ClassText: string;
  StartSel, EndSel, SelStart, SelEnd: DWORD;
  MessageResult: DWORD_PTR;
  TextLength, Copied: Integer;
  Buffer: string;
begin
  Result := False;
  Text := '';
  if Target = 0 then
    Exit;
  ClassText := LowerCase(GetWindowClassName(Target));
  if (Pos('edit', ClassText) = 0) and (Pos('tmemo', ClassText) = 0) then
    Exit;
  if IsNativePasswordEdit(Target) then
    Exit;

  StartSel := 0;
  EndSel := 0;
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
       LPARAM(PChar(Buffer)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
       WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  Copied := Integer(MessageResult);
  if (Copied <= 0) or (EndSel > DWORD(Copied)) then
    Exit;
  SetLength(Buffer, Copied);

  SelStart := StartSel;
  SelEnd := EndSel;
  if SelStart = SelEnd then
  begin
    // No selection: take the word immediately before the caret.
    if SelStart = 0 then
      Exit;
    while (SelStart > 0) and (Ord(Buffer[SelStart]) > 32) do
      Dec(SelStart);
    if SelStart = SelEnd then
      Exit;
    if SendMessageTimeout(Target, EM_SETSEL, SelStart, SelEnd,
         SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT,
         @MessageResult) = 0 then
      Exit;
  end;

  Text := Copy(Buffer, SelStart + 1, SelEnd - SelStart);
  if Text <> '' then
  begin
    FSelectionWindow := Target;
    FSelectionIsNative := True;
    Result := True;
  end;
end;

function TOperationWorker.GetClipboardSelection(Request: TOperationRequest;
  out Text: string): Boolean;
var
  OldSequence: DWORD;
  Changed: Boolean;
  Excluded: TArray<string>;
begin
  Result := False;
  Text := '';
  FClipboardSkipReason := '';
  Excluded := Request.ExcludedProcesses;
  if not FSnapshot.CanUseFallback(
       function(Owner: HWND; ProcessName: string): Boolean
       var
         Name: string;
       begin
         Result := False;
         for Name in Excluded do
           if SameText(Name, ProcessName) then
             Exit(True);
       end, FClipboardSkipReason) then
  begin
    DiagnosticsLogFmt('target.clipboard skipped reason=%s', [FClipboardSkipReason]);
    Exit;
  end;

  if not WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) then
    Exit;
  if GetFocusedWindow <> Request.FocusWnd then
  begin
    DiagnosticsLog('target.clipboard skipped reason=focus_changed');
    Exit;
  end;
  if not FSnapshot.Save(FWindow) then
    Exit;

  OldSequence := GetClipboardSequenceNumber;
  Changed := False;
  try
    if not SendChord(VK_CONTROL, Ord('C')) then
    begin
      DiagnosticsLogFmt('target.clipboard copy_send_failed error=%d', [GetLastError]);
      Exit;
    end;
    if not WaitForClipboardChange(OldSequence, CLIPBOARD_COPY_TIMEOUT) then
    begin
      DiagnosticsLog('target.clipboard copy_timeout');
      Exit;
    end;
    Changed := True;

    Text := ReadClipboardText(FWindow);
    if (Text = '') or (Length(Text) > MAX_SELECTION_LEN) then
    begin
      Text := '';
      Exit;
    end;
    // Editors such as VS Code copy the whole line when nothing is selected.
    if CharInSet(Text[Length(Text)], [#10, #13]) then
    begin
      DiagnosticsLog('target.clipboard rejected_whole_line=true');
      Text := '';
      Exit;
    end;

    FSelectionWindow := GetFocusedWindow;
    FSelectionIsNative := False;
    Result := FSelectionWindow <> 0;
  finally
    Changed := Changed or (GetClipboardSequenceNumber <> OldSequence);
    if Changed then
      FSnapshot.Restore(FWindow)
    else
      FSnapshot.Discard;
  end;
end;

function TOperationWorker.ReplaceSelection(const Value: string): Boolean;
var
  MessageResult: DWORD_PTR;
begin
  Result := False;
  if (FSelectionWindow = 0) or (GetFocusedWindow <> FSelectionWindow) then
    Exit;
  if FSelectionIsNative then
    Result := SendMessageTimeoutW(FSelectionWindow, EM_REPLACESEL, 1,
      LPARAM(PChar(Value)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
      WINDOW_MESSAGE_TIMEOUT, @MessageResult) <> 0
  else
    Result := WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) and
      TypeUnicodeText(Value);
end;

procedure TOperationWorker.Process(Request: TOperationRequest;
  Res: TOperationResult);
var
  Focus: TUIAFocusInfo;
  Text, Converted, Source: string;
  IsSelection: Boolean;
  Pair: TLayoutPair;
begin
  FSelectionWindow := 0;
  FSelectionIsNative := False;
  FClipboardSkipReason := '';

  if GetFocusedWindow <> Request.FocusWnd then
  begin
    DiagnosticsLog('operation.skipped reason=focus_changed');
    Res.BufferAction := baClear;
    Exit;
  end;

  // An application that is not responding (common right after resume from
  // sleep) would only queue our input and stall UI Automation.
  if IsWindowHung(Request.FocusWnd) or IsWindowHung(GetForegroundWindow) then
  begin
    DiagnosticsLog('operation.skipped reason=target_not_responding');
    Res.BufferAction := baClear;
    Notify(Res, 'target_hung', 'Окно не отвечает, повторите действие через несколько секунд.');
    Exit;
  end;

  // One UI Automation round trip: password flag plus selection.
  Focus := QueryUIAutomationFocus;
  if Focus.IsPassword or IsNativePasswordEdit(Request.FocusWnd) then
  begin
    DiagnosticsLog('operation.skipped reason=password_field');
    Res.FocusIsPassword := True;
    Res.BufferAction := baClear;
    Notify(Res, 'password', 'Поле ввода пароля: преобразование отключено.');
    Exit;
  end;
  if not Focus.HasSelection then
    DiagnosticsLogFmt('target.uia unavailable stage=%s result=0x%.8x',
      [Focus.FailureStage, Cardinal(Focus.ErrorCode)]);

  // Target text, in order of reliability and of how little it disturbs the
  // target application.
  IsSelection := True;
  if GetNativeSelection(Request.FocusWnd, Text) then
    Source := 'native'
  else if Request.BufferText <> '' then
  begin
    Text := Request.BufferText;
    IsSelection := False;
    Source := 'buffer';
  end
  else if Focus.HasSelection then
  begin
    Text := Focus.SelectionText;
    FSelectionWindow := Request.FocusWnd;
    FSelectionIsNative := False;
    Source := 'uia';
  end
  else if GetClipboardSelection(Request, Text) then
    Source := 'clipboard'
  else
  begin
    DiagnosticsLog('target.selected source=none');
    if FClipboardSkipReason = 'clipboard_has_image_or_files' then
      Notify(Res, 'clipboard_image',
        'Не удалось получить выделенный текст: в буфере обмена изображение или файлы, ' +
        'поэтому копирование не выполнялось.');
    Exit;
  end;
  DiagnosticsLogFmt('target.selected source=%s length=%d', [Source, Length(Text)]);

  case Request.Action of
    laConvert:
      begin
        if not FCatalog.ChoosePair(Text, Request.WindowLayout,
             Request.PreviousLayout, Pair) then
        begin
          DiagnosticsLog('convert.no_layout_pair');
          Notify(Res, 'single_layout',
            'В Windows установлена только одна раскладка клавиатуры.');
          Exit;
        end;
        Converted := ConvertTextBetweenLayouts(Text, FCatalog.KeyChars(Pair.Source),
          FCatalog.KeyChars(Pair.Target));
        Res.SourceLayout := Pair.Source;
        Res.TargetLayout := Pair.Target;
        DiagnosticsLogFmt('convert.layouts source=%.8x target=%.8x',
          [NativeUInt(Pair.Source), NativeUInt(Pair.Target)]);
      end;
    laUpperCase:
      Converted := ChangeTextCase(Text, True);
    laLowerCase:
      Converted := ChangeTextCase(Text, False);
    laInvertCase:
      Converted := InvertTextCase(Text);
  else
    Exit;
  end;

  if IsSelection then
    Res.Success := (Converted = Text) or ReplaceSelection(Converted)
  else
    Res.Success := (Converted = Text) or
      (WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) and
       (GetFocusedWindow = Request.FocusWnd) and
       SendBackspaces(Length(Text)) and TypeUnicodeText(Converted));

  if Res.Success then
  begin
    Res.BufferAction := baSet;
    Res.NewBufferText := Converted;
    if (Request.Action = laConvert) and (Res.TargetLayout <> 0) then
      PostMessage(Request.FocusWnd, WM_INPUTLANGCHANGEREQUEST, 0,
        LPARAM(Res.TargetLayout));
  end
  else
  begin
    Res.BufferAction := baClear;
    DiagnosticsLogFmt('operation.replace_failed source=%s', [Source]);
  end;
end;

end.
