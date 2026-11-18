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
  uSettings, uLayoutConverter, uClipboardSnapshot, uConversionChain,
  uUIAutomation, uSpellCheck;

type
  TBufferAction = (baKeep, baClear, baSet);

  TOperationRequest = class
  public
    Sequence: Cardinal;
    Action: TLSAction;
    // Part of the tracked phrase to transform; Mode = bmNone when the phrase
    // is unavailable and other text sources must be used.
    Plan: TBufferPlan;
    // Automatic correction after a space: applied only if nothing has been
    // typed since (GKeystrokeCount still equals KeystrokeStamp).
    Automatic: Boolean;
    KeystrokeStamp: Integer;
    ToggleCapsLock: Boolean;  // Turn Caps Lock off after the correction,
    CapsOffKey: Word;         // with this key (Shift if Shift turns it off).
    // Triggered by a double Alt: wait until the application leaves its menu
    // mode and take the focused window again.
    SettleFocus: Boolean;
    AutoSwitchExceptions: TArray<string>;
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
    UsedBuffer: Boolean;   // The request plan was applied.
    OriginalText: string;  // Text before a selection/caret replacement.
    LookupText: string;    // laTranslate / laWebSearch: text to look up.
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
    FSelectionRange: IUnknown; // UI Automation range to select before typing.
    FSpell: TSpellCheck;
    function ApproveAutoSwitch(Request: TOperationRequest;
      const Original, Converted: string; Res: TOperationResult): Boolean;
    procedure HandleRequest(Request: TOperationRequest);
    procedure Process(Request: TOperationRequest; Res: TOperationResult);
    function ReadNativeEdit(Target: HWND; out Text: string;
      out SelStart, SelEnd: DWORD): Boolean;
    function GetNativeSelection(Target: HWND; out Text: string;
      AllowCaretWord: Boolean = True): Boolean;
    function TypingContinued(Request: TOperationRequest): Boolean;
    procedure ProcessLookup(Request: TOperationRequest; Res: TOperationResult;
      const Focus: TUIAFocusInfo);
    function ReplaceNativeBeforeCaret(Target: HWND;
      const Expected, Replacement: string): Boolean;
    function GetClipboardSelection(Request: TOperationRequest;
      out Text: string): Boolean;
    function ReplaceSelection(const Value: string): Boolean;
    function TransformText(Request: TOperationRequest; const Text: string;
      Res: TOperationResult; out Converted: string): Boolean;
    procedure SwitchLayout(FocusWnd: HWND; Target: HKL);
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

var
  // Physical key presses seen by the UI thread (incremented there).
  GKeystrokeCount: Integer;

implementation

uses
  Winapi.ActiveX,
  uDiagnostics, uWinUtils, uLocale, uTextTools;

const
  WM_LS_EXECUTE = WM_APP + 100;

  MAX_SELECTION_LEN = 1024 * 1024;
  CLIPBOARD_COPY_TIMEOUT = 500;
  MODIFIER_RELEASE_TIMEOUT = 1000;
  TARGET_KEYUP_SETTLE_DELAY = 30;
  WINDOW_MESSAGE_TIMEOUT = 250;
  MAX_CARET_TEXT_LEN = 300;
  LAYOUT_SWITCH_TIMEOUT = 150;
  FOCUS_SETTLE_DELAY = 120;

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
    FSpell := TSpellCheck.Create;
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
    FreeAndNil(FSpell);
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
        [Request.Sequence, Length(Request.Plan.Text), Pointer(Request.FocusWnd),
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

function IsNativeEditClass(const ClassText: string): Boolean;
begin
  Result := (Pos('edit', ClassText) > 0) or (Pos('tmemo', ClassText) > 0);
end;

// Reads the text and selection of a standard Edit/RichEdit control.  Text is
// indexed like the selection: RichEdit counts a paragraph break as one
// character while WM_GETTEXT returns CRLF, so CRLF is folded to CR there.
function TOperationWorker.ReadNativeEdit(Target: HWND; out Text: string;
  out SelStart, SelEnd: DWORD): Boolean;
var
  ClassText: string;
  MessageResult: DWORD_PTR;
  TextLength, Copied: Integer;
begin
  Result := False;
  Text := '';
  SelStart := 0;
  SelEnd := 0;
  if Target = 0 then
    Exit;
  ClassText := LowerCase(GetWindowClassName(Target));
  if not IsNativeEditClass(ClassText) or IsNativePasswordEdit(Target) then
    Exit;

  if SendMessageTimeout(Target, EM_GETSEL, WPARAM(@SelStart), LPARAM(@SelEnd),
       SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  MessageResult := 0;
  if SendMessageTimeoutW(Target, WM_GETTEXTLENGTH, 0, 0,
       SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  TextLength := Integer(MessageResult);
  if (TextLength <= 0) or (TextLength > MAX_SELECTION_LEN) then
    Exit;

  SetLength(Text, TextLength + 1);
  MessageResult := 0;
  if SendMessageTimeoutW(Target, WM_GETTEXT, WPARAM(TextLength + 1),
       LPARAM(PChar(Text)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
       WINDOW_MESSAGE_TIMEOUT, @MessageResult) = 0 then
    Exit;
  Copied := Integer(MessageResult);
  if Copied <= 0 then
    Exit;
  SetLength(Text, Copied);
  if Pos('richedit', ClassText) > 0 then
    Text := StringReplace(Text, #13#10, #13, [rfReplaceAll]);
  Result := (SelStart <= SelEnd) and (SelEnd <= DWORD(Length(Text)));
end;

function TOperationWorker.GetNativeSelection(Target: HWND;
  out Text: string; AllowCaretWord: Boolean): Boolean;
var
  Buffer: string;
  SelStart, SelEnd: DWORD;
  MessageResult: DWORD_PTR;
begin
  Result := False;
  Text := '';
  if not ReadNativeEdit(Target, Buffer, SelStart, SelEnd) then
    Exit;

  if SelStart = SelEnd then
  begin
    // No selection: take the word immediately before the caret.
    if (SelStart = 0) or not AllowCaretWord then
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

function TOperationWorker.ReplaceNativeBeforeCaret(Target: HWND;
  const Expected, Replacement: string): Boolean;
var
  Text: string;
  SelStart, SelEnd, StartPos: DWORD;
  MessageResult: DWORD_PTR;
begin
  // Replaces the Expected text that ends at the caret in a standard
  // Edit/RichEdit control with one EM_REPLACESEL: exact, a single undo step
  // and independent of how the application converts injected keystrokes.
  Result := False;
  if (Expected = '') or not ReadNativeEdit(Target, Text, SelStart, SelEnd) then
    Exit;
  if (SelStart <> SelEnd) or (SelEnd < DWORD(Length(Expected))) then
    Exit;
  StartPos := SelEnd - DWORD(Length(Expected));
  if Copy(Text, StartPos + 1, Length(Expected)) <> Expected then
  begin
    DiagnosticsLog('target.native_buffer mismatch=true');
    Exit;
  end;
  if SendMessageTimeout(Target, EM_SETSEL, StartPos, SelEnd,
       SMTO_ABORTIFHUNG or SMTO_BLOCK, WINDOW_MESSAGE_TIMEOUT,
       @MessageResult) = 0 then
    Exit;
  Result := SendMessageTimeoutW(Target, EM_REPLACESEL, 1,
    LPARAM(PChar(Replacement)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
    WINDOW_MESSAGE_TIMEOUT, @MessageResult) <> 0;
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
    Exit(SendMessageTimeoutW(FSelectionWindow, EM_REPLACESEL, 1,
      LPARAM(PChar(Value)), SMTO_ABORTIFHUNG or SMTO_BLOCK,
      WINDOW_MESSAGE_TIMEOUT, @MessageResult) <> 0);

  if not WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) then
    Exit;
  // Text found before the caret is not selected yet: typing replaces it only
  // after the range has been selected.
  if Assigned(FSelectionRange) and not UIASelectRange(FSelectionRange) then
  begin
    DiagnosticsLog('target.uia_caret select_failed');
    Exit;
  end;
  Result := TypeUnicodeText(Value);
end;

function TOperationWorker.TransformText(Request: TOperationRequest;
  const Text: string; Res: TOperationResult; out Converted: string): Boolean;
var
  Pair: TLayoutPair;
begin
  Result := False;
  Converted := Text;
  if Request.Plan.Mode in [bmUndo, bmFix] then
  begin
    Converted := Request.Plan.Replacement;
    Res.TargetLayout := Request.Plan.ForcedTarget;
    Exit(True);
  end;
  case Request.Action of
    laConvert, laAutoSwitch:
      begin
        if (Request.Plan.ForcedSource <> 0) and (Request.Plan.ForcedTarget <> 0) then
        begin
          // Continuing a chain: keep the direction of the previous step.
          Pair.Source := Request.Plan.ForcedSource;
          Pair.Target := Request.Plan.ForcedTarget;
        end
        else if not FCatalog.ChoosePair(Text, Request.WindowLayout,
             Request.PreviousLayout, Pair) then
        begin
          DiagnosticsLog('convert.no_layout_pair');
          Notify(Res, 'single_layout',
            T('В Windows установлена только одна раскладка клавиатуры.',
              'Only one keyboard layout is installed in Windows.'));
          Exit;
        end;
        Converted := ConvertTextBetweenLayouts(Text, FCatalog.KeyChars(Pair.Source),
          FCatalog.KeyChars(Pair.Target));
        Res.SourceLayout := Pair.Source;
        Res.TargetLayout := Pair.Target;
        DiagnosticsLogFmt('convert.layouts source=%.8x target=%.8x forced=%s',
          [NativeUInt(Pair.Source), NativeUInt(Pair.Target),
           BoolToStr(Request.Plan.ForcedSource <> 0, True)]);
      end;
    laUpperCase:
      Converted := ChangeTextCase(Text, True);
    laLowerCase:
      Converted := ChangeTextCase(Text, False);
    laInvertCase:
      Converted := InvertTextCase(Text);
    laTransliterate:
      Converted := TransliterateText(Text);
  else
    Exit;
  end;
  Result := True;
end;

function IsConsoleWindowClass(const ClassName: string): Boolean;
begin
  Result := SameText(ClassName, 'ConsoleWindowClass') or
    SameText(ClassName, 'CASCADIA_HOSTING_WINDOW_CLASS') or
    SameText(ClassName, 'PseudoConsoleWindow');
end;

procedure TOperationWorker.SwitchLayout(FocusWnd: HWND; Target: HKL);

  function CurrentLayout: HKL;
  begin
    Result := GetKeyboardLayout(GetWindowThreadProcessId(FocusWnd, nil));
  end;

  function WaitForLayout(TimeoutMS: DWORD): Boolean;
  var
    Started: DWORD;
  begin
    Started := GetTickCount;
    repeat
      if CurrentLayout = Target then
        Exit(True);
      Sleep(10);
    until GetTickCount - Started >= TimeoutMS;
    Result := CurrentLayout = Target;
  end;

var
  Root: HWND;
  Attempt: Integer;
begin
  if (FocusWnd = 0) or (Target = 0) or (CurrentLayout = Target) then
    Exit;

  PostMessage(FocusWnd, WM_INPUTLANGCHANGEREQUEST, 0, LPARAM(Target));
  if WaitForLayout(LAYOUT_SWITCH_TIMEOUT) then
    Exit;

  // Some frameworks handle the request only in the top-level window.
  Root := GetAncestor(FocusWnd, GA_ROOT);
  if (Root <> 0) and (Root <> FocusWnd) then
  begin
    PostMessage(Root, WM_INPUTLANGCHANGEREQUEST, 0, LPARAM(Target));
    if WaitForLayout(LAYOUT_SWITCH_TIMEOUT) then
    begin
      DiagnosticsLog('layout.switched via=root_window');
      Exit;
    end;
  end;

  // Consoles ignore WM_INPUTLANGCHANGEREQUEST.  Win+Space cycles the input
  // languages; the layout is checked after every step so the cycle stops
  // exactly at the target.  Limited to consoles, where the check is reliable.
  if not IsConsoleWindowClass(GetWindowClassName(Root)) and
     not IsConsoleWindowClass(GetWindowClassName(FocusWnd)) then
  begin
    DiagnosticsLogFmt('layout.switch_failed class="%s"', [GetWindowClassName(Root)]);
    Exit;
  end;
  for Attempt := 1 to Length(TKeyboardLayoutCatalog.InstalledLayouts) - 1 do
  begin
    if not WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) or
       (GetFocusedWindow <> FocusWnd) then
      Break;
    SendChord(VK_LWIN, VK_SPACE);
    if WaitForLayout(LAYOUT_SWITCH_TIMEOUT * 2) then
    begin
      DiagnosticsLogFmt('layout.switched via=win_space steps=%d', [Attempt]);
      Exit;
    end;
  end;
  DiagnosticsLog('layout.switch_failed via=win_space');
end;

function TOperationWorker.ApproveAutoSwitch(Request: TOperationRequest;
  const Original, Converted: string; Res: TOperationResult): Boolean;
const
  ResultNames: array[TSpellCheckResult] of string = ('unknown', 'correct', 'misspelled');
var
  SourceTag, TargetTag: string;
  SourceResult, TargetResult: TSpellCheckResult;
  Item: string;
begin
  // Switch only when the word is wrong as typed and a correct word of the
  // other language after conversion.  Words are not written to the log.
  Result := False;
  if not IsAutoSwitchCandidate(Converted) then
  begin
    DiagnosticsLog('autoswitch.skipped reason=not_a_word');
    Exit;
  end;
  for Item in Request.AutoSwitchExceptions do
    if AnsiSameText(Item, Original) or AnsiSameText(Item, Converted) then
    begin
      DiagnosticsLog('autoswitch.skipped reason=exception');
      Exit;
    end;
  SourceTag := LayoutLanguageTag(Res.SourceLayout);
  TargetTag := LayoutLanguageTag(Res.TargetLayout);
  SourceResult := FSpell.CheckWord(SourceTag, Original);
  if SourceResult = scMisspelled then
    TargetResult := FSpell.CheckWord(TargetTag, Converted)
  else
    TargetResult := scUnknown;
  Result := (SourceResult = scMisspelled) and (TargetResult = scCorrect);
  DiagnosticsLogFmt('autoswitch.check source=%s:%s target=%s:%s length=%d switch=%s',
    [SourceTag, ResultNames[SourceResult], TargetTag, ResultNames[TargetResult],
     Length(Original), BoolToStr(Result, True)]);
end;

function TOperationWorker.TypingContinued(Request: TOperationRequest): Boolean;
begin
  Result := Request.Automatic and
    (AtomicCmpExchange(GKeystrokeCount, 0, 0) <> Request.KeystrokeStamp);
  if Result then
    DiagnosticsLog('autocorrect.skipped reason=typing_continued');
end;

procedure TOperationWorker.ProcessLookup(Request: TOperationRequest;
  Res: TOperationResult; const Focus: TUIAFocusInfo);
const
  MAX_LOOKUP_LEN = 1000;
var
  Text, Source: string;
  CaretText: WideString;
  CaretRange: IUnknown;
begin
  // Nothing is replaced: a real selection first, then what was just typed,
  // then the word before the caret, the clipboard fallback last.
  if GetNativeSelection(Request.FocusWnd, Text, False) then
    Source := 'native'
  else if Focus.HasSelection then
  begin
    Text := Focus.SelectionText;
    Source := 'uia';
  end
  else if Trim(Request.Plan.Text) <> '' then
  begin
    Text := Trim(Request.Plan.Text);
    Source := 'buffer';
  end
  else if GetNativeSelection(Request.FocusWnd, Text, True) then
    Source := 'native_caret'
  else if UIAGetTextBeforeCaret(Focus, MAX_CARET_TEXT_LEN, CaretText, CaretRange) then
  begin
    Text := CaretText;
    Source := 'uia_caret';
  end
  else if GetClipboardSelection(Request, Text) then
    Source := 'clipboard'
  else
  begin
    DiagnosticsLog('lookup.no_text');
    Notify(Res, 'lookup_empty', T('Выделите текст, который нужно перевести или найти.',
      'Select the text to translate or search for.'));
    Exit;
  end;
  Text := Trim(StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]));
  if Length(Text) > MAX_LOOKUP_LEN then
    SetLength(Text, MAX_LOOKUP_LEN);
  DiagnosticsLogFmt('lookup.text source=%s length=%d', [Source, Length(Text)]);
  Res.LookupText := Text;
  Res.Success := Text <> '';
  Res.BufferAction := baKeep;
end;

procedure TOperationWorker.Process(Request: TOperationRequest;
  Res: TOperationResult);
var
  Focus: TUIAFocusInfo;
  Text, Region, Converted, Typed, Source: string;
  CaretText: WideString;
  CaretRange: IUnknown;
begin
  FSelectionWindow := 0;
  FSelectionIsNative := False;
  FSelectionRange := nil;
  FClipboardSkipReason := '';

  if Request.SettleFocus then
  begin
    WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT);
    Sleep(FOCUS_SETTLE_DELAY);
    if (GetFocusedWindow <> 0) and (GetFocusedWindow <> Request.FocusWnd) then
    begin
      DiagnosticsLogFmt('operation.focus_settled from=%p to=%p',
        [Pointer(Request.FocusWnd), Pointer(GetFocusedWindow)]);
      Request.FocusWnd := GetFocusedWindow;
    end;
  end;

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
    Notify(Res, 'target_hung', T('Окно не отвечает, повторите действие через несколько секунд.',
      'The window is not responding, try again in a few seconds.'));
    Exit;
  end;

  // One UI Automation round trip: password flag, selection, text pattern.
  Focus := QueryUIAutomationFocus;
  if Focus.IsPassword or IsNativePasswordEdit(Request.FocusWnd) then
  begin
    DiagnosticsLog('operation.skipped reason=password_field');
    Res.FocusIsPassword := True;
    Res.BufferAction := baClear;
    Notify(Res, 'password', T('Поле ввода пароля: преобразование отключено.',
      'Password field: conversion is disabled.'));
    Exit;
  end;

  if Request.Action in [laTranslate, laWebSearch] then
  begin
    ProcessLookup(Request, Res, Focus);
    Exit;
  end;

  // 1. Text typed since the last caret jump: exact, no clipboard, and it
  //    supports widening from the last word to the whole phrase.
  if Request.Plan.Mode <> bmNone then
  begin
    Region := Request.Plan.Region;
    DiagnosticsLogFmt('target.selected source=buffer mode=%d region_length=%d delete=%d',
      [Ord(Request.Plan.Mode), Length(Region), Request.Plan.DeleteCount]);
    if not TransformText(Request, Region, Res, Converted) then
      Exit;
    if (Request.Action = laAutoSwitch) and
       not ApproveAutoSwitch(Request, Region, Converted, Res) then
    begin
      Res.BufferAction := baKeep;
      Exit;
    end;
    Res.UsedBuffer := True;
    Typed := Converted + Request.Plan.Tail;
    if Converted = Region then
      Res.Success := True
    else if TypingContinued(Request) then
    begin
      // The text before the caret is no longer what the plan expects.
      Res.BufferAction := baKeep;
      Exit;
    end
    else if ReplaceNativeBeforeCaret(Request.FocusWnd,
         Region + Request.Plan.Tail, Typed) then
    begin
      Res.Success := True;
      DiagnosticsLog('target.buffer applied=native');
    end
    else
      Res.Success := WaitForModifiersReleased(MODIFIER_RELEASE_TIMEOUT) and
        (GetFocusedWindow = Request.FocusWnd) and not TypingContinued(Request) and
        SendBackspaces(Request.Plan.DeleteCount) and TypeUnicodeText(Typed);
    if Res.Success and Request.ToggleCapsLock then
    begin
      SendKeyTap(Request.CapsOffKey);
      DiagnosticsLog('autocorrect.caps_lock_turned_off');
    end;
    if Res.Success then
    begin
      Res.BufferAction := baSet;
      Res.NewBufferText := Request.Plan.Head + Typed;
      if Res.TargetLayout <> 0 then
        SwitchLayout(Request.FocusWnd, Res.TargetLayout);
    end
    else
    begin
      Res.BufferAction := baClear;
      DiagnosticsLog('operation.replace_failed source=buffer');
    end;
    Exit;
  end;

  // 2. Selection or the word before the caret, in order of reliability and
  //    of how little it disturbs the target application.
  if GetNativeSelection(Request.FocusWnd, Text) then
    Source := 'native'
  else if Focus.HasSelection then
  begin
    Text := Focus.SelectionText;
    FSelectionWindow := Request.FocusWnd;
    Source := 'uia';
  end
  else if UIAGetTextBeforeCaret(Focus, MAX_CARET_TEXT_LEN, CaretText, CaretRange) then
  begin
    Text := CaretText;
    FSelectionWindow := Request.FocusWnd;
    FSelectionRange := CaretRange;
    Source := 'uia_caret';
  end
  else if GetClipboardSelection(Request, Text) then
    Source := 'clipboard'
  else
  begin
    DiagnosticsLogFmt('target.selected source=none uia_stage=%s uia_result=0x%.8x',
      [Focus.FailureStage, Cardinal(Focus.ErrorCode)]);
    if FClipboardSkipReason = 'clipboard_has_image_or_files' then
      Notify(Res, 'clipboard_image',
        T('Не удалось получить выделенный текст: в буфере обмена изображение или файлы, ' +
          'поэтому копирование не выполнялось.',
          'Could not get the selected text: the clipboard holds an image or files, ' +
          'so nothing was copied.'));
    Exit;
  end;
  DiagnosticsLogFmt('target.selected source=%s length=%d', [Source, Length(Text)]);

  // Undo only ever works on the tracked text.
  if Request.Action = laUndo then
    Exit;
  if not TransformText(Request, Text, Res, Converted) then
    Exit;
  Res.OriginalText := Text;
  Res.Success := (Converted = Text) or ReplaceSelection(Converted);
  FSelectionRange := nil;
  if Res.Success then
  begin
    Res.BufferAction := baSet;
    Res.NewBufferText := Converted;
    if Res.TargetLayout <> 0 then
      SwitchLayout(Request.FocusWnd, Res.TargetLayout);
  end
  else
  begin
    Res.BufferAction := baClear;
    DiagnosticsLogFmt('operation.replace_failed source=%s', [Source]);
  end;
end;

end.
