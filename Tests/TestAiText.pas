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
  end;

implementation

uses
  Winapi.Windows, System.SysUtils;

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

initialization
  TDUnitX.RegisterTestFixture(TAiTextTests);

end.
