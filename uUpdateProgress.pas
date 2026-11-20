unit uUpdateProgress;

// Windows of the update, in the Windows 11 style of uModernUI (light or dark
// like the system, title bar in the colour of the window, rounded corners):
//
// * the progress of an update download - version, an accent progress bar
//   (running while the size is unknown), "1.2 of 4.1 MB (29%)" and Cancel.
//   It appears in the bottom-right corner, next to the tray; closing only
//   hides it, the download goes on;
// * "What's new" before an update - the release notes rendered from
//   Markdown, Install (or Open download page) and Later.

interface

uses
  Winapi.Windows,
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  uModernUI;

type
  TUpdateProgressWindow = class
  private
    FForm: TForm;
    FTheme: TUiTheme;
    FTitle: TLabel;
    FBar: TPaintBox;
    FStatus: TLabel;
    FCancel: TFlatButton;
    FTimer: TTimer;
    FOnCancel: TNotifyEvent;
    FPercent: Integer;
    FMarquee: Boolean;
    FMarqueePos: Integer;
    procedure CancelClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure BarPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure PlaceNearTray;
    procedure ApplyTheme;
    function Scale(Value: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const Version: string);
    // Kilobytes received and expected; Total = 0 when the size is unknown.
    procedure SetProgress(ReceivedKB, TotalKB: Int64);
    procedure ShowInstalling;
    procedure ShowWindow;
    procedure Close;
    // -1 while the size is unknown.
    property Percent: Integer read FPercent;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

// "1,2 МБ из 4,1 МБ (29%)" in the current UI language.
function FormatDownloadProgress(ReceivedKB, TotalKB: Int64): string;

// "What's new" window shown before an update: release notes and
// Install / Open page / Later.  Returns True if the user chose to install
// (or to open the page when Installable is False).
function ShowReleaseNotes(const Version, Notes: string; Installable: Boolean): Boolean;

implementation

uses
  Winapi.Messages, Winapi.UxTheme, System.Math, Vcl.ComCtrls,
  uLocale, uWinUtils;

function FormatMegabytes(KB: Int64): string;
begin
  Result := FormatFloat('0.0', KB / 1024) + T(' МБ', ' MB');
end;

function FormatDownloadProgress(ReceivedKB, TotalKB: Int64): string;
begin
  if TotalKB > 0 then
    Result := Format(T('%s из %s (%d%%)', '%s of %s (%d%%)'),
      [FormatMegabytes(ReceivedKB), FormatMegabytes(TotalKB),
       ReceivedKB * 100 div TotalKB])
  else
    Result := Format(T('Загружено %s', '%s downloaded'), [FormatMegabytes(ReceivedKB)]);
end;

{ TUpdateProgressWindow }

constructor TUpdateProgressWindow.Create;
begin
  inherited Create;
  FPercent := -1;
  FForm := TForm.CreateNew(nil);
  FForm.BorderStyle := bsSingle;
  FForm.BorderIcons := [biSystemMenu];
  FForm.FormStyle := fsStayOnTop;
  FForm.Position := poDesigned;
  FForm.Font.Name := ModernFontName;
  FForm.Font.Size := 9;
  FForm.ClientWidth := Scale(400);
  FForm.ClientHeight := Scale(150);
  FForm.OnClose := FormClose;

  FTitle := TLabel.Create(FForm);
  FTitle.Parent := FForm;
  FTitle.SetBounds(Scale(20), Scale(18), Scale(360), Scale(24));
  FTitle.AutoSize := False;
  FTitle.Font.Name := ModernFontName(True);
  FTitle.Font.Size := 12;
  FTitle.Font.Style := [fsBold];
  FTitle.ShowAccelChar := False;

  FBar := TPaintBox.Create(FForm);
  FBar.Parent := FForm;
  FBar.SetBounds(Scale(20), Scale(56), Scale(360), Scale(6));
  FBar.OnPaint := BarPaint;

  FStatus := TLabel.Create(FForm);
  FStatus.Parent := FForm;
  FStatus.SetBounds(Scale(20), Scale(70), Scale(360), Scale(18));
  FStatus.AutoSize := False;
  FStatus.ShowAccelChar := False;

  FCancel := TFlatButton.Create(FForm);
  FCancel.Parent := FForm;
  FCancel.SetBounds(Scale(280), Scale(102), Scale(100), Scale(32));
  FCancel.OnClick := CancelClick;

  FTimer := TTimer.Create(FForm);
  FTimer.Enabled := False;
  FTimer.Interval := 25;
  FTimer.OnTimer := TimerTick;
end;

destructor TUpdateProgressWindow.Destroy;
begin
  FForm.Free;
  inherited;
end;

function TUpdateProgressWindow.Scale(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

procedure TUpdateProgressWindow.ApplyTheme;
begin
  FTheme := CurrentUiTheme;
  FForm.Color := FTheme.Back;
  FTitle.Font.Color := FTheme.Text;
  FStatus.Font.Color := FTheme.Muted;
  FCancel.Theme := FTheme;
  FCancel.Font.Assign(FForm.Font);
  FCancel.Invalidate;
  ApplyWindowChrome(FForm.Handle, FTheme, FTheme.Back);
end;

procedure TUpdateProgressWindow.PlaceNearTray;
var
  WorkArea: TRect;
begin
  WorkArea := Screen.WorkAreaRect;
  FForm.Left := WorkArea.Right - FForm.Width - Scale(12);
  FForm.Top := WorkArea.Bottom - FForm.Height - Scale(12);
end;

procedure TUpdateProgressWindow.BarPaint(Sender: TObject);
var
  Canvas: TCanvas;
  R: TRect;
  Radius, Fill, Segment: Integer;
begin
  Canvas := FBar.Canvas;
  R := FBar.ClientRect;
  Radius := R.Height;
  Canvas.Brush.Color := FTheme.Back;
  Canvas.FillRect(R);
  // Track.
  Canvas.Brush.Color := FTheme.Border;
  Canvas.Pen.Color := FTheme.Border;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius);
  Canvas.Brush.Color := FTheme.Accent;
  Canvas.Pen.Color := FTheme.Accent;
  if FMarquee then
  begin
    // A segment running from left to right while the size is unknown.
    Segment := R.Width div 4;
    Canvas.RoundRect(Max(R.Left, FMarqueePos - Segment), R.Top, Min(R.Right, FMarqueePos),
      R.Bottom, Radius, Radius);
  end
  else if FPercent > 0 then
  begin
    Fill := Max(Radius, R.Width * FPercent div 100);
    Canvas.RoundRect(R.Left, R.Top, R.Left + Fill, R.Bottom, Radius, Radius);
  end;
end;

procedure TUpdateProgressWindow.TimerTick(Sender: TObject);
begin
  Inc(FMarqueePos, Scale(6));
  if FMarqueePos > FBar.Width + FBar.Width div 4 then
    FMarqueePos := 0;
  FBar.Invalidate;
end;

procedure TUpdateProgressWindow.Start(const Version: string);
begin
  FPercent := -1;
  ApplyTheme;
  FForm.Caption := T('Обновление LayoutSwitcher', 'LayoutSwitcher update');
  FTitle.Caption := Format(T('Загрузка версии %s', 'Downloading version %s'), [Version]);
  FStatus.Caption := T('Подключение…', 'Connecting…');
  FCancel.Caption := T('Отмена', 'Cancel');
  FCancel.Enabled := True;
  FMarquee := True;
  FMarqueePos := 0;
  FTimer.Enabled := True;
  ShowWindow;
end;

procedure TUpdateProgressWindow.SetProgress(ReceivedKB, TotalKB: Int64);
begin
  if TotalKB > 0 then
  begin
    FMarquee := False;
    FTimer.Enabled := False;
    FPercent := ReceivedKB * 100 div TotalKB;
  end
  else
    FPercent := -1;
  FStatus.Caption := FormatDownloadProgress(ReceivedKB, TotalKB);
  FBar.Invalidate;
end;

procedure TUpdateProgressWindow.ShowInstalling;
begin
  FMarquee := False;
  FTimer.Enabled := False;
  FPercent := 100;
  FBar.Invalidate;
  FStatus.Caption := T('Запуск установки…', 'Starting the installer…');
  FCancel.Enabled := False;
  FForm.Update;
end;

procedure TUpdateProgressWindow.ShowWindow;
begin
  if not FForm.Visible then
    PlaceNearTray;
  FForm.Show;
  FForm.BringToFront;
end;

procedure TUpdateProgressWindow.Close;
begin
  FTimer.Enabled := False;
  FForm.Hide;
end;

procedure TUpdateProgressWindow.CancelClick(Sender: TObject);
begin
  FCancel.Enabled := False;
  FStatus.Caption := T('Отмена…', 'Cancelling…');
  if Assigned(FOnCancel) then
    FOnCancel(Self);
end;

procedure TUpdateProgressWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Closing only hides the window; the download continues.
  Action := caHide;
end;

{ What's new }

type
  TReleaseNotesDialog = class(TForm)
  private
    FTheme: TUiTheme;
    procedure OkClick(Sender: TObject);
    procedure LaterClick(Sender: TObject);
    procedure DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure NotesEnter(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    Notes: TRichEdit;
  end;

procedure TReleaseNotesDialog.CreateWnd;
begin
  inherited;
  ApplyWindowChrome(Handle, FTheme, FTheme.Back);
end;

procedure TReleaseNotesDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TReleaseNotesDialog.LaterClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TReleaseNotesDialog.DialogKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      ModalResult := mrCancel;
    VK_RETURN:
      ModalResult := mrOk;
  end;
end;

procedure TReleaseNotesDialog.NotesEnter(Sender: TObject);
begin
  HideCaret(Notes.Handle);
end;

// The notes usually start with "## LayoutSwitcher 2.4.0": the window title
// already says it.
function WithoutVersionHeading(const Notes, Version: string): string;
var
  Lines: TArray<string>;
  First: Integer;
begin
  Lines := Notes.Replace(#13#10, #10).Split([#10]);
  First := 0;
  while (First < Length(Lines)) and (Trim(Lines[First]) = '') do
    Inc(First);
  if (First < Length(Lines)) and Lines[First].TrimLeft.StartsWith('#') and
     Lines[First].Contains(Version) then
    Inc(First);
  Result := string.Join(#10, Copy(Lines, First, MaxInt));
end;

function ShowReleaseNotes(const Version, Notes: string; Installable: Boolean): Boolean;
var
  Form: TReleaseNotesDialog;
  Header, Body, Footer: TPanel;
  Badge, Title, Subtitle, Why: TLabel;
  Ok, Later: TFlatButton;
  Text, Current: string;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, Screen.PixelsPerInch, 96);
  end;

  function NewPanel(AParent: TWinControl; AAlign: TAlign; ATop: Integer): TPanel;
  begin
    Result := TPanel.Create(Form);
    Result.Parent := AParent;
    Result.Top := ATop;
    Result.Align := AAlign;
    Result.BevelOuter := bvNone;
    Result.ParentBackground := False;
    Result.ShowCaption := False;
  end;

  function NewLabel(AParent: TWinControl; ATop, Size: Integer; Bold: Boolean;
    Color: TColor; Display: Boolean = False): TLabel;
  begin
    Result := TLabel.Create(Form);
    Result.Parent := AParent;
    Result.Top := ATop;
    Result.Align := alTop;
    Result.ShowAccelChar := False;
    Result.Font.Name := ModernFontName(Display);
    Result.Font.Size := Size;
    if Bold then
      Result.Font.Style := [fsBold];
    Result.Font.Color := Color;
  end;

begin
  Form := TReleaseNotesDialog.CreateNew(nil);
  try
    Form.FTheme := CurrentUiTheme;
    Form.BorderStyle := bsSizeable;
    Form.BorderIcons := [biSystemMenu];
    Form.Position := poScreenCenter;
    Form.FormStyle := fsStayOnTop;
    Form.KeyPreview := True;
    Form.OnKeyDown := Form.DialogKeyDown;
    Form.Font.Name := ModernFontName;
    Form.Font.Size := 9;
    Form.Color := Form.FTheme.Back;
    Form.Caption := T('Обновление LayoutSwitcher', 'LayoutSwitcher update');
    Form.ClientWidth := S(580);
    Form.ClientHeight := S(480);
    Form.Constraints.MinWidth := S(420);
    Form.Constraints.MinHeight := S(320);

    Footer := NewPanel(Form, alBottom, 0);
    Footer.Height := S(64);
    Footer.Color := Form.FTheme.Footer;
    Footer.Padding.SetBounds(S(24), S(16), S(24), S(16));

    Ok := TFlatButton.Create(Form);
    Ok.Parent := Footer;
    Ok.Left := 2000;
    Ok.Align := alRight;
    Ok.Primary := True;
    Ok.Theme := Form.FTheme;
    Ok.Font.Assign(Form.Font);
    if Installable then
    begin
      Ok.Caption := T('Установить', 'Install');
      Ok.Width := S(130);
    end
    else
    begin
      Ok.Caption := T('Открыть страницу загрузки', 'Open download page');
      Ok.Width := S(210);
    end;
    Ok.OnClick := Form.OkClick;

    Later := TFlatButton.Create(Form);
    Later.Parent := Footer;
    Later.Left := 1000;
    Later.Align := alRight;
    Later.AlignWithMargins := True;
    Later.Margins.SetBounds(0, 0, S(8), 0);
    Later.Width := S(100);
    Later.Theme := Form.FTheme;
    Later.Font.Assign(Form.Font);
    Later.Caption := T('Позже', 'Later');
    Later.OnClick := Form.LaterClick;

    Header := NewPanel(Form, alTop, 0);
    Header.Color := Form.FTheme.Back;
    Header.Padding.SetBounds(S(24), S(20), S(24), S(8));
    Badge := NewLabel(Header, 0, 8, True, Form.FTheme.Accent);
    Badge.Caption := T('ДОСТУПНО ОБНОВЛЕНИЕ', 'UPDATE AVAILABLE');
    Title := NewLabel(Header, 100, 18, True, Form.FTheme.Text, True);
    Title.Caption := 'LayoutSwitcher ' + Version;
    Subtitle := NewLabel(Header, 200, 9, False, Form.FTheme.Muted);
    Current := GetExecutableVersion;
    if Current <> '' then
      Subtitle.Caption := Format(T('Сейчас установлена версия %s. Что нового:',
        'You have version %s. What''s new:'), [Current])
    else
      Subtitle.Caption := T('Что нового:', 'What''s new:');
    Header.Height := Header.Padding.Top + Header.Padding.Bottom + Badge.Height +
      Title.Height + Subtitle.Height + S(4);
    if not Installable then
    begin
      // Otherwise "nothing happens" for a copy started from a build folder.
      // Between the title and "What's new"; three lines at most.
      Why := NewLabel(Header, 150, 9, False, Form.FTheme.Accent);
      Why.AlignWithMargins := True;
      Why.Margins.SetBounds(0, S(6), 0, S(6));
      Why.AutoSize := False;
      Why.WordWrap := True;
      Why.Height := S(54);
      Why.Caption := T('Эту копию нельзя обновить автоматически: сама обновляется только ' +
        'программа, установленная установщиком, а эта запущена из другой папки (или к ' +
        'релизу не приложен установщик). Кнопка откроет страницу загрузки.',
        'This copy cannot update itself: only a program installed by the installer ' +
        'does, and this one runs from another folder (or the release has no installer). ' +
        'The button opens the download page.');
      Header.Height := Header.Height + Why.Height + S(12);
    end;

    Body := NewPanel(Form, alClient, 0);
    Body.Color := Form.FTheme.Back;
    Body.Padding.SetBounds(S(24), S(8), S(16), S(8));
    Form.Notes := TRichEdit.Create(Form);
    Form.Notes.Parent := Body;
    Form.Notes.Align := alClient;
    Form.Notes.BorderStyle := bsNone;
    Form.Notes.ReadOnly := True;
    Form.Notes.PlainText := False;
    Form.Notes.ScrollBars := ssVertical;
    Form.Notes.WantReturns := False;
    Form.Notes.HideSelection := True;
    Form.Notes.Color := Form.FTheme.Back;
    Form.Notes.OnEnter := Form.NotesEnter;
    Text := Trim(WithoutVersionHeading(Notes, Version));
    if Text = '' then
      Text := T('Описание изменений не опубликовано.', 'No release notes were published.');
    RenderMarkdown(Form.Notes, Text, Form.FTheme, ModernFontName);
    // Scroll bar in the colours of the theme.
    if Form.FTheme.Dark then
      SetWindowTheme(Form.Notes.Handle, 'DarkMode_Explorer', nil)
    else
      SetWindowTheme(Form.Notes.Handle, 'Explorer', nil);

    Form.ActiveControl := nil;
    Result := Form.ShowModal = mrOk;
  finally
    Form.Free;
  end;
end;

end.
