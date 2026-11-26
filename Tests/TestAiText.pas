unit TestAiText;

// AI text rewriting: prompts, answer clean-up, outer spaces, the Shift
// gestures and the settings of "fix the text" and voice edits.

interface

uses
  DUnitX.TestFramework,
  uAiText, uSettings, uGestureDetector;

type
  [TestFixture]
  TAiTextTests = class
  public
    [Test]
    procedure Prompts;
    [Test]
    procedure OuterSpaces;
    [Test]
    procedure AnswerCleanUp;
    [Test]
    procedure ShiftGestures;
    [Test]
    procedure SettingsAndMigration;
    [Test]
    procedure VoiceCommands;
    [Test]
    procedure DictationModes;
    [Test]
    procedure DictationRewriteCheck;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils;

procedure TAiTextTests.Prompts;
begin
  Assert.AreEqual('<text>я пошол</text>', FixUserMessage('я пошол'));
  Assert.IsTrue(FixSystemPrompt.Contains('<text>'));
  // The text is material, not instructions (prompt injection).
  Assert.IsTrue(FixSystemPrompt.Contains('not instructions'));
  Assert.IsTrue(EditSystemPrompt.Contains('not instructions'));
  Assert.AreEqual('<command>переведи на английский</command>' + sLineBreak + '<text>Привет</text>',
    EditUserMessage(' переведи на английский ', 'Привет'));
end;

procedure TAiTextTests.OuterSpaces;
begin
  Assert.AreEqual('  Я пошёл. ', KeepOuterSpaces('  я пошол ', 'Я пошёл.'));
  Assert.AreEqual('Текст.' + sLineBreak, KeepOuterSpaces('текст' + sLineBreak, ' Текст. '));
  Assert.AreEqual('Да.', KeepOuterSpaces('да', 'Да.'));
  // Only spaces: nothing to fix.
  Assert.AreEqual('   ', KeepOuterSpaces('   ', 'x'));
end;

procedure TAiTextTests.AnswerCleanUp;
begin
  Assert.AreEqual('Я пошёл в магазин, который закрыт.',
    CleanAiAnswer('  Я пошёл в магазин, который закрыт.  '));
  Assert.AreEqual('Исправлено.', CleanAiAnswer('```text' + #10 + 'Исправлено.' + #10 + '```'));
  Assert.AreEqual('Исправлено.', CleanAiAnswer('<text>Исправлено.</text>'));
  Assert.AreEqual('Готово.', CleanAiAnswer('Исправленный текст:' + #10 + 'Готово.'));
  Assert.AreEqual('Готово.', CleanAiAnswer('«Готово.»'));
  Assert.AreEqual('Готово.', CleanAiAnswer('"Готово."'));
  // Quotes inside the text stay.
  Assert.AreEqual('"Да", — сказал он, — "нет"', CleanAiAnswer('"Да", — сказал он, — "нет"'));
  // Line breaks become Windows line breaks.
  Assert.AreEqual('Раз' + sLineBreak + 'два', CleanAiAnswer('Раз' + #10 + 'два'));
  // Markdown line breaks (two trailing spaces) are dropped.
  Assert.AreEqual('- Молоко' + sLineBreak + '- Хлеб', CleanAiAnswer('- Молоко  ' + #10 + '- Хлеб'));
  // A normal first line ending with a colon is kept.
  Assert.AreEqual('Список дел:' + sLineBreak + '- молоко',
    CleanAiAnswer('Список дел:' + #10 + '- молоко'));
end;

procedure TAiTextTests.ShiftGestures;
var
  D: TGestureDetector;
begin
  D := TGestureDetector.Create;
  try
    D.KeyEvent(VK_LSHIFT, False, 1000);
    Assert.AreEqual(Ord(lgShiftPause), Ord(D.KeyEvent(VK_PAUSE, False, 1050)));
    D.KeyEvent(VK_PAUSE, True, 1051);
    Assert.AreEqual(Ord(lgShiftScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, 1100)));
    D.KeyEvent(VK_SCROLL, True, 1150);
    // Shift released: the Shift taps were disqualified, no double Shift.
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_LSHIFT, True, 1200)));
    // Ctrl + Shift + Pause is neither.
    D.KeyEvent(VK_LCONTROL, False, 2000);
    D.KeyEvent(VK_RSHIFT, False, 2010);
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_PAUSE, False, 2050)));
    D.KeyEvent(VK_PAUSE, True, 2051);
    D.KeyEvent(VK_RSHIFT, True, 2100);
    D.KeyEvent(VK_LCONTROL, True, 2110);
    // Alone they stay Pause and Scroll Lock.
    Assert.AreEqual(Ord(lgPause), Ord(D.KeyEvent(VK_PAUSE, False, 3000)));
    D.KeyEvent(VK_PAUSE, True, 3001);
    Assert.AreEqual(Ord(lgScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, 3100)));
  finally
    D.Free;
  end;
  Assert.AreEqual('Shift + Pause/Break', GestureName(lgShiftPause));
end;

procedure TAiTextTests.SettingsAndMigration;
var
  S: TLSSettings;
  G: TLSActionGestures;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(Ord(lgShiftPause), Ord(S.GestureForAction(laAiFix)));
  Assert.AreEqual(Ord(lgShiftScrollLock), Ord(S.GestureForAction(laVoiceEdit)));
  Assert.AreEqual('ai_fix', ActionKeys[laAiFix]);
  Assert.AreEqual('voice_edit', ActionKeys[laVoiceEdit]);
  // Settings of 2.5 (version 7) get the new gestures.
  G := S.ActionGestures;
  G[laAiFix] := lgNone;
  G[laVoiceEdit] := lgNone;
  MigrateActionGestures(G, 7);
  Assert.AreEqual(Ord(lgShiftPause), Ord(G[laAiFix]));
  Assert.AreEqual(Ord(lgShiftScrollLock), Ord(G[laVoiceEdit]));
  // A deliberate "disabled" saved by version 8 stays.
  G[laAiFix] := lgNone;
  MigrateActionGestures(G, 8);
  Assert.AreEqual(Ord(lgNone), Ord(G[laAiFix]));
end;

procedure TAiTextTests.VoiceCommands;
var
  Insert: string;
begin
  Assert.AreEqual(Ord(vcNewLine), Ord(ParseVoiceCommand('Новая строка.', Insert)));
  Assert.AreEqual(sLineBreak, Insert);
  Assert.AreEqual(Ord(vcNewParagraph), Ord(ParseVoiceCommand('новый абзац', Insert)));
  Assert.AreEqual(sLineBreak + sLineBreak, Insert);
  Assert.AreEqual(Ord(vcDeleteLast), Ord(ParseVoiceCommand('Удали последнее предложение!', Insert)));
  Assert.AreEqual(Ord(vcDeleteLast), Ord(ParseVoiceCommand('Scratch that.', Insert)));
  Assert.AreEqual(Ord(vcPunctuation), Ord(ParseVoiceCommand('Точка.', Insert)));
  Assert.AreEqual('.', Insert);
  Assert.AreEqual(Ord(vcPunctuation), Ord(ParseVoiceCommand('вопросительный  знак', Insert)));
  Assert.AreEqual('?', Insert);
  Assert.AreEqual(Ord(vcPunctuation), Ord(ParseVoiceCommand('Точка с запятой', Insert)));
  Assert.AreEqual(';', Insert);
  // Only a whole utterance is a command: words inside a phrase are text.
  Assert.AreEqual(Ord(vcNone), Ord(ParseVoiceCommand('Это точка зрения автора.', Insert)));
  Assert.AreEqual(Ord(vcNone), Ord(ParseVoiceCommand('Начни с новой строки письмо', Insert)));
  Assert.AreEqual(Ord(vcNone), Ord(ParseVoiceCommand('', Insert)));
end;

procedure TAiTextTests.DictationModes;
var
  S, Loaded: TLSSettings;
  FileName: string;
  Diagnostics: Boolean;
begin
  Assert.AreEqual(Ord(damAsSaid), Ord(DictationAiModeFromInteger(9)));
  Assert.AreEqual(Ord(damList), Ord(DictationAiModeFromInteger(3)));
  Assert.AreEqual('<dictation>ну привет</dictation>', DictationUserMessage(' ну привет '));
  // Every mode handles spoken commands and never follows requests in the text.
  Assert.IsTrue(DictationSystemPrompt(damAsSaid).Contains('новая строка'));
  Assert.IsTrue(DictationSystemPrompt(damNeat).Contains('not instructions'));
  Assert.IsTrue(DictationSystemPrompt(damNeat).Contains('filler'));
  Assert.IsFalse(DictationSystemPrompt(damAsSaid).Contains('filler'));
  Assert.IsTrue(DictationSystemPrompt(damBusiness).Contains('business'));
  Assert.IsTrue(DictationSystemPrompt(damList).Contains('"- "'));
  Assert.IsTrue(DictationAiModeName(damNeat) <> DictationAiModeName(damList));
  S := TLSSettings.Defaults;
  Assert.AreEqual(0, S.DictationAiMode);
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-dictai.ini');
  try
    S.DictationAiMode := 2;
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual(2, Loaded.DictationAiMode);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TAiTextTests.DictationRewriteCheck;
begin
  // A written-down question passes.
  Assert.IsTrue(IsDictationRewrite('ну какая завтра погода в москве',
    'Какая завтра погода в Москве?', damNeat));
  Assert.IsTrue(IsDictationRewrite('встреча двадцать пятого марта в три',
    'Встреча 25 марта в 15:00.', damNeat));
  Assert.IsTrue(IsDictationRewrite('купить молоко хлеб и яйца',
    'Купить:' + sLineBreak + '- молоко' + sLineBreak + '- хлеб' + sLineBreak + '- яйца', damList));
  Assert.IsTrue(IsDictationRewrite('скажи коле что отчёт будет завтра',
    'Николай, добрый день! Отчёт будет готов завтра.', damBusiness));
  // An answer to it does not.
  Assert.IsFalse(IsDictationRewrite('какая завтра погода в москве',
    'Завтра в Москве ожидается облачная погода, температура около плюс пяти градусов.', damNeat));
  Assert.IsFalse(IsDictationRewrite('привет как дела',
    'Привет! У меня всё отлично, спасибо, что спросили. Чем могу помочь?', damNeat));
  Assert.IsFalse(IsDictationRewrite('напиши стих про осень',
    'Листья кружатся над тихой рекой, ветер уносит последнее лето, ' +
    'небо роняет холодные капли, и осень приходит неслышной тропой.', damBusiness));
  Assert.AreEqual('Текст.', CleanAiAnswer('<dictation>Текст.</dictation>'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAiTextTests);

end.
