unit uDictationPage;

// The "Dictation" page of the settings window: the list of recognition
// models with their pros and cons, download and removal of a model, the
// cloud service fields.  Built in code on a page of the settings window.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls,
  uSettings, uSpeechModels, uModernUI;

type
  TDictationPage = class(TComponent)
  private
    FPage: TTabSheet;
    FWnd: HWND;
    FLoading: Boolean;
    FModelId: string;
    FInstall: TSpeechInstallThread;
    FInstallIndex: Integer;
    FStage: TSpeechInstallStage;
    FPercent: Integer;       // -1 when unknown
    FSpeedKB: Integer;
    FLastError: string;
    FTheme: TUiTheme;
    FGesture: TLSGesture;
    FOnChange: TNotifyEvent;
    FOnUnloadModel: TNotifyEvent;
    lblIntro: TLabel;
    lbModels: TListBox;
    lblPros: TLabel;
    lblCons: TLabel;
    lblStatus: TLabel;
    pbDownload: TProgressBar;
    btnDownload: TButton;
    btnDelete: TButton;
    lblCloudUrl, lblCloudKey, lblCloudModel: TLabel;
    edCloudUrl, edCloudKey, edCloudModel: TEdit;
    function S(Value: Integer): Integer;
    function SelectedIndex: Integer;
    procedure WndMethod(var Message: TMessage);
    procedure ModelsDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    procedure ModelsClick(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure CloudExit(Sender: TObject);
    procedure UpdateDetails;
    function DownloadDetails: string;
    procedure Changed;
    function MakeLabel(X, Y, W, H: Integer; WordWrap: Boolean): TLabel;
    function MakeEdit(X, Y, W: Integer): TEdit;
  public
    constructor CreatePage(AOwner: TComponent; Page: TTabSheet);
    destructor Destroy; override;
    procedure Load(const Settings: TLSSettings);
    procedure Save(var Settings: TLSSettings);
    procedure ApplyLanguage;
    // The download runs (the window should not be closed by the user).
    function Busy: Boolean;
    // Raised when the user changed a value: Save and apply the settings.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Before a model is deleted: its files must not be in use.
    property OnUnloadModel: TNotifyEvent read FOnUnloadModel write FOnUnloadModel;
  end;

implementation

uses
  System.Math, uLocale;

const
  WM_SPEECH_PROGRESS = WM_APP + 40;
  WM_SPEECH_DONE = WM_APP + 41;
  ITEM_HEIGHT = 38;

{ TDictationPage }

constructor TDictationPage.CreatePage(AOwner: TComponent; Page: TTabSheet);
var
  I, Y: Integer;
begin
  inherited Create(AOwner);
  FPage := Page;
  FWnd := AllocateHWnd(WndMethod);
  FInstallIndex := -1;
  FTheme := CurrentUiTheme(True);
  Y := 8;
  lblIntro := MakeLabel(12, Y, 480, 32, True);
  Inc(Y, 40);
  lbModels := TListBox.Create(Self);
  lbModels.Parent := FPage;
  lbModels.SetBounds(S(12), S(Y), S(480), S(ITEM_HEIGHT * Length(SpeechModels) + 4));
  lbModels.Style := lbOwnerDrawFixed;
  lbModels.ItemHeight := S(ITEM_HEIGHT);
  lbModels.OnDrawItem := ModelsDrawItem;
  lbModels.OnClick := ModelsClick;
  for I := Low(SpeechModels) to High(SpeechModels) do
    lbModels.Items.Add(SpeechModels[I].Id);
  Inc(Y, ITEM_HEIGHT * Length(SpeechModels) + 12);
  lblPros := MakeLabel(12, Y, 480, 46, True);
  Inc(Y, 48);
  lblCons := MakeLabel(12, Y, 480, 46, True);
  Inc(Y, 52);
  // Local models: status, download and removal.
  lblStatus := MakeLabel(12, Y + 4, 300, 17, False);
  lblStatus.EllipsisPosition := epEndEllipsis;
  pbDownload := TProgressBar.Create(Self);
  pbDownload.Parent := FPage;
  pbDownload.SetBounds(S(12), S(Y + 26), S(300), S(10));
  pbDownload.Visible := False;
  btnDelete := TButton.Create(Self);
  btnDelete.Parent := FPage;
  btnDelete.SetBounds(S(322), S(Y), S(80), S(25));
  btnDelete.OnClick := DeleteClick;
  btnDownload := TButton.Create(Self);
  btnDownload.Parent := FPage;
  btnDownload.SetBounds(S(408), S(Y), S(84), S(25));
  btnDownload.OnClick := DownloadClick;
  // Cloud service: in the same place.
  lblCloudUrl := MakeLabel(12, Y + 3, 220, 17, False);
  edCloudUrl := MakeEdit(240, Y, 252);
  lblCloudKey := MakeLabel(12, Y + 31, 220, 17, False);
  edCloudKey := MakeEdit(240, Y + 28, 252);
  edCloudKey.PasswordChar := '*';
  lblCloudModel := MakeLabel(12, Y + 59, 220, 17, False);
  edCloudModel := MakeEdit(240, Y + 56, 252);
  ApplyLanguage;
end;

destructor TDictationPage.Destroy;
begin
  if FInstall <> nil then
  begin
    FInstall.Terminate;
    FInstall.WaitFor;
    FreeAndNil(FInstall);
  end;
  DeallocateHWnd(FWnd);
  inherited;
end;

function TDictationPage.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

function TDictationPage.MakeLabel(X, Y, W, H: Integer; WordWrap: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FPage;
  Result.AutoSize := False;
  Result.WordWrap := WordWrap;
  Result.SetBounds(S(X), S(Y), S(W), S(H));
end;

function TDictationPage.MakeEdit(X, Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := FPage;
  Result.SetBounds(S(X), S(Y), S(W), S(21));
  Result.OnExit := CloudExit;
end;

function TDictationPage.Busy: Boolean;
begin
  Result := FInstall <> nil;
end;

function TDictationPage.SelectedIndex: Integer;
begin
  Result := lbModels.ItemIndex;
  if (Result < 0) or (Result > High(SpeechModels)) then
    Result := FindSpeechModel(DEFAULT_SPEECH_MODEL);
end;

procedure TDictationPage.ApplyLanguage;
var
  Hint: string;
begin
  if FGesture <> lgNone then
    Hint := GestureName(FGesture)
  else
    Hint := T('сочетание (вкладка «Сочетания»)', 'the shortcut (Shortcuts tab)');
  lblIntro.Caption := Format(T(
    'Нажмите %s, продиктуйте текст и нажмите ещё раз: текст появится там, где стоит ' +
    'курсор. Esc отменяет. Выберите модель распознавания:',
    'Press %s, dictate and press it again: the text appears at the cursor. ' +
    'Esc cancels. Choose the recognition model:'), [Hint]);
  lblCloudUrl.Caption := T('Адрес API:', 'API address:');
  lblCloudKey.Caption := T('Ключ API:', 'API key:');
  lblCloudModel.Caption := T('Модель:', 'Model:');
  btnDelete.Caption := T('Удалить', 'Delete');
  lbModels.Invalidate;
  UpdateDetails;
end;

procedure TDictationPage.Load(const Settings: TLSSettings);
var
  Index: Integer;
begin
  FLoading := True;
  try
    FModelId := Settings.DictationModel;
    FGesture := Settings.GestureForAction(laDictate);
    Index := FindSpeechModel(FModelId);
    if Index < 0 then
      Index := FindSpeechModel(DEFAULT_SPEECH_MODEL);
    lbModels.ItemIndex := Index;
    edCloudUrl.Text := Settings.DictationCloudUrl;
    edCloudKey.Text := Settings.DictationCloudKey;
    edCloudModel.Text := Settings.DictationCloudModel;
  finally
    FLoading := False;
  end;
  ApplyLanguage;
end;

procedure TDictationPage.Save(var Settings: TLSSettings);
begin
  Settings.DictationModel := SpeechModels[SelectedIndex].Id;
  Settings.DictationCloudUrl := Trim(edCloudUrl.Text);
  if Settings.DictationCloudUrl = '' then
    Settings.DictationCloudUrl := DEFAULT_SPEECH_CLOUD_URL;
  Settings.DictationCloudKey := Trim(edCloudKey.Text);
  Settings.DictationCloudModel := Trim(edCloudModel.Text);
  if Settings.DictationCloudModel = '' then
    Settings.DictationCloudModel := DEFAULT_SPEECH_CLOUD_MODEL;
end;

procedure TDictationPage.Changed;
begin
  if not FLoading and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TDictationPage.ModelsClick(Sender: TObject);
begin
  UpdateDetails;
  if SpeechModels[SelectedIndex].Id <> FModelId then
  begin
    FModelId := SpeechModels[SelectedIndex].Id;
    Changed;
  end;
end;

procedure TDictationPage.CloudExit(Sender: TObject);
begin
  Changed;
end;

procedure TDictationPage.ModelsDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Model: TSpeechModel;
  Title, Info: string;
  Selected: Boolean;
  R: TRect;
begin
  Canvas := lbModels.Canvas;
  Model := SpeechModels[Index];
  Selected := odSelected in State;
  if Selected then
    Canvas.Brush.Color := FTheme.Hover
  else
    Canvas.Brush.Color := clWindow;
  Canvas.FillRect(Rect);
  if Selected then
  begin
    // Accent mark of the chosen model, as in Windows 11 lists.
    Canvas.Brush.Color := FTheme.Accent;
    Canvas.FillRect(System.Types.Rect(Rect.Left + S(2), Rect.Top + S(9), Rect.Left + S(5),
      Rect.Bottom - S(9)));
  end;
  Canvas.Brush.Style := bsClear;
  Title := Model.Name;
  if Model.Recommended then
    Title := Title + T('  · рекомендуется', '  · recommended');
  if Model.IsCloud then
    Info := T('Без загрузки · запись отправляется в интернет',
      'No download · the recording is sent over the internet')
  else
  begin
    Info := Format(T('Загрузка %d МБ · %s', 'Download %d MB · %s'), [Model.DownloadMB,
      Model.Languages]);
    if IsSpeechModelInstalled(Model) then
      Info := T('✓ Скачана · ', '✓ Downloaded · ') + Info;
  end;
  R := System.Types.Rect(Rect.Left + S(14), Rect.Top + S(3), Rect.Right - S(6), Rect.Top + S(20));
  Canvas.Font.Assign(lbModels.Font);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FTheme.Text;
  DrawText(Canvas.Handle, PChar(Title), -1, R, DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX);
  R := System.Types.Rect(Rect.Left + S(14), Rect.Top + S(20), Rect.Right - S(6), Rect.Bottom - S(2));
  Canvas.Font.Style := [];
  Canvas.Font.Color := FTheme.Muted;
  DrawText(Canvas.Handle, PChar(Info), -1, R, DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX);
  if odFocused in State then
    Canvas.DrawFocusRect(Rect);
end;

procedure TDictationPage.UpdateDetails;
const
  StageText: array[TSpeechInstallStage] of record Ru, En: string end = (
    (Ru: 'Загрузка движка распознавания…'; En: 'Downloading the recognition engine…'),
    (Ru: 'Загрузка модели…'; En: 'Downloading the model…'),
    (Ru: 'Проверка файла…'; En: 'Checking the file…'),
    (Ru: 'Распаковка…'; En: 'Unpacking…'));
var
  Model: TSpeechModel;
  Installed, Cloud, Downloading: Boolean;
begin
  if lbModels = nil then
    Exit;
  Model := SpeechModels[SelectedIndex];
  lblPros.Caption := T('Плюсы: ', 'Pros: ') + Model.Pros;
  lblCons.Caption := T('Минусы: ', 'Cons: ') + Model.Cons;
  Cloud := Model.IsCloud;
  Installed := IsSpeechModelInstalled(Model);
  Downloading := FInstall <> nil;
  lblCloudUrl.Visible := Cloud;
  edCloudUrl.Visible := Cloud;
  lblCloudKey.Visible := Cloud;
  edCloudKey.Visible := Cloud;
  lblCloudModel.Visible := Cloud;
  edCloudModel.Visible := Cloud;
  lblStatus.Visible := not Cloud or (Downloading and (FInstallIndex <> SelectedIndex));
  btnDownload.Visible := not Cloud;
  btnDelete.Visible := not Cloud and Installed and not Downloading;
  pbDownload.Visible := Downloading and not Cloud;
  if Downloading then
  begin
    btnDownload.Caption := T('Отмена', 'Cancel');
    btnDownload.Enabled := True;
    lblStatus.Caption := T(StageText[FStage].Ru, StageText[FStage].En) + DownloadDetails;
  end
  else if Cloud then
    lblStatus.Caption := ''
  else if Installed then
  begin
    btnDownload.Caption := T('Скачать', 'Download');
    btnDownload.Enabled := False;
    lblStatus.Caption := Format(T('Модель скачана, на диске %d МБ.', 'Downloaded, %d MB on disk.'),
      [SpeechModelDiskMB(Model)]);
  end
  else
  begin
    btnDownload.Caption := T('Скачать', 'Download');
    btnDownload.Enabled := True;
    if FLastError <> '' then
      lblStatus.Caption := T('Ошибка: ', 'Error: ') + FLastError
    else if not IsSpeechEngineInstalled then
      lblStatus.Caption := Format(T('Не скачана. Вместе с движком около %d МБ.',
        'Not downloaded. About %d MB with the engine.'), [Model.DownloadMB + 22])
    else
      lblStatus.Caption := Format(T('Не скачана (%d МБ).', 'Not downloaded (%d MB).'),
        [Model.DownloadMB]);
  end;
  lblStatus.Hint := lblStatus.Caption;
  lblStatus.ShowHint := True;
end;

// " 45% · 2,5 MB/s · about 40 s left" while a file is downloaded.
function TDictationPage.DownloadDetails: string;
var
  TotalMB, LeftSec: Integer;
begin
  Result := '';
  if not (FStage in [sisDownloadEngine, sisDownloadModel]) or (FPercent < 0) then
    Exit;
  Result := Format(' %d%%', [FPercent]);
  if FSpeedKB <= 0 then
    Exit;
  Result := Result + Format(T(' · %.1f МБ/с', ' · %.1f MB/s'), [FSpeedKB / 1024]);
  if FStage = sisDownloadEngine then
    TotalMB := 31
  else
    TotalMB := SpeechModels[FInstallIndex].DownloadMB;
  LeftSec := Round(TotalMB * (100 - FPercent) / 100 * 1024 / FSpeedKB);
  if LeftSec >= 90 then
    Result := Result + Format(T(' · осталось ~%d мин', ' · ~%d min left'), [(LeftSec + 30) div 60])
  else
    Result := Result + Format(T(' · осталось ~%d с', ' · ~%d s left'), [Max(LeftSec, 1)]);
end;

procedure TDictationPage.DownloadClick(Sender: TObject);
begin
  if FInstall <> nil then
  begin
    // Cancel: the thread reports back when it has stopped.
    FInstall.Terminate;
    btnDownload.Enabled := False;
    Exit;
  end;
  FLastError := '';
  FInstallIndex := SelectedIndex;
  FStage := sisDownloadModel;
  if not IsSpeechEngineInstalled then
    FStage := sisDownloadEngine;
  pbDownload.Position := 0;
  pbDownload.Style := pbstNormal;
  FPercent := 0;
  FSpeedKB := 0;
  FInstall := TSpeechInstallThread.Create(SpeechModels[FInstallIndex], FWnd,
    WM_SPEECH_PROGRESS, WM_SPEECH_DONE);
  UpdateDetails;
end;

procedure TDictationPage.DeleteClick(Sender: TObject);
var
  Model: TSpeechModel;
begin
  Model := SpeechModels[SelectedIndex];
  if MessageBox(GetParent(FPage.Handle), PChar(Format(T('Удалить модель «%s» с диска?',
       'Delete the model "%s" from the disk?'), [Model.Name])), 'LayoutSwitcher',
       MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  if Assigned(FOnUnloadModel) then
    FOnUnloadModel(Self);
  if not DeleteSpeechModel(Model) then
    FLastError := T('файлы заняты, попробуйте позже', 'the files are in use, try later');
  lbModels.Invalidate;
  UpdateDetails;
end;

procedure TDictationPage.WndMethod(var Message: TMessage);
var
  ErrorText: PChar;
begin
  case Message.Msg of
    WM_SPEECH_PROGRESS:
      begin
        FStage := TSpeechInstallStage(Message.WParam and $FF);
        FSpeedKB := Integer(Message.WParam shr 8);
        FPercent := Integer(Message.LParam);
        if Integer(Message.LParam) < 0 then
          pbDownload.Style := pbstMarquee
        else
        begin
          pbDownload.Style := pbstNormal;
          pbDownload.Position := Integer(Message.LParam);
        end;
        UpdateDetails;
      end;
    WM_SPEECH_DONE:
      begin
        if FInstall <> nil then
        begin
          FInstall.WaitFor;
          FreeAndNil(FInstall);
        end;
        ErrorText := PChar(Message.LParam);
        if ErrorText <> nil then
        begin
          FLastError := ErrorText;
          StrDispose(ErrorText);
        end;
        pbDownload.Style := pbstNormal;
        lbModels.Invalidate;
        UpdateDetails;
        Changed;
      end;
  else
    Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
  end;
end;

end.
