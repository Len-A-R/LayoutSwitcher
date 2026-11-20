unit uModernUI;

// Shared look of the Windows 11 style windows (settings, AI explanation):
// colours following the system theme and the accent colour, the window
// frame (title bar colour, rounded corners), a flat button and the side
// navigation of the settings window.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.ComCtrls;

type
  TUiTheme = record
    Dark: Boolean;
    Back, Card, Footer, Text, Muted, Accent, AccentText, Error, Hover, Border: TColor;
  end;

  // A flat button with rounded corners and a hover state.
  TFlatButton = class(TCustomControl)
  private
    FHover: Boolean;
    FPrimary: Boolean;
    FTheme: TUiTheme;
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
    property Theme: TUiTheme read FTheme write FTheme;
    property Caption;
    property Font;
    property OnClick;
  end;

  // Side navigation: one item per page of a page control whose tabs are
  // hidden, an icon (Segoe Fluent Icons) and the page caption.
  TNavBar = class(TCustomControl)
  private
    FPages: TPageControl;
    FIcons: TArray<Char>;
    FHover: Integer;
    FTheme: TUiTheme;
    FTitle: string;
    FSubtitle: string;
    FIconFont: string;
    FTextFont: string;
    FOnChange: TNotifyEvent;
    function S(Value: Integer): Integer;
    function ItemTop(Index: Integer): Integer;
    function ItemAt(Y: Integer): Integer;
    procedure Select(Index: Integer);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(Pages: TPageControl; const Icons: array of Char; const Theme: TUiTheme);
    property Title: string read FTitle write FTitle;
    property Subtitle: string read FSubtitle write FSubtitle;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

function CurrentUiTheme(ForceLight: Boolean = False): TUiTheme;
// Dark title bar (or not), its colour, rounded corners; ignored by Windows
// versions that do not know an attribute.
procedure ApplyWindowChrome(Wnd: HWND; const Theme: TUiTheme; CaptionColor: TColor);
// "Segoe UI Variable Text" on Windows 11, "Segoe UI" otherwise.
function ModernFontName(Display: Boolean = False): string;
function IconFontName: string;

implementation

uses
  Winapi.DwmApi, System.Win.Registry, System.Math;

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWA_CAPTION_COLOR = 35;
  DWMWA_TEXT_COLOR = 36;
  DWMWCP_ROUND = 2;

function ModernFontName(Display: Boolean): string;
begin
  if Display and (Screen.Fonts.IndexOf('Segoe UI Variable Display') >= 0) then
    Result := 'Segoe UI Variable Display'
  else if Screen.Fonts.IndexOf('Segoe UI Variable Text') >= 0 then
    Result := 'Segoe UI Variable Text'
  else
    Result := 'Segoe UI';
end;

function IconFontName: string;
begin
  if Screen.Fonts.IndexOf('Segoe Fluent Icons') >= 0 then
    Result := 'Segoe Fluent Icons'
  else
    Result := 'Segoe MDL2 Assets';
end;

procedure ApplyWindowChrome(Wnd: HWND; const Theme: TUiTheme; CaptionColor: TColor);
var
  Value: BOOL;
  Corner: DWORD;
  Caption, TextColor: COLORREF;
begin
  if (Wnd = 0) or (Win32MajorVersion < 10) then
    Exit;
  Value := Theme.Dark;
  DwmSetWindowAttribute(Wnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @Value, SizeOf(Value));
  Corner := DWMWCP_ROUND;
  DwmSetWindowAttribute(Wnd, DWMWA_WINDOW_CORNER_PREFERENCE, @Corner, SizeOf(Corner));
  Caption := ColorToRGB(CaptionColor);
  DwmSetWindowAttribute(Wnd, DWMWA_CAPTION_COLOR, @Caption, SizeOf(Caption));
  TextColor := ColorToRGB(Theme.Text);
  DwmSetWindowAttribute(Wnd, DWMWA_TEXT_COLOR, @TextColor, SizeOf(TextColor));
end;

{ Theme }

function CurrentUiTheme(ForceLight: Boolean): TUiTheme;
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
      Result.Dark := not ForceLight and (Registry.ReadInteger('AppsUseLightTheme') = 0);
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

{ TNavBar }

constructor TNavBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  DoubleBuffered := True;
  FHover := -1;
  FIconFont := IconFontName;
  FTextFont := ModernFontName;
end;

function TNavBar.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

procedure TNavBar.Setup(Pages: TPageControl; const Icons: array of Char; const Theme: TUiTheme);
var
  I: Integer;
begin
  FPages := Pages;
  SetLength(FIcons, Length(Icons));
  for I := 0 to High(Icons) do
    FIcons[I] := Icons[I];
  FTheme := Theme;
  Color := Theme.Footer;
  Invalidate;
end;

function TNavBar.ItemTop(Index: Integer): Integer;
begin
  Result := S(76) + Index * S(38);
end;

function TNavBar.ItemAt(Y: Integer): Integer;
begin
  Result := -1;
  if (FPages = nil) or (Y < ItemTop(0)) then
    Exit;
  Result := (Y - ItemTop(0)) div S(38);
  if Result >= FPages.PageCount then
    Result := -1;
end;

procedure TNavBar.Select(Index: Integer);
begin
  if (FPages = nil) or (Index < 0) or (Index >= FPages.PageCount) or
     (FPages.ActivePageIndex = Index) then
    Exit;
  FPages.ActivePageIndex := Index;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TNavBar.Paint;
var
  I, Top, Radius: Integer;
  R: TRect;
  Selected: Boolean;
begin
  Canvas.Brush.Color := FTheme.Footer;
  Canvas.FillRect(ClientRect);
  // The application name and the version.
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := ModernFontName(True);
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FTheme.Text;
  Canvas.TextOut(S(20), S(18), FTitle);
  Canvas.Font.Name := FTextFont;
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [];
  Canvas.Font.Color := FTheme.Muted;
  Canvas.TextOut(S(20), S(44), FSubtitle);
  if FPages = nil then
    Exit;
  Radius := S(8);
  for I := 0 to FPages.PageCount - 1 do
  begin
    Top := ItemTop(I);
    R := Rect(S(8), Top, Width - S(8), Top + S(34));
    Selected := I = FPages.ActivePageIndex;
    if Selected or (I = FHover) then
    begin
      Canvas.Brush.Style := bsSolid;
      if Selected then
        Canvas.Brush.Color := FTheme.Hover
      else
        Canvas.Brush.Color := FTheme.Card;
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius);
    end;
    if Selected then
    begin
      // The accent pill of Windows 11 navigation.
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FTheme.Accent;
      Canvas.Pen.Color := FTheme.Accent;
      Canvas.RoundRect(R.Left, R.Top + S(9), R.Left + S(3), R.Bottom - S(9), S(3), S(3));
    end;
    Canvas.Brush.Style := bsClear;
    if I <= High(FIcons) then
    begin
      Canvas.Font.Name := FIconFont;
      Canvas.Font.Size := 11;
      Canvas.Font.Style := [];
      Canvas.Font.Color := FTheme.Text;
      Canvas.TextOut(R.Left + S(14), R.Top + (R.Height - Canvas.TextHeight(FIcons[I])) div 2,
        FIcons[I]);
    end;
    Canvas.Font.Name := FTextFont;
    Canvas.Font.Size := 9;
    if Selected then
      Canvas.Font.Style := [fsBold]
    else
      Canvas.Font.Style := [];
    Canvas.Font.Color := FTheme.Text;
    Canvas.TextOut(R.Left + S(44), R.Top + (R.Height - Canvas.TextHeight('Ag')) div 2,
      FPages.Pages[I].Caption);
    if Focused and Selected and ((Perform(WM_QUERYUISTATE, 0, 0) and UISF_HIDEFOCUS) = 0) then
    begin
      Canvas.Pen.Color := FTheme.Text;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius);
    end;
  end;
end;

procedure TNavBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited;
  Index := ItemAt(Y);
  if Index <> FHover then
  begin
    FHover := Index;
    if Index >= 0 then
      Cursor := crHandPoint
    else
      Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TNavBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
    Select(ItemAt(Y));
end;

procedure TNavBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if FPages = nil then
    Exit;
  case Key of
    VK_UP:
      begin
        Select(Max(0, FPages.ActivePageIndex - 1));
        Key := 0;
      end;
    VK_DOWN:
      begin
        Select(Min(FPages.PageCount - 1, FPages.ActivePageIndex + 1));
        Key := 0;
      end;
  end;
end;

procedure TNavBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHover := -1;
  Invalidate;
end;

procedure TNavBar.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS;
end;

procedure TNavBar.DoEnter;
begin
  inherited;
  Invalidate;
end;

procedure TNavBar.DoExit;
begin
  inherited;
  Invalidate;
end;

end.
