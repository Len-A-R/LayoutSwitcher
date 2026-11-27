unit TestRadial;

// The radial menu of the middle mouse button: which slice a direction
// points at, the packing of screen points into messages; the three-finger
// hold of the touchpad.

interface

uses
  DUnitX.TestFramework,
  uRadialMenu, uMouseHook, uTouchpad;

type
  [TestFixture]
  TRadialTests = class
  public
    [Test]
    procedure Slices;
    [Test]
    procedure Points;
    [Test]
    procedure TouchpadHold;
    [Test]
    procedure TouchpadSettings;
  end;

implementation

uses
  System.Types, System.SysUtils, System.IOUtils, uSettings;

function Fingers(Count: Integer; Shift: Integer = 0): TArray<TTouchContact>;
var
  I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Result[I].Id := I;
    Result[I].X := 3000 + I * 1500 + Shift;
    Result[I].Y := 5000;
  end;
end;

// Frames every 10 ms from From for Duration ms; True if the hold fired.
function HoldFor(H: TThreeFingerHold; Count: Integer; From, Duration: Cardinal;
  Shift: Integer = 0): Boolean;
var
  T: Cardinal;
begin
  Result := False;
  T := From;
  while T <= From + Duration do
  begin
    if H.Feed(Fingers(Count, Shift), T) then
      Result := True;
    Inc(T, 10);
  end;
end;

procedure TRadialTests.TouchpadHold;
var
  H: TThreeFingerHold;
  T: Cardinal;
  Fired: Integer;
begin
  Assert.AreEqual(72, Integer(SizeOf(THidPValueCaps)));
  Assert.AreEqual(64, Integer(SizeOf(THidPCaps)));
  H := TThreeFingerHold.Create;
  try
    // Fingers put down one by one, then held still: once.
    T := 1000;
    Assert.IsFalse(H.Feed(Fingers(1), T));
    Assert.IsFalse(H.Feed(Fingers(2), T + 10));
    Assert.IsFalse(H.Feed(Fingers(3), T + 20));
    Fired := 0;
    T := T + 30;
    while T < 1000 + 20 + TOUCH_HOLD_MS + 200 do
    begin
      if H.Feed(Fingers(3, 50), T) then
        Inc(Fired);
      Inc(T, 10);
    end;
    Assert.AreEqual(1, Fired);
    // Lifted: the next hold fires again.
    Assert.IsFalse(H.Feed(nil, T));
    Assert.AreEqual(Ord(fhIdle), Ord(H.State));
    Assert.IsFalse(HoldFor(H, 3, T + 10, TOUCH_HOLD_MS - 20));
    Assert.IsTrue(HoldFor(H, 3, T + TOUCH_HOLD_MS, 30));
    H.Feed(nil, T + 1000);

    // A swipe of Windows (three fingers moving): nothing.
    T := 5000;
    H.Feed(Fingers(3), T);
    Assert.IsFalse(HoldFor(H, 3, T + 10, TOUCH_HOLD_MS + 100, TOUCH_MOVE_TOLERANCE + 100));
    Assert.AreEqual(Ord(fhDone), Ord(H.State));
    H.Feed(nil, T + 1000);

    // A quick tap of Windows: lifted before the time.
    T := 8000;
    H.Feed(Fingers(3), T);
    Assert.IsFalse(H.Feed(nil, T + 120));
    Assert.AreEqual(Ord(fhIdle), Ord(H.State));

    // Four fingers: nothing, even when one is lifted again.
    T := 9000;
    H.Feed(Fingers(3), T);
    H.Feed(Fingers(4), T + 10);
    Assert.IsFalse(HoldFor(H, 3, T + 20, TOUCH_HOLD_MS + 100));
    H.Feed(nil, T + 1000);

    // Reports stopped (fingers gone without the last report): a new start.
    T := 12000;
    H.Feed(Fingers(2), T);
    H.Feed(Fingers(3), T + 10);
    Assert.IsFalse(H.Feed(Fingers(3), T + 10 + TOUCH_STALE_MS + 100));
    Assert.IsTrue(HoldFor(H, 3, T + 20 + TOUCH_STALE_MS + 100, TOUCH_HOLD_MS));
  finally
    H.Free;
  end;
end;

procedure TRadialTests.TouchpadSettings;
var
  S, Loaded: TLSSettings;
  FileName: string;
  Diagnostics: Boolean;
begin
  S := TLSSettings.Defaults;
  Assert.IsTrue(S.TouchpadRadialMenu);
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-touchpad.ini');
  try
    S.TouchpadRadialMenu := False;
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsFalse(Loaded.TouchpadRadialMenu);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TRadialTests.Slices;
begin
  // Eight slices, the first one centred at the top, clockwise.
  Assert.AreEqual(0, RadialSliceAt(0, -100, 8));
  Assert.AreEqual(1, RadialSliceAt(70, -70, 8));
  Assert.AreEqual(2, RadialSliceAt(100, 0, 8));
  Assert.AreEqual(2, RadialSliceAt(105, 40, 8));
  Assert.AreEqual(4, RadialSliceAt(0, 100, 8));
  Assert.AreEqual(6, RadialSliceAt(-100, 0, 8));
  Assert.AreEqual(7, RadialSliceAt(-70, -70, 8));
  // Just left of the top is still the top slice.
  Assert.AreEqual(0, RadialSliceAt(-10, -100, 8));
  Assert.AreEqual(-1, RadialSliceAt(1, 1, 0));
end;

procedure TRadialTests.Points;
var
  P: TPoint;
begin
  P := UnpackPoint(PackPoint(Point(1234, 567)));
  Assert.AreEqual(1234, P.X);
  Assert.AreEqual(567, P.Y);
  // A monitor left of the main one has negative coordinates.
  P := UnpackPoint(PackPoint(Point(-1500, -20)));
  Assert.AreEqual(-1500, P.X);
  Assert.AreEqual(-20, P.Y);
end;

initialization
  TDUnitX.RegisterTestFixture(TRadialTests);

end.
