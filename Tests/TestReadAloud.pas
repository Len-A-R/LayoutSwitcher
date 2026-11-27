unit TestReadAloud;

// Reading the selection aloud: the Alt+Scroll Lock gesture, its default and
// migration, the language of a text and the choice of a voice.

interface

uses
  DUnitX.TestFramework,
  uReadAloud, uSettings, uGestureDetector, uNeuralVoice, uSherpaOnnx, uSpeechModels;

type
  [TestFixture]
  TReadAloudTests = class
  public
    [Test]
    procedure AltScrollLockGesture;
    [Test]
    procedure SettingsAndMigration;
    [Test]
    procedure Languages;
    [Test]
    procedure VoiceChoice;
    [Test]
    procedure Pauses;
    [Test]
    procedure NeuralText;
    [Test]
    procedure NeuralCatalogue;
    [Test]
    procedure MixedLanguages;
    [Test]
    procedure TechnicalText;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils;

procedure TReadAloudTests.AltScrollLockGesture;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    D.KeyEvent(VK_LMENU, False, 1000);
    Assert.AreEqual(Ord(lgAltScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, 1050)));
    D.KeyEvent(VK_SCROLL, True, 1100);
    // Alt released after the combination: not a tap of a double Alt.
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_LMENU, True, 1150)));
    D.KeyEvent(VK_LMENU, False, 1200);
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_LMENU, True, 1250)));
    // Right Alt works too.
    D.KeyEvent(VK_RMENU, False, 3000);
    Assert.AreEqual(Ord(lgAltScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, 3050)));
    D.KeyEvent(VK_SCROLL, True, 3100);
    D.KeyEvent(VK_RMENU, True, 3150);
    // Ctrl + Alt + Scroll Lock is not it.
    D.KeyEvent(VK_LCONTROL, False, 5000);
    D.KeyEvent(VK_LMENU, False, 5010);
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_SCROLL, False, 5050)));
    D.KeyEvent(VK_SCROLL, True, 5100);
    D.KeyEvent(VK_LMENU, True, 5150);
    D.KeyEvent(VK_LCONTROL, True, 5160);
    // Alone it stays dictation.
    Assert.AreEqual(Ord(lgScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, 7000)));
  finally
    D.Free;
  end;
  Assert.AreEqual('Alt + Scroll Lock', GestureName(lgAltScrollLock));
end;

procedure TReadAloudTests.SettingsAndMigration;
var
  S, Loaded: TLSSettings;
  G: TLSActionGestures;
  FileName: string;
  Diagnostics: Boolean;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(Ord(lgAltScrollLock), Ord(S.GestureForAction(laReadAloud)));
  Assert.AreEqual('read_aloud', ActionKeys[laReadAloud]);
  Assert.AreEqual(1, S.ReadAloudSpeed);
  // Settings of 2.5 (version 8) get the new gesture...
  G := S.ActionGestures;
  G[laReadAloud] := lgNone;
  MigrateActionGestures(G, 8);
  Assert.AreEqual(Ord(lgAltScrollLock), Ord(G[laReadAloud]));
  // ...unless the user gave it to another action.
  G := S.ActionGestures;
  G[laReadAloud] := lgNone;
  G[laExplain] := lgAltScrollLock;
  MigrateActionGestures(G, 8);
  Assert.AreEqual(Ord(lgNone), Ord(G[laReadAloud]));
  // A deliberate "disabled" of version 9 stays.
  G[laExplain] := lgPause;
  MigrateActionGestures(G, 9);
  Assert.AreEqual(Ord(lgNone), Ord(G[laReadAloud]));
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-readaloud.ini');
  try
    S.ReadAloudVoiceRu := 'piper:ru-ruslan';
    S.ReadAloudVoiceEn := 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\X';
    S.ReadAloudSpeed := 3;
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual(S.ReadAloudVoiceRu, Loaded.ReadAloudVoiceRu);
    Assert.AreEqual(S.ReadAloudVoiceEn, Loaded.ReadAloudVoiceEn);
    Assert.AreEqual(3, Loaded.ReadAloudSpeed);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TReadAloudTests.Languages;
begin
  Assert.AreEqual(Integer($0419), Integer(TextLanguage('Привет, мир! Hello')));
  Assert.AreEqual(Integer($0409), Integer(TextLanguage('Hello, world! Ок')));
  Assert.AreEqual(Integer($0419), Integer(ParseVoiceLanguage('419')));
  Assert.AreEqual(Integer($0409), Integer(ParseVoiceLanguage('409;9')));
  Assert.AreEqual(0, Integer(ParseVoiceLanguage('')));
  Assert.AreEqual(1, ReadAloudSpeedIndex(7));
  Assert.AreEqual(4, ReadAloudSpeedIndex(4));
end;

procedure TReadAloudTests.VoiceChoice;
var
  Voices: TArray<TReadAloudVoice>;

  function V(const Name: string; Language: Word): TReadAloudVoice;
  begin
    Result.Id := Name;
    Result.Name := Name;
    Result.Language := Language;
  end;

begin
  Voices := [V('Zira', $0409), V('Hazel', $0809), V('Irina', $0419)];
  Assert.AreEqual(2, FindVoiceForLanguage(Voices, $0419));
  Assert.AreEqual(0, FindVoiceForLanguage(Voices, $0409));
  // en-GB only: still English.
  Assert.AreEqual(0, FindVoiceForLanguage([V('Hazel', $0809)], $0409));
  Assert.AreEqual(-1, FindVoiceForLanguage([V('Zira', $0409)], $0419));
end;

procedure TReadAloudTests.Pauses;
var
  X: string;
begin
  X := PrepareSpeech('Привет! Это тест, т. е. проверка.', True);
  Assert.AreEqual('Привет!<silence msec="380"/> Это тест,<silence msec="140"/> то есть ' +
    'проверка.<silence msec="380"/>', X);
  // Initials and "г." do not end a sentence; a dash between words pauses.
  X := PrepareSpeech('В 2024 г. у А. С. Пушкина — юбилей', True);
  Assert.AreEqual('В 2024 г. у А. С. Пушкина <silence msec="200"/>— юбилей.<silence msec="380"/>', X);
  // Lines without a final mark (a heading, list items) and paragraphs.
  X := PrepareSpeech('Список' + sLineBreak + '- молоко' + sLineBreak + sLineBreak + 'Всё...', True);
  Assert.AreEqual('Список.<silence msec="380"/> молоко.<silence msec="380"/><silence msec="750"/> ' +
    'Всё…<silence msec="550"/>', X);
  // XML characters are escaped; "и т. д." at the end keeps its full stop.
  X := PrepareSpeech('If A < B & C, done', False);
  Assert.AreEqual('If A &lt; B &amp; C,<silence msec="140"/> done.<silence msec="380"/>', X);
  Assert.AreEqual('Яблоки и так далее.<silence msec="380"/> Да.<silence msec="380"/>',
    PrepareSpeech('Яблоки и т. д. Да.', True));
  // Markdown marks are not read.
  Assert.AreEqual('Важно.<silence msec="380"/>', PrepareSpeech('**Важно**', True));
end;

procedure TReadAloudTests.NeuralText;
var
  P: TArray<string>;
begin
  P := PrepareNeuralText('Список' + sLineBreak + '- молоко' + sLineBreak + '- хлеб' + sLineBreak +
    sLineBreak + 'Это тест, т. е. проверка — с тире.', True);
  Assert.AreEqual(2, Integer(Length(P)));
  Assert.AreEqual('Список. молоко. хлеб.', P[0]);
  Assert.AreEqual('Это тест, то есть проверка, с тире.', P[1]);
  // The clause terminators of espeak-ng, as piper-phonemize maps them.
  Assert.AreEqual('.', ClausePunctuation(40 or $00080000));
  Assert.AreEqual(',', ClausePunctuation(20 or $00001000 or $00040000));
  Assert.AreEqual('?', ClausePunctuation(40 or $00002000 or $00080000));
  Assert.IsTrue(IsSentenceEnd(45 or $00003000 or $00080000));
  Assert.IsFalse(IsSentenceEnd(20 or $00001000 or $00040000));
  Assert.AreEqual('hɛloʊ', RemoveLanguageFlags('(en)hɛloʊ(ru)'));
end;

procedure TReadAloudTests.NeuralCatalogue;
var
  Packages: TArray<TSpeechPackage>;
  V: TNeuralVoiceInfo;
begin
  // The mirrored C structures of sherpa-onnx 2.0.3 (x64).
  Assert.AreEqual(456, SherpaTtsConfigSize);
  Assert.AreEqual(104, SherpaGenerationConfigSize);
  Assert.AreEqual(2, FindNeuralVoice('piper:ru-dmitri'));
  Assert.IsTrue(NeuralVoices[0].Recommended);
  Assert.AreEqual(-1, FindNeuralVoice('piper:nobody'));
  for V in NeuralVoices do
  begin
    Assert.AreEqual(64, Integer(Length(V.Sha256)));
    Assert.IsTrue(V.License <> '');
  end;
  Packages := NeuralVoicePackages(NeuralVoices[0]);
  Assert.AreEqual(2, Integer(Length(Packages)));
  // Only espeak-ng.dll and its data of the 59 MB archive.
  Assert.AreEqual(2, Integer(Length(Packages[0].Members)));
  Assert.AreEqual('vits-piper-ru_RU-ruslan-medium/ru_RU-ruslan-medium.onnx', Packages[1].Members[0]);
  Assert.IsTrue(Packages[1].Url.EndsWith('tts-models/vits-piper-ru_RU-ruslan-medium.tar.bz2'));
end;

procedure TReadAloudTests.MixedLanguages;
var
  P: TArray<TReadSegment>;
  Ru, En: string;
begin
  // A whole English phrase gets the English voice.
  P := SplitByLanguage('Он сказал: The quick brown fox jumps. И ушёл.');
  Assert.AreEqual(3, Integer(Length(P)));
  Assert.AreEqual('Он сказал:', P[0].Text);
  Assert.AreEqual(Integer($0419), Integer(P[0].Language));
  Assert.AreEqual('The quick brown fox jumps.', P[1].Text);
  Assert.AreEqual(Integer($0409), Integer(P[1].Language));
  Assert.AreEqual('И ушёл.', P[2].Text);
  // Short inserts stay in the Russian phrase.
  P := SplitByLanguage('Нажмите Ctrl+C и откройте Word, 2 раза.');
  Assert.AreEqual(1, Integer(Length(P)));
  Assert.AreEqual(Integer($0419), Integer(P[0].Language));
  // English text with a Russian word: Cyrillic always to the Russian voice.
  P := SplitByLanguage('Say привет to everyone here');
  Assert.AreEqual(3, Integer(Length(P)));
  Assert.AreEqual('Say', P[0].Text);
  Assert.AreEqual(Integer($0409), Integer(P[0].Language));
  Assert.AreEqual('привет', P[1].Text);
  Assert.AreEqual('to everyone here', P[2].Text);
  // The rule is per sentence: an English sentence next to it does not
  // split a Russian one.
  P := SplitByLanguage('Он сказал: We need to ship this feature before Friday. ' +
    'Нажмите Ctrl+C и откройте Word.');
  Assert.AreEqual(3, Integer(Length(P)));
  Assert.AreEqual('Нажмите Ctrl+C и откройте Word.', P[2].Text);
  Assert.AreEqual(Integer($0419), Integer(P[2].Language));
  // Short English text alone stays English.
  P := SplitByLanguage('Thank you!');
  Assert.AreEqual(1, Integer(Length(P)));
  Assert.AreEqual(Integer($0409), Integer(P[0].Language));
  // The single voice of the first builds goes to its language.
  Ru := '';
  En := '';
  MigrateReadAloudVoice('piper:ru-irina', Ru, En);
  Assert.AreEqual('piper:ru-irina', Ru);
  MigrateReadAloudVoice('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enUS_ZiraM', Ru, En);
  Assert.IsTrue(En.EndsWith('ZiraM'));
  Ru := '';
  MigrateReadAloudVoice('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\TTS_MS_RU-RU_IRINA_11.0', Ru, En);
  Assert.IsTrue(Ru.EndsWith('IRINA_11.0'));
end;

procedure TReadAloudTests.TechnicalText;

  function N(const S: string): string;
  begin
    Result := NormalizeTechText(S, True);
  end;

begin
  // Paths, file names, links, sites: skipped with what they leave.
  Assert.AreEqual('Откройте файл.', N('Откройте файл C:\work\LayoutSwitcher\uMain.pas.'));
  Assert.AreEqual('', N('src/components/Button.tsx'));
  Assert.AreEqual('', N('- ./src/app/main.ts'));
  Assert.AreEqual('Ошибка здесь.', N('Ошибка здесь (uMain.pas:3747).'));
  Assert.AreEqual('Изменены и тесты.', N('Изменены uMain.pas, uReadAloud.pas, README.md и тесты.'));
  Assert.AreEqual('В лежит', N('В D:\work\_speech\ лежит'));
  Assert.AreEqual('См. там всё.', N('См. https://github.com/k2-fsa/sherpa-onnx/releases/download/x.tar.bz2, там всё.'));
  Assert.AreEqual('', N('www.example.org/page'));
  Assert.AreEqual('Источник: документация.', N('Источник: learn.microsoft.com/ru-ru/windows/win32/api документация.'));
  Assert.AreEqual('Поиск дал ответ.', N('Поиск https://www.google.com/search?q=delphi+uia&hl=ru дал ответ.'));
  Assert.AreEqual('Пишите.', N('Пишите user@mail.ru.'));
  Assert.AreEqual('Смотрите [документацию].', N('Смотрите [документацию](https://example.com/a_(b)).'));
  Assert.AreEqual('Первая'#13#10#13#10'Вторая', N('Первая'#13#10'docs.github.com'#13#10'Вторая'));
  // Program names and abbreviations are not files.
  Assert.AreEqual('Node.js и ASP.NET, т.е. e.g. done.Now', N('Node.js и ASP.NET, т.е. e.g. done.Now'));
  Assert.AreEqual('Сумма хеш верна', N('Сумма 1d2414ac8921f718ba3188782f80475f525a3d82 верна'));
  Assert.AreEqual('идентификатор', N('{FF48DBA4-60EF-4201-AA87-54103EEF594E}'));
  Assert.AreEqual('read aloud и Read Aloud Voice Ru', N('read_aloud и ReadAloudVoiceRu'));
  // Ordinary text stays.
  Assert.AreEqual('и/или 60 км/ч, 12/05, версия 2.5.0, iPhone.', N('и/или 60 км/ч, 12/05, версия 2.5.0, iPhone.'));
  Assert.AreEqual('Привет, мир! Это обычный текст.', N('Привет, мир! Это обычный текст.'));
  Assert.AreEqual('See for details.', NormalizeTechText('See src/main.ts:7 for details.', False));
end;

initialization
  TDUnitX.RegisterTestFixture(TReadAloudTests);

end.
