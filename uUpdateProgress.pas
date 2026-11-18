unit uUpdateProgress;

// Small window that shows the progress of an update download: version,
// progress bar, "1.2 of 4.1 MB (29%)" and a Cancel button.  It appears in
// the bottom-right corner of the work area, next to the tray.  Closing the
// window only hides it; the download goes on.

interface

uses
  Winapi.Windows,
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics;

type
  TUpdateProgressWindow = class
  private
    FForm: TForm;
    FTitle: TLabel;
    FBar: TProgressBar;
    FStatus: TLabel;
    FCancel: TButton;
    FOnCancel: TNotifyEvent;
    FPercent: Integer;
    procedure CancelClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure PlaceNearTray;
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

implementation

uses
  uLocale;

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
  FForm.BorderStyle := bsToolWindow;
  FForm.BorderIcons := [biSystemMenu];
  FForm.FormStyle := fsStayOnTop;
  FForm.Position := poDesigned;
  FForm.Font.Name := 'Segoe UI';
  FForm.Font.Height := -Scale(12);
  FForm.ClientWidth := Scale(380);
  FForm.ClientHeight := Scale(118);
  FForm.OnClose := FormClose;

  FTitle := TLabel.Create(FForm);
  FTitle.Parent := FForm;
  FTitle.SetBounds(Scale(12), Scale(12), Scale(356), Scale(18));
  FTitle.Font.Style := [fsBold];

  FBar := TProgressBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.SetBounds(Scale(12), Scale(38), Scale(356), Scale(18));
  FBar.Min := 0;
  FBar.Max := 100;

  FStatus := TLabel.Create(FForm);
  FStatus.Parent := FForm;
  FStatus.SetBounds(Scale(12), Scale(64), Scale(250), Scale(18));

  FCancel := TButton.Create(FForm);
  FCancel.Parent := FForm;
  FCancel.SetBounds(Scale(278), Scale(80), Scale(90), Scale(28));
  FCancel.Cancel := True;
  FCancel.OnClick := CancelClick;
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

procedure TUpdateProgressWindow.PlaceNearTray;
var
  WorkArea: TRect;
begin
  WorkArea := Screen.WorkAreaRect;
  FForm.Left := WorkArea.Right - FForm.Width - Scale(12);
  FForm.Top := WorkArea.Bottom - FForm.Height - Scale(12);
end;

procedure TUpdateProgressWindow.Start(const Version: string);
begin
  FPercent := -1;
  FForm.Caption := T('LayoutSwitcher — обновление', 'LayoutSwitcher - update');
  FTitle.Caption := Format(T('Загрузка LayoutSwitcher %s', 'Downloading LayoutSwitcher %s'),
    [Version]);
  FStatus.Caption := T('Подключение...', 'Connecting...');
  FCancel.Caption := T('Отмена', 'Cancel');
  FCancel.Enabled := True;
  // Marquee until the size of the file is known.
  FBar.Style := pbstMarquee;
  FBar.Position := 0;
  ShowWindow;
end;

procedure TUpdateProgressWindow.SetProgress(ReceivedKB, TotalKB: Int64);
begin
  if TotalKB > 0 then
  begin
    if FBar.Style <> pbstNormal then
      FBar.Style := pbstNormal;
    FPercent := ReceivedKB * 100 div TotalKB;
    FBar.Position := FPercent;
  end
  else
    FPercent := -1;
  FStatus.Caption := FormatDownloadProgress(ReceivedKB, TotalKB);
end;

procedure TUpdateProgressWindow.ShowInstalling;
begin
  FBar.Style := pbstNormal;
  FBar.Position := 100;
  FStatus.Caption := T('Запуск установки...', 'Starting the installer...');
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
  FForm.Hide;
end;

procedure TUpdateProgressWindow.CancelClick(Sender: TObject);
begin
  FCancel.Enabled := False;
  FStatus.Caption := T('Отмена...', 'Cancelling...');
  if Assigned(FOnCancel) then
    FOnCancel(Self);
end;

procedure TUpdateProgressWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Closing only hides the window; the download continues.
  Action := caHide;
end;

end.
