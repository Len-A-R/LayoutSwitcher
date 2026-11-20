unit uExplainWindow;

// The window with the AI explanation of the selected text, in the style of
// Windows 11: light or dark like the system, the title bar in the colour of
// the content, rounded corners, the selected text as a quote card with the
// accent colour, the answer rendered from Markdown (headings, lists, bold,
// code), an animated accent line while waiting, flat buttons.  Esc closes.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.ComCtrls,
  uModernUI;

type
  TExplainWindow = class(TForm)
  private
    FTheme: TUiTheme;
    FFontName: string;
    FHeader: TPanel;
    FHint: TLabel;
    FQuote: TPanel;
    FQuoteBar: TPanel;
    FQuoteText: TLabel;
    FLoading: TPaintBox;
    FLoadingTimer: TTimer;
    FLoadingPos: Integer;
    FBody: TPanel;
    FAnswer: TRichEdit;
    FFooter: TPanel;
    FStatus: TLabel;
    FCopy: TFlatButton;
    FClose: TFlatButton;
    FCopyTimer: TTimer;
    FPlainAnswer: string;
    procedure CopyClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure CopyTimerTick(Sender: TObject);
    procedure LoadingTick(Sender: TObject);
    procedure LoadingPaint(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure AnswerHideCaret(Sender: TObject);
    procedure AnswerMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure AnswerKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    function S(Value: Integer): Integer;
    procedure ApplyTheme;
    procedure ApplyWindowFrame;
    procedure LayoutQuote;
    procedure SetLoading(Value: Boolean);
    procedure RenderAnswer(const Markdown: string);
    procedure RenderPlain(const Text: string; Color: TColor; Italic: Boolean);
    procedure SetParagraphSpacing;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Shows the window for a new question; Service names the AI service.
    procedure StartQuestion(const Text, Service: string);
    procedure ShowAnswer(const Answer: string; ElapsedMS: Cardinal);
    procedure ShowError(const Text: string);
  end;

implementation

uses
  Winapi.DwmApi, Winapi.RichEdit, Winapi.UxTheme, System.Win.Registry, System.Math, System.StrUtils,
  Vcl.Clipbrd, uLocale;


{ TExplainWindow }

function TExplainWindow.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

constructor TExplainWindow.Create(AOwner: TComponent);

  function NewPanel(AParent: TWinControl; AAlign: TAlign): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := AParent;
    Result.Align := AAlign;
    Result.BevelOuter := bvNone;
    Result.ParentBackground := False;
    Result.ShowCaption := False;
  end;

begin
  inherited CreateNew(AOwner);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  FormStyle := fsStayOnTop;
  Position := poDesigned;
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnResize := FormResize;
  // Windows 11 text font when present.
  if Screen.Fonts.IndexOf('Segoe UI Variable Text') >= 0 then
    FFontName := 'Segoe UI Variable Text'
  else
    FFontName := 'Segoe UI';
  Font.Name := FFontName;
  Font.Size := 9;
  ClientWidth := S(520);
  ClientHeight := S(380);
  Constraints.MinWidth := S(340);
  Constraints.MinHeight := S(240);

  FFooter := NewPanel(Self, alBottom);
  FFooter.Height := S(56);
  FFooter.Padding.SetBounds(S(16), S(12), S(16), S(12));

  // alRight: the larger Left is further right.
  FClose := TFlatButton.Create(Self);
  FClose.Parent := FFooter;
  FClose.Left := 2000;
  FClose.Align := alRight;
  FClose.Width := S(104);
  FClose.Primary := True;
  FClose.OnClick := CloseClick;

  FCopy := TFlatButton.Create(Self);
  FCopy.Parent := FFooter;
  FCopy.Left := 1000;
  FCopy.Align := alRight;
  FCopy.Width := S(124);
  FCopy.AlignWithMargins := True;
  FCopy.Margins.SetBounds(0, 0, S(8), 0);
  FCopy.OnClick := CopyClick;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := FFooter;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.Font.Size := 8;
  FStatus.ShowAccelChar := False;

  // alTop: the smaller Top is higher.
  FHeader := NewPanel(Self, alTop);
  FHeader.Top := 0;
  FHeader.Padding.SetBounds(S(20), S(14), S(20), S(6));

  FHint := TLabel.Create(Self);
  FHint.Parent := FHeader;
  FHint.Top := 0;
  FHint.Align := alTop;
  FHint.Font.Size := 8;
  FHint.ShowAccelChar := False;

  FQuote := NewPanel(FHeader, alTop);
  FQuote.Top := 1000;
  FQuote.AlignWithMargins := True;
  FQuote.Margins.SetBounds(0, S(6), 0, 0);

  FQuoteBar := NewPanel(FQuote, alLeft);
  FQuoteBar.Width := S(3);

  FQuoteText := TLabel.Create(Self);
  FQuoteText.Parent := FQuote;
  FQuoteText.Align := alClient;
  FQuoteText.AlignWithMargins := True;
  FQuoteText.Margins.SetBounds(S(12), S(8), S(12), S(8));
  FQuoteText.WordWrap := True;
  FQuoteText.ShowAccelChar := False;
  FQuoteText.Font.Size := 10;
  FQuoteText.Font.Style := [fsBold];

  FLoading := TPaintBox.Create(Self);
  FLoading.Parent := Self;
  FLoading.Top := 2000;
  FLoading.Align := alTop;
  FLoading.Height := S(3);
  FLoading.OnPaint := LoadingPaint;
  FLoadingTimer := TTimer.Create(Self);
  FLoadingTimer.Enabled := False;
  FLoadingTimer.Interval := 25;
  FLoadingTimer.OnTimer := LoadingTick;

  FBody := NewPanel(Self, alClient);
  FBody.Padding.SetBounds(S(20), S(10), S(12), S(4));

  FAnswer := TRichEdit.Create(Self);
  FAnswer.Parent := FBody;
  FAnswer.Align := alClient;
  FAnswer.BorderStyle := bsNone;
  FAnswer.ReadOnly := True;
  FAnswer.PlainText := False;
  FAnswer.ScrollBars := ssVertical;
  FAnswer.WantReturns := False;
  FAnswer.HideSelection := True;
  // Read-only text: no blinking caret.
  FAnswer.OnEnter := AnswerHideCaret;
  FAnswer.OnMouseUp := AnswerMouseUp;
  FAnswer.OnKeyUp := AnswerKeyUp;

  FCopyTimer := TTimer.Create(Self);
  FCopyTimer.Enabled := False;
  FCopyTimer.Interval := 1500;
  FCopyTimer.OnTimer := CopyTimerTick;
end;

procedure TExplainWindow.CreateWnd;
begin
  inherited;
  ApplyWindowFrame;
end;

procedure TExplainWindow.ApplyWindowFrame;
begin
  if HandleAllocated then
    ApplyWindowChrome(Handle, FTheme, FTheme.Back);
end;

procedure TExplainWindow.ApplyTheme;
begin
  FTheme := CurrentUiTheme;
  Color := FTheme.Back;
  FHeader.Color := FTheme.Back;
  FBody.Color := FTheme.Back;
  FFooter.Color := FTheme.Footer;
  FHint.Font.Color := FTheme.Muted;
  FQuote.Color := FTheme.Card;
  FQuoteBar.Color := FTheme.Accent;
  FQuoteText.Font.Color := FTheme.Text;
  FAnswer.Color := FTheme.Back;
  FStatus.Font.Color := FTheme.Muted;
  FCopy.Theme := FTheme;
  FClose.Theme := FTheme;
  FCopy.Font.Assign(Font);
  FClose.Font.Assign(Font);
  FCopy.Invalidate;
  FClose.Invalidate;
  ApplyWindowFrame;
  // Scroll bar of the answer in the colours of the theme (Windows 10 1809+).
  if FAnswer.HandleAllocated then
  begin
    if FTheme.Dark then
      SetWindowTheme(FAnswer.Handle, 'DarkMode_Explorer', nil)
    else
      SetWindowTheme(FAnswer.Handle, 'Explorer', nil);
    SetWindowPos(FAnswer.Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_FRAMECHANGED);
  end;
end;

procedure TExplainWindow.LayoutQuote;
var
  R: TRect;
  TextHeight, MaxHeight: Integer;
begin
  // The quote card is as high as its text, at most four lines.
  R := Rect(0, 0, Max(S(100), FQuote.Width - FQuoteBar.Width - S(24)), 0);
  FQuoteText.Canvas.Font.Assign(FQuoteText.Font);
  DrawText(FQuoteText.Canvas.Handle, PChar(FQuoteText.Caption), -1, R,
    DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  TextHeight := R.Height;
  MaxHeight := FQuoteText.Canvas.TextHeight('Ag') * 4;
  FQuote.Height := Min(TextHeight, MaxHeight) + S(16);
  FHeader.Height := FHint.Height + FQuote.Height + S(6) + FHeader.Padding.Top +
    FHeader.Padding.Bottom;
end;

procedure TExplainWindow.AnswerHideCaret(Sender: TObject);
begin
  HideCaret(FAnswer.Handle);
end;

procedure TExplainWindow.AnswerMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  HideCaret(FAnswer.Handle);
end;

procedure TExplainWindow.AnswerKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  HideCaret(FAnswer.Handle);
end;

procedure TExplainWindow.FormResize(Sender: TObject);
begin
  if Assigned(FQuote) then
    LayoutQuote;
end;

procedure TExplainWindow.SetLoading(Value: Boolean);
begin
  FLoadingPos := 0;
  FLoadingTimer.Enabled := Value;
  FLoading.Invalidate;
end;

procedure TExplainWindow.LoadingTick(Sender: TObject);
begin
  Inc(FLoadingPos, S(6));
  if FLoadingPos > FLoading.Width + FLoading.Width div 3 then
    FLoadingPos := 0;
  FLoading.Invalidate;
end;

procedure TExplainWindow.LoadingPaint(Sender: TObject);
var
  Segment: Integer;
begin
  FLoading.Canvas.Brush.Color := FTheme.Back;
  FLoading.Canvas.FillRect(FLoading.ClientRect);
  if not FLoadingTimer.Enabled then
    Exit;
  // An accent segment running from left to right.
  Segment := FLoading.Width div 3;
  FLoading.Canvas.Brush.Color := FTheme.Accent;
  FLoading.Canvas.FillRect(Rect(FLoadingPos - Segment, 0, FLoadingPos, FLoading.Height));
end;

procedure TExplainWindow.SetParagraphSpacing;
begin
  SetRichEditSpacing(FAnswer);
end;

procedure TExplainWindow.RenderPlain(const Text: string; Color: TColor; Italic: Boolean);
begin
  FAnswer.Lines.BeginUpdate;
  try
    FAnswer.Clear;
    FAnswer.SelStart := 0;
    FAnswer.SelAttributes.Name := FFontName;
    FAnswer.SelAttributes.Size := 10;
    FAnswer.SelAttributes.Color := Color;
    if Italic then
      FAnswer.SelAttributes.Style := [fsItalic]
    else
      FAnswer.SelAttributes.Style := [];
    FAnswer.SelText := Text;
    SetParagraphSpacing;
  finally
    FAnswer.Lines.EndUpdate;
  end;
end;

procedure TExplainWindow.RenderAnswer(const Markdown: string);
begin
  RenderMarkdown(FAnswer, Markdown, FTheme, FFontName);
end;

procedure TExplainWindow.StartQuestion(const Text, Service: string);
var
  Cursor: TPoint;
  Work: TRect;
  Line: string;
begin
  ApplyTheme;
  Caption := T('Объяснение', 'Explanation');
  FHint.Caption := T('Вы выделили', 'You selected');
  FCopy.Caption := T('Копировать', 'Copy');
  FClose.Caption := T('Закрыть', 'Close');
  FCopy.Enabled := False;
  Line := Trim(StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]));
  if Length(Line) > 300 then
    Line := Copy(Line, 1, 300) + '…';
  FQuoteText.Caption := Line;
  FStatus.Caption := Service;
  FPlainAnswer := '';
  RenderPlain(T('Думаю над ответом…', 'Thinking about the answer…'), FTheme.Muted, True);
  SetLoading(True);

  // Next to the mouse pointer, inside the work area of its monitor.
  GetCursorPos(Cursor);
  Work := Screen.MonitorFromPoint(Cursor).WorkareaRect;
  Left := Cursor.X + S(16);
  Top := Cursor.Y + S(16);
  if Left + Width > Work.Right then
    Left := Work.Right - Width;
  if Top + Height > Work.Bottom then
    Top := Cursor.Y - Height - S(16);
  if Left < Work.Left then
    Left := Work.Left;
  if Top < Work.Top then
    Top := Work.Top;
  Show;
  LayoutQuote;
  // The answer has the focus (scrolling with the keyboard), not a button.
  if FAnswer.CanFocus then
  begin
    ActiveControl := FAnswer;
    HideCaret(FAnswer.Handle);
  end;
  // A background program may not take the focus; the window is topmost anyway.
  SetForegroundWindow(Handle);
end;

procedure TExplainWindow.ShowAnswer(const Answer: string; ElapsedMS: Cardinal);
begin
  SetLoading(False);
  FPlainAnswer := MarkdownToPlainText(Answer);
  RenderAnswer(Answer);
  FCopy.Enabled := True;
  FStatus.Caption := FStatus.Caption + Format(T(' · %.1f с', ' · %.1f s'), [ElapsedMS / 1000]);
end;

procedure TExplainWindow.ShowError(const Text: string);
begin
  SetLoading(False);
  FPlainAnswer := '';
  RenderPlain('⚠  ' + Text, FTheme.Error, False);
  FCopy.Enabled := False;
end;

procedure TExplainWindow.CopyClick(Sender: TObject);
begin
  if FPlainAnswer = '' then
    Exit;
  Clipboard.AsText := FPlainAnswer;
  FCopy.Caption := T('Скопировано ✓', 'Copied ✓');
  FCopyTimer.Enabled := False;
  FCopyTimer.Enabled := True;
end;

procedure TExplainWindow.CopyTimerTick(Sender: TObject);
begin
  FCopyTimer.Enabled := False;
  FCopy.Caption := T('Копировать', 'Copy');
end;

procedure TExplainWindow.CloseClick(Sender: TObject);
begin
  SetLoading(False);
  Hide;
end;

procedure TExplainWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    SetLoading(False);
    Hide;
    Key := 0;
  end;
end;

end.
