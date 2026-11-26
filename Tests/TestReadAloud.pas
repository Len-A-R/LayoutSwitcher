unit TestReadAloud;

// Reading the selection aloud: the Alt+Scroll Lock gesture, its default and
// migration, the language of a text and the choice of a voice.

interface

uses
  DUnitX.TestFramework,
  uReadAloud, uSettings, uGestureDetector;

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
    S.ReadAloudVoice := 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\X';
    S.ReadAloudSpeed := 3;
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual(S.ReadAloudVoice, Loaded.ReadAloudVoice);
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

initialization
  TDUnitX.RegisterTestFixture(TReadAloudTests);

end.
