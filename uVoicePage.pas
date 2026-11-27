unit uVoicePage;

// The "Read aloud" page of the settings window: the voices (neural ones to
// download and the voices of Windows) with what each is good for, download
// and removal of a neural voice, a sample, the speed.  Built in code on a
// page of the settings window.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, Vcl.ComCtrls,
  uSettings, uSpeechModels, uModernUI, uReadAloud, uNeuralVoice;

type
  TVoiceKind = (vkAuto, vkNeural, vkWindows);

  TVoiceItem = record
    Kind: TVoiceKind;
    Id: string;             // the setting: '', "piper:<id>" or a token id
    Index: Integer;         // NeuralVoices index or the Windows voice index
  end;

  TVoicePage = class(TComponent)
  private
    FPage: TTabSheet;
    FWnd: HWND;
    FReadAloud: TReadAloud;
    FLoading: Boolean;
    FItems: TArray<TVoiceItem>;
    FWindowsVoices: TArray<TReadAloudVoice>;
    // The voice for each language; the list shows the voices of FLanguage.
    FVoiceRu: string;
    FVoiceEn: string;
    FLanguage: Word;
    FInstall: TSpeechInstallThread;
    FInstallItem: Integer;
    FStage: TSpeechInstallStage;
    FPercent: Integer;
    FSpeedKB: Integer;
    FLastError: string;
    FTheme: TUiTheme;
    FGesture: TLSGesture;
    FOnChange: TNotifyEvent;
    lblIntro: TLabel;
    lblLanguage: TLabel;
    cbLanguage: TComboBox;
    lbVoices: TListBox;
    lblDetails: TLabel;
    lblStatus: TLabel;
    pbDownload: TProgressBar;
    btnDownload: TButton;
    btnDelete: TButton;
    lblSpeed: TLabel;
    cbSpeed: TComboBox;
    btnListen: TButton;
    cbResults: TCheckBox;
    function S(Value: Integer): Integer;
    function MakeLabel(X, Y, W, H: Integer; WordWrap: Boolean): TLabel;
    function MakeButton(X, Y, W: Integer; OnClick: TNotifyEvent): TButton;
    function Selected: TVoiceItem;
    procedure FillItems;
    procedure SelectVoice(const Id: string);
    procedure WndMethod(var Message: TMessage);
    procedure VoicesDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    procedure VoicesClick(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ListenClick(Sender: TObject);
    procedure SpeedChange(Sender: TObject);
    procedure LanguageChange(Sender: TObject);
    function CurrentVoice: string;
    procedure UpdateDetails;
    procedure Changed;
  public
    constructor CreatePage(AOwner: TComponent; Page: TTabSheet; ReadAloud: TReadAloud);
    destructor Destroy; override;
    procedure Load(const Settings: TLSSettings);
    procedure Save(var Settings: TLSSettings);
    procedure ApplyLanguage;
    function Busy: Boolean;
    // Raised when the user changed a value: Save and apply the settings.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  System.Math, uLocale;

const
  WM_VOICE_PROGRESS = WM_APP + 42;
  WM_VOICE_DONE = WM_APP + 43;
  ITEM_HEIGHT = 36;

function LanguageName(Language: Word): string;
begin
  case Language and $3FF of
    $19: Result := T('русский', 'Russian');
    $09: Result := T('английский', 'English');
  else
    Result := T('другой язык', 'another language');
  end;
end;

{ TVoicePage }

constructor TVoicePage.CreatePage(AOwner: TComponent; Page: TTabSheet; ReadAloud: TReadAloud);
var
  I: Integer;
begin
  inherited Create(AOwner);
  FPage := Page;
  FReadAloud := ReadAloud;
  FWnd := AllocateHWnd(WndMethod);
  FInstallItem := -1;
  FTheme := CurrentUiTheme(True);
  FLanguage := $0419;
  lblIntro := MakeLabel(12, 8, 480, 32, True);
  // Mixed text: every language is read with its own voice.
  lblLanguage := MakeLabel(12, 47, 220, 17, False);
  cbLanguage := TComboBox.Create(Self);
  cbLanguage.Parent := FPage;
  cbLanguage.Style := csDropDownList;
  cbLanguage.SetBounds(S(240), S(44), S(252), S(21));
  cbLanguage.OnChange := LanguageChange;
  lbVoices := TListBox.Create(Self);
  lbVoices.Parent := FPage;
  lbVoices.SetBounds(S(12), S(74), S(480), S(ITEM_HEIGHT * 4 + 4));
  lbVoices.Style := lbOwnerDrawFixed;
  lbVoices.ItemHeight := S(ITEM_HEIGHT);
  lbVoices.OnDrawItem := VoicesDrawItem;
  lbVoices.OnClick := VoicesClick;
  lblDetails := MakeLabel(12, 228, 480, 46, True);
  lblStatus := MakeLabel(12, 282, 300, 17, False);
  lblStatus.EllipsisPosition := epEndEllipsis;
  pbDownload := TProgressBar.Create(Self);
  pbDownload.Parent := FPage;
  pbDownload.SetBounds(S(12), S(304), S(300), S(10));
  pbDownload.Visible := False;
  btnDelete := MakeButton(322, 278, 80, DeleteClick);
  btnDownload := MakeButton(408, 278, 84, DownloadClick);
  lblSpeed := MakeLabel(12, 329, 220, 17, False);
  cbSpeed := TComboBox.Create(Self);
  cbSpeed.Parent := FPage;
  cbSpeed.Style := csDropDownList;
  cbSpeed.SetBounds(S(240), S(326), S(76), S(21));
  for I := Low(READ_ALOUD_SPEED_NAMES) to High(READ_ALOUD_SPEED_NAMES) do
    cbSpeed.Items.Add(READ_ALOUD_SPEED_NAMES[I]);
  cbSpeed.OnChange := SpeedChange;
  btnListen := MakeButton(392, 324, 100, ListenClick);
  cbResults := TCheckBox.Create(Self);
  cbResults.Parent := FPage;
  cbResults.SetBounds(S(12), S(360), S(480), S(17));
  cbResults.OnClick := SpeedChange;
  ApplyLanguage;
end;

destructor TVoicePage.Destroy;
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

function TVoicePage.S(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Screen.PixelsPerInch, 96);
end;

function TVoicePage.MakeLabel(X, Y, W, H: Integer; WordWrap: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FPage;
  Result.AutoSize := False;
  Result.WordWrap := WordWrap;
  Result.ShowAccelChar := False;
  Result.SetBounds(S(X), S(Y), S(W), S(H));
end;

function TVoicePage.MakeButton(X, Y, W: Integer; OnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FPage;
  Result.SetBounds(S(X), S(Y), S(W), S(25));
  Result.OnClick := OnClick;
end;

function TVoicePage.Busy: Boolean;
begin
  Result := FInstall <> nil;
end;

procedure TVoicePage.FillItems;
var
  Item: TVoiceItem;
  I: Integer;
begin
  FItems := nil;
  Item.Kind := vkAuto;
  Item.Id := '';
  Item.Index := -1;
  FItems := FItems + [Item];
  if NeuralVoicesSupported then
    for I := Low(NeuralVoices) to High(NeuralVoices) do
      if (NeuralVoices[I].Language and $3FF) = (FLanguage and $3FF) then
    begin
      Item.Kind := vkNeural;
      Item.Id := NEURAL_VOICE_PREFIX + NeuralVoices[I].Id;
      Item.Index := I;
      FItems := FItems + [Item];
    end;
  FWindowsVoices := FReadAloud.Voices;
  for I := 0 to High(FWindowsVoices) do
    if (FWindowsVoices[I].Language and $3FF) = (FLanguage and $3FF) then
  begin
    Item.Kind := vkWindows;
    Item.Id := FWindowsVoices[I].Id;
    Item.Index := I;
    FItems := FItems + [Item];
  end;
  lbVoices.Items.BeginUpdate;
  try
    lbVoices.Items.Clear;
    for Item in FItems do
      lbVoices.Items.Add(Item.Id);
  finally
    lbVoices.Items.EndUpdate;
  end;
end;

procedure TVoicePage.SelectVoice(const Id: string);
var
  I: Integer;
begin
  lbVoices.ItemIndex := 0;
  for I := 0 to High(FItems) do
    if SameText(FItems[I].Id, Id) then
      lbVoices.ItemIndex := I;
end;

function TVoicePage.Selected: TVoiceItem;
begin
  if (lbVoices.ItemIndex >= 0) and (lbVoices.ItemIndex <= High(FItems)) then
    Result := FItems[lbVoices.ItemIndex]
  else
    Result := FItems[0];
end;

procedure TVoicePage.ApplyLanguage;
var
  Hint: string;
  I: Integer;
begin
  if FGesture <> lgNone then
    Hint := GestureName(FGesture)
  else
    Hint := T('сочетание (вкладка «Сочетания»)', 'the shortcut (Shortcuts tab)');
  lblIntro.Caption := Format(T(
    'Выделите текст и нажмите %s — программа прочитает его вслух; ещё раз или Esc — ' +
    'остановить. Выберите голос:', 'Select a text and press %s to hear it; press it again ' +
    'or Esc to stop. Choose the voice:'), [Hint]);
  lblSpeed.Caption := T('Скорость чтения:', 'Reading speed:');
  lblLanguage.Caption := T('Голос для текста на языке:', 'Voice for text in:');
  I := Max(cbLanguage.ItemIndex, 0);
  cbLanguage.Items.Clear;
  cbLanguage.Items.Add(T('русском', 'Russian'));
  cbLanguage.Items.Add(T('английском', 'English'));
  cbLanguage.ItemIndex := I;
  btnListen.Caption := T('Прослушать', 'Listen');
  cbResults.Caption := T('Читать вслух ответ «Объяснить» и результат «Перевести»',
    'Read aloud the answer of Explain and the result of Translate');
  btnDelete.Caption := T('Удалить', 'Delete');
  lbVoices.Invalidate;
  UpdateDetails;
end;

procedure TVoicePage.Load(const Settings: TLSSettings);
begin
  FLoading := True;
  try
    FGesture := Settings.GestureForAction(laReadAloud);
    FVoiceRu := Settings.ReadAloudVoiceRu;
    FVoiceEn := Settings.ReadAloudVoiceEn;
    FillItems;
    SelectVoice(CurrentVoice);
    cbSpeed.ItemIndex := ReadAloudSpeedIndex(Settings.ReadAloudSpeed);
    cbResults.Checked := Settings.ReadAloudResults;
  finally
    FLoading := False;
  end;
  ApplyLanguage;
end;

function TVoicePage.CurrentVoice: string;
begin
  if FLanguage = $0419 then
    Result := FVoiceRu
  else
    Result := FVoiceEn;
end;

procedure TVoicePage.LanguageChange(Sender: TObject);
begin
  if cbLanguage.ItemIndex = 1 then
    FLanguage := $0409
  else
    FLanguage := $0419;
  FLastError := '';
  FillItems;
  SelectVoice(CurrentVoice);
  UpdateDetails;
end;

procedure TVoicePage.Save(var Settings: TLSSettings);
begin
  Settings.ReadAloudVoiceRu := FVoiceRu;
  Settings.ReadAloudVoiceEn := FVoiceEn;
  if cbSpeed.ItemIndex >= 0 then
    Settings.ReadAloudSpeed := cbSpeed.ItemIndex;
  Settings.ReadAloudResults := cbResults.Checked;
end;

procedure TVoicePage.Changed;
begin
  if not FLoading and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TVoicePage.VoicesClick(Sender: TObject);
begin
  UpdateDetails;
  if Selected.Id <> CurrentVoice then
  begin
    if FLanguage = $0419 then
      FVoiceRu := Selected.Id
    else
      FVoiceEn := Selected.Id;
    Changed;
  end;
end;

procedure TVoicePage.SpeedChange(Sender: TObject);
begin
  Changed;
end;

procedure TVoicePage.VoicesDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Item: TVoiceItem;
  Voice: TNeuralVoiceInfo;
  Title, Info: string;
  R: TRect;
begin
  Canvas := lbVoices.Canvas;
  if (Index < 0) or (Index > High(FItems)) then
    Exit;
  Item := FItems[Index];
  if odSelected in State then
    Canvas.Brush.Color := FTheme.Hover
  else
    Canvas.Brush.Color := clWindow;
  Canvas.FillRect(Rect);
  if odSelected in State then
  begin
    Canvas.Brush.Color := FTheme.Accent;
    Canvas.FillRect(System.Types.Rect(Rect.Left + S(2), Rect.Top + S(9), Rect.Left + S(5),
      Rect.Bottom - S(9)));
  end;
  Canvas.Brush.Style := bsClear;
  case Item.Kind of
    vkAuto:
      begin
        Title := T('Автоматически', 'Automatic');
        Info := T('Скачанный нейросетевой голос, а если его нет — голос Windows',
          'A downloaded neural voice, otherwise a Windows voice');
      end;
    vkNeural:
      begin
        Voice := NeuralVoices[Item.Index];
        Title := Voice.Name + T('  · нейросетевой', '  · neural');
        if Voice.Recommended then
          Title := Title + T(' · рекомендуется', ' · recommended');
        if Voice.Male then
          Info := T('мужской', 'male')
        else
          Info := T('женский', 'female');
        Info := LanguageName(Voice.Language) + ', ' + Info;
        if IsNeuralVoiceInstalled(Voice) then
          Info := T('✓ Скачан · ', '✓ Downloaded · ') + Info
        else
          Info := Format(T('Загрузка %d МБ · ', 'Download %d MB · '), [Voice.DownloadMB]) + Info;
      end;
  else
    Title := FWindowsVoices[Item.Index].Name;
    Info := T('Голос Windows · ', 'Windows voice · ') + LanguageName(FWindowsVoices[Item.Index].Language);
  end;
  R := System.Types.Rect(Rect.Left + S(14), Rect.Top + S(3), Rect.Right - S(6), Rect.Top + S(20));
  Canvas.Font.Assign(lbVoices.Font);
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

procedure TVoicePage.UpdateDetails;
const
  StageText: array[TSpeechInstallStage] of record Ru, En: string end = (
    (Ru: 'Загрузка движка…'; En: 'Downloading the engine…'),
    (Ru: 'Загрузка…'; En: 'Downloading…'),
    (Ru: 'Проверка файла…'; En: 'Checking the file…'),
    (Ru: 'Распаковка…'; En: 'Unpacking…'),
    (Ru: 'Загрузка транскрипции (espeak-ng)…'; En: 'Downloading the phonemizer (espeak-ng)…'),
    (Ru: 'Загрузка голоса…'; En: 'Downloading the voice…'));
var
  Item: TVoiceItem;
  Voice: TNeuralVoiceInfo;
  Installed, Downloading, Neural: Boolean;
begin
  if (lbVoices = nil) or (Length(FItems) = 0) then
    Exit;
  Item := Selected;
  Neural := Item.Kind = vkNeural;
  Downloading := FInstall <> nil;
  Installed := Neural and IsNeuralVoiceInstalled(NeuralVoices[Item.Index]);
  case Item.Kind of
    vkAuto:
      lblDetails.Caption := T('Первый скачанный нейросетевой голос этого языка, иначе голос ' +
        'Windows. В тексте на двух языках каждая часть читается голосом своего языка.',
        'The first downloaded neural voice of this language, otherwise a Windows voice. A text ' +
        'in two languages is read with the voice of each language.');
    vkNeural:
      lblDetails.Caption := T('Естественное звучание, паузы и интонация по знакам препинания. ' +
        'Работает на компьютере, текст никуда не отправляется. Голос: ',
        'Natural sound, pauses and intonation by punctuation. Runs on the computer, the text is ' +
        'not sent anywhere. Voice: ') + NeuralVoices[Item.Index].License + '.';
  else
    lblDetails.Caption := T('Уже установлен в Windows, ничего скачивать не нужно. Звучит ' +
      'заметно механичнее нейросетевых голосов.', 'Already installed in Windows, nothing to ' +
      'download. Sounds noticeably more mechanical than neural voices.');
  end;
  btnDownload.Visible := Neural or Downloading;
  btnDelete.Visible := Neural and Installed and not Downloading;
  lblStatus.Visible := Neural or Downloading;
  pbDownload.Visible := Downloading;
  btnListen.Enabled := not Neural or Installed;
  if Downloading then
  begin
    btnDownload.Caption := T('Отмена', 'Cancel');
    btnDownload.Enabled := True;
    lblStatus.Caption := T(StageText[FStage].Ru, StageText[FStage].En);
    if (FPercent >= 0) and (FStage in [sisDownloadEngine, sisDownloadPhonemizer, sisDownloadVoice]) then
    begin
      lblStatus.Caption := lblStatus.Caption + Format(' %d%%', [FPercent]);
      if FSpeedKB > 0 then
        lblStatus.Caption := lblStatus.Caption + Format(T(' · %.1f МБ/с', ' · %.1f MB/s'),
          [FSpeedKB / 1024]);
    end;
  end
  else if Neural then
  begin
    Voice := NeuralVoices[Item.Index];
    btnDownload.Caption := T('Скачать', 'Download');
    btnDownload.Enabled := not Installed;
    if Installed then
      lblStatus.Caption := Format(T('Голос скачан, на диске %d МБ.', 'Downloaded, %d MB on disk.'),
        [NeuralVoiceDiskMB(Voice)])
    else if FLastError <> '' then
      lblStatus.Caption := T('Ошибка: ', 'Error: ') + FLastError
    else if NeuralVoiceDownloadMB(Voice) > Voice.DownloadMB then
      lblStatus.Caption := Format(T('Не скачан. В первый раз около %d МБ (с движком и ' +
        'транскрипцией).', 'Not downloaded. About %d MB the first time (with the engine and ' +
        'the phonemizer).'), [NeuralVoiceDownloadMB(Voice)])
    else
      lblStatus.Caption := Format(T('Не скачан (%d МБ).', 'Not downloaded (%d MB).'),
        [Voice.DownloadMB]);
  end;
  lblStatus.Hint := lblStatus.Caption;
  lblStatus.ShowHint := True;
end;

procedure TVoicePage.DownloadClick(Sender: TObject);
var
  Item: TVoiceItem;
begin
  if FInstall <> nil then
  begin
    // Cancel: the thread reports back when it has stopped.
    FInstall.Terminate;
    btnDownload.Enabled := False;
    Exit;
  end;
  Item := Selected;
  if Item.Kind <> vkNeural then
    Exit;
  FLastError := '';
  FInstallItem := lbVoices.ItemIndex;
  FStage := sisDownloadVoice;
  FPercent := 0;
  FSpeedKB := 0;
  pbDownload.Position := 0;
  pbDownload.Style := pbstNormal;
  FInstall := TSpeechInstallThread.CreatePackages(NeuralVoicePackages(NeuralVoices[Item.Index]),
    True, FWnd, WM_VOICE_PROGRESS, WM_VOICE_DONE);
  UpdateDetails;
end;

procedure TVoicePage.DeleteClick(Sender: TObject);
var
  Voice: TNeuralVoiceInfo;
begin
  if Selected.Kind <> vkNeural then
    Exit;
  Voice := NeuralVoices[Selected.Index];
  if MessageBox(GetParent(FPage.Handle), PChar(Format(T('Удалить голос «%s» с диска?',
       'Delete the voice "%s" from the disk?'), [Voice.Name])), 'LayoutSwitcher',
       MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  // Its files must not be in use.
  FReadAloud.Stop;
  FReadAloud.Unload;
  if not DeleteNeuralVoice(Voice) then
    FLastError := T('файлы заняты, попробуйте позже', 'the files are in use, try later');
  lbVoices.Invalidate;
  UpdateDetails;
end;

procedure TVoicePage.ListenClick(Sender: TObject);
var
  Item: TVoiceItem;
  Language: Word;
  Sample, ErrorText: string;
  Speaking: Boolean;
begin
  Item := Selected;
  Language := FLanguage;
  if (Language and $3FF) = $19 then
    Sample := 'Привет! Так звучит этот голос. Выделите любой текст и нажмите сочетание ' +
      'клавиш — я прочитаю его вслух, с паузами и интонацией.'
  else
    Sample := 'Hello! This is how this voice sounds. Select any text and press the shortcut, ' +
      'and I will read it aloud.';
  if FReadAloud.Speaking then
  begin
    FReadAloud.Stop;
    Exit;
  end;
  if Language = $0419 then
    Speaking := FReadAloud.Speak(Sample, Item.Id, FVoiceEn, Max(cbSpeed.ItemIndex, 0), ErrorText)
  else
    Speaking := FReadAloud.Speak(Sample, FVoiceRu, Item.Id, Max(cbSpeed.ItemIndex, 0), ErrorText);
  if not Speaking then
    MessageBox(GetParent(FPage.Handle), PChar(ErrorText), 'LayoutSwitcher', MB_OK or MB_ICONWARNING);
end;

procedure TVoicePage.WndMethod(var Message: TMessage);
var
  ErrorText: PChar;
begin
  case Message.Msg of
    WM_VOICE_PROGRESS:
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
    WM_VOICE_DONE:
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
        lbVoices.Invalidate;
        UpdateDetails;
        Changed;
      end;
  else
    Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
  end;
end;

end.
