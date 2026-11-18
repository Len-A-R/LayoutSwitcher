program LSIntegration;

// Scenario tests against real windows: the real TOperationWorker (UI
// Automation, EM_GETSEL/EM_REPLACESEL, SendInput, layout switching) works on
// edit boxes of this program's own window.
//
// The test window takes the focus and types into itself for about ten
// seconds.  Input is only ever sent while this window is in the foreground;
// if the focus moves elsewhere the run stops.  Start it with
// Tests\Integration\run-integration.cmd and do not touch the keyboard.

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  uSettings in '..\..\uSettings.pas',
  uLocale in '..\..\uLocale.pas',
  uWinUtils in '..\..\uWinUtils.pas',
  uDiagnostics in '..\..\uDiagnostics.pas',
  uUIAutomation in '..\..\uUIAutomation.pas',
  uLayoutConverter in '..\..\uLayoutConverter.pas',
  uClipboardSnapshot in '..\..\uClipboardSnapshot.pas',
  uConversionChain in '..\..\uConversionChain.pas',
  uOperationWorker in '..\..\uOperationWorker.pas';

const
  WM_RESULT = WM_APP + 10;
  RESULT_TIMEOUT_MS = 15000;

type
  TFocusLost = class(Exception);

  THarnessForm = class(TForm)
  private
    FResult: TOperationResult;
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    Edit: TEdit;
    Password: TEdit;
    Rich: TRichEdit;
    function TakeResult: TOperationResult;
  end;

var
  Form: THarnessForm;
  Worker: TOperationWorker;
  Chain: TConversionChain;
  EnLayout, RuLayout: HKL;
  Passed, Failed, Skipped: Integer;
  Sequence: Cardinal;

procedure THarnessForm.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_RESULT then
  begin
    FreeAndNil(FResult);
    FResult := TOperationResult(Message.LParam);
    Exit;
  end;
  inherited;
end;

function THarnessForm.TakeResult: TOperationResult;
begin
  Result := FResult;
  FResult := nil;
end;

procedure Pump(MS: Cardinal);
var
  Started: DWORD;
begin
  Started := GetTickCount;
  repeat
    Application.ProcessMessages;
    Sleep(5);
  until GetTickCount - Started >= MS;
end;

procedure EnsureForeground(Control: TWinControl);
begin
  SetForegroundWindow(Form.Handle);
  Control.SetFocus;
  Pump(100);
  if (GetForegroundWindow <> Form.Handle) or (GetFocus <> Control.Handle) then
    raise TFocusLost.Create('the test window lost the focus');
end;

function Run(Action: TLSAction; Control: TWinControl;
  const Plan: TBufferPlan): TOperationResult;
var
  Request: TOperationRequest;
  Started: DWORD;
begin
  EnsureForeground(Control);
  Request := TOperationRequest.Create;
  Inc(Sequence);
  Request.Sequence := Sequence;
  Request.Action := Action;
  Request.Plan := Plan;
  Request.FocusWnd := Control.Handle;
  Request.WindowLayout := GetKeyboardLayout(0);
  Request.PreviousLayout := 0;
  if not Worker.Post(Request) then
    raise Exception.Create('cannot post the request');
  Started := GetTickCount;
  Result := nil;
  while Result = nil do
  begin
    Application.ProcessMessages;
    Result := Form.TakeResult;
    if (Result = nil) and (GetTickCount - Started > RESULT_TIMEOUT_MS) then
      raise Exception.Create('no result from the worker');
    Sleep(5);
  end;
  // Let the injected keystrokes reach the edit box.
  Pump(250);
  if GetForegroundWindow <> Form.Handle then
    raise TFocusLost.Create('the test window lost the focus');
end;

procedure Check(const Name: string; Condition: Boolean; const Details: string = '');
begin
  if Condition then
  begin
    Inc(Passed);
    Writeln('PASS  ', Name);
  end
  else
  begin
    Inc(Failed);
    Writeln('FAIL  ', Name, '  ', Details);
  end;
end;

procedure Skip(const Name, Reason: string);
begin
  Inc(Skipped);
  Writeln('SKIP  ', Name, '  (', Reason, ')');
end;

procedure SetEdit(const Text: string; SelStart, SelLength: Integer);
begin
  Form.Edit.Text := Text;
  Form.Edit.SelStart := SelStart;
  Form.Edit.SelLength := SelLength;
  Chain.Reset;
end;

// Applies a buffer plan exactly as the main window does after a result.
function RunBuffered(Action: TLSAction; out Res: TOperationResult): TBufferPlan;
begin
  Result := Chain.Plan(Action, Form.Edit.Text);
  Res := Run(Action, Form.Edit, Result);
  if Res.Success and Res.UsedBuffer then
    Chain.Completed(Result, Action, Res.NewBufferText, Res.SourceLayout,
      Res.TargetLayout)
  else
    Chain.Reset;
end;

procedure ScenarioPhraseChain;
var
  Res: TOperationResult;
begin
  if (EnLayout = 0) or (RuLayout = 0) then
  begin
    Skip('phrase chain', 'US English and Russian layouts are not both installed');
    Exit;
  end;
  SetEdit('ghbdtn vbh', 10, 0);
  RunBuffered(laConvert, Res);
  try
    Check('phrase: 1st press converts the last word',
      Form.Edit.Text = 'ghbdtn мир', Form.Edit.Text);
    Check('phrase: layout switched to Russian',
      GetKeyboardLayout(0) = RuLayout, IntToHex(NativeUInt(GetKeyboardLayout(0)), 8));
  finally
    Res.Free;
  end;
  RunBuffered(laConvert, Res);
  Res.Free;
  Check('phrase: 2nd press converts the whole phrase',
    Form.Edit.Text = 'привет мир', Form.Edit.Text);
  RunBuffered(laConvert, Res);
  Res.Free;
  Check('phrase: 3rd press reverts', Form.Edit.Text = 'ghbdtn vbh', Form.Edit.Text);
end;

procedure ScenarioUndo;
var
  Res: TOperationResult;
begin
  SetEdit('hello world', 11, 0);
  RunBuffered(laUpperCase, Res);
  Res.Free;
  Check('undo: uppercase applied', Form.Edit.Text = 'hello WORLD', Form.Edit.Text);
  RunBuffered(laUndo, Res);
  Res.Free;
  Check('undo: text restored', Form.Edit.Text = 'hello world', Form.Edit.Text);
end;

procedure ScenarioCaseAndTranslit;
var
  Res: TOperationResult;
begin
  SetEdit('Hello', 5, 0);
  RunBuffered(laInvertCase, Res);
  Res.Free;
  Check('invert case', Form.Edit.Text = 'hELLO', Form.Edit.Text);
  SetEdit('privet', 6, 0);
  RunBuffered(laTransliterate, Res);
  Res.Free;
  Check('transliteration', Form.Edit.Text = 'привет', Form.Edit.Text);
end;

procedure ScenarioNativeSelection;
var
  Res: TOperationResult;
  NoPlan: TBufferPlan;
begin
  if (EnLayout = 0) or (RuLayout = 0) then
  begin
    Skip('native selection', 'US English and Russian layouts are not both installed');
    Exit;
  end;
  ActivateKeyboardLayout(EnLayout, 0);
  NoPlan := Chain.Plan(laNone, '');
  SetEdit('one ghbdtn two', 4, 6);
  Res := Run(laConvert, Form.Edit, NoPlan);
  try
    Check('native: selection converted', Form.Edit.Text = 'one привет two',
      Form.Edit.Text);
    Check('native: source reported', Res.Success and not Res.UsedBuffer);
  finally
    Res.Free;
  end;

  ActivateKeyboardLayout(EnLayout, 0);
  SetEdit('one ghbdtn', 10, 0);
  Res := Run(laConvert, Form.Edit, NoPlan);
  Res.Free;
  Check('native: word before the caret converted', Form.Edit.Text = 'one привет',
    Form.Edit.Text);
end;

procedure ScenarioPassword;
var
  Res: TOperationResult;
  Plan: TBufferPlan;
begin
  Form.Password.Text := 'ghbdtn';
  Form.Password.SelStart := 6;
  Chain.Reset;
  Plan := Chain.Plan(laConvert, 'ghbdtn');
  Res := Run(laConvert, Form.Password, Plan);
  try
    Check('password: skipped', Res.FocusIsPassword and not Res.Success);
    Check('password: text untouched', Form.Password.Text = 'ghbdtn', Form.Password.Text);
  finally
    Res.Free;
  end;
end;

procedure ScenarioRichEditAfterLineBreak;
var
  Res: TOperationResult;
  Plan: TBufferPlan;
  Text: string;
begin
  if (EnLayout = 0) or (RuLayout = 0) then
  begin
    Skip('richedit', 'US English and Russian layouts are not both installed');
    Exit;
  end;
  ActivateKeyboardLayout(EnLayout, 0);
  // RichEdit counts a paragraph break as one character, WM_GETTEXT as two.
  Form.Rich.Text := 'first line' + sLineBreak + 'second ghbdtn';
  Form.Rich.SelStart := Form.Rich.GetTextLen;
  Chain.Reset;
  Plan := Chain.Plan(laConvert, 'ghbdtn');
  Res := Run(laConvert, Form.Rich, Plan);
  try
    Text := StringReplace(Form.Rich.Text, sLineBreak, '|', [rfReplaceAll]);
    Check('richedit: last word after a line break', Text = 'first line|second привет',
      Text);
  finally
    Res.Free;
  end;

  ActivateKeyboardLayout(EnLayout, 0);
  Form.Rich.Text := 'first line' + sLineBreak + 'second ghbdtn';
  Form.Rich.SelStart := Form.Rich.GetTextLen;
  Chain.Reset;
  Res := Run(laConvert, Form.Rich, Chain.Plan(laNone, ''));
  try
    Text := StringReplace(Form.Rich.Text, sLineBreak, '|', [rfReplaceAll]);
    Check('richedit: word before the caret after a line break',
      Text = 'first line|second привет', Text);
  finally
    Res.Free;
  end;
end;

procedure FindLayouts;
var
  Layout: HKL;
begin
  EnLayout := 0;
  RuLayout := 0;
  for Layout in TKeyboardLayoutCatalog.InstalledLayouts do
    if NativeUInt(Layout) and $FFFFFFFF = $04090409 then
      EnLayout := Layout
    else if NativeUInt(Layout) and $FFFFFFFF = $04190419 then
      RuLayout := Layout;
end;

begin
  Application.Initialize;
  Form := THarnessForm.CreateNew(nil);
  Chain := TConversionChain.Create;
  try
    Form.Caption := 'LayoutSwitcher integration tests - do not touch the keyboard';
    Form.SetBounds(200, 200, 520, 220);
    Form.Edit := TEdit.Create(Form);
    Form.Edit.Parent := Form;
    Form.Edit.SetBounds(16, 16, 470, 24);
    Form.Password := TEdit.Create(Form);
    Form.Password.Parent := Form;
    Form.Password.PasswordChar := '*';
    Form.Password.SetBounds(16, 56, 470, 24);
    Form.Rich := TRichEdit.Create(Form);
    Form.Rich.Parent := Form;
    Form.Rich.SetBounds(16, 92, 470, 60);
    Form.Rich.PlainText := True;
    Form.Show;
    Pump(300);

    FindLayouts;
    if EnLayout <> 0 then
      ActivateKeyboardLayout(EnLayout, 0);
    Worker := TOperationWorker.Create(Form.Handle, WM_RESULT);
    try
      if not Worker.WaitUntilReady(5000) then
        raise Exception.Create('worker did not start');
      try
        ScenarioPhraseChain;
        ScenarioUndo;
        ScenarioCaseAndTranslit;
        ScenarioNativeSelection;
        ScenarioPassword;
        ScenarioRichEditAfterLineBreak;
      except
        on E: TFocusLost do
        begin
          Inc(Failed);
          Writeln('ABORTED  ', E.Message, ' - run again without touching the keyboard');
        end;
      end;
    finally
      Worker.Free;
    end;
  finally
    Chain.Free;
    Form.Free;
  end;
  Writeln;
  Writeln(Format('Passed: %d  Failed: %d  Skipped: %d', [Passed, Failed, Skipped]));
  if Failed > 0 then
    ExitCode := 1;
end.
