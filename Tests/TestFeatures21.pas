unit TestFeatures21;

// Tests for the 2.1 features: transliteration, the Left Shift + Right Shift
// chord, undo of the last correction and version comparison.

{$Q-}

interface

uses
  DUnitX.TestFramework,
  uSettings, uGestureDetector, uConversionChain;

type
  [TestFixture]
  TTransliterationTests = class
  public
    [Test]
    [TestCase('word', 'привет,privet')]
    [TestCase('capital', 'Москва,Moskva')]
    [TestCase('digraph capital', 'Щука,Shchuka')]
    [TestCase('all caps', 'ЩУКА,SHCHUKA')]
    [TestCase('yo', 'Ёлка,Yolka')]
    [TestCase('signs dropped', 'объём,obyom')]
    [TestCase('ukrainian', 'Їжак,Yizhak')]
    procedure CyrillicToLatin(const Input, Expected: string);
    [Test]
    [TestCase('word', 'privet,привет')]
    [TestCase('capital', 'Moskva,Москва')]
    [TestCase('digraphs', 'Shchuka zhuk,Щука жук')]
    [TestCase('yo', 'yolka,ёлка')]
    [TestCase('ts and ch', 'tsvet chay,цвет чай')]
    procedure LatinToCyrillic(const Input, Expected: string);
    [Test]
    procedure KeepsDigitsAndPunctuation;
  end;

  [TestFixture]
  TBothShiftTests = class
  private
    FDetector: TGestureDetector;
    FTime: Cardinal;
    function Ev(VK: Cardinal; Up: Boolean): TLSGesture;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChordIsRecognised;
    [Test]
    procedure ChordWithLetterIsIgnored;
    [Test]
    procedure ChordDoesNotCountAsDoubleShift;
    [Test]
    procedure DoubleCapsLock;
    [Test]
    procedure ShiftCapsLockIsNotATap;
    [Test]
    procedure CapsLockBetweenShiftTapsCancelsDoubleShift;
  end;

  [TestFixture]
  TSettingsMigrationTests = class
  public
    [Test]
    procedure OldSettingsGetNewDefaults;
    [Test]
    procedure TakenGestureIsNotStolen;
    [Test]
    procedure ExplicitAssignmentIsKept;
  end;

  [TestFixture]
  TUndoTests = class
  private
    FChain: TConversionChain;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NothingToUndoInitially;
    [Test]
    procedure UndoRestoresWordWithMinimalEdit;
    [Test]
    procedure UndoAfterPhraseRestoresPreviousStep;
    [Test]
    procedure UndoSwitchesLayoutBack;
    [Test]
    procedure TypingDisablesUndo;
    [Test]
    procedure NoRedo;
    [Test]
    procedure UndoAfterSelectionReplacement;
  end;

  [TestFixture]
  TVersionTests = class
  public
    [Test]
    procedure ComparesVersions;
    [Test]
    procedure NormalisesTags;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils,
  uLayoutConverter, uUpdateCheck;

const
  EN = HKL($04090409);
  RU = HKL($04190419);

{ TTransliterationTests }

procedure TTransliterationTests.CyrillicToLatin(const Input, Expected: string);
begin
  Assert.AreEqual(Expected, TransliterateText(Input));
end;

procedure TTransliterationTests.LatinToCyrillic(const Input, Expected: string);
begin
  Assert.AreEqual(Expected, TransliterateText(Input));
end;

procedure TTransliterationTests.KeepsDigitsAndPunctuation;
begin
  Assert.AreEqual('privet, mir! 2026', TransliterateText('привет, мир! 2026'));
end;

{ TBothShiftTests }

procedure TBothShiftTests.Setup;
begin
  FDetector := TGestureDetector.Create;
  FDetector.Interval := 500;
  FTime := 1000;
end;

procedure TBothShiftTests.TearDown;
begin
  FDetector.Free;
end;

function TBothShiftTests.Ev(VK: Cardinal; Up: Boolean): TLSGesture;
begin
  Inc(FTime, 30);
  Result := FDetector.KeyEvent(VK, Up, FTime);
end;

procedure TBothShiftTests.ChordIsRecognised;
begin
  Ev(VK_LSHIFT, False);
  Ev(VK_RSHIFT, False);
  Assert.AreEqual(lgNone, Ev(VK_RSHIFT, True));
  Assert.AreEqual(lgBothShift, Ev(VK_LSHIFT, True));
end;

procedure TBothShiftTests.ChordWithLetterIsIgnored;
begin
  Ev(VK_LSHIFT, False);
  Ev(VK_RSHIFT, False);
  Ev(Ord('A'), False);
  Ev(Ord('A'), True);
  Ev(VK_LSHIFT, True);
  Assert.AreEqual(lgNone, Ev(VK_RSHIFT, True));
end;

procedure TBothShiftTests.ChordDoesNotCountAsDoubleShift;
begin
  Ev(VK_LSHIFT, False);
  Ev(VK_RSHIFT, False);
  Ev(VK_LSHIFT, True);
  Assert.AreEqual(lgBothShift, Ev(VK_RSHIFT, True));
  // A single tap right after the chord must not complete a double Shift.
  Ev(VK_LSHIFT, False);
  Assert.AreEqual(lgNone, Ev(VK_LSHIFT, True));
end;

procedure TBothShiftTests.DoubleCapsLock;
begin
  Ev(VK_CAPITAL, False);
  Assert.AreEqual(lgNone, Ev(VK_CAPITAL, True));
  Ev(VK_CAPITAL, False);
  Assert.AreEqual(lgDoubleCapsLock, Ev(VK_CAPITAL, True));
end;

procedure TBothShiftTests.ShiftCapsLockIsNotATap;
begin
  Ev(VK_LSHIFT, False);
  Ev(VK_CAPITAL, False);
  Ev(VK_CAPITAL, True);
  Ev(VK_LSHIFT, True);
  Ev(VK_LSHIFT, False);
  Ev(VK_CAPITAL, False);
  Ev(VK_CAPITAL, True);
  Assert.AreEqual(lgNone, Ev(VK_LSHIFT, True));
end;

procedure TBothShiftTests.CapsLockBetweenShiftTapsCancelsDoubleShift;
begin
  Ev(VK_LSHIFT, False);
  Ev(VK_LSHIFT, True);
  Ev(VK_CAPITAL, False);
  Ev(VK_CAPITAL, True);
  Ev(VK_LSHIFT, False);
  Assert.AreEqual(lgNone, Ev(VK_LSHIFT, True));
end;

{ TSettingsMigrationTests }

procedure TSettingsMigrationTests.OldSettingsGetNewDefaults;
var
  G: TLSActionGestures;
begin
  // As written by 2.0/2.1: the new actions stored as "not assigned".
  G := TLSSettings.Defaults.ActionGestures;
  G[laTransliterate] := lgNone;
  G[laUndo] := lgNone;
  MigrateActionGestures(G);
  Assert.AreEqual(lgBothShift, G[laTransliterate]);
  Assert.AreEqual(lgDoubleCapsLock, G[laUndo]);
end;

procedure TSettingsMigrationTests.TakenGestureIsNotStolen;
var
  G: TLSActionGestures;
begin
  G := TLSSettings.Defaults.ActionGestures;
  G[laTransliterate] := lgNone;
  G[laUndo] := lgNone;
  G[laInvertCase] := lgBothShift;
  MigrateActionGestures(G);
  Assert.AreEqual(lgNone, G[laTransliterate]);
  Assert.AreEqual(lgBothShift, G[laInvertCase]);
  Assert.AreEqual(lgDoubleCapsLock, G[laUndo]);
end;

procedure TSettingsMigrationTests.ExplicitAssignmentIsKept;
var
  G: TLSActionGestures;
begin
  G := TLSSettings.Defaults.ActionGestures;
  G[laConvert] := lgNone;
  G[laTransliterate] := lgDoubleShift;
  G[laUndo] := lgNone;
  MigrateActionGestures(G);
  Assert.AreEqual(lgDoubleShift, G[laTransliterate]);
  Assert.AreEqual(lgDoubleCapsLock, G[laUndo]);
end;

{ TUndoTests }

procedure TUndoTests.Setup;
begin
  FChain := TConversionChain.Create;
end;

procedure TUndoTests.TearDown;
begin
  FChain.Free;
end;

procedure TUndoTests.NothingToUndoInitially;
begin
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laUndo, 'abc').Mode));
end;

procedure TUndoTests.UndoRestoresWordWithMinimalEdit;
var
  Plan, Undo: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn vbh');
  FChain.Completed(Plan, laConvert, 'ghbdtn мир', EN, RU);
  Undo := FChain.Plan(laUndo, 'ghbdtn мир');
  Assert.AreEqual(Ord(bmUndo), Ord(Undo.Mode));
  Assert.AreEqual('мир', Undo.Region);
  Assert.AreEqual('vbh', Undo.Replacement);
  Assert.AreEqual(3, Undo.DeleteCount);
  Assert.AreEqual('ghbdtn vbh', Undo.Head + Undo.Replacement + Undo.Tail);
end;

procedure TUndoTests.UndoAfterPhraseRestoresPreviousStep;
var
  Plan, Undo: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn vbh');
  FChain.Completed(Plan, laConvert, 'ghbdtn мир', EN, RU);
  Plan := FChain.Plan(laConvert, 'ghbdtn мир');
  FChain.Completed(Plan, laConvert, 'привет мир', EN, RU);
  Undo := FChain.Plan(laUndo, 'привет мир');
  Assert.AreEqual('ghbdtn мир', Undo.Head + Undo.Replacement + Undo.Tail);
  // Text is retyped from the first difference up to the caret.
  Assert.AreEqual('привет мир', Undo.Region);
  Assert.AreEqual(10, Undo.DeleteCount);
end;

procedure TUndoTests.UndoSwitchesLayoutBack;
var
  Plan, Undo: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn');
  FChain.Completed(Plan, laConvert, 'привет', EN, RU);
  Undo := FChain.Plan(laUndo, 'привет');
  Assert.AreEqual(NativeUInt(EN), NativeUInt(Undo.ForcedTarget));

  Plan := FChain.Plan(laUpperCase, 'abc');
  FChain.Completed(Plan, laUpperCase, 'ABC', 0, 0);
  Undo := FChain.Plan(laUndo, 'ABC');
  Assert.AreEqual(NativeUInt(0), NativeUInt(Undo.ForcedTarget));
end;

procedure TUndoTests.TypingDisablesUndo;
var
  Plan: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn');
  FChain.Completed(Plan, laConvert, 'привет', EN, RU);
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laUndo, 'привет!').Mode));
end;

procedure TUndoTests.NoRedo;
var
  Plan, Undo: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn');
  FChain.Completed(Plan, laConvert, 'привет', EN, RU);
  Undo := FChain.Plan(laUndo, 'привет');
  FChain.Completed(Undo, laUndo, 'ghbdtn', EN, EN);
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laUndo, 'ghbdtn').Mode));
end;

procedure TUndoTests.UndoAfterSelectionReplacement;
var
  Undo: TBufferPlan;
begin
  FChain.CompletedWhole(laTransliterate, 'privet', 'привет', 0, 0);
  Undo := FChain.Plan(laUndo, 'privet');
  Assert.AreEqual(Ord(bmUndo), Ord(Undo.Mode));
  Assert.AreEqual('privet', Undo.Region);
  Assert.AreEqual('привет', Undo.Replacement);
end;

{ TVersionTests }

procedure TVersionTests.ComparesVersions;
begin
  Assert.IsTrue(CompareVersions('2.1.0', '2.0.0.0') > 0);
  Assert.IsTrue(CompareVersions('v2.0.1', '2.1.0.0') < 0);
  Assert.AreEqual(0, CompareVersions('2.1', '2.1.0.0'));
  Assert.IsTrue(CompareVersions('2.10.0', '2.9.9') > 0);
end;

procedure TVersionTests.NormalisesTags;
begin
  Assert.AreEqual('2.1.0', NormalizeVersionTag(' v2.1.0 '));
  Assert.AreEqual('2.1.0', NormalizeVersionTag('V2.1.0'));
  Assert.AreEqual('2.1.0', NormalizeVersionTag('2.1.0'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTransliterationTests);
  TDUnitX.RegisterTestFixture(TBothShiftTests);
  TDUnitX.RegisterTestFixture(TSettingsMigrationTests);
  TDUnitX.RegisterTestFixture(TUndoTests);
  TDUnitX.RegisterTestFixture(TVersionTests);

end.
