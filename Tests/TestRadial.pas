unit TestRadial;

// The radial menu of the middle mouse button: which slice a direction
// points at, the packing of screen points into messages.

interface

uses
  DUnitX.TestFramework,
  uRadialMenu, uMouseHook;

type
  [TestFixture]
  TRadialTests = class
  public
    [Test]
    procedure Slices;
    [Test]
    procedure Points;
  end;

implementation

uses
  System.Types;

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
