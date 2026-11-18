unit uLayoutIndicator;

// Small "RU" / "EN" badge shown next to the text caret for a moment after the
// keyboard layout of the focused window changes.  The window never takes
// focus and lets mouse clicks through.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.Classes, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics;

type
  TLayoutIndicator = class
  private
    FForm: TForm;
    FLabel: TLabel;
    FTimer: TTimer;
    procedure HideTimer(Sender: TObject);
    function AnchorPoint: TPoint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ShowLayout(Layout: HKL);
    procedure HideNow;
  end;

// Two-letter ISO 639 language name of a keyboard layout: "RU", "EN", "UK"...
function LayoutShortName(Layout: HKL): string;

implementation

uses
  System.SysUtils,
  Winapi.MultiMon;

const
  DISPLAY_TIME_MS = 1200;
  PADDING_X = 6;
  PADDING_Y = 2;

type
  TIndicatorForm = class(TForm)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure WndProc(var Message: TMessage); override;
  end;

  TLSGUIThreadInfo = record
    cbSize: DWORD;
    flags: DWORD;
    hwndActive: HWND;
    hwndFocus: HWND;
    hwndCapture: HWND;
    hwndMenuOwner: HWND;
    hwndMoveSize: HWND;
    hwndCaret: HWND;
    rcCaret: TRect;
  end;

function LSGetGUIThreadInfo(ThreadID: DWORD; var Info: TLSGUIThreadInfo): BOOL;
  stdcall; external user32 name 'GetGUIThreadInfo';

function LayoutShortName(Layout: HKL): string;
var
  Buffer: array[0..15] of Char;
begin
  if GetLocaleInfo(LoWord(NativeUInt(Layout)), LOCALE_SISO639LANGNAME, Buffer,
       Length(Buffer)) > 0 then
    Result := UpperCase(string(Buffer))
  else
    Result := IntToHex(LoWord(NativeUInt(Layout)), 4);
end;

{ TIndicatorForm }

procedure TIndicatorForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW or
    WS_EX_TOPMOST or WS_EX_TRANSPARENT;
  Params.WndParent := 0;
end;

procedure TIndicatorForm.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_MOUSEACTIVATE then
  begin
    Message.Result := MA_NOACTIVATE;
    Exit;
  end;
  inherited;
end;

{ TLayoutIndicator }

constructor TLayoutIndicator.Create;
begin
  inherited Create;
  FForm := TIndicatorForm.CreateNew(nil);
  FForm.BorderStyle := bsNone;
  FForm.Color := RGB(32, 96, 192);
  FForm.AlphaBlend := True;
  FForm.AlphaBlendValue := 235;
  FLabel := TLabel.Create(FForm);
  FLabel.Parent := FForm;
  FLabel.Font.Name := 'Segoe UI';
  FLabel.Font.Size := 9;
  FLabel.Font.Style := [fsBold];
  FLabel.Font.Color := clWhite;
  FLabel.Transparent := True;
  FLabel.AutoSize := True;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := DISPLAY_TIME_MS;
  FTimer.OnTimer := HideTimer;
end;

destructor TLayoutIndicator.Destroy;
begin
  FTimer.Free;
  FForm.Free;
  inherited;
end;

function TLayoutIndicator.AnchorPoint: TPoint;
var
  Info: TLSGUIThreadInfo;
  Foreground: HWND;
begin
  // The system caret if the application exposes one, otherwise the pointer.
  Foreground := GetForegroundWindow;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if (Foreground <> 0) and
     LSGetGUIThreadInfo(GetWindowThreadProcessId(Foreground, nil), Info) and
     (Info.hwndCaret <> 0) then
  begin
    Result := Point(Info.rcCaret.Left, Info.rcCaret.Bottom + 4);
    Winapi.Windows.ClientToScreen(Info.hwndCaret, Result);
  end
  else
  begin
    GetCursorPos(Result);
    Inc(Result.X, 16);
    Inc(Result.Y, 20);
  end;
end;

procedure TLayoutIndicator.ShowLayout(Layout: HKL);
var
  Anchor: TPoint;
  Width, Height: Integer;
  Monitor: HMONITOR;
  Info: TMonitorInfo;
begin
  FLabel.Caption := LayoutShortName(Layout);
  Width := FLabel.Width + PADDING_X * 2;
  Height := FLabel.Height + PADDING_Y * 2;
  FLabel.SetBounds(PADDING_X, PADDING_Y, FLabel.Width, FLabel.Height);

  Anchor := AnchorPoint;
  Monitor := MonitorFromPoint(Anchor, MONITOR_DEFAULTTONEAREST);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetMonitorInfo(Monitor, @Info) then
  begin
    if Anchor.X + Width > Info.rcWork.Right then
      Anchor.X := Info.rcWork.Right - Width;
    if Anchor.Y + Height > Info.rcWork.Bottom then
      Anchor.Y := Info.rcWork.Bottom - Height;
    if Anchor.X < Info.rcWork.Left then
      Anchor.X := Info.rcWork.Left;
    if Anchor.Y < Info.rcWork.Top then
      Anchor.Y := Info.rcWork.Top;
  end;

  // Never activate: the user keeps typing in the target window.
  SetWindowPos(FForm.Handle, HWND_TOPMOST, Anchor.X, Anchor.Y, Width, Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TLayoutIndicator.HideNow;
begin
  FTimer.Enabled := False;
  if FForm.HandleAllocated then
    ShowWindow(FForm.Handle, SW_HIDE);
end;

procedure TLayoutIndicator.HideTimer(Sender: TObject);
begin
  HideNow;
end;

end.
