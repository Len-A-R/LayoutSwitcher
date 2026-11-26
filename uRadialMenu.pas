unit uRadialMenu;

// The radial menu of the middle mouse button: a ring of slices around the
// pointer, an icon and a short name in each, the highlighted slice in the
// accent colour, its full name and a hint in the centre.  In the colours of
// the Windows theme, smoothed with GDI+, a layered window with per-pixel
// alpha that never takes the focus and lets the mouse through (uMouseHook
// gives it the buttons).

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types,
  System.Math, Vcl.Controls, Vcl.Forms, Vcl.Graphics, uModernUI;

type
  TRadialItem = record
    Glyph: Char;            // Segoe Fluent Icons
    Caption: string;        // under the icon
    Title: string;          // in the centre when highlighted
    Hint: string;
    Tag: Integer;           // what the owner runs
  end;

  TRadialMenu = class(TCustomForm)
  private
    FItems: TArray<TRadialItem>;
    FCenter: TPoint;
    FHighlight: Integer;
    FTheme: TUiTheme;
    FTitle: string;
    FHint: string;
    FRenderError: DWORD;
    function S(Value: Integer): Integer;
    procedure Render;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
  public
    constructor CreateMenu(AOwner: TComponent);
    // Shows the menu centred at Center (screen coordinates).
    procedure Popup(const Items: TArray<TRadialItem>; const Center: TPoint; const Title, Hint: string);
    procedure HideMenu;
    // The slices without showing the menu (a flick).
    procedure SetItems(const Items: TArray<TRadialItem>);
    function Shown: Boolean;
    // Highlights the slice under the point (none in the centre or outside).
    procedure TrackPoint(const P: TPoint);
    // The slice under the point, -1 in the centre or far outside.
    function ItemAt(const P: TPoint): Integer;
    // The slice in the direction from A to B (a flick).
    function ItemInDirection(const A, B: TPoint): Integer;
    property Items: TArray<TRadialItem> read FItems;
    property Highlight: Integer read FHighlight;
    // GetLastError of the last failed UpdateLayeredWindow (diagnostics).
    property RenderError: DWORD read FRenderError;
  end;

// The slice of Count slices (the first one centred at the top, clockwise)
// for the angle of the vector (DX, DY) on the screen.
function RadialSliceAt(DX, DY, Count: Integer): Integer;

implementation

uses
  Winapi.GDIPAPI, Winapi.GDIPOBJ;

const
  OUTER_RADIUS = 158;
  INNER_RADIUS = 72;
  CENTER_RADIUS = 66;
  SHADOW = 14;
  GAP_DEGREES = 1.2;

function RadialSliceAt(DX, DY, Count: Integer): Integer;
var
  Angle, Slice: Double;
begin
  if Count <= 0 then
    Exit(-1);
  // 0 at the top, clockwise (screen Y grows downwards).
  Angle := RadToDeg(ArcTan2(DX, -DY));
  if Angle < 0 then
    Angle := Angle + 360;
  Slice := 360 / Count;
  Result := Trunc((Angle + Slice / 2) / Slice) mod Count;
end;

{ TRadialMenu }

constructor TRadialMenu.CreateMenu(AOwner: TComponent);
begin
  CreateNew(AOwner);
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  FHighlight := -1;
  Width := S((OUTER_RADIUS + SHADOW) * 2);
  Height := Width;
end;

procedure TRadialMenu.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  // Layered, click-through, never active, no taskbar button.
  Params.ExStyle := Params.ExStyle or WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_NOACTIVATE or
    WS_EX_TOOLWINDOW or WS_EX_TOPMOST;
  Params.WndParent := 0;
end;

procedure TRadialMenu.CreateWnd;
begin
  inherited;
  // The VCL drops WS_EX_LAYERED of a form without AlphaBlend: back on, for
  // UpdateLayeredWindow.
  SetWindowLong(Handle, GWL_EXSTYLE, GetWindowLong(Handle, GWL_EXSTYLE) or WS_EX_LAYERED or
    WS_EX_TRANSPARENT or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW);
end;

procedure TRadialMenu.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

function TRadialMenu.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

function TRadialMenu.Shown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

procedure TRadialMenu.Popup(const Items: TArray<TRadialItem>; const Center: TPoint;
  const Title, Hint: string);
var
  Area: TRect;
  Half: Integer;
begin
  FItems := Items;
  FTheme := CurrentUiTheme;
  FTitle := Title;
  FHint := Hint;
  FHighlight := -1;
  Half := Width div 2;
  // Inside the work area of the monitor; the centre stays under the
  // pointer when it can.
  Area := Screen.MonitorFromPoint(Center).WorkareaRect;
  FCenter := Point(EnsureRange(Center.X, Area.Left + Half, Max(Area.Left + Half, Area.Right - Half)),
    EnsureRange(Center.Y, Area.Top + Half, Max(Area.Top + Half, Area.Bottom - Half)));
  HandleNeeded;
  Render;
  ShowWindow(Handle, SW_SHOWNOACTIVATE);
  SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
end;

procedure TRadialMenu.SetItems(const Items: TArray<TRadialItem>);
begin
  FItems := Items;
end;

procedure TRadialMenu.HideMenu;
begin
  if HandleAllocated then
    ShowWindow(Handle, SW_HIDE);
  FHighlight := -1;
end;

function TRadialMenu.ItemAt(const P: TPoint): Integer;
var
  D: Double;
begin
  Result := -1;
  D := Sqrt(Sqr(Int64(P.X - FCenter.X)) + Sqr(Int64(P.Y - FCenter.Y)));
  // The ring, and a margin outside it (a quick movement overshoots).
  if (D > S(INNER_RADIUS)) and (D < S(OUTER_RADIUS) * 2) then
    Result := RadialSliceAt(P.X - FCenter.X, P.Y - FCenter.Y, Length(FItems));
end;

function TRadialMenu.ItemInDirection(const A, B: TPoint): Integer;
begin
  Result := RadialSliceAt(B.X - A.X, B.Y - A.Y, Length(FItems));
end;

procedure TRadialMenu.TrackPoint(const P: TPoint);
var
  Index: Integer;
begin
  Index := ItemAt(P);
  if Index <> FHighlight then
  begin
    FHighlight := Index;
    Render;
  end;
end;

function Argb(Color: TColor; Alpha: Byte): Cardinal;
var
  RGBColor: Cardinal;
begin
  RGBColor := ColorToRGB(Color);
  Result := MakeColor(Alpha, GetRValue(RGBColor), GetGValue(RGBColor), GetBValue(RGBColor));
end;

procedure TRadialMenu.Render;
var
  Size, I, Count, Cx, Cy, Ro, Ri, Rc: Integer;
  Bitmap: TGPBitmap;
  G: TGPGraphics;
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  Pen: TGPPen;
  IconFont, LabelFont, TitleFont, HintFont: TGPFont;
  Format: TGPStringFormat;
  Slice, Start, Mid, Rm: Double;
  Item: TRadialItem;
  Ring, Hover, Ink, Muted, CenterFill, AccentInk: Cardinal;
  HBmp: HBITMAP;
  ScreenDC, MemDC: HDC;
  OldBmp: HGDIOBJ;
  Blend: TBlendFunction;
  Pos, Src: TPoint;
  Sz: TSize;
  Title, Hint: string;
  R: TGPRectF;
begin
  if not HandleAllocated then
    Exit;
  Size := Width;
  Cx := Size div 2;
  Cy := Size div 2;
  Ro := S(OUTER_RADIUS);
  Ri := S(INNER_RADIUS);
  Rc := S(CENTER_RADIUS);
  Count := Length(FItems);
  if FTheme.Dark then
  begin
    Ring := Argb(RGB(44, 44, 46), 242);
    CenterFill := Argb(RGB(32, 32, 34), 250);
    Hover := Argb(RGB(62, 62, 66), 255);
  end
  else
  begin
    Ring := Argb(RGB(236, 237, 240), 242);
    CenterFill := Argb(clWhite, 252);
    Hover := Argb(RGB(222, 224, 228), 255);
  end;
  Ink := Argb(FTheme.Text, 255);
  Muted := Argb(FTheme.Muted, 255);
  AccentInk := Argb(FTheme.AccentText, 255);

  Bitmap := TGPBitmap.Create(Size, Size, PixelFormat32bppPARGB);
  G := TGPGraphics.Create(Bitmap);
  Format := TGPStringFormat.Create;
  IconFont := TGPFont.Create(IconFontName, S(20), FontStyleRegular, UnitPixel);
  LabelFont := TGPFont.Create(ModernFontName, S(11), FontStyleRegular, UnitPixel);
  TitleFont := TGPFont.Create(ModernFontName(True), S(14), FontStyleBold, UnitPixel);
  HintFont := TGPFont.Create(ModernFontName, S(10), FontStyleRegular, UnitPixel);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    G.Clear(MakeColor(0, 0, 0, 0));
    Format.SetAlignment(StringAlignmentCenter);
    Format.SetLineAlignment(StringAlignmentCenter);
    // Text that does not fit ends with an ellipsis inside its circle.
    Format.SetTrimming(StringTrimmingEllipsisWord);

    // A soft shadow around the ring.
    for I := SHADOW downto 1 do
    begin
      Brush := TGPSolidBrush.Create(MakeColor(Round(10 * (1 - I / SHADOW)) + 2, 0, 0, 0));
      try
        G.FillEllipse(Brush, Cx - Ro - I, Cy - Ro - I + S(3), (Ro + I) * 2, (Ro + I) * 2);
      finally
        Brush.Free;
      end;
    end;

    // Under the slices: the gaps between them become thin lines.
    Brush := TGPSolidBrush.Create(Argb(FTheme.Border, 250));
    try
      G.FillEllipse(Brush, Cx - Ro, Cy - Ro, Ro * 2, Ro * 2);
    finally
      Brush.Free;
    end;

    // The slices.
    if Count > 0 then
    begin
      Slice := 360 / Count;
      for I := 0 to Count - 1 do
      begin
        Item := FItems[I];
        // GDI+ angles: 0 at three o'clock, clockwise; slice 0 is centred at
        // the top.
        Start := -90 - Slice / 2 + I * Slice + GAP_DEGREES / 2;
        Path := TGPGraphicsPath.Create;
        try
          Path.AddArc(Cx - Ro, Cy - Ro, Ro * 2, Ro * 2, Start, Slice - GAP_DEGREES);
          Path.AddArc(Cx - Ri, Cy - Ri, Ri * 2, Ri * 2, Start + Slice - GAP_DEGREES,
            -(Slice - GAP_DEGREES));
          Path.CloseFigure;
          if I = FHighlight then
            Brush := TGPSolidBrush.Create(Argb(FTheme.Accent, 255))
          else
            Brush := TGPSolidBrush.Create(Ring);
          try
            G.FillPath(Brush, Path);
          finally
            Brush.Free;
          end;
        finally
          Path.Free;
        end;
        // Icon and name in the middle of the slice.
        Mid := DegToRad(-90 + I * Slice);
        Rm := (Ro + Ri) / 2;
        if I = FHighlight then
          Brush := TGPSolidBrush.Create(AccentInk)
        else
          Brush := TGPSolidBrush.Create(Ink);
        try
          R := MakeRect(Cx + Rm * Cos(Mid) - S(40), Cy + Rm * Sin(Mid) - S(24), S(80), S(28));
          G.DrawString(Item.Glyph, 1, IconFont, R, Format, Brush);
          R := MakeRect(Cx + Rm * Cos(Mid) - S(46), Cy + Rm * Sin(Mid) + S(4), S(92), S(18));
          G.DrawString(Item.Caption, -1, LabelFont, R, Format, Brush);
        finally
          Brush.Free;
        end;
      end;
    end;

    // The centre: the highlighted command or the title.
    Brush := TGPSolidBrush.Create(CenterFill);
    Pen := TGPPen.Create(Argb(FTheme.Border, 255), 1);
    try
      G.FillEllipse(Brush, Cx - Rc, Cy - Rc, Rc * 2, Rc * 2);
      G.DrawEllipse(Pen, Cx - Rc, Cy - Rc, Rc * 2, Rc * 2);
    finally
      Pen.Free;
      Brush.Free;
    end;
    if (FHighlight >= 0) and (FHighlight < Count) then
    begin
      Title := FItems[FHighlight].Title;
      Hint := FItems[FHighlight].Hint;
    end
    else
    begin
      Title := FTitle;
      Hint := FHint;
    end;
    Brush := TGPSolidBrush.Create(Ink);
    try
      R := MakeRect(Single(Cx - Rc + S(8)), Single(Cy - S(26)), Single((Rc - S(8)) * 2), Single(S(24)));
      G.DrawString(Title, -1, TitleFont, R, Format, Brush);
    finally
      Brush.Free;
    end;
    Brush := TGPSolidBrush.Create(Muted);
    try
      R := MakeRect(Single(Cx - Rc + S(12)), Single(Cy + S(1)), Single((Rc - S(12)) * 2), Single(S(30)));
      G.DrawString(Hint, -1, HintFont, R, Format, Brush);
    finally
      Brush.Free;
    end;

    // To the layered window.
    Bitmap.GetHBITMAP(MakeColor(0, 0, 0, 0), HBmp);
    ScreenDC := GetDC(0);
    MemDC := CreateCompatibleDC(ScreenDC);
    OldBmp := SelectObject(MemDC, HBmp);
    try
      Blend.BlendOp := AC_SRC_OVER;
      Blend.BlendFlags := 0;
      Blend.SourceConstantAlpha := 255;
      Blend.AlphaFormat := AC_SRC_ALPHA;
      Pos := Point(FCenter.X - Size div 2, FCenter.Y - Size div 2);
      Src := Point(0, 0);
      Sz.cx := Size;
      Sz.cy := Size;
      if UpdateLayeredWindow(Handle, ScreenDC, @Pos, @Sz, MemDC, @Src, 0, @Blend, ULW_ALPHA) then
        FRenderError := 0
      else
        FRenderError := GetLastError;
    finally
      SelectObject(MemDC, OldBmp);
      DeleteDC(MemDC);
      ReleaseDC(0, ScreenDC);
      DeleteObject(HBmp);
    end;
  finally
    HintFont.Free;
    TitleFont.Free;
    LabelFont.Free;
    IconFont.Free;
    Format.Free;
    G.Free;
    Bitmap.Free;
  end;
end;

end.
