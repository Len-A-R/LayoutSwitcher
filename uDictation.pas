unit uDictation;

// Dictation: the gesture starts recording, the same gesture (or the
// indicator) stops it, the recording is recognized in a background thread
// and the text goes back to the main form, which types it.  Esc or the
// close button of the indicator cancels.
//
// The indicator never takes the focus: the text must land in the window
// the user dictates into.  A loaded model stays in memory for a few
// minutes, so that the next phrase starts at once.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.ExtCtrls,
  uModernUI, uAudioRecorder, uSpeechModels, uSpeechCloud, uSherpaOnnx;

type
  TDictationState = (dsIdle, dsRecording, dsRecognizing);

  // Text = '' and ErrorText = '' means nothing was said.
  TDictationResultEvent = procedure(const Text, ErrorText: string;
    Punctuation: Boolean) of object;

  TDictationIndicator = class(TCustomForm)
  private
    FTheme: TUiTheme;
    FTimer: TTimer;
    FState: TDictationState;
    FLevels: array[0..15] of Integer;
    FLevelIndex: Integer;
    FPhase: Integer;
    FRecorder: TAudioRecorder;
    FMessage: string;
    FHint: string;
    FOnCancel: TNotifyEvent;
    FOnStop: TNotifyEvent;
    FCloseRect: TRect;
    FHoverClose: Boolean;
    function S(Value: Integer): Integer;
    procedure Tick(Sender: TObject);
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor CreateIndicator(AOwner: TComponent; Recorder: TAudioRecorder);
    procedure ShowState(State: TDictationState; const Hint: string);
    procedure ShowMessageText(const Text: string);
    procedure HideIndicator;
    function Shown: Boolean;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    property OnStop: TNotifyEvent read FOnStop write FOnStop;
  end;

  TDictation = class(TComponent)
  private
    FRecorder: TAudioRecorder;
    FIndicator: TDictationIndicator;
    FState: TDictationState;
    FModel: TSpeechModel;
    FCloud: TSpeechCloudConfig;
    // The loaded model while idle; a recognition thread takes it and gives
    // it back when done.
    FRecognizer: TSpeechRecognizer;
    FThread: TThread;
    FSequence: Integer;
    FIdleTimer: TTimer;
    FMaxTimer: TTimer;
    FHideTimer: TTimer;
    FOnResult: TDictationResultEvent;
    FStopHint: string;
    procedure IndicatorCancel(Sender: TObject);
    procedure IndicatorStop(Sender: TObject);
    procedure RecognitionDone(Sender: TObject);
    procedure IdleTimeout(Sender: TObject);
    procedure MaxCheck(Sender: TObject);
    procedure HideIndicator(Sender: TObject);
    procedure EnsureIndicator;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Starts recording with the model; False with ErrorText when it cannot.
    function Start(const Model: TSpeechModel; const Cloud: TSpeechCloudConfig;
      const StopHint: string; out ErrorText: string): Boolean;
    // Ends the recording and recognizes it.
    procedure Stop;
    procedure Cancel;
    // A message in the indicator for a few seconds.
    procedure ShowError(const Text: string);
    // Frees the loaded model (settings changed, low memory).
    procedure UnloadModel;
    property State: TDictationState read FState;
    property OnResult: TDictationResultEvent read FOnResult write FOnResult;
  end;

const
  DICTATION_MAX_SECONDS = 120;

implementation

uses
  System.Math, Winapi.GDIPAPI, Winapi.GDIPOBJ, uLocale;

// GDI draws circles and rounded corners without anti-aliasing (jagged
// edges); GDI+ smooths them.
procedure FillSmooth(Canvas: TCanvas; const R: TRect; Color: TColor; Radius: Integer);
var
  Graphics: TGPGraphics;
  Brush: TGPSolidBrush;
  Path: TGPGraphicsPath;
  RGBColor: Cardinal;
  D: Integer;
begin
  RGBColor := ColorToRGB(Color);
  Graphics := TGPGraphics.Create(Canvas.Handle);
  Brush := TGPSolidBrush.Create(MakeColor(255, GetRValue(RGBColor), GetGValue(RGBColor),
    GetBValue(RGBColor)));
  try
    Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    Graphics.SetPixelOffsetMode(PixelOffsetModeHalf);
    if Radius < 0 then
      Graphics.FillEllipse(Brush, R.Left, R.Top, R.Width, R.Height)
    else
    begin
      D := Radius * 2;
      Path := TGPGraphicsPath.Create;
      try
        Path.AddArc(R.Left, R.Top, D, D, 180, 90);
        Path.AddArc(R.Right - D, R.Top, D, D, 270, 90);
        Path.AddArc(R.Right - D, R.Bottom - D, D, D, 0, 90);
        Path.AddArc(R.Left, R.Bottom - D, D, D, 90, 90);
        Path.CloseFigure;
        Graphics.FillPath(Brush, Path);
      finally
        Path.Free;
      end;
    end;
  finally
    Brush.Free;
    Graphics.Free;
  end;
end;

const
  IDLE_UNLOAD_MS = 5 * 60 * 1000;
  MIN_SECONDS = 0.4;
  // A peak below this (percent of the full scale) is silence.
  SILENCE_PEAK = 2;

type
  TRecognitionThread = class(TThread)
  private
    FOwner: TDictation;
    FModel: TSpeechModel;
    FCloud: TSpeechCloudConfig;
    FSamples: TArray<Single>;
    FSequence: Integer;
    FText: string;
    FError: string;
    FRecognizer: TSpeechRecognizer;
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
    constructor Create(Owner: TDictation; const Model: TSpeechModel;
      const Cloud: TSpeechCloudConfig; const Samples: TArray<Single>; Sequence: Integer);
  end;

{ TRecognitionThread }

destructor TRecognitionThread.Destroy;
begin
  // Not taken back by the owner (it was destroyed meanwhile).
  FRecognizer.Free;
  inherited;
end;

constructor TRecognitionThread.Create(Owner: TDictation; const Model: TSpeechModel;
  const Cloud: TSpeechCloudConfig; const Samples: TArray<Single>; Sequence: Integer);
begin
  FOwner := Owner;
  FRecognizer := Owner.FRecognizer;
  Owner.FRecognizer := nil;
  FModel := Model;
  FCloud := Cloud;
  FSamples := Samples;
  FSequence := Sequence;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TRecognitionThread.Execute;
begin
  NameThreadForDebugging('LayoutSwitcher.Recognition');
  try
    if FModel.IsCloud then
    begin
      if not TranscribeCloud(FCloud, FSamples, FText, FError) and (FError = '') then
        FError := 'error';
    end
    else
    begin
      if (FRecognizer <> nil) and (FRecognizer.ModelId <> FModel.Id) then
        FreeAndNil(FRecognizer);
      if FRecognizer = nil then
        FRecognizer := TSpeechRecognizer.Create(FModel,
          EnsureRange(TThread.ProcessorCount div 2, 1, 4));
      FText := FRecognizer.Recognize(FSamples);
    end;
  except
    on E: Exception do
      FError := E.Message;
  end;
end;

{ TDictationIndicator }

constructor TDictationIndicator.CreateIndicator(AOwner: TComponent; Recorder: TAudioRecorder);
begin
  CreateNew(AOwner);
  FRecorder := Recorder;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  DoubleBuffered := True;
  FTheme := CurrentUiTheme;
  Color := FTheme.Card;
  Font.Name := ModernFontName;
  Font.Size := 10;
  Font.Color := FTheme.Text;
  ClientWidth := S(470);
  ClientHeight := S(64);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.Enabled := False;
  FTimer.OnTimer := Tick;
end;

procedure TDictationIndicator.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE or WS_EX_TOPMOST;
  Params.WndParent := 0;
end;

function TDictationIndicator.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

procedure TDictationIndicator.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

procedure TDictationIndicator.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTCLIENT;
end;

procedure TDictationIndicator.ShowState(State: TDictationState; const Hint: string);
var
  Area: TRect;
  Monitor: TMonitor;
  Foreground: HWND;
begin
  FState := State;
  FHint := Hint;
  FMessage := '';
  FillChar(FLevels, SizeOf(FLevels), 0);
  FTheme := CurrentUiTheme;
  Color := FTheme.Card;
  Font.Color := FTheme.Text;
  // Bottom centre of the monitor the user works on.
  Foreground := GetForegroundWindow;
  Monitor := Screen.MonitorFromWindow(Foreground);
  if Monitor <> nil then
    Area := Monitor.WorkareaRect
  else
    Area := Screen.WorkAreaRect;
  Left := Area.Left + (Area.Width - Width) div 2;
  Top := Area.Bottom - Height - S(48);
  // Shown without the VCL (Visible := True would activate the window and
  // take the focus from the field the user dictates into).
  if not Shown then
    ApplyWindowChrome(Handle, FTheme, FTheme.Card);
  SetWindowPos(Handle, HWND_TOPMOST, Left, Top, Width, Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  FTimer.Enabled := True;
  Invalidate;
end;

function TDictationIndicator.Shown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

procedure TDictationIndicator.HideIndicator;
begin
  FTimer.Enabled := False;
  if HandleAllocated then
    ShowWindow(Handle, SW_HIDE);
end;

procedure TDictationIndicator.ShowMessageText(const Text: string);
begin
  FState := dsIdle;
  FMessage := Text;
  if not Shown then
    ShowState(dsIdle, '');
  FMessage := Text;
  FTimer.Enabled := False;
  // A long message gets a taller window.
  Invalidate;
end;

procedure TDictationIndicator.Tick(Sender: TObject);
begin
  Inc(FPhase);
  if (FState = dsRecording) and (FRecorder <> nil) then
  begin
    FLevels[FLevelIndex] := FRecorder.Level;
    FLevelIndex := (FLevelIndex + 1) mod Length(FLevels);
  end;
  Invalidate;
end;

procedure TDictationIndicator.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if FCloseRect.Contains(Point(X, Y)) then
  begin
    if Assigned(FOnCancel) then
      FOnCancel(Self);
  end
  else if (FState = dsRecording) and Assigned(FOnStop) then
    FOnStop(Self);
end;

procedure TDictationIndicator.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hover: Boolean;
begin
  inherited;
  Hover := FCloseRect.Contains(Point(X, Y));
  if Hover <> FHoverClose then
  begin
    FHoverClose := Hover;
    Invalidate;
  end;
end;

procedure TDictationIndicator.Paint;
var
  R, TextRect: TRect;
  I, Index, BarX, BarH, BarW, Gap, MidY, Level: Integer;
  Glyph, Title, Secs: string;
  GlyphColor: TColor;
begin
  R := ClientRect;
  Canvas.Brush.Color := FTheme.Card;
  Canvas.FillRect(R);
  Canvas.Pen.Color := FTheme.Border;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(R);
  Canvas.Brush.Style := bsSolid;
  MidY := R.Height div 2;

  // Microphone glyph in a circle: red while recording.
  if FState = dsRecording then
    GlyphColor := RGB(220, 53, 69)
  else
    GlyphColor := FTheme.Accent;
  FillSmooth(Canvas, Rect(S(14), MidY - S(18), S(50), MidY + S(18)), GlyphColor, -1);
  Canvas.Font.Name := IconFontName;
  Canvas.Font.Size := 14;
  Canvas.Font.Color := clWhite;
  Canvas.Brush.Style := bsClear;
  if FMessage <> '' then
    Glyph := #$E7BA      // warning
  else
    Glyph := #$E720;     // microphone
  TextRect := Rect(S(14), MidY - S(18), S(50), MidY + S(18));
  DrawText(Canvas.Handle, PChar(Glyph), 1, TextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  // Close button.
  FCloseRect := Rect(R.Right - S(40), MidY - S(16), R.Right - S(8), MidY + S(16));
  if FHoverClose then
  begin
    FillSmooth(Canvas, FCloseRect, FTheme.Hover, S(4));
  end;
  Canvas.Font.Name := IconFontName;
  Canvas.Font.Size := 9;
  Canvas.Font.Color := FTheme.Muted;
  Glyph := #$E711;
  TextRect := FCloseRect;
  DrawText(Canvas.Handle, PChar(Glyph), 1, TextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  Canvas.Font.Name := ModernFontName;
  Canvas.Brush.Style := bsClear;
  if FMessage <> '' then
  begin
    Canvas.Font.Size := 9;
    Canvas.Font.Color := FTheme.Text;
    TextRect := Rect(S(62), S(6), FCloseRect.Left - S(6), R.Bottom - S(6));
    DrawText(Canvas.Handle, PChar(FMessage), -1, TextRect,
      DT_WORDBREAK or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX or DT_EDITCONTROL);
    Exit;
  end;

  if FState = dsRecording then
    Title := T('Говорите…', 'Speak…')
  else
    Title := T('Распознаю', 'Recognizing') + Copy('...', 1, (FPhase div 6) mod 4);
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FTheme.Text;
  Canvas.TextOut(S(62), MidY - S(20), Title);
  Canvas.Font.Style := [];
  Canvas.Font.Size := 8;
  Canvas.Font.Color := FTheme.Muted;
  TextRect := Rect(S(62), MidY + S(2), FCloseRect.Left - S(96), MidY + S(20));
  DrawText(Canvas.Handle, PChar(FHint), -1, TextRect, DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX);

  if FState = dsRecording then
  begin
    // Level bars, the newest on the right, and the elapsed time.
    BarW := S(3);
    Gap := S(2);
    BarX := FCloseRect.Left - S(14) - Length(FLevels) * (BarW + Gap);
    for I := 0 to High(FLevels) do
    begin
      Index := (FLevelIndex + I) mod Length(FLevels);
      Level := Min(100, FLevels[Index] * 2);
      BarH := Max(S(2), MulDiv(S(26), Level, 100));
      FillSmooth(Canvas, Rect(BarX, MidY - BarH div 2, BarX + BarW, MidY + BarH div 2 + 1),
        FTheme.Accent, Min(BarW div 2, BarH div 2));
      Inc(BarX, BarW + Gap);
    end;
    if FRecorder <> nil then
    begin
      Secs := Format('%d:%.2d', [Trunc(FRecorder.Seconds) div 60, Trunc(FRecorder.Seconds) mod 60]);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Size := 8;
      Canvas.Font.Color := FTheme.Muted;
      Canvas.TextOut(FCloseRect.Left - S(14) - Length(FLevels) * (BarW + Gap) -
        Canvas.TextWidth(Secs) - S(8), MidY - Canvas.TextHeight(Secs) div 2, Secs);
    end;
  end;
end;

{ TDictation }

constructor TDictation.Create(AOwner: TComponent);
begin
  inherited;
  FRecorder := TAudioRecorder.Create;
  FIdleTimer := TTimer.Create(Self);
  FIdleTimer.Enabled := False;
  FIdleTimer.Interval := IDLE_UNLOAD_MS;
  FIdleTimer.OnTimer := IdleTimeout;
  FMaxTimer := TTimer.Create(Self);
  FMaxTimer.Enabled := False;
  FMaxTimer.Interval := 500;
  FMaxTimer.OnTimer := MaxCheck;
  FHideTimer := TTimer.Create(Self);
  FHideTimer.Enabled := False;
  FHideTimer.OnTimer := HideIndicator;
end;

destructor TDictation.Destroy;
begin
  // A running recognition thread frees its recognizer itself.
  if FThread <> nil then
    FThread.OnTerminate := nil;
  FreeAndNil(FRecognizer);
  FreeAndNil(FRecorder);
  inherited;
end;

procedure TDictation.EnsureIndicator;
begin
  if FIndicator = nil then
  begin
    FIndicator := TDictationIndicator.CreateIndicator(Self, FRecorder);
    FIndicator.OnCancel := IndicatorCancel;
    FIndicator.OnStop := IndicatorStop;
  end;
end;

function TDictation.Start(const Model: TSpeechModel; const Cloud: TSpeechCloudConfig;
  const StopHint: string; out ErrorText: string): Boolean;
begin
  Result := False;
  ErrorText := '';
  if FState <> dsIdle then
    Exit;
  FModel := Model;
  FCloud := Cloud;
  FStopHint := StopHint;
  if not FRecorder.Start(DICTATION_MAX_SECONDS, ErrorText) then
    Exit;
  FState := dsRecording;
  FHideTimer.Enabled := False;
  EnsureIndicator;
  FIndicator.ShowState(dsRecording, StopHint);
  FMaxTimer.Enabled := True;
  Result := True;
end;

procedure TDictation.Stop;
var
  Samples: TArray<Single>;
  Peak, I: Integer;
  Value: Single;
begin
  if FState <> dsRecording then
    Exit;
  FMaxTimer.Enabled := False;
  Samples := FRecorder.Stop;
  // Too short or silent: nothing to recognize.
  Peak := 0;
  for I := 0 to High(Samples) do
  begin
    Value := Abs(Samples[I]);
    if Value * 100 > Peak then
      Peak := Trunc(Value * 100);
  end;
  if (Length(Samples) < MIN_SECONDS * RECORD_SAMPLE_RATE) or (Peak < SILENCE_PEAK) then
  begin
    FState := dsIdle;
    if Peak < SILENCE_PEAK then
      ShowError(T('Не слышно речи. Проверьте, что микрофон включён и выбран в Windows.',
        'No speech heard. Check that the microphone is on and selected in Windows.'))
    else
      HideIndicator(nil);
    Exit;
  end;
  FState := dsRecognizing;
  FIdleTimer.Enabled := False;
  Inc(FSequence);
  FIndicator.ShowState(dsRecognizing, FModel.Name);
  FThread := TRecognitionThread.Create(Self, FModel, FCloud, Samples, FSequence);
  FThread.OnTerminate := RecognitionDone;
end;

procedure TDictation.Cancel;
begin
  case FState of
    dsRecording:
      begin
        FMaxTimer.Enabled := False;
        FRecorder.Stop;
        FState := dsIdle;
      end;
    dsRecognizing:
      begin
        // The result of the running recognition is dropped.
        Inc(FSequence);
        FState := dsIdle;
      end;
  end;
  HideIndicator(nil);
end;

procedure TDictation.RecognitionDone(Sender: TObject);
var
  Thread: TRecognitionThread;
begin
  Thread := TRecognitionThread(Sender);
  if FThread = Thread then
    FThread := nil;
  // The model stays loaded for the next phrase.
  if (Thread.FRecognizer <> nil) and (FRecognizer = nil) then
  begin
    FRecognizer := Thread.FRecognizer;
    Thread.FRecognizer := nil;
  end;
  if not Thread.FModel.IsCloud then
  begin
    FIdleTimer.Enabled := False;
    FIdleTimer.Enabled := True;
  end;
  if Thread.FSequence <> FSequence then
  begin
    // Cancelled; a newer recording may run already.
    if FState = dsIdle then
      HideIndicator(nil);
    Exit;
  end;
  FState := dsIdle;
  if Thread.FError <> '' then
    ShowError(T('Не удалось распознать речь: ', 'Speech recognition failed: ') + Thread.FError)
  else if Trim(Thread.FText) = '' then
    ShowError(T('Речь не распознана. Попробуйте говорить ближе к микрофону.',
      'No speech recognized. Try speaking closer to the microphone.'))
  else
    HideIndicator(nil);
  if Assigned(FOnResult) then
    FOnResult(Thread.FText, Thread.FError, Thread.FModel.Punctuation);
end;

procedure TDictation.ShowError(const Text: string);
begin
  EnsureIndicator;
  FIndicator.ShowMessageText(Text);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := 4000;
  FHideTimer.Enabled := True;
end;

procedure TDictation.HideIndicator(Sender: TObject);
begin
  FHideTimer.Enabled := False;
  if (FIndicator <> nil) and (FState = dsIdle) then
    FIndicator.HideIndicator;
end;

procedure TDictation.IndicatorCancel(Sender: TObject);
begin
  Cancel;
end;

procedure TDictation.IndicatorStop(Sender: TObject);
begin
  Stop;
end;

procedure TDictation.MaxCheck(Sender: TObject);
begin
  if (FState = dsRecording) and (FRecorder.Seconds >= DICTATION_MAX_SECONDS - 0.2) then
    Stop;
end;

procedure TDictation.IdleTimeout(Sender: TObject);
begin
  FIdleTimer.Enabled := False;
  FreeAndNil(FRecognizer);
end;

procedure TDictation.UnloadModel;
begin
  FreeAndNil(FRecognizer);
end;

end.
