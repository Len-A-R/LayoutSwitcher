unit TestFeatures22;

// Tests for the 2.2 features: automatic corrections, templates, web lookups,
// settings export/import and update assets.

interface

uses
  DUnitX.TestFramework,
  uSettings, uTextTools, uConversionChain, uGestureDetector;

type
  [TestFixture]
  TAutoCorrectionTests = class
  public
    [Test]
    [TestCase('word', 'пРИВЕТ,Привет')]
    [TestCase('latin', 'hELLO,Hello')]
    [TestCase('punctuation kept', 'пРИВЕТ!,Привет!')]
    procedure FixesCapsLockMistake(const Input, Expected: string);
    [Test]
    procedure IgnoresNormalWords;
    [Test]
    [TestCase('russian', 'ПРивет,Привет')]
    [TestCase('english', 'HEllo,Hello')]
    [TestCase('punctuation', 'ПРивет!,Привет!')]
    procedure FixesTwoCapitals(const Input, Expected: string);
    [Test]
    procedure TwoCapitalsKeepsExceptionsAndAcronyms;
  end;

  [TestFixture]
  TSnippetTests = class
  public
    [Test]
    procedure ParsesLines;
    [Test]
    procedure ExpandsPlaceholders;
    [Test]
    procedure FindsExactAbbreviationOnly;
  end;

  [TestFixture]
  TLookupTests = class
  public
    [Test]
    procedure PercentEncodesUtf8;
    [Test]
    procedure TranslatesRussianIntoEnglish;
    [Test]
    procedure TranslatesOtherTextIntoRussian;
    [Test]
    procedure BuildsSearchUrls;
  end;

  [TestFixture]
  TReplacementPlanTests = class
  public
    [Test]
    procedure ReplacesWordKeepsSpace;
    [Test]
    procedure AutomaticFixCanBeUndone;
  end;

  [TestFixture]
  TAltGestureTests = class
  private
    FTime: Cardinal;
  public
    [Test]
    procedure DoubleRightAlt;
    [Test]
    procedure DoubleLeftAlt;
    [Test]
    procedure LeftThenRightAltIsNotADoubleTap;
    [Test]
    procedure AltShiftAndAltTabAreIgnored;
    [Test]
    procedure DoubleAltGrIsRightAlt;
    [Test]
    procedure RealCtrlBeforeRightAltIsNotAltGr;
    [Test]
    procedure AltGrWithCharacterIsNotATap;
    [Test]
    procedure FakeCtrlDoesNotBreakPendingTaps;
    [Test]
    procedure AltGrWithFakeRightCtrlFromLog;
    [Test]
    procedure DefaultsAndMigrationByVersion;
  end;

  [TestFixture]
  TSettingsFileTests = class
  public
    [Test]
    procedure ExportImportRoundTrip;
    [Test]
    procedure ImportRejectsForeignFile;
    [Test]
    procedure SetupAssetName;
    [Test]
    procedure FormatsDownloadProgress;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.DateUtils,
  uLocale, uUpdateCheck, uUpdateProgress;

{ TAutoCorrectionTests }

procedure TAutoCorrectionTests.FixesCapsLockMistake(const Input, Expected: string);
begin
  Assert.IsTrue(IsCapsLockMistake(Input));
  Assert.AreEqual(Expected, FixCapsLockMistake(Input));
end;

procedure TAutoCorrectionTests.IgnoresNormalWords;
begin
  Assert.IsFalse(IsCapsLockMistake('Привет'));
  Assert.IsFalse(IsCapsLockMistake('ПРИВЕТ'));
  Assert.IsFalse(IsCapsLockMistake('пР'));       // too short
  Assert.IsFalse(IsCapsLockMistake('мВт'));      // two lower-case letters
  Assert.IsFalse(IsCapsLockMistake('iPHONE15')); // digits
end;

procedure TAutoCorrectionTests.FixesTwoCapitals(const Input, Expected: string);
var
  Fixed: string;
begin
  Assert.IsTrue(FixTwoCapitals(Input, nil, Fixed));
  Assert.AreEqual(Expected, Fixed);
end;

procedure TAutoCorrectionTests.TwoCapitalsKeepsExceptionsAndAcronyms;
var
  Fixed: string;
  Exceptions: TArray<string>;
begin
  Exceptions := ['VMware', 'МБайт'];
  Assert.IsFalse(FixTwoCapitals('VMware', Exceptions, Fixed));
  Assert.IsFalse(FixTwoCapitals('МБайт', Exceptions, Fixed));
  Assert.IsFalse(FixTwoCapitals('ПРИвет', nil, Fixed));  // three capitals
  Assert.IsFalse(FixTwoCapitals('ПРи', nil, Fixed));     // too short
  Assert.IsFalse(FixTwoCapitals('MP3s', nil, Fixed));    // digits
  Assert.IsFalse(FixTwoCapitals('ООО', nil, Fixed));     // acronym
  Assert.IsFalse(FixTwoCapitals('ПрИвет', nil, Fixed));  // not adjacent
end;

{ TSnippetTests }

procedure TSnippetTests.ParsesLines;
var
  Items: TArray<TSnippet>;
begin
  Items := ParseSnippets(';дата={date}' + sLineBreak + '# comment' + sLineBreak +
    '' + sLineBreak + 'no separator' + sLineBreak + 'two words=x' + sLineBreak +
    ';adr=Москва, ул. Ленина = 1');
  Assert.AreEqual<Integer>(2, Length(Items));
  Assert.AreEqual(';дата', Items[0].Abbreviation);
  Assert.AreEqual(';adr', Items[1].Abbreviation);
  Assert.AreEqual('Москва, ул. Ленина = 1', Items[1].Template);
end;

procedure TSnippetTests.ExpandsPlaceholders;
var
  Moment: TDateTime;
begin
  Moment := EncodeDateTime(2026, 11, 18, 9, 5, 0, 0);
  Assert.AreEqual('18.11.2026', ExpandSnippet('{date}', Moment));
  Assert.AreEqual('09:05', ExpandSnippet('{TIME}', Moment));
  Assert.AreEqual('Сегодня 18.11.2026 09:05', ExpandSnippet('Сегодня {datetime}', Moment));
end;

procedure TSnippetTests.FindsExactAbbreviationOnly;
var
  Items: TArray<TSnippet>;
  Template: string;
begin
  Items := ParseSnippets(';дата={date}');
  Assert.IsTrue(FindSnippet(Items, ';дата', Template));
  Assert.AreEqual('{date}', Template);
  Assert.IsFalse(FindSnippet(Items, ';дат', Template));
  Assert.IsFalse(FindSnippet(Items, 'дата', Template));
end;

{ TLookupTests }

procedure TLookupTests.PercentEncodesUtf8;
begin
  Assert.AreEqual('%D0%BC%D0%B8%D1%80%20a-b_c.d~', PercentEncode('мир a-b_c.d~'));
  Assert.AreEqual('a%26b%3Dc', PercentEncode('a&b=c'));
end;

procedure TLookupTests.TranslatesRussianIntoEnglish;
begin
  Assert.AreEqual(
    'https://translate.yandex.ru/?source_lang=ru&target_lang=en&text=%D0%BC%D0%B8%D1%80',
    BuildTranslateUrl(TRANSLATOR_YANDEX, 'мир'));
  Assert.AreEqual('https://www.deepl.com/translator#ru/en/%D0%BC%D0%B8%D1%80',
    BuildTranslateUrl(TRANSLATOR_DEEPL, 'мир'));
end;

procedure TLookupTests.TranslatesOtherTextIntoRussian;
begin
  Assert.AreEqual('https://translate.google.com/?sl=auto&tl=ru&text=hello%20world&op=translate',
    BuildTranslateUrl(TRANSLATOR_GOOGLE, 'hello world'));
end;

procedure TLookupTests.BuildsSearchUrls;
begin
  Assert.AreEqual('https://yandex.ru/search/?text=a%20b', BuildSearchUrl(SEARCH_YANDEX, 'a b'));
  Assert.AreEqual('https://www.google.com/search?q=a', BuildSearchUrl(SEARCH_GOOGLE, 'a'));
  Assert.AreEqual('https://www.bing.com/search?q=a', BuildSearchUrl(SEARCH_BING, 'a'));
  Assert.AreEqual('https://duckduckgo.com/?q=a', BuildSearchUrl(SEARCH_DUCKDUCKGO, 'a'));
end;

{ TReplacementPlanTests }

procedure TReplacementPlanTests.ReplacesWordKeepsSpace;
var
  Plan: TBufferPlan;
begin
  Plan := TConversionChain.PlanReplacement('как пРИВЕТ ', 5, 6, 'Привет');
  Assert.AreEqual(Ord(bmFix), Ord(Plan.Mode));
  Assert.AreEqual('пРИВЕТ', Plan.Region);
  Assert.AreEqual(' ', Plan.Tail);
  Assert.AreEqual('как ', Plan.Head);
  Assert.AreEqual(7, Plan.DeleteCount);
end;

procedure TReplacementPlanTests.AutomaticFixCanBeUndone;
var
  Chain: TConversionChain;
  Plan, Undo: TBufferPlan;
begin
  Chain := TConversionChain.Create;
  try
    Plan := TConversionChain.PlanReplacement('пРИВЕТ ', 1, 6, 'Привет');
    Chain.Completed(Plan, laNone, 'Привет ', 0, 0);
    Undo := Chain.Plan(laUndo, 'Привет ');
    Assert.AreEqual(Ord(bmUndo), Ord(Undo.Mode));
    Assert.AreEqual('пРИВЕТ ', Undo.Head + Undo.Replacement + Undo.Tail);
    // The next conversion starts fresh on the corrected word.
    Assert.AreEqual(Ord(bmWord), Ord(Chain.Plan(laConvert, 'Привет ').Mode));
  finally
    Chain.Free;
  end;
end;

{ TAltGestureTests }

function Press(D: TGestureDetector; VK: Cardinal; var Time: Cardinal): TLSGesture;
begin
  Inc(Time, 40);
  D.KeyEvent(VK, False, Time);
  Inc(Time, 40);
  Result := D.KeyEvent(VK, True, Time);
end;

procedure TAltGestureTests.DoubleRightAlt;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    Assert.AreEqual(lgNone, Press(D, VK_RMENU, FTime));
    Assert.AreEqual(lgDoubleRAlt, Press(D, VK_RMENU, FTime));
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.DoubleLeftAlt;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    Press(D, VK_LMENU, FTime);
    Assert.AreEqual(lgDoubleLAlt, Press(D, VK_LMENU, FTime));
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.LeftThenRightAltIsNotADoubleTap;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    Press(D, VK_LMENU, FTime);
    Assert.AreEqual(lgNone, Press(D, VK_RMENU, FTime));
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.AltShiftAndAltTabAreIgnored;
var
  D: TGestureDetector;
  I: Integer;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    for I := 1 to 2 do
    begin
      D.KeyEvent(VK_LMENU, False, FTime);
      D.KeyEvent(VK_LSHIFT, False, FTime + 20);
      D.KeyEvent(VK_LSHIFT, True, FTime + 40);
      Assert.AreEqual(lgNone, D.KeyEvent(VK_LMENU, True, FTime + 60));
      Inc(FTime, 100);
    end;
    for I := 1 to 2 do
    begin
      D.KeyEvent(VK_LMENU, False, FTime);
      D.KeyEvent(VK_TAB, False, FTime + 20);
      D.KeyEvent(VK_TAB, True, FTime + 40);
      Assert.AreEqual(lgNone, D.KeyEvent(VK_LMENU, True, FTime + 60));
      Inc(FTime, 100);
    end;
  finally
    D.Free;
  end;
end;

function AltGrTap(D: TGestureDetector; var Time: Cardinal): TLSGesture;
begin
  // Windows sends a fake Left Ctrl with the same time right before Right Alt.
  D.KeyEvent(VK_LCONTROL, False, Time);
  D.KeyEvent(VK_RMENU, False, Time);
  D.KeyEvent(VK_LCONTROL, True, Time + 40);
  Result := D.KeyEvent(VK_RMENU, True, Time + 40);
  Inc(Time, 100);
end;

procedure TAltGestureTests.DoubleAltGrIsRightAlt;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    Assert.AreEqual(lgNone, AltGrTap(D, FTime));
    Assert.AreEqual(lgDoubleRAlt, AltGrTap(D, FTime));
    Assert.IsFalse(D.CtrlDown);
    Assert.AreEqual(0, D.HeldKeyCount);
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.RealCtrlBeforeRightAltIsNotAltGr;
var
  D: TGestureDetector;
  I: Integer;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    for I := 1 to 2 do
    begin
      D.KeyEvent(VK_LCONTROL, False, FTime);
      D.KeyEvent(VK_RMENU, False, FTime + 150);
      D.KeyEvent(VK_RMENU, True, FTime + 200);
      Assert.AreEqual(lgNone, D.KeyEvent(VK_LCONTROL, True, FTime + 250));
      Inc(FTime, 300);
    end;
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.AltGrWithCharacterIsNotATap;
var
  D: TGestureDetector;
  I: Integer;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    // AltGr+8 types the rouble sign on the Russian layout.
    for I := 1 to 2 do
    begin
      D.KeyEvent(VK_LCONTROL, False, FTime);
      D.KeyEvent(VK_RMENU, False, FTime);
      D.KeyEvent(Ord('8'), False, FTime + 20);
      D.KeyEvent(Ord('8'), True, FTime + 30);
      D.KeyEvent(VK_LCONTROL, True, FTime + 40);
      Assert.AreEqual(lgNone, D.KeyEvent(VK_RMENU, True, FTime + 40));
      Inc(FTime, 100);
    end;
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.AltGrWithFakeRightCtrlFromLog;
var
  D: TGestureDetector;

  // Exact sequence from a diagnostic log: the keyboard driver reports the
  // fake Ctrl of AltGr as Right Ctrl, 1 ms before Right Alt.
  function Tap(T0: Cardinal): TLSGesture;
  begin
    D.KeyEvent(VK_RCONTROL, False, T0);
    D.KeyEvent(VK_RMENU, False, T0 + 1);
    D.KeyEvent(VK_RCONTROL, True, T0 + 136);
    Result := D.KeyEvent(VK_RMENU, True, T0 + 136);
  end;

begin
  D := TGestureDetector.Create;
  try
    Assert.AreEqual(lgNone, Tap(27610));
    Assert.AreEqual(lgDoubleRAlt, Tap(27890));
    Assert.IsFalse(D.CtrlDown);
    // Two AltGr taps must never look like a double Right Ctrl either.
    Assert.AreEqual(lgNone, Tap(30466));
    Assert.AreEqual(lgDoubleRAlt, Tap(30722));
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.FakeCtrlDoesNotBreakPendingTaps;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    FTime := 1000;
    // A real Left Ctrl tap followed by AltGr must not count as double LCtrl.
    D.KeyEvent(VK_LCONTROL, False, FTime);
    D.KeyEvent(VK_LCONTROL, True, FTime + 40);
    Inc(FTime, 100);
    Assert.AreEqual(lgNone, AltGrTap(D, FTime));
    D.KeyEvent(VK_LCONTROL, False, FTime);
    Assert.AreEqual(lgNone, D.KeyEvent(VK_LCONTROL, True, FTime + 40));
  finally
    D.Free;
  end;
end;

procedure TAltGestureTests.DefaultsAndMigrationByVersion;
var
  G: TLSActionGestures;
begin
  G := TLSSettings.Defaults.ActionGestures;
  Assert.AreEqual(lgDoubleRAlt, G[laTranslate]);
  Assert.AreEqual(lgDoubleLAlt, G[laWebSearch]);

  // Written by 2.1/2.2 (version 2): transliteration deliberately disabled.
  G[laTransliterate] := lgNone;
  G[laTranslate] := lgNone;
  G[laWebSearch] := lgNone;
  MigrateActionGestures(G, 2);
  Assert.AreEqual(lgNone, G[laTransliterate]);
  Assert.AreEqual(lgDoubleRAlt, G[laTranslate]);
  Assert.AreEqual(lgDoubleLAlt, G[laWebSearch]);

  // Current version: nothing changes.
  G[laTranslate] := lgNone;
  MigrateActionGestures(G, CURRENT_SETTINGS_VERSION);
  Assert.AreEqual(lgNone, G[laTranslate]);
end;

{ TSettingsFileTests }

procedure TSettingsFileTests.ExportImportRoundTrip;
var
  FileName: string;
  Source, Loaded: TLSSettings;
  Diagnostics: Boolean;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-test.ini');
  try
    Source := TLSSettings.Defaults;
    Source.AssignGesture(laTranslate, lgDoubleRCtrl);
    Source.DoubleTapInterval := 350;
    Source.FixTwoCapitals := True;
    Source.TwoCapitalsExceptions := ['VMware', 'OAuth'];
    Source.Snippets := ';a=C:\path\new' + sLineBreak + ';b=x\\y';
    Source.ExcludedProcesses := ['ShareX.exe', 'obs64.exe'];
    Source.Language := llEnglish;
    Source.SearchEngine := SEARCH_BING;
    Source.LastUpdateCheck := 46000;
    Assert.IsTrue(ExportSettings(Source, FileName, True));

    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsTrue(Diagnostics);
    Assert.AreEqual(lgDoubleRCtrl, Loaded.GestureForAction(laTranslate));
    Assert.AreEqual(lgNone, Loaded.GestureForAction(laLowerCase));
    Assert.AreEqual(Cardinal(350), Loaded.DoubleTapInterval);
    Assert.IsTrue(Loaded.FixTwoCapitals);
    Assert.AreEqual('VMware; OAuth', string.Join('; ', Loaded.TwoCapitalsExceptions));
    // Backslashes and line breaks survive the INI escaping.
    Assert.AreEqual(Source.Snippets, Loaded.Snippets);
    Assert.AreEqual('ShareX.exe; obs64.exe', ProcessListToText(Loaded.ExcludedProcesses));
    Assert.AreEqual(Ord(llEnglish), Ord(Loaded.Language));
    Assert.AreEqual(SEARCH_BING, Loaded.SearchEngine);
    // The last update check is not carried over to another computer.
    Assert.AreEqual(Double(0), Double(Loaded.LastUpdateCheck));
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TSettingsFileTests.ImportRejectsForeignFile;
var
  FileName: string;
  Loaded: TLSSettings;
  Diagnostics: Boolean;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-foreign-test.ini');
  try
    TFile.WriteAllText(FileName, '[Other]' + sLineBreak + 'a=1');
    Assert.IsFalse(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsFalse(ImportSettings(FileName + '.missing', Loaded, Diagnostics));
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TSettingsFileTests.FormatsDownloadProgress;
var
  Saved: TLSLanguage;
begin
  Saved := CurrentLanguageSetting;
  try
    SetUILanguage(llRussian);
    Assert.AreEqual(FormatFloat('0.0', 1) + ' МБ из ' + FormatFloat('0.0', 4) + ' МБ (25%)',
      FormatDownloadProgress(1024, 4096));
    Assert.AreEqual('Загружено ' + FormatFloat('0.0', 0.5) + ' МБ',
      FormatDownloadProgress(512, 0));
    SetUILanguage(llEnglish);
    Assert.AreEqual(FormatFloat('0.0', 4) + ' MB of ' + FormatFloat('0.0', 4) + ' MB (100%)',
      FormatDownloadProgress(4096, 4096));
  finally
    SetUILanguage(Saved);
  end;
end;

procedure TSettingsFileTests.SetupAssetName;
begin
  Assert.IsTrue(IsSetupAssetName('LayoutSwitcher-Setup-2.2.0.0.exe'));
  Assert.IsFalse(IsSetupAssetName('LayoutSwitcher-2.2.0.0-x64.exe'));
  Assert.IsFalse(IsSetupAssetName('LayoutSwitcher-Setup-2.2.0.0.zip'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAutoCorrectionTests);
  TDUnitX.RegisterTestFixture(TSnippetTests);
  TDUnitX.RegisterTestFixture(TLookupTests);
  TDUnitX.RegisterTestFixture(TReplacementPlanTests);
  TDUnitX.RegisterTestFixture(TAltGestureTests);
  TDUnitX.RegisterTestFixture(TSettingsFileTests);

end.
