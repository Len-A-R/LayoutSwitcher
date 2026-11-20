unit TestFeatures24;

// Tests for 2.4: switching inside a word, learned words, extended typos,
// sentence capitals, double spaces, templates with {clipboard}/{cursor}.

interface

uses
  DUnitX.TestFramework,
  uTextTools, uInWordSwitch, uSettings;

type
  [TestFixture]
  TInWordSwitchTests = class
  public
    [Test]
    procedure KnowsWordStarts;
    [Test]
    procedure SwitchesImpossibleStarts;
    [Test]
    procedure LeavesRealWordsAndAbbreviations;
    [Test]
    procedure DetectsMostRussianWordsTypedInEnglish;
  end;

  [TestFixture]
  TLearningTests = class
  public
    [Test]
    procedure CountsAndForgets;
    [Test]
    procedure KeepsAtMostHundredWords;
    [Test]
    procedure LearnedWordsAreCaseInsensitive;
  end;

  [TestFixture]
  TExtendedTypoTests = class
  public
    [Test]
    procedure SingleEdit;
    [Test]
    procedure ExtendedOnlyForLongWordsAndUniqueFix;
  end;

  [TestFixture]
  TSentenceTests = class
  public
    [Test]
    procedure SentenceStart;
    [Test]
    procedure Capitalization;
    [Test]
    procedure DoubleSpace;
  end;

  [TestFixture]
  TTemplateTests = class
  public
    [Test]
    procedure ClipboardAndEscapes;
    [Test]
    procedure CursorPosition;
    [Test]
    procedure OldExpansionUnchanged;
  end;

  [TestFixture]
  TSettings24Tests = class
  public
    [Test]
    procedure DefaultsAndExport;
  end;

implementation

uses
  System.SysUtils, System.DateUtils, System.IOUtils;

{ TInWordSwitchTests }

procedure TInWordSwitchTests.KnowsWordStarts;
begin
  Assert.IsTrue(IsKnownWordStart(wlRussian, 'при'));
  Assert.IsTrue(IsKnownWordStart(wlRussian, 'Прив'));
  Assert.IsTrue(IsKnownWordStart(wlRussian, 'ёлк'));     // ё is е
  Assert.IsTrue(IsKnownWordStart(wlEnglish, 'hel'));
  Assert.IsTrue(IsKnownWordStart(wlEnglish, 'unha'));    // prefix "un" applied
  Assert.IsFalse(IsKnownWordStart(wlEnglish, 'ghb'));
  Assert.IsFalse(IsKnownWordStart(wlRussian, 'руд' + 'щ'));
  Assert.IsFalse(IsKnownWordStart(wlRussian, 'пр'));      // too short
  Assert.IsFalse(IsKnownWordStart(wlUnknown, 'при'));
  Assert.AreEqual(Ord(wlRussian), Ord(WordStartLanguage('ru-RU')));
  Assert.AreEqual(Ord(wlEnglish), Ord(WordStartLanguage('en-GB')));
  Assert.AreEqual(Ord(wlUnknown), Ord(WordStartLanguage('uk-UA')));
end;

procedure TInWordSwitchTests.SwitchesImpossibleStarts;
begin
  // "ghb" -> "при" (привет), "rfr" -> "как", "ytn" -> "нет".
  Assert.IsTrue(ShouldSwitchInWord(wlEnglish, wlRussian, 'ghb', 'при'));
  Assert.IsTrue(ShouldSwitchInWord(wlEnglish, wlRussian, 'Ghb', 'При'));
  Assert.IsTrue(ShouldSwitchInWord(wlEnglish, wlRussian, 'ytn', 'нет'));
  // ";bp" -> "жиз": punctuation keys are Russian letters.
  Assert.IsTrue(ShouldSwitchInWord(wlEnglish, wlRussian, ';bp', 'жиз'));
  // "руддщ" -> "hello" needs the 4th letter: "руд" is Russian, "рудд" is not.
  Assert.IsFalse(ShouldSwitchInWord(wlRussian, wlEnglish, 'руд', 'hel'));
  Assert.IsTrue(ShouldSwitchInWord(wlRussian, wlEnglish, 'рудд', 'hell'));
end;

procedure TInWordSwitchTests.LeavesRealWordsAndAbbreviations;
begin
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlRussian, 'the', 'еру'));
  Assert.IsFalse(ShouldSwitchInWord(wlRussian, wlEnglish, 'при', 'ghb'));
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlRussian, 'GHB', 'ПРИ'));  // abbreviation
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlRussian, 'gh1', 'пр1'));
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlRussian, 'gh', 'пр'));
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlRussian, 'ghbdt', 'приве'));
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlUnknown, 'ghb', 'при'));
  Assert.IsFalse(ShouldSwitchInWord(wlEnglish, wlEnglish, 'ghb', 'ghb'));
end;

procedure TInWordSwitchTests.DetectsMostRussianWordsTypedInEnglish;
const
  Words: array[0..9] of string = ('привет', 'спасибо', 'хорошо', 'сегодня',
    'работа', 'вопрос', 'нужно', 'потому', 'человек', 'сделать');
  Ru = 'йцукенгшщзхъфывапролджэячсмитьбю';
  En = 'qwertyuiop[]asdfghjkl;''zxcvbnm,.';
var
  Word, Typed: string;
  Ch: Char;
  Detected: Integer;
begin
  Detected := 0;
  for Word in Words do
  begin
    Typed := '';
    for Ch in Word do
      Typed := Typed + En[Pos(Ch, Ru)];
    if ShouldSwitchInWord(wlEnglish, wlRussian, Copy(Typed, 1, 3), Copy(Word, 1, 3)) or
       ShouldSwitchInWord(wlEnglish, wlRussian, Copy(Typed, 1, 4), Copy(Word, 1, 4)) then
      Inc(Detected);
  end;
  Assert.IsTrue(Detected >= 9, Format('detected %d of 10', [Detected]));
end;

{ TLearningTests }

procedure TLearningTests.CountsAndForgets;
var
  Counts: TArray<string>;
begin
  Counts := nil;
  Assert.AreEqual(1, BumpLearnCount(Counts, 'Привет', 1));
  Assert.AreEqual(2, BumpLearnCount(Counts, 'привет', 1));
  Assert.AreEqual('привет=2', string.Join(';', Counts));
  Assert.AreEqual(1, BumpLearnCount(Counts, 'как', 1));
  Assert.AreEqual(1, BumpLearnCount(Counts, 'привет', -1));
  Assert.AreEqual(0, BumpLearnCount(Counts, 'привет', -5));
  Assert.AreEqual('как=1', string.Join(';', Counts));
end;

procedure TLearningTests.KeepsAtMostHundredWords;
var
  Counts: TArray<string>;
  I: Integer;
begin
  Counts := nil;
  for I := 1 to 120 do
    BumpLearnCount(Counts, 'слово' + IntToStr(I), 1);
  Assert.AreEqual<Integer>(100, Length(Counts));
  Assert.AreEqual('слово21=1', Counts[0]);   // the oldest ones dropped
end;

procedure TLearningTests.LearnedWordsAreCaseInsensitive;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  S.AutoSwitchLearned := ['привет', 'жизнь'];
  Assert.IsTrue(S.IsAutoSwitchLearned('Привет'));
  Assert.IsTrue(S.IsAutoSwitchLearned('ЖИЗНЬ'));
  Assert.IsFalse(S.IsAutoSwitchLearned('пока'));
end;

{ TExtendedTypoTests }

procedure TExtendedTypoTests.SingleEdit;
begin
  Assert.IsTrue(IsSingleEdit('превет', 'привет'));    // replaced
  Assert.IsTrue(IsSingleEdit('привт', 'привет'));     // missing
  Assert.IsTrue(IsSingleEdit('приввет', 'привет'));   // extra
  Assert.IsFalse(IsSingleEdit('wrold', 'world'));   // a swap, not one edit
  Assert.IsFalse(IsSingleEdit('привет', 'привет'));
  Assert.IsFalse(IsSingleEdit('пвет', 'привет'));
end;

procedure TExtendedTypoTests.ExtendedOnlyForLongWordsAndUniqueFix;
var
  Fixed: string;
begin
  // Suggestions as returned by the Windows spell checker (ru-RU).
  Assert.IsFalse(ChooseTypoFix('превет', ['привет', 'преет'], Fixed));   // not extended
  Assert.IsTrue(ChooseTypoFix('превет', ['привет', 'преет', 'поревёт', 'прервёт',
    'поревет', 'прервет', 'привит', 'правит', 'правят', 'приват'], Fixed, True));
  Assert.AreEqual('привет', Fixed);
  Assert.IsTrue(ChooseTypoFix('приввет', ['привет', 'привета', 'привете', 'привету',
    'приветы', 'приветь', 'привьёт', 'привьет'], Fixed, True));
  Assert.AreEqual('привет', Fixed);
  Assert.IsTrue(ChooseTypoFix('Спосибо', ['спасибо', 'способы', 'способа', 'способе',
    'способу'], Fixed, True));
  Assert.AreEqual('Спасибо', Fixed);
  Assert.IsTrue(ChooseTypoFix('сегоня', ['сегодня', 'сгоняя'], Fixed, True));
  Assert.AreEqual('сегодня', Fixed);
  Assert.IsTrue(ChooseTypoFix('рабоат', ['работа', 'работ', 'рабат', 'робота', 'рабата'],
    Fixed, True));
  Assert.AreEqual('работа', Fixed);
  // Two insertions are equally likely: приват or привет.
  Assert.IsFalse(ChooseTypoFix('привт', ['приват', 'привет', 'привит', 'принт', 'причт',
    'приют', 'прият', 'прев'], Fixed, True));
  // An added letter while a replacement is possible: хорошел or хорошо.
  Assert.IsFalse(ChooseTypoFix('хорошл', ['хорошел', 'хорош', 'хорошо', 'хороша', 'хороши'],
    Fixed, True));
  // ...but a replacement far down the list does not count (программ is 5th).
  Assert.IsTrue(ChooseTypoFix('програма', ['программа', 'программе', 'программу',
    'программы', 'программ'], Fixed, True));
  Assert.AreEqual('программа', Fixed);
  // The best one-letter candidate must be among the first two suggestions.
  Assert.IsFalse(ChooseTypoFix('превет', ['предмет', 'пресет', 'перевод', 'привет'],
    Fixed, True));
  // Four letters: only swaps.
  Assert.IsFalse(ChooseTypoFix('мома', ['мама'], Fixed, True));
  // Two different swaps stay ambiguous in the extended mode too.
  Assert.IsFalse(ChooseTypoFix('abdcef', ['abcdef', 'badcef'], Fixed, True));
  Assert.IsTrue(ChooseTypoFix('пирвет', ['привет'], Fixed, True));
end;

{ TSentenceTests }

procedure TSentenceTests.SentenceStart;
begin
  Assert.IsTrue(IsSentenceStart('Привет. '));
  Assert.IsTrue(IsSentenceStart('Как дела? '));
  Assert.IsTrue(IsSentenceStart('Ура! '));
  Assert.IsTrue(IsSentenceStart('Done.  '));
  Assert.IsTrue(IsSentenceStart('(в скобках). '));
  Assert.IsFalse(IsSentenceStart('Привет.'));         // no space yet
  Assert.IsFalse(IsSentenceStart('и т.д. '));
  Assert.IsFalse(IsSentenceStart('e.g. '));
  Assert.IsFalse(IsSentenceStart('А. '));             // initial
  Assert.IsFalse(IsSentenceStart('в 2026 г. '));
  Assert.IsFalse(IsSentenceStart('см. '));
  Assert.IsFalse(IsSentenceStart('Mr. '));
  Assert.IsFalse(IsSentenceStart('пункт 10. '));
  Assert.IsFalse(IsSentenceStart('Ну... '));
  Assert.IsFalse(IsSentenceStart('Ну… '));
  Assert.IsFalse(IsSentenceStart('привет '));
  Assert.IsFalse(IsSentenceStart(''));
end;

procedure TSentenceTests.Capitalization;
begin
  Assert.IsTrue(CanCapitalize('привет'));
  Assert.IsTrue(CanCapitalize('привет,'));
  Assert.IsFalse(CanCapitalize('Привет'));
  Assert.IsFalse(CanCapitalize('example.com'));
  Assert.IsFalse(CanCapitalize('user@mail.ru'));
  Assert.IsFalse(CanCapitalize('c:\temp'));
  Assert.IsFalse(CanCapitalize('my_var'));
  Assert.IsFalse(CanCapitalize('123'));
  Assert.AreEqual('Привет,', CapitalizeFirst('привет,'));
end;

procedure TSentenceTests.DoubleSpace;
begin
  Assert.IsTrue(EndsWithDoubleSpace('слово  '));
  Assert.IsFalse(EndsWithDoubleSpace('слово '));
  Assert.IsFalse(EndsWithDoubleSpace('слово   '));   // deliberate indentation
  Assert.IsFalse(EndsWithDoubleSpace('  '));
end;

{ TTemplateTests }

procedure TTemplateTests.ClipboardAndEscapes;
var
  Back: Integer;
begin
  Assert.AreEqual('Ссылка: https://x.ru', ExpandSnippet('Ссылка: {clipboard}', Now,
    'https://x.ru', Back));
  Assert.AreEqual(0, Back);
  Assert.AreEqual('Строка 1'#13#10'Строка 2'#9'!', ExpandSnippet('Строка 1\nСтрока 2\t!',
    Now, '', Back));
  Assert.AreEqual('C:\new', ExpandSnippet('C:\\new', Now, '', Back));
  // Clipboard line breaks become CRLF; escapes inside it are not expanded.
  Assert.AreEqual('a'#13#10'b\n', ExpandSnippet('{clipboard}', Now, 'a'#10'b\n', Back));
  // At most 2000 characters of the clipboard, a surrogate pair is not cut.
  Assert.AreEqual<Integer>(2000, Length(ExpandSnippet('{clipboard}', Now,
    StringOfChar('a', 5000), Back)));
  Assert.AreEqual<Integer>(1999, Length(ExpandSnippet('{clipboard}', Now,
    StringOfChar('a', 1999) + '👍', Back)));
  Assert.IsTrue(SnippetUsesClipboard('x {CLIPBOARD}'));
  Assert.IsFalse(SnippetUsesClipboard('{date}'));
end;

procedure TTemplateTests.CursorPosition;
var
  Back: Integer;
begin
  Assert.AreEqual('<b></b>', ExpandSnippet('<b>{cursor}</b>', Now, '', Back));
  Assert.AreEqual(4, Back);
  // A line break counts as one caret step.
  Assert.AreEqual('Привет, !'#13#10'С уважением', ExpandSnippet(
    'Привет, {cursor}!\nС уважением', Now, '', Back));
  Assert.AreEqual(1 + 1 + Length('С уважением'), Back);
  // An emoji (surrogate pair) after {cursor} is one Left press.
  Assert.AreEqual('ok 👍', ExpandSnippet('ok{cursor} 👍', Now, '', Back));
  Assert.AreEqual(2, Back);
  // Only the first {cursor} counts, others are removed.
  Assert.AreEqual('ab', ExpandSnippet('a{cursor}b{cursor}', Now, '', Back));
  Assert.AreEqual(1, Back);
end;

procedure TTemplateTests.OldExpansionUnchanged;
var
  Moment: TDateTime;
  Back: Integer;
begin
  Moment := EncodeDateTime(2026, 11, 18, 9, 5, 0, 0);
  Assert.AreEqual('18.11.2026 09:05', ExpandSnippet('{date} {time}', Moment, '', Back));
  Assert.AreEqual('18.11.2026', ExpandSnippet('{date}', Moment));
end;

{ TSettings24Tests }

procedure TSettings24Tests.DefaultsAndExport;
var
  FileName: string;
  Source, Loaded: TLSSettings;
  Diagnostics: Boolean;
begin
  Source := TLSSettings.Defaults;
  Assert.IsFalse(Source.InWordSwitch);
  Assert.IsTrue(Source.LearnManualConversions);
  Assert.IsFalse(Source.FixTyposExtended);
  Assert.IsFalse(Source.CapitalizeSentences);
  Assert.IsFalse(Source.FixDoubleSpace);
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-24.ini');
  try
    Source.InWordSwitch := True;
    Source.LearnManualConversions := False;
    Source.FixTyposExtended := True;
    Source.CapitalizeSentences := True;
    Source.FixDoubleSpace := True;
    Source.AutoSwitchLearned := ['привет', 'жизнь'];
    Source.AutoSwitchLearnCounts := ['как=1'];
    Assert.IsTrue(ExportSettings(Source, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsTrue(Loaded.InWordSwitch);
    Assert.IsFalse(Loaded.LearnManualConversions);
    Assert.IsTrue(Loaded.FixTyposExtended);
    Assert.IsTrue(Loaded.CapitalizeSentences);
    Assert.IsTrue(Loaded.FixDoubleSpace);
    Assert.AreEqual('привет; жизнь', string.Join('; ', Loaded.AutoSwitchLearned));
    Assert.AreEqual('как=1', string.Join('; ', Loaded.AutoSwitchLearnCounts));
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TInWordSwitchTests);
  TDUnitX.RegisterTestFixture(TLearningTests);
  TDUnitX.RegisterTestFixture(TExtendedTypoTests);
  TDUnitX.RegisterTestFixture(TSentenceTests);
  TDUnitX.RegisterTestFixture(TTemplateTests);
  TDUnitX.RegisterTestFixture(TSettings24Tests);

end.
