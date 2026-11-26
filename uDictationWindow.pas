unit uDictationWindow;

// The dictation window: the text appears while the user speaks, OK types it
// into the field the caret was in, Cancel drops it.  A borderless card in the
// style of Windows 11 (light or dark like the system, rounded corners, a
// shadow) at the bottom of the screen.  The window takes the focus, so that
// the text can be corrected before it is inserted, and gives the focus back
// to the field it came from when it closes.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  uModernUI, uAudioRecorder;

type
  TDictationWindowState = (dwRecording, dwRecognizing, dwEditing);

  // The animated header: a window of its own, drawn in memory and shown
  // at once (a paint box on the form is erased first and flickers).
  THeaderBox = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Canvas;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property OnMouseDown;
    property OnMouseMove;
  end;

  TDictationWindow = class(TForm)
  private
    FTheme: TUiTheme;
    FRecorder: TAudioRecorder;
    FState: TDictationWindowState;
    FLive: Boolean;
    FHeader: THeaderBox;
    FBody: TPanel;
    FMemo: TMemo;
    FFooter: TPanel;
    FHint: TLabel;
    FOk: TFlatButton;
    FCancel: TFlatButton;
    FTimer: TTimer;
    FLevels: array[0..19] of Integer;
    FLevelIndex: Integer;
    FPhase: Integer;
    FStatus: string;
    FCloseRect: TRect;
    FHoverClose: Boolean;
    FReturnConsumed: Boolean;
    FTargetWindow: HWND;
    FTargetFocus: HWND;
    FOnOk: TNotifyEvent;
    FOnCancel: TNotifyEvent;
    FOnEdit: TNotifyEvent;
    function S(Value: Integer): Integer;
    procedure ApplyTheme;
    procedure Tick(Sender: TObject);
    procedure HeaderPaint(Sender: TObject);
    procedure HeaderMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MemoMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure DoEdit;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
  public
    constructor CreateWindow(AOwner: TComponent; Recorder: TAudioRecorder);
    // Remembers the window and the field with the focus, shows the window
    // empty in the recording state and takes the focus.  Live: the text
    // appears while the user speaks (not with a cloud model).
    procedure Open(const Hint: string; Live: Boolean);
    procedure SetText(const Text: string);
    procedure SetState(State: TDictationWindowState);
    // A message instead of the subtitle (an error); '' removes it.
    procedure SetStatus(const Text: string);
    // Hides the window and gives the focus back to the remembered field.
    procedure CloseAndReturnFocus;
    // Gives the focus back to the remembered window and field again (the
    // first attempt was refused); True when that window is in front.
    function ReturnFocus: Boolean;
    function Text: string;
    function Shown: Boolean;
    function HasFocus: Boolean;
    property TargetWindow: HWND read FTargetWindow;
    property OnOk: TNotifyEvent read FOnOk write FOnOk;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    // The user clicked into the text or started typing while recording:
    // the recording ends and the text becomes editable.
    property OnEdit: TNotifyEvent read FOnEdit write FOnEdit;
  end;

implementation

uses
  System.Math, System.Variants, Winapi.OleAcc, uLocale, uDictation;

// A background program may not take the focus by itself: attached to the
// input of the foreground window it may.
procedure TakeForeground(Wnd: HWND);
var
  Foreground: HWND;
  ForegroundThread, Mine: DWORD;
begin
  Foreground := GetForegroundWindow;
  ForegroundThread := GetWindowThreadProcessId(Foreground, nil);
  Mine := GetCurrentThreadId;
  if (Foreground <> 0) and (ForegroundThread <> Mine) and
     AttachThreadInput(Mine, ForegroundThread, True) then
  try
    BringWindowToTop(Wnd);
    SetForegroundWindow(Wnd);
    // Active and focused in the shared input state as well: otherwise the
    // window is in front, but the keys of the user reach nobody.
    SetActiveWindow(Wnd);
    Winapi.Windows.SetFocus(Wnd);
  finally
    AttachThreadInput(Mine, ForegroundThread, False);
  end
  else
    SetForegroundWindow(Wnd);
end;

{ THeaderBox }

constructor THeaderBox.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
end;

procedure THeaderBox.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Paint fills everything.
  Message.Result := 1;
end;

procedure THeaderBox.Paint;
begin
  if Assigned(FOnPaint) then
    FOnPaint(Self);
end;

// Where the text goes, in screen coordinates: the caret (the system caret,
// or the one browsers and Office report through MSAA), else the focused
// control.  False when none is known.
function TargetAnchor(const Info: TGUIThreadInfo; out Anchor: TRect; out IsCaret: Boolean): Boolean;
var
  Acc: IAccessible;
  X, Y, W, H: Integer;
  TopLeft, BottomRight: TPoint;
begin
  Result := False;
  IsCaret := False;
  if (Info.hwndCaret <> 0) and not IsRectEmpty(Info.rcCaret) then
  begin
    TopLeft := Info.rcCaret.TopLeft;
    BottomRight := Info.rcCaret.BottomRight;
    Winapi.Windows.ClientToScreen(Info.hwndCaret, TopLeft);
    Winapi.Windows.ClientToScreen(Info.hwndCaret, BottomRight);
    Anchor := Rect(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y);
    IsCaret := True;
    Exit(True);
  end;
  if Info.hwndFocus = 0 then
    Exit;
  try
    if Succeeded(AccessibleObjectFromWindow(Info.hwndFocus, OBJID_CARET, IID_IAccessible, Acc)) and
       (Acc <> nil) and Succeeded(Acc.accLocation(X, Y, W, H, CHILDID_SELF)) and
       ((X <> 0) or (Y <> 0)) and (H > 0) then
    begin
      Anchor := Rect(X, Y, X + Max(W, 1), Y + H);
      IsCaret := True;
      Exit(True);
    end;
  except
    // An application with a broken accessibility server.
  end;
  // The focused control itself, unless it is the whole window.
  if (GetAncestor(Info.hwndFocus, GA_ROOT) <> Info.hwndFocus) and GetWindowRect(Info.hwndFocus, Anchor) and
     not IsRectEmpty(Anchor) then
    Result := True;
end;

{ TDictationWindow }

function TDictationWindow.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

constructor TDictationWindow.CreateWindow(AOwner: TComponent; Recorder: TAudioRecorder);

  function NewPanel(AAlign: TAlign): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := Self;
    Result.Align := AAlign;
    Result.BevelOuter := bvNone;
    Result.ParentBackground := False;
    Result.ShowCaption := False;
  end;

begin
  inherited CreateNew(AOwner);
  FRecorder := Recorder;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  Position := poDesigned;
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnKeyPress := FormKeyPress;
  Font.Name := ModernFontName;
  Font.Size := 9;
  ClientWidth := S(560);
  ClientHeight := S(276);

  FHeader := THeaderBox.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Height := S(64);
  FHeader.OnPaint := HeaderPaint;
  FHeader.OnMouseDown := HeaderMouseDown;
  FHeader.OnMouseMove := HeaderMouseMove;

  FFooter := NewPanel(alBottom);
  FFooter.Height := S(60);
  FFooter.Padding.SetBounds(S(20), S(12), S(16), S(14));

  // alRight: the larger Left is further right.
  FOk := TFlatButton.Create(Self);
  FOk.Parent := FFooter;
  FOk.Left := 2000;
  FOk.Align := alRight;
  FOk.Width := S(104);
  FOk.Primary := True;
  FOk.Caption := T('ОК', 'OK');
  FOk.OnClick := OkClick;

  FCancel := TFlatButton.Create(Self);
  FCancel.Parent := FFooter;
  FCancel.Left := 1000;
  FCancel.Align := alRight;
  FCancel.Width := S(104);
  FCancel.AlignWithMargins := True;
  FCancel.Margins.SetBounds(0, 0, S(8), 0);
  FCancel.Caption := T('Отмена', 'Cancel');
  FCancel.OnClick := CancelClick;

  FHint := TLabel.Create(Self);
  FHint.Parent := FFooter;
  FHint.Align := alClient;
  FHint.Layout := tlCenter;
  FHint.EllipsisPosition := epEndEllipsis;
  FHint.Font.Size := 8;
  FHint.ShowAccelChar := False;

  FBody := NewPanel(alClient);
  FBody.Padding.SetBounds(S(22), S(2), S(18), S(8));

  FMemo := TMemo.Create(Self);
  FMemo.Parent := FBody;
  FMemo.Align := alClient;
  FMemo.BorderStyle := bsNone;
  FMemo.ScrollBars := ssNone;
  FMemo.WordWrap := True;
  FMemo.WantReturns := True;
  FMemo.Font.Name := ModernFontName;
  FMemo.Font.Size := 12;
  FMemo.OnMouseDown := MemoMouseDown;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

procedure TDictationWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // No taskbar button; a shadow around the borderless card.
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TDictationWindow.CreateWnd;
begin
  inherited;
  ApplyWindowChrome(Handle, FTheme, FTheme.Back);
end;

procedure TDictationWindow.ApplyTheme;
begin
  FTheme := CurrentUiTheme;
  Color := FTheme.Back;
  FBody.Color := FTheme.Back;
  FMemo.Color := FTheme.Back;
  FMemo.Font.Color := FTheme.Text;
  FFooter.Color := FTheme.Footer;
  FHint.Font.Color := FTheme.Muted;
  FOk.Theme := FTheme;
  FCancel.Theme := FTheme;
  FOk.Font.Assign(Font);
  FCancel.Font.Assign(Font);
  FOk.Invalidate;
  FCancel.Invalidate;
  if HandleAllocated then
    ApplyWindowChrome(Handle, FTheme, FTheme.Back);
end;

procedure TDictationWindow.Open(const Hint: string; Live: Boolean);
var
  Info: TGUIThreadInfo;
  Area, Anchor: TRect;
  Monitor: TMonitor;
  IsCaret, Known: Boolean;
  Gap: Integer;
begin
  // The field the text is for.
  FTargetWindow := GetForegroundWindow;
  FTargetFocus := 0;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Known := False;
  IsCaret := False;
  if GetGUIThreadInfo(GetWindowThreadProcessId(FTargetWindow, nil), Info) then
  begin
    FTargetFocus := Info.hwndFocus;
    Known := TargetAnchor(Info, Anchor, IsCaret);
  end;

  ApplyTheme;
  FLive := Live;
  FStatus := '';
  FHint.Caption := Hint;
  FillChar(FLevels, SizeOf(FLevels), 0);
  FMemo.Clear;
  SetState(dwRecording);

  if Known then
    Monitor := Screen.MonitorFromRect(Anchor)
  else
    Monitor := Screen.MonitorFromWindow(FTargetWindow);
  if Monitor <> nil then
    Area := Monitor.WorkareaRect
  else
    Area := Screen.WorkAreaRect;
  if Known then
  begin
    // A tall control (a document): its bottom edge is the anchor, so that
    // the window does not cover the text being written.
    if not IsCaret and (Anchor.Height > S(120)) then
      Anchor.Top := Anchor.Bottom - 1;
    // Under the caret or the control, else above it; the left edge in
    // line with it, inside the work area.
    Gap := S(10);
    if IsCaret then
      Left := Anchor.Left - S(24)
    else
      Left := Anchor.Left;
    if Anchor.Bottom + Gap + Height <= Area.Bottom then
      Top := Anchor.Bottom + Gap
    else if Anchor.Top - Gap - Height >= Area.Top then
      Top := Anchor.Top - Gap - Height
    else
      Top := Area.Bottom - Height - S(8);
    Left := EnsureRange(Left, Area.Left + S(8), Max(Area.Left + S(8), Area.Right - Width - S(8)));
    Top := EnsureRange(Top, Area.Top + S(8), Max(Area.Top + S(8), Area.Bottom - Height - S(8)));
  end
  else
  begin
    // Nothing known about the field: bottom centre of the monitor.
    Left := Area.Left + (Area.Width - Width) div 2;
    Top := Area.Bottom - Height - S(48);
  end;
  Show;
  TakeForeground(Handle);
  ActiveControl := FMemo;
  // The text has the keyboard focus (Enter, Esc, corrections).
  if FMemo.HandleAllocated and (GetForegroundWindow = Handle) then
    Winapi.Windows.SetFocus(FMemo.Handle);
  FTimer.Enabled := True;
end;

procedure TDictationWindow.SetText(const Text: string);
var
  Old: string;
  Same: Integer;
begin
  Old := FMemo.Text;
  if Old = Text then
    Exit;
  // Only the changed end is replaced: the rest of the text stays still
  // instead of being redrawn on every update.
  Same := 0;
  while (Same < Length(Old)) and (Same < Length(Text)) and (Old[Same + 1] = Text[Same + 1]) do
    Inc(Same);
  SendMessage(FMemo.Handle, WM_SETREDRAW, 0, 0);
  try
    FMemo.SelStart := Same;
    FMemo.SelLength := Length(Old) - Same;
    FMemo.SelText := Copy(Text, Same + 1, MaxInt);
    FMemo.SelStart := Length(Text);
  finally
    SendMessage(FMemo.Handle, WM_SETREDRAW, 1, 0);
  end;
  SendMessage(FMemo.Handle, EM_SCROLLCARET, 0, 0);
  // A shorter text leaves the space under it to erase.
  InvalidateRect(FMemo.Handle, nil, Length(Text) < Length(Old));
end;

procedure TDictationWindow.SetState(State: TDictationWindowState);
begin
  FState := State;
  // Live text is not edited while it changes.
  FMemo.ReadOnly := State <> dwEditing;
  if State = dwEditing then
  begin
    FMemo.SelStart := Length(FMemo.Text);
    if Visible and FMemo.CanFocus then
      FMemo.SetFocus;
  end;
  FHeader.Invalidate;
end;

procedure TDictationWindow.SetStatus(const Text: string);
begin
  FStatus := Text;
  FHeader.Invalidate;
end;

function TDictationWindow.ReturnFocus: Boolean;
var
  Mine, TargetThread: DWORD;
begin
  Result := False;
  if not IsWindow(FTargetWindow) then
    Exit;
  if GetForegroundWindow <> FTargetWindow then
  begin
    if not SetForegroundWindow(FTargetWindow) then
      // Not allowed directly (this window is not in front any more).
      TakeForeground(FTargetWindow);
  end;
  // The field that had the focus inside that window.
  if IsWindow(FTargetFocus) then
  begin
    Mine := GetCurrentThreadId;
    TargetThread := GetWindowThreadProcessId(FTargetFocus, nil);
    if (TargetThread <> Mine) and AttachThreadInput(Mine, TargetThread, True) then
    try
      if Winapi.Windows.GetFocus <> FTargetFocus then
        Winapi.Windows.SetFocus(FTargetFocus);
    finally
      AttachThreadInput(Mine, TargetThread, False);
    end;
  end;
  Result := GetForegroundWindow = FTargetWindow;
end;

procedure TDictationWindow.CloseAndReturnFocus;
begin
  FTimer.Enabled := False;
  if not Visible then
    Exit;
  // The field gets the focus back first: hiding the active window would
  // activate some other window.
  ReturnFocus;
  Hide;
end;

function TDictationWindow.Text: string;
begin
  Result := FMemo.Text;
end;

function TDictationWindow.Shown: Boolean;
begin
  Result := Visible;
end;

function TDictationWindow.HasFocus: Boolean;
begin
  Result := Visible and HandleAllocated and (GetForegroundWindow = Handle);
end;

procedure TDictationWindow.Tick(Sender: TObject);
begin
  Inc(FPhase);
  if (FState = dwRecording) and (FRecorder <> nil) then
  begin
    FLevels[FLevelIndex] := FRecorder.Level;
    FLevelIndex := (FLevelIndex + 1) mod Length(FLevels);
  end;
  if FState <> dwEditing then
    FHeader.Invalidate;
end;

procedure TDictationWindow.HeaderPaint(Sender: TObject);
var
  C: TCanvas;
  R, TextRect: TRect;
  MidY, I, Index, Level, BarX, BarW, BarH, Gap, Right: Integer;
  Glyph, Title, Subtitle, Secs: string;
  GlyphColor: TColor;
begin
  C := FHeader.Canvas;
  R := FHeader.ClientRect;
  C.Brush.Color := FTheme.Back;
  C.FillRect(R);
  MidY := R.Height div 2 + S(4);

  // Microphone in a circle: red while recording, accent while recognizing.
  case FState of
    dwRecording:
      begin
        GlyphColor := RGB(220, 53, 69);
        Glyph := #$E720;
      end;
    dwRecognizing:
      begin
        GlyphColor := FTheme.Accent;
        Glyph := #$E720;
      end;
  else
    GlyphColor := FTheme.Accent;
    Glyph := #$E70F;     // pencil: the text can be corrected
  end;
  TextRect := Rect(S(20), MidY - S(18), S(56), MidY + S(18));
  FillSmooth(C, TextRect, GlyphColor, -1);
  C.Brush.Style := bsClear;
  C.Font.Name := IconFontName;
  C.Font.Size := 13;
  C.Font.Style := [];
  C.Font.Color := clWhite;
  DrawText(C.Handle, PChar(Glyph), 1, TextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  // Close button.
  FCloseRect := Rect(R.Right - S(46), MidY - S(16), R.Right - S(14), MidY + S(16));
  if FHoverClose then
    FillSmooth(C, FCloseRect, FTheme.Hover, S(4));
  C.Brush.Style := bsClear;
  C.Font.Size := 9;
  C.Font.Color := FTheme.Muted;
  Glyph := #$E711;
  TextRect := FCloseRect;
  DrawText(C.Handle, PChar(Glyph), 1, TextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  Right := FCloseRect.Left - S(12);

  if FState = dwRecording then
  begin
    // Level bars, the newest on the right, and the elapsed time.
    BarW := S(3);
    Gap := S(2);
    BarX := Right - Length(FLevels) * (BarW + Gap);
    Right := BarX - S(8);
    for I := 0 to High(FLevels) do
    begin
      Index := (FLevelIndex + I) mod Length(FLevels);
      Level := Min(100, FLevels[Index] * 2);
      BarH := Max(S(2), MulDiv(S(24), Level, 100));
      FillSmooth(C, Rect(BarX, MidY - BarH div 2, BarX + BarW, MidY + BarH div 2 + 1),
        FTheme.Accent, Min(BarW div 2, BarH div 2));
      Inc(BarX, BarW + Gap);
    end;
    if FRecorder <> nil then
    begin
      Secs := Format('%d:%.2d', [Trunc(FRecorder.Seconds) div 60, Trunc(FRecorder.Seconds) mod 60]);
      C.Brush.Style := bsClear;
      C.Font.Name := ModernFontName;
      C.Font.Size := 8;
      C.Font.Color := FTheme.Muted;
      Right := Right - C.TextWidth(Secs);
      C.TextOut(Right, MidY - C.TextHeight(Secs) div 2, Secs);
      Dec(Right, S(8));
    end;
  end;

  case FState of
    dwRecording:
      begin
        Title := T('Говорите…', 'Speak…');
        if FLive then
          Subtitle := T('Щёлкните по тексту, чтобы исправить его', 'Click the text to correct it')
        else
          Subtitle := T('Текст появится, когда вы закончите', 'The text appears when you finish');
      end;
    dwRecognizing:
      begin
        Title := T('Распознаю', 'Recognizing') + Copy('...', 1, (FPhase div 6) mod 4);
        Subtitle := T('Ещё мгновение', 'One moment');
      end;
  else
    Title := T('Проверьте текст', 'Check the text');
    Subtitle := T('Его можно исправить перед вставкой', 'You can correct it before inserting');
  end;
  C.Brush.Style := bsClear;
  C.Font.Name := ModernFontName;
  C.Font.Size := 11;
  C.Font.Style := [fsBold];
  C.Font.Color := FTheme.Text;
  C.TextOut(S(70), MidY - S(21), Title);
  C.Font.Style := [];
  C.Font.Size := 8;
  if FStatus <> '' then
  begin
    Subtitle := FStatus;
    C.Font.Color := FTheme.Error;
  end
  else
    C.Font.Color := FTheme.Muted;
  TextRect := Rect(S(70), MidY + S(1), Right, MidY + S(19));
  DrawText(C.Handle, PChar(Subtitle), -1, TextRect, DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX);
end;

procedure TDictationWindow.HeaderMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  if FCloseRect.Contains(Point(X, Y)) then
    CancelClick(Self)
  else
  begin
    // The window is moved by its header.
    ReleaseCapture;
    Perform(WM_SYSCOMMAND, SC_MOVE or HTCAPTION, 0);
  end;
end;

procedure TDictationWindow.HeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hover: Boolean;
begin
  Hover := FCloseRect.Contains(Point(X, Y));
  if Hover <> FHoverClose then
  begin
    FHoverClose := Hover;
    FHeader.Invalidate;
  end;
end;

procedure TDictationWindow.DoEdit;
begin
  if (FState = dwRecording) and Assigned(FOnEdit) then
    FOnEdit(Self);
end;

procedure TDictationWindow.MemoMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  DoEdit;
end;

procedure TDictationWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  FReturnConsumed := False;
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        CancelClick(Self);
      end;
    VK_RETURN:
      // Shift+Enter or Ctrl+Enter: a new line in the text.
      if Shift * [ssShift, ssCtrl] = [] then
      begin
        Key := 0;
        FReturnConsumed := True;
        OkClick(Self);
      end;
    VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN, VK_CAPITAL, VK_SCROLL, VK_PAUSE,
    VK_TAB:
      ;
  else
    // Typing while recording: the user wants to correct the text.
    DoEdit;
  end;
end;

procedure TDictationWindow.FormKeyPress(Sender: TObject; var Key: Char);
begin
  if (Key = #27) or ((Key = #13) and FReturnConsumed) then
    Key := #0;
end;

procedure TDictationWindow.OkClick(Sender: TObject);
begin
  if Assigned(FOnOk) then
    FOnOk(Self);
end;

procedure TDictationWindow.CancelClick(Sender: TObject);
begin
  if Assigned(FOnCancel) then
    FOnCancel(Self);
end;

end.
