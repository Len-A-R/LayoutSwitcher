unit TestGestureDetector;

// Simulated tick counts wrap around on purpose.
{$Q-}

interface

uses
  DUnitX.TestFramework,
  uSettings, uGestureDetector;

type
  [TestFixture]
  TGestureDetectorTests = class
  private
    FDetector: TGestureDetector;
    FTime: Cardinal;
    function Press(VK: Cardinal; HoldMS: Cardinal = 50): TLSGesture;
    function Down(VK: Cardinal): TLSGesture;
    function Up(VK: Cardinal): TLSGesture;
    procedure Wait(MS: Cardinal);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure DoubleShiftIsRecognised;
    [Test]
    procedure LeftThenRightShiftCountsAsDoubleShift;
    [Test]
    procedure SlowDoubleShiftIsIgnored;
    [Test]
    procedure LongHoldIsNotATap;
    [Test]
    procedure ShiftUsedForCapitalLetterIsNotATap;
    [Test]
    procedure AltShiftLanguageHotkeyIsIgnored;
    [Test]
    procedure TripleShiftTriggersOnce;
    [Test]
    procedure DoubleLeftCtrl;
    [Test]
    procedure DoubleRightCtrl;
    [Test]
    procedure CtrlCopyIsIgnored;
    [Test]
    procedure BothCtrlChord;
    [Test]
    procedure BothCtrlChordWithOtherKeyIsIgnored;
    [Test]
    procedure ChordDoesNotProduceSingleCtrlTaps;
    [Test]
    procedure OtherModifierCancelsPendingTap;
    [Test]
    procedure AutoRepeatDoesNotBreakTap;
    [Test]
    procedure ResetTapsCancelsPendingTap;
    [Test]
    procedure IntervalIsConfigurable;
    [Test]
    procedure TickCountWrapAround;
    [Test]
    procedure LostReleasesAfterLockBlockTaps;
    [Test]
    procedure ReleaseStaleKeysRestoresTaps;
    [Test]
    procedure ReleaseStaleKeysAfterCtrlAltDel;
    [Test]
    procedure ReleaseStaleKeysKeepsPhysicallyHeldKeys;
    [Test]
    procedure ReleaseStaleKeysIgnoresFreshKeys;
    [Test]
    procedure ResetAllForgetsHeldKeys;
  end;

  [TestFixture]
  TSettingsTests = class
  public
    [Test]
    procedure DefaultsMatchClassicGestures;
    [Test]
    procedure AssigningGestureDisablesPreviousOwner;
    [Test]
    procedure ActionForGestureLooksUpAssignment;
    [Test]
    procedure ParsesProcessList;
    [Test]
    procedure ExclusionIsCaseInsensitive;
    [Test]
    procedure ClampsInterval;
    [Test]
    [TestCase('quoted', '"C:\Program Files\LS\LS.exe",C:\Program Files\LS\LS.exe')]
    [TestCase('quoted with args', '"C:\LS\LS.exe" /min,C:\LS\LS.exe')]
    [TestCase('plain', 'D:\Downloads\LS.exe,D:\Downloads\LS.exe')]
    procedure ExtractsStartupPath(const Command, Expected: string);
  end;

implementation

uses
  Winapi.Windows;

{ TGestureDetectorTests }

procedure TGestureDetectorTests.Setup;
begin
  FDetector := TGestureDetector.Create;
  FDetector.Interval := 500;
  FTime := 100000;
end;

procedure TGestureDetectorTests.TearDown;
begin
  FDetector.Free;
end;

procedure TGestureDetectorTests.Wait(MS: Cardinal);
begin
  Inc(FTime, MS);
end;

function TGestureDetectorTests.Down(VK: Cardinal): TLSGesture;
begin
  Result := FDetector.KeyEvent(VK, False, FTime);
end;

function TGestureDetectorTests.Up(VK: Cardinal): TLSGesture;
begin
  Result := FDetector.KeyEvent(VK, True, FTime);
end;

function TGestureDetectorTests.Press(VK, HoldMS: Cardinal): TLSGesture;
var
  DownResult: TLSGesture;
begin
  DownResult := Down(VK);
  Wait(HoldMS);
  Result := Up(VK);
  if DownResult <> lgNone then
    Result := DownResult;
end;

procedure TGestureDetectorTests.DoubleShiftIsRecognised;
begin
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
  Wait(100);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.LeftThenRightShiftCountsAsDoubleShift;
begin
  Press(VK_LSHIFT);
  Wait(100);
  Assert.AreEqual(lgDoubleShift, Press(VK_RSHIFT));
end;

procedure TGestureDetectorTests.SlowDoubleShiftIsIgnored;
begin
  Press(VK_LSHIFT);
  Wait(700);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
  // ...but the slow second tap starts a new pair.
  Wait(100);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.LongHoldIsNotATap;
begin
  Press(VK_LSHIFT);
  Wait(100);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT, 800));
end;

procedure TGestureDetectorTests.ShiftUsedForCapitalLetterIsNotATap;
begin
  Down(VK_LSHIFT);
  Wait(30);
  Down(Ord('A'));
  Wait(30);
  Up(Ord('A'));
  Wait(30);
  Assert.AreEqual(lgNone, Up(VK_LSHIFT));
  Wait(50);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.AltShiftLanguageHotkeyIsIgnored;
var
  I: Integer;
begin
  for I := 1 to 2 do
  begin
    Down(VK_LMENU);
    Wait(20);
    Down(VK_LSHIFT);
    Wait(20);
    Assert.AreEqual(lgNone, Up(VK_LSHIFT));
    Wait(20);
    Assert.AreEqual(lgNone, Up(VK_LMENU));
    Wait(50);
  end;

  // Shift pressed first, Alt added while it is held.
  for I := 1 to 2 do
  begin
    Down(VK_LSHIFT);
    Wait(20);
    Down(VK_LMENU);
    Wait(20);
    Assert.AreEqual(lgNone, Up(VK_LMENU));
    Wait(20);
    Assert.AreEqual(lgNone, Up(VK_LSHIFT));
    Wait(50);
  end;
end;

procedure TGestureDetectorTests.TripleShiftTriggersOnce;
begin
  Press(VK_LSHIFT);
  Wait(80);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
  Wait(80);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.DoubleLeftCtrl;
begin
  Press(VK_LCONTROL);
  Wait(100);
  Assert.AreEqual(lgDoubleLCtrl, Press(VK_LCONTROL));
end;

procedure TGestureDetectorTests.DoubleRightCtrl;
begin
  Press(VK_RCONTROL);
  Wait(100);
  Assert.AreEqual(lgDoubleRCtrl, Press(VK_RCONTROL));
end;

procedure TGestureDetectorTests.CtrlCopyIsIgnored;
var
  I: Integer;
begin
  for I := 1 to 2 do
  begin
    Down(VK_LCONTROL);
    Wait(20);
    Down(Ord('C'));
    Wait(20);
    Up(Ord('C'));
    Wait(20);
    Assert.AreEqual(lgNone, Up(VK_LCONTROL));
    Wait(50);
  end;
end;

procedure TGestureDetectorTests.BothCtrlChord;
begin
  Down(VK_LCONTROL);
  Wait(30);
  Assert.AreEqual(lgNone, Down(VK_RCONTROL));
  Wait(30);
  Assert.AreEqual(lgNone, Up(VK_LCONTROL));
  Wait(30);
  Assert.AreEqual(lgBothCtrl, Up(VK_RCONTROL));
end;

procedure TGestureDetectorTests.BothCtrlChordWithOtherKeyIsIgnored;
begin
  Down(VK_LCONTROL);
  Down(VK_RCONTROL);
  Down(Ord('X'));
  Up(Ord('X'));
  Up(VK_LCONTROL);
  Assert.AreEqual(lgNone, Up(VK_RCONTROL));
end;

procedure TGestureDetectorTests.ChordDoesNotProduceSingleCtrlTaps;
begin
  Press(VK_LCONTROL);
  Wait(50);
  Down(VK_LCONTROL);
  Down(VK_RCONTROL);
  Wait(30);
  Assert.AreEqual(lgNone, Up(VK_LCONTROL));
  Assert.AreEqual(lgBothCtrl, Up(VK_RCONTROL));
  Wait(50);
  Assert.AreEqual(lgNone, Press(VK_LCONTROL));
end;

procedure TGestureDetectorTests.OtherModifierCancelsPendingTap;
begin
  Press(VK_LSHIFT);
  Wait(50);
  Press(VK_LCONTROL);
  Wait(50);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.AutoRepeatDoesNotBreakTap;
begin
  Press(VK_LSHIFT);
  Wait(50);
  Down(VK_LSHIFT);
  Wait(20);
  Down(VK_LSHIFT); // auto-repeat
  Wait(20);
  Assert.AreEqual(lgDoubleShift, Up(VK_LSHIFT));
end;

procedure TGestureDetectorTests.ResetTapsCancelsPendingTap;
begin
  Press(VK_LSHIFT);
  FDetector.ResetTaps;
  Wait(50);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.IntervalIsConfigurable;
begin
  FDetector.Interval := 300;
  Press(VK_LSHIFT);
  Wait(400);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
  FDetector.Interval := 900;
  Wait(700);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.LostReleasesAfterLockBlockTaps;
begin
  // Win+L: both key-ups go to the secure desktop and never arrive.
  Down(VK_LWIN);
  Wait(30);
  Down(Ord('L'));
  Wait(60000);
  Press(VK_LSHIFT);
  Wait(100);
  Assert.AreEqual(lgNone, Press(VK_LSHIFT));
  Assert.AreEqual(2, FDetector.HeldKeyCount);
end;

procedure TGestureDetectorTests.ReleaseStaleKeysRestoresTaps;
var
  NothingHeld: TKeyStateQuery;
begin
  NothingHeld :=
    function(VK: Cardinal): Boolean
    begin
      Result := False;
    end;
  Down(VK_LWIN);
  Down(Ord('L'));
  Wait(60000);
  Assert.AreEqual(2, FDetector.ReleaseStaleKeys(NothingHeld, FTime, 250));
  Assert.AreEqual(0, FDetector.HeldKeyCount);
  Press(VK_LSHIFT);
  Wait(100);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.ReleaseStaleKeysAfterCtrlAltDel;
var
  NothingHeld: TKeyStateQuery;
begin
  NothingHeld :=
    function(VK: Cardinal): Boolean
    begin
      Result := False;
    end;
  Down(VK_LCONTROL);
  Down(VK_LMENU);
  Down(VK_DELETE);
  Wait(5000);
  FDetector.ReleaseStaleKeys(NothingHeld, FTime, 250);
  Press(VK_LCONTROL);
  Wait(100);
  Assert.AreEqual(lgDoubleLCtrl, Press(VK_LCONTROL));
end;

procedure TGestureDetectorTests.ReleaseStaleKeysKeepsPhysicallyHeldKeys;
var
  OnlyShiftHeld: TKeyStateQuery;
begin
  OnlyShiftHeld :=
    function(VK: Cardinal): Boolean
    begin
      Result := VK = VK_LSHIFT;
    end;
  Down(VK_LSHIFT);
  Down(Ord('Q'));
  Wait(1000);
  Assert.AreEqual(1, FDetector.ReleaseStaleKeys(OnlyShiftHeld, FTime, 250));
  Assert.IsTrue(FDetector.IsDown(VK_LSHIFT));
  Assert.IsFalse(FDetector.IsDown(Ord('Q')));
end;

procedure TGestureDetectorTests.ReleaseStaleKeysIgnoresFreshKeys;
var
  NothingHeld: TKeyStateQuery;
begin
  NothingHeld :=
    function(VK: Cardinal): Boolean
    begin
      Result := False;
    end;
  // The physical state may already show a release that Raw Input has not
  // delivered yet; recently pressed keys must be left alone.
  Down(Ord('A'));
  Wait(100);
  Assert.AreEqual(0, FDetector.ReleaseStaleKeys(NothingHeld, FTime, 250));
  Assert.IsTrue(FDetector.IsDown(Ord('A')));
end;

procedure TGestureDetectorTests.ResetAllForgetsHeldKeys;
begin
  Down(VK_LWIN);
  Down(Ord('L'));
  FDetector.ResetAll;
  Assert.AreEqual(0, FDetector.HeldKeyCount);
  Press(VK_LSHIFT);
  Wait(100);
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT));
end;

procedure TGestureDetectorTests.TickCountWrapAround;
begin
  FTime := $FFFFFF00;
  Press(VK_LSHIFT, 50);
  Wait(200); // crosses zero
  Assert.AreEqual(lgDoubleShift, Press(VK_LSHIFT, 50));
end;

{ TSettingsTests }

procedure TSettingsTests.DefaultsMatchClassicGestures;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(lgDoubleShift, S.GestureForAction(laConvert));
  Assert.AreEqual(lgDoubleLCtrl, S.GestureForAction(laUpperCase));
  Assert.AreEqual(lgDoubleRCtrl, S.GestureForAction(laLowerCase));
  Assert.AreEqual(lgBothCtrl, S.GestureForAction(laInvertCase));
  Assert.AreEqual(Cardinal(500), S.DoubleTapInterval);
  Assert.IsTrue(S.IsProcessExcluded('ShareX.exe'));
end;

procedure TSettingsTests.AssigningGestureDisablesPreviousOwner;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  S.AssignGesture(laInvertCase, lgDoubleShift);
  Assert.AreEqual(lgDoubleShift, S.GestureForAction(laInvertCase));
  Assert.AreEqual(lgNone, S.GestureForAction(laConvert));
  S.AssignGesture(laConvert, lgNone);
  Assert.AreEqual(lgDoubleShift, S.GestureForAction(laInvertCase));
end;

procedure TSettingsTests.ActionForGestureLooksUpAssignment;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(laConvert, S.ActionForGesture(lgDoubleShift));
  Assert.AreEqual(laNone, S.ActionForGesture(lgNone));
  S.AssignGesture(laConvert, lgNone);
  Assert.AreEqual(laNone, S.ActionForGesture(lgDoubleShift));
end;

procedure TSettingsTests.ParsesProcessList;
var
  List: TArray<string>;
begin
  List := ParseProcessList(' ShareX.exe; greenshot ;C:\Tools\obs64.exe,,sharex.EXE');
  Assert.AreEqual<Integer>(3, Length(List));
  Assert.AreEqual('ShareX.exe', List[0]);
  Assert.AreEqual('greenshot.exe', List[1]);
  Assert.AreEqual('obs64.exe', List[2]);
  Assert.AreEqual('ShareX.exe; greenshot.exe; obs64.exe', ProcessListToText(List));
end;

procedure TSettingsTests.ExclusionIsCaseInsensitive;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  Assert.IsTrue(S.IsProcessExcluded('sharex.EXE'));
  Assert.IsFalse(S.IsProcessExcluded('notepad.exe'));
  Assert.IsFalse(S.IsProcessExcluded(''));
end;

procedure TSettingsTests.ClampsInterval;
begin
  Assert.AreEqual(Cardinal(200), ClampDoubleTapInterval(10));
  Assert.AreEqual(Cardinal(1000), ClampDoubleTapInterval(5000));
  Assert.AreEqual(Cardinal(450), ClampDoubleTapInterval(450));
end;

procedure TSettingsTests.ExtractsStartupPath(const Command, Expected: string);
begin
  Assert.AreEqual(Expected, StartupCommandToPath(Command));
end;

initialization
  TDUnitX.RegisterTestFixture(TGestureDetectorTests);
  TDUnitX.RegisterTestFixture(TSettingsTests);

end.
