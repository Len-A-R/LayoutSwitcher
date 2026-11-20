unit TestTranslate;

// "Replace text with translation": the Right Ctrl + Right Alt gesture,
// translator requests and responses, the phrase plan, settings.

// Simulated tick counts.
{$Q-}

interface

uses
  DUnitX.TestFramework,
  uSettings, uGestureDetector, uTranslate, uConversionChain;

type
  [TestFixture]
  TCtrlAltChordTests = class
  private
    FDetector: TGestureDetector;
    FTime: Cardinal;
    function Ev(VK: Cardinal; Up: Boolean; WaitBefore: Cardinal = 0): TLSGesture;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CtrlThenAlt;
    [Test]
    procedure AltThenCtrl;
    [Test]
    procedure AltGrWithFakeLeftCtrl;
    [Test]
    procedure AltGrWithFakeRightCtrlCtrlFirst;
    [Test]
    procedure AltGrWithFakeRightCtrlAltFirst;
    [Test]
    procedure AltGrAloneIsNotTheChord;
    [Test]
    procedure SlowChordIsIgnored;
    [Test]
    procedure OtherKeyCancelsChord;
    [Test]
    procedure ChordDoesNotProduceTaps;
    [Test]
    procedure PauseKey;
  end;

  [TestFixture]
  TTranslateTests = class
  public
    [Test]
    procedure ChoosesTarget;
    [Test]
    procedure ParsesGoogle;
    [Test]
    procedure ParsesDeepL;
    [Test]
    procedure BuildsRequests;
    [Test]
    procedure KeepsOuterSpaces;
    [Test]
    procedure RejectsEmptyAndLongText;
    [Test]
    procedure PhrasePlan;
    [Test]
    procedure SettingsAndMigration;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils;

{ TCtrlAltChordTests }

procedure TCtrlAltChordTests.Setup;
begin
  FDetector := TGestureDetector.Create;
  FTime := 100000;
end;

procedure TCtrlAltChordTests.TearDown;
begin
  FDetector.Free;
end;

function TCtrlAltChordTests.Ev(VK: Cardinal; Up: Boolean; WaitBefore: Cardinal): TLSGesture;
begin
  Inc(FTime, WaitBefore);
  Result := FDetector.KeyEvent(VK, Up, FTime);
end;

procedure TCtrlAltChordTests.CtrlThenAlt;
begin
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RCONTROL, False)));
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RMENU, False, 60)));
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RMENU, True, 80)));
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RCONTROL, True, 30)));
end;

procedure TCtrlAltChordTests.AltThenCtrl;
begin
  Ev(VK_RMENU, False);
  Ev(VK_RCONTROL, False, 60);
  Ev(VK_RCONTROL, True, 80);
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RMENU, True, 30)));
end;

procedure TCtrlAltChordTests.AltGrWithFakeLeftCtrl;
begin
  // AltGr: fake Left Ctrl right before Right Alt; real Right Ctrl later.
  Ev(VK_LCONTROL, False);
  Ev(VK_RMENU, False, 1);
  Ev(VK_RCONTROL, False, 60);
  Ev(VK_RCONTROL, True, 80);
  Ev(VK_LCONTROL, True, 30);
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RMENU, True)));
end;

procedure TCtrlAltChordTests.AltGrWithFakeRightCtrlCtrlFirst;
begin
  // The driver reports the fake Ctrl as Right Ctrl, which is already held.
  Ev(VK_RCONTROL, False);
  Ev(VK_RCONTROL, False, 60);   // fake (looks like auto-repeat)
  Ev(VK_RMENU, False, 1);
  Ev(VK_RCONTROL, True, 80);    // fake release together with Alt
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RMENU, True)));
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RCONTROL, True, 20)));   // real release
end;

procedure TCtrlAltChordTests.AltGrWithFakeRightCtrlAltFirst;
begin
  Ev(VK_RCONTROL, False);       // fake
  Ev(VK_RMENU, False, 1);
  Ev(VK_RCONTROL, False, 60);   // real Right Ctrl, not together with Alt
  Ev(VK_RCONTROL, True, 80);
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RMENU, True, 20)));
end;

procedure TCtrlAltChordTests.AltGrAloneIsNotTheChord;
begin
  Ev(VK_RCONTROL, False);       // fake
  Ev(VK_RMENU, False, 1);
  Ev(VK_RCONTROL, True, 80);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RMENU, True)));
  Ev(VK_LCONTROL, False, 700);  // fake Left Ctrl variant (not a double Alt)
  Ev(VK_RMENU, False, 1);
  Ev(VK_LCONTROL, True, 80);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RMENU, True)));
end;

procedure TCtrlAltChordTests.SlowChordIsIgnored;
begin
  Ev(VK_RCONTROL, False);
  Ev(VK_RMENU, False, 200);
  Ev(VK_RMENU, True, 400);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RCONTROL, True, 10)));
end;

procedure TCtrlAltChordTests.OtherKeyCancelsChord;
begin
  // Ctrl+Alt+Delete-like combinations are not the gesture.
  Ev(VK_RCONTROL, False);
  Ev(VK_RMENU, False, 30);
  Ev(VK_DELETE, False, 30);
  Ev(VK_DELETE, True, 30);
  Ev(VK_RMENU, True, 30);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_RCONTROL, True, 10)));
end;

procedure TCtrlAltChordTests.ChordDoesNotProduceTaps;
var
  G: TLSGesture;
begin
  // Two chords in a row are two chords, never a double Right Ctrl/Alt.
  Ev(VK_RCONTROL, False);
  Ev(VK_RMENU, False, 30);
  Ev(VK_RMENU, True, 50);
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RCONTROL, True, 10)));
  Ev(VK_RCONTROL, False, 100);
  Ev(VK_RMENU, False, 30);
  G := Ev(VK_RMENU, True, 50);
  Assert.AreEqual(Ord(lgNone), Ord(G));
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Ev(VK_RCONTROL, True, 10)));
end;

procedure TCtrlAltChordTests.PauseKey;
begin
  // Press and release arrive together.
  Assert.AreEqual(Ord(lgPause), Ord(Ev(VK_PAUSE, False)));
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_PAUSE, True)));
  // With a modifier held it is not the gesture.
  Ev(VK_LSHIFT, False, 100);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_PAUSE, False, 20)));
  Ev(VK_PAUSE, True);
  Ev(VK_LSHIFT, True, 20);
  // It cancels a pending first Shift tap: Shift, Pause, Shift is no double Shift.
  Ev(VK_LSHIFT, False, 1000);
  Ev(VK_LSHIFT, True, 40);
  Assert.AreEqual(Ord(lgPause), Ord(Ev(VK_PAUSE, False, 40)));
  Ev(VK_PAUSE, True);
  Ev(VK_LSHIFT, False, 40);
  Assert.AreEqual(Ord(lgNone), Ord(Ev(VK_LSHIFT, True, 40)));
  Assert.AreEqual('Pause/Break', GestureName(lgPause));
end;

{ TTranslateTests }

procedure TTranslateTests.ChoosesTarget;
begin
  Assert.AreEqual('en', ChooseTranslationTarget('Привет, мир'));
  Assert.AreEqual('ru', ChooseTranslationTarget('Hello world'));
  Assert.AreEqual('ru', ChooseTranslationTarget('Guten Tag'));
end;

procedure TTranslateTests.ParsesGoogle;
var
  Text: string;
begin
  // Real response format of translate.googleapis.com (client=gtx, dt=t).
  Assert.IsTrue(ParseGoogleTranslate('[[["Hi, how are you? ","Привет, как дела? ",null,null,10],' +
    '["Fine.","Хорошо.",null,null,10]],null,"ru",null,null,null,1,[],[["ru"],null,[1],["ru"]]]',
    Text));
  Assert.AreEqual('Hi, how are you? Fine.', Text);
  Assert.IsFalse(ParseGoogleTranslate('{"error":1}', Text));
  Assert.IsFalse(ParseGoogleTranslate('not json', Text));
  Assert.IsFalse(ParseGoogleTranslate('[]', Text));
end;

procedure TTranslateTests.ParsesDeepL;
var
  Text: string;
begin
  Assert.IsTrue(ParseDeepL('{"translations":[{"detected_source_language":"RU",' +
    '"text":"Hello, world"}]}', Text));
  Assert.AreEqual('Hello, world', Text);
  Assert.IsFalse(ParseDeepL('{"message":"Wrong endpoint"}', Text));
  Assert.IsFalse(ParseDeepL('{"translations":[]}', Text));
end;

procedure TTranslateTests.BuildsRequests;
begin
  Assert.AreEqual('client=gtx&sl=auto&tl=en&dt=t&q=%D0%B4%D0%B0%20%26%20%3D',
    GoogleTranslateBody('да & =', 'en'));
  Assert.AreEqual('text=Hi&target_lang=EN-US', DeepLBody('Hi', 'en'));
  Assert.AreEqual('text=Hi&target_lang=RU', DeepLBody('Hi', 'ru'));
  Assert.AreEqual('https://api-free.deepl.com/v2/translate', DeepLEndpoint('abc:fx'));
  Assert.AreEqual('https://api.deepl.com/v2/translate', DeepLEndpoint('abc'));
end;

procedure TTranslateTests.KeepsOuterSpaces;
begin
  Assert.AreEqual('  Hello ', KeepOuterSpaces('  Привет ', 'Hello'));
  Assert.AreEqual('Hello', KeepOuterSpaces('Привет', ' Hello '));
  Assert.AreEqual('Hi', KeepOuterSpaces('', 'Hi'));
end;

procedure TTranslateTests.RejectsEmptyAndLongText;
var
  Text, Service, Error: string;
begin
  // No network call for these.
  Assert.IsFalse(TranslateOnline('   ', 'en', '', Text, Service, Error));
  Assert.AreEqual('empty', Error);
  Assert.IsFalse(TranslateOnline(StringOfChar('a', MAX_TRANSLATE_LENGTH + 1), 'ru', '',
    Text, Service, Error));
  Assert.AreEqual('too_long', Error);
end;

procedure TTranslateTests.PhrasePlan;
var
  Plan: TBufferPlan;
begin
  Plan := TConversionChain.PlanPhrase('  привет мир  ');
  Assert.AreEqual(Ord(bmPhrase), Ord(Plan.Mode));
  Assert.AreEqual('привет мир', Plan.Region);
  Assert.AreEqual('  ', Plan.Head);
  Assert.AreEqual('  ', Plan.Tail);
  Plan := TConversionChain.PlanPhrase('   ');
  Assert.AreEqual(Ord(bmNone), Ord(Plan.Mode));
  Plan := TConversionChain.PlanPhrase('');
  Assert.AreEqual(Ord(bmNone), Ord(Plan.Mode));
end;

procedure TTranslateTests.SettingsAndMigration;
var
  S, Loaded: TLSSettings;
  G: TLSActionGestures;
  FileName: string;
  Diagnostics: Boolean;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(S.GestureForAction(laTranslateReplace)));
  Assert.AreEqual(Ord(laTranslateReplace), Ord(S.ActionForGesture(lgRCtrlRAlt)));
  // Settings of 2.4 get the new gesture, unless it is taken.
  G := S.ActionGestures;
  G[laTranslateReplace] := lgNone;
  MigrateActionGestures(G, 4);
  Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(G[laTranslateReplace]));
  G := S.ActionGestures;
  G[laTranslateReplace] := lgNone;
  G[laUndo] := lgRCtrlRAlt;
  MigrateActionGestures(G, 4);
  Assert.AreEqual(Ord(lgNone), Ord(G[laTranslateReplace]));
  // The DeepL key is saved, but never exported.
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-translate.ini');
  try
    S.DeepLApiKey := 'secret:fx';
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Assert.IsFalse(TFile.ReadAllText(FileName).Contains('secret'));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual('', Loaded.DeepLApiKey);
    Assert.AreEqual(Ord(lgRCtrlRAlt), Ord(Loaded.GestureForAction(laTranslateReplace)));
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCtrlAltChordTests);
  TDUnitX.RegisterTestFixture(TTranslateTests);

end.
