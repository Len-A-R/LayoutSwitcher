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
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.ComCtrls;

type
  // Markdown subset of AI answers.
  TMdRun = record
    Text: string;
    Bold: Boolean;
    Code: Boolean;
  end;

  TMdLineKind = (mlText, mlHeading, mlBullet, mlNumbered, mlCode, mlBlank);

  TMdLine = record
    Kind: TMdLineKind;
    Marker: string;          // "•" or "3." for list items
    Runs: TArray<TMdRun>;
  end;

// Lines of a Markdown text: "# heading", "- item", "1. item", ``` code
// blocks ```, inline **bold** and `code`.  Covered by tests.
function ParseMarkdown(const Text: string): TArray<TMdLine>;
function MarkdownToPlainText(const Text: string): string;

type
  TExplainTheme = record
    Dark: Boolean;
    Back, Card, Footer, Text, Muted, Accent, AccentText, Error, Hover, Border: TColor;
  end;

  // A flat button with rounded corners and a hover state.
  TFlatButton = class(TCustomControl)
  private
    FHover: Boolean;
    FPrimary: Boolean;
    FTheme: TExplainTheme;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMTextChanged(var Message: TMessage); message CM_TEXTCHANGED;
    procedure CMEnabledChanged(var Message: TMessage); message CM_ENABLEDCHANGED;
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Primary: Boolean read FPrimary write FPrimary;
    property Theme: TExplainTheme read FTheme write FTheme;
    property Caption;
    property OnClick;
  end;

  TExplainWindow = class(TForm)
  private
    FTheme: TExplainTheme;
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

function CurrentExplainTheme: TExplainTheme;

implementation

uses
  Winapi.DwmApi, Winapi.RichEdit, Winapi.UxTheme, System.Win.Registry, System.Math, System.StrUtils,
  Vcl.Clipbrd, uLocale;

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWA_CAPTION_COLOR = 35;
  DWMWA_TEXT_COLOR = 36;
  DWMWCP_ROUND = 2;

{ Markdown }

function ParseInline(const Text: string): TArray<TMdRun>;
var
  I, Close: Integer;
  Buffer: string;

  procedure Flush(Bold, Code: Boolean);
  var
    Run: TMdRun;
  begin
    if Buffer = '' then
      Exit;
    Run.Text := Buffer;
    Run.Bold := Bold;
    Run.Code := Code;
    Result := Result + [Run];
    Buffer := '';
  end;

begin
  Result := nil;
  Buffer := '';
  I := 1;
  while I <= Length(Text) do
  begin
    if (Text[I] = '`') then
    begin
      Close := PosEx('`', Text, I + 1);
      if Close > I + 1 then
      begin
        Flush(False, False);
        Buffer := Copy(Text, I + 1, Close - I - 1);
        Flush(False, True);
        I := Close + 1;
        Continue;
      end;
    end
    else if (Text[I] = '*') and (I < Length(Text)) and (Text[I + 1] = '*') then
    begin
      Close := PosEx('**', Text, I + 2);
      if Close > I + 2 then
      begin
        Flush(False, False);
        Buffer := Copy(Text, I + 2, Close - I - 2);
        Flush(True, False);
        I := Close + 2;
        Continue;
      end;
    end;
    Buffer := Buffer + Text[I];
    Inc(I);
  end;
  Flush(False, False);
end;

function ParseMarkdown(const Text: string): TArray<TMdLine>;
var
  Raw, Line, Trimmed: string;
  Item: TMdLine;
  InCode: Boolean;
  Digits: Integer;
  Run: TMdRun;
begin
  Result := nil;
  InCode := False;
  for Raw in Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    Line := Raw.TrimRight;
    Trimmed := Line.TrimLeft;
    Item.Marker := '';
    Item.Runs := nil;
    if Trimmed.StartsWith('```') then
    begin
      InCode := not InCode;
      Continue;
    end;
    if InCode then
    begin
      Item.Kind := mlCode;
      Run.Text := Line;
      Run.Bold := False;
      Run.Code := True;
      Item.Runs := [Run];
      Result := Result + [Item];
      Continue;
    end;
    if Trimmed = '' then
    begin
      // One blank line between paragraphs is enough.
      if (Length(Result) > 0) and (Result[High(Result)].Kind <> mlBlank) then
      begin
        Item.Kind := mlBlank;
        Result := Result + [Item];
      end;
      Continue;
    end;
    if Trimmed.StartsWith('#') then
    begin
      Item.Kind := mlHeading;
      Item.Runs := ParseInline(Trimmed.TrimLeft(['#']).Trim);
    end
    else if (Trimmed.StartsWith('- ') or Trimmed.StartsWith('* ') or
             Trimmed.StartsWith('• ')) then
    begin
      Item.Kind := mlBullet;
      Item.Marker := '•';
      Item.Runs := ParseInline(Copy(Trimmed, 3, MaxInt).Trim);
    end
    else
    begin
      Digits := 0;
      while (Digits < Length(Trimmed)) and CharInSet(Trimmed[Digits + 1], ['0'..'9']) do
        Inc(Digits);
      if (Digits > 0) and (Digits < 4) and (Length(Trimmed) > Digits + 1) and
         CharInSet(Trimmed[Digits + 1], ['.', ')']) and (Trimmed[Digits + 2] = ' ') then
      begin
        Item.Kind := mlNumbered;
        Item.Marker := Copy(Trimmed, 1, Digits) + '.';
        Item.Runs := ParseInline(Copy(Trimmed, Digits + 3, MaxInt).Trim);
      end
      else
      begin
        Item.Kind := mlText;
        Item.Runs := ParseInline(Trimmed);
      end;
    end;
    Result := Result + [Item];
  end;
  // No blank line at the end.
  while (Length(Result) > 0) and (Result[High(Result)].Kind = mlBlank) do
    SetLength(Result, Length(Result) - 1);
end;

function MarkdownToPlainText(const Text: string): string;
var
  Line: TMdLine;
  Run: TMdRun;
  Parts: TStringList;
  S: string;
begin
  Parts := TStringList.Create;
  try
    for Line in ParseMarkdown(Text) do
    begin
      S := '';
      if Line.Marker <> '' then
        S := Line.Marker + ' ';
      for Run in Line.Runs do
        S := S + Run.Text;
      Parts.Add(S);
    end;
    Result := Parts.Text.TrimRight;
  finally
    Parts.Free;
  end;
end;

{ Theme }

function CurrentExplainTheme: TExplainTheme;
var
  Registry: TRegistry;
  Color: DWORD;
  Opaque: BOOL;
  R, G, B: Byte;
begin
  Result.Dark := False;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
       Registry.ValueExists('AppsUseLightTheme') then
      Result.Dark := Registry.ReadInteger('AppsUseLightTheme') = 0;
  finally
    Registry.Free;
  end;
  // Accent colour of Windows; a grey colourisation falls back to the
  // default Windows 11 blue.
  Result.Accent := RGB($00, $67, $C0);
  if Succeeded(DwmGetColorizationColor(Color, Opaque)) then
  begin
    R := (Color shr 16) and $FF;
    G := (Color shr 8) and $FF;
    B := Color and $FF;
    if MaxIntValue([R, G, B]) - MinIntValue([R, G, B]) > 40 then
      Result.Accent := RGB(R, G, B);
  end;
  Result.AccentText := clWhite;
  if Result.Dark then
  begin
    Result.Back := RGB($20, $20, $20);
    Result.Card := RGB($2C, $2C, $2C);
    Result.Footer := RGB($1A, $1A, $1A);
    Result.Text := RGB($F2, $F2, $F2);
    Result.Muted := RGB($A0, $A0, $A0);
    Result.Error := RGB($FF, $99, $A4);
    Result.Hover := RGB($3A, $3A, $3A);
    Result.Border := RGB($3A, $3A, $3A);
  end
  else
  begin
    Result.Back := RGB($FF, $FF, $FF);
    Result.Card := RGB($F3, $F4, $F6);
    Result.Footer := RGB($F7, $F7, $F8);
    Result.Text := RGB($1F, $1F, $1F);
    Result.Muted := RGB($6B, $6B, $6B);
    Result.Error := RGB($C4, $2B, $1C);
    Result.Hover := RGB($E6, $E7, $EA);
    Result.Border := RGB($E1, $E2, $E5);
  end;
end;

{ TFlatButton }

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  TabStop := True;
  Cursor := crHandPoint;
  DoubleBuffered := True;
end;

procedure TFlatButton.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FHover := True;
  Invalidate;
end;

procedure TFlatButton.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHover := False;
  Invalidate;
end;

procedure TFlatButton.CMTextChanged(var Message: TMessage);
begin
  inherited;
  Invalidate;
end;

procedure TFlatButton.CMEnabledChanged(var Message: TMessage);
begin
  inherited;
  Invalidate;
end;

procedure TFlatButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (Key = VK_RETURN) or (Key = VK_SPACE) then
  begin
    Click;
    Key := 0;
  end;
end;

procedure TFlatButton.DoEnter;
begin
  inherited;
  Invalidate;
end;

procedure TFlatButton.DoExit;
begin
  inherited;
  Invalidate;
end;

procedure TFlatButton.Paint;
var
  Fill, Ink: TColor;
  R: TRect;
  Radius: Integer;
begin
  if FPrimary then
  begin
    Fill := FTheme.Accent;
    if FHover then
      // A little lighter on hover.
      Fill := RGB(Min(255, GetRValue(ColorToRGB(Fill)) + 20),
        Min(255, GetGValue(ColorToRGB(Fill)) + 20), Min(255, GetBValue(ColorToRGB(Fill)) + 20));
    Ink := FTheme.AccentText;
  end
  else
  begin
    if FHover and Enabled then
      Fill := FTheme.Hover
    else
      Fill := FTheme.Card;
    Ink := FTheme.Text;
  end;
  if not Enabled then
    Ink := FTheme.Muted;
  Canvas.Brush.Color := Parent.Brush.Color;
  Canvas.FillRect(ClientRect);
  Radius := MulDiv(8, Screen.PixelsPerInch, 96);
  Canvas.Brush.Color := Fill;
  if FPrimary then
    Canvas.Pen.Color := Fill
  else
    Canvas.Pen.Color := FTheme.Border;
  Canvas.RoundRect(0, 0, Width, Height, Radius, Radius);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := Ink;
  Canvas.Brush.Style := bsClear;
  R := ClientRect;
  DrawText(Canvas.Handle, PChar(Caption), -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  // A ring only when the keyboard is used (Windows hides focus cues for
  // mouse users).
  if Focused and ((Perform(WM_QUERYUISTATE, 0, 0) and UISF_HIDEFOCUS) = 0) then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := FTheme.Text;
    Canvas.Pen.Width := 1;
    Canvas.RoundRect(1, 1, Width - 1, Height - 1, Radius, Radius);
  end;
end;

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
var
  Value: BOOL;
  Corner: DWORD;
  Caption, TextColor: COLORREF;
begin
  if not HandleAllocated or (Win32MajorVersion < 10) then
    Exit;
  // Each attribute is ignored by Windows versions that do not know it.
  Value := FTheme.Dark;
  DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Value, SizeOf(Value));
  Corner := DWMWCP_ROUND;
  DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, @Corner, SizeOf(Corner));
  Caption := ColorToRGB(FTheme.Back);
  DwmSetWindowAttribute(Handle, DWMWA_CAPTION_COLOR, @Caption, SizeOf(Caption));
  TextColor := ColorToRGB(FTheme.Text);
  DwmSetWindowAttribute(Handle, DWMWA_TEXT_COLOR, @TextColor, SizeOf(TextColor));
end;

procedure TExplainWindow.ApplyTheme;
begin
  FTheme := CurrentExplainTheme;
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
var
  Format: TParaFormat2;
begin
  // Line spacing 1.2 and some space after each paragraph, for the whole text.
  FAnswer.SelectAll;
  FillChar(Format, SizeOf(Format), 0);
  Format.cbSize := SizeOf(Format);
  Format.dwMask := PFM_LINESPACING or PFM_SPACEAFTER;
  Format.bLineSpacingRule := 5;     // dyLineSpacing in 1/20 of a line
  Format.dyLineSpacing := 24;
  Format.dySpaceAfter := 80;        // twips
  SendMessage(FAnswer.Handle, EM_SETPARAFORMAT, 0, LPARAM(@Format));
  FAnswer.SelStart := 0;
  FAnswer.SelLength := 0;
  // Moving the selection shows the caret again.
  HideCaret(FAnswer.Handle);
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
var
  Lines: TArray<TMdLine>;
  Line: TMdLine;
  Run: TMdRun;
  I, LineStart: Integer;
  Para: TParaFormat2;

  procedure Put(const Text: string; Bold, Code: Boolean; Size: Integer; Color: TColor);
  begin
    FAnswer.SelStart := FAnswer.GetTextLen;
    FAnswer.SelLength := 0;
    if Code then
      FAnswer.SelAttributes.Name := 'Consolas'
    else
      FAnswer.SelAttributes.Name := FFontName;
    FAnswer.SelAttributes.Size := Size;
    FAnswer.SelAttributes.Color := Color;
    if Bold then
      FAnswer.SelAttributes.Style := [fsBold]
    else
      FAnswer.SelAttributes.Style := [];
    FAnswer.SelText := Text;
  end;

begin
  Lines := ParseMarkdown(Markdown);
  FAnswer.Lines.BeginUpdate;
  try
    FAnswer.Clear;
    for I := 0 to High(Lines) do
    begin
      Line := Lines[I];
      LineStart := FAnswer.GetTextLen;
      case Line.Kind of
        mlBlank:
          ; // the paragraph spacing separates paragraphs
        mlHeading:
          for Run in Line.Runs do
            Put(Run.Text, True, Run.Code, 12, FTheme.Text);
        mlBullet, mlNumbered:
          begin
            Put(Line.Marker + #9, Line.Kind = mlNumbered, False, 10, FTheme.Accent);
            for Run in Line.Runs do
              Put(Run.Text, Run.Bold, Run.Code, 10, FTheme.Text);
          end;
        mlCode:
          Put(Line.Runs[0].Text, False, True, 9, FTheme.Text);
      else
        for Run in Line.Runs do
          Put(Run.Text, Run.Bold, Run.Code, 10, FTheme.Text);
      end;
      if Line.Kind = mlBlank then
        Continue;
      // List items: a hanging indent, the text aligned after the marker.
      if Line.Kind in [mlBullet, mlNumbered] then
      begin
        FAnswer.SelStart := LineStart;
        FAnswer.SelLength := FAnswer.GetTextLen - LineStart;
        FillChar(Para, SizeOf(Para), 0);
        Para.cbSize := SizeOf(Para);
        Para.dwMask := PFM_STARTINDENT or PFM_OFFSET or PFM_TABSTOPS;
        Para.dxStartIndent := 120;
        Para.dxOffset := 280;
        Para.cTabCount := 1;
        Para.rgxTabs[0] := 400;
        SendMessage(FAnswer.Handle, EM_SETPARAFORMAT, 0, LPARAM(@Para));
      end;
      if I < High(Lines) then
        Put(#13, False, False, 10, FTheme.Text);
    end;
    SetParagraphSpacing;
  finally
    FAnswer.Lines.EndUpdate;
  end;
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
