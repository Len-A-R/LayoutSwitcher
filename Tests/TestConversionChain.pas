unit TestConversionChain;

interface

uses
  DUnitX.TestFramework,
  uSettings, uConversionChain;

type
  [TestFixture]
  TConversionChainTests = class
  private
    FChain: TConversionChain;
    // Simulates the worker: applies the plan with a fake transformation.
    function Apply(Action: TLSAction; const Buffer: string;
      const Transform: string; out Plan: TBufferPlan): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure FindsLastWord;
    [Test]
    procedure FindsLastWordBeforeTrailingSpaces;
    [Test]
    procedure NoWordInBlankText;

    [Test]
    procedure FirstPressTakesLastWord;
    [Test]
    procedure TrailingSpacesStayAfterWord;
    [Test]
    procedure SecondPressTakesRestOfPhrase;
    [Test]
    procedure ThirdPressRevertsWholePhrase;
    [Test]
    procedure SingleWordSecondPressReverts;
    [Test]
    procedure FourthPressStartsOver;
    [Test]
    procedure TypingBreaksChain;
    [Test]
    procedure OtherActionBreaksChain;
    [Test]
    procedure CaseActionWidensButDoesNotRevert;
    [Test]
    procedure ResetBreaksChain;
    [Test]
    procedure SelectionReplacementRevertsWhole;
    [Test]
    procedure EmptyBufferHasNoPlan;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  EN = HKL($04090409);
  RU = HKL($04190419);

procedure TConversionChainTests.Setup;
begin
  FChain := TConversionChain.Create;
end;

procedure TConversionChainTests.TearDown;
begin
  FChain.Free;
end;

function TConversionChainTests.Apply(Action: TLSAction; const Buffer: string;
  const Transform: string; out Plan: TBufferPlan): string;
var
  Source, Target: HKL;
begin
  Plan := FChain.Plan(Action, Buffer);
  Assert.AreNotEqual(Ord(bmNone), Ord(Plan.Mode), 'plan expected');
  Assert.AreEqual(Length(Plan.Region), Length(Transform), 'transform length');
  Result := Plan.Head + Transform + Plan.Tail;
  if Plan.ForcedSource <> 0 then
  begin
    Source := Plan.ForcedSource;
    Target := Plan.ForcedTarget;
  end
  else
  begin
    Source := EN;
    Target := RU;
  end;
  FChain.Completed(Plan, Action, Result, Source, Target);
end;

procedure TConversionChainTests.FindsLastWord;
var
  S, L: Integer;
begin
  Assert.IsTrue(FindLastWord('ghbdtn vbh', S, L));
  Assert.AreEqual(8, S);
  Assert.AreEqual(3, L);
  Assert.IsTrue(FindLastWord('vbh', S, L));
  Assert.AreEqual(1, S);
  Assert.AreEqual(3, L);
end;

procedure TConversionChainTests.FindsLastWordBeforeTrailingSpaces;
var
  S, L: Integer;
begin
  Assert.IsTrue(FindLastWord('ghbdtn vbh,  ', S, L));
  Assert.AreEqual(8, S);
  Assert.AreEqual(4, L);
end;

procedure TConversionChainTests.NoWordInBlankText;
var
  S, L: Integer;
begin
  Assert.IsFalse(FindLastWord('', S, L));
  Assert.IsFalse(FindLastWord('   ', S, L));
end;

procedure TConversionChainTests.FirstPressTakesLastWord;
var
  Plan: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn vbh');
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
  Assert.AreEqual('vbh', Plan.Region);
  Assert.AreEqual('ghbdtn ', Plan.Head);
  Assert.AreEqual('', Plan.Tail);
  Assert.AreEqual(3, Plan.DeleteCount);
  Assert.AreEqual(NativeUInt(0), NativeUInt(Plan.ForcedSource));
end;

procedure TConversionChainTests.TrailingSpacesStayAfterWord;
var
  Plan: TBufferPlan;
begin
  Plan := FChain.Plan(laConvert, 'ghbdtn  ');
  Assert.AreEqual('ghbdtn', Plan.Region);
  Assert.AreEqual('  ', Plan.Tail);
  Assert.AreEqual(8, Plan.DeleteCount);
end;

procedure TConversionChainTests.SecondPressTakesRestOfPhrase;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  Assert.AreEqual('ghbdtn мир', Buffer);

  Plan := FChain.Plan(laConvert, Buffer);
  Assert.AreEqual(Ord(bmPhrase), Ord(Plan.Mode));
  Assert.AreEqual('ghbdtn ', Plan.Region);
  Assert.AreEqual('мир', Plan.Tail);
  Assert.AreEqual(Length(Buffer), Plan.DeleteCount);
  // Same direction as the word converted first.
  Assert.AreEqual(NativeUInt(EN), NativeUInt(Plan.ForcedSource));
  Assert.AreEqual(NativeUInt(RU), NativeUInt(Plan.ForcedTarget));
end;

procedure TConversionChainTests.ThirdPressRevertsWholePhrase;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  Buffer := Apply(laConvert, Buffer, 'привет ', Plan);
  Assert.AreEqual('привет мир', Buffer);

  Plan := FChain.Plan(laConvert, Buffer);
  Assert.AreEqual(Ord(bmRevert), Ord(Plan.Mode));
  Assert.AreEqual('привет мир', Plan.Region);
  Assert.AreEqual(NativeUInt(RU), NativeUInt(Plan.ForcedSource));
  Assert.AreEqual(NativeUInt(EN), NativeUInt(Plan.ForcedTarget));
end;

procedure TConversionChainTests.SingleWordSecondPressReverts;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn', 'привет', Plan);
  Plan := FChain.Plan(laConvert, Buffer);
  Assert.AreEqual(Ord(bmRevert), Ord(Plan.Mode));
  Assert.AreEqual('привет', Plan.Region);
  Assert.AreEqual(NativeUInt(RU), NativeUInt(Plan.ForcedSource));
end;

procedure TConversionChainTests.FourthPressStartsOver;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  Buffer := Apply(laConvert, Buffer, 'привет ', Plan);
  Buffer := Apply(laConvert, Buffer, 'ghbdtn vbh', Plan);
  Plan := FChain.Plan(laConvert, Buffer);
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
  Assert.AreEqual('vbh', Plan.Region);
end;

procedure TConversionChainTests.TypingBreaksChain;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  Plan := FChain.Plan(laConvert, Buffer + ' rfr');
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
  Assert.AreEqual('rfr', Plan.Region);
end;

procedure TConversionChainTests.OtherActionBreaksChain;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  Plan := FChain.Plan(laUpperCase, Buffer);
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
  Assert.AreEqual('мир', Plan.Region);
end;

procedure TConversionChainTests.CaseActionWidensButDoesNotRevert;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laUpperCase, 'hello world', 'WORLD', Plan);
  Plan := FChain.Plan(laUpperCase, Buffer);
  Assert.AreEqual(Ord(bmPhrase), Ord(Plan.Mode));
  Assert.AreEqual('hello ', Plan.Region);
  Assert.AreEqual(NativeUInt(0), NativeUInt(Plan.ForcedSource));
  Buffer := Apply(laUpperCase, Buffer, 'HELLO ', Plan);
  Plan := FChain.Plan(laUpperCase, Buffer);
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
end;

procedure TConversionChainTests.ResetBreaksChain;
var
  Plan: TBufferPlan;
  Buffer: string;
begin
  Buffer := Apply(laConvert, 'ghbdtn vbh', 'мир', Plan);
  FChain.Reset;
  Plan := FChain.Plan(laConvert, Buffer);
  Assert.AreEqual(Ord(bmWord), Ord(Plan.Mode));
end;

procedure TConversionChainTests.SelectionReplacementRevertsWhole;
var
  Plan: TBufferPlan;
begin
  FChain.CompletedWhole(laConvert, 'привет мир', 'ghbdtn vbh', EN, RU);
  Plan := FChain.Plan(laConvert, 'привет мир');
  Assert.AreEqual(Ord(bmRevert), Ord(Plan.Mode));
  Assert.AreEqual('привет мир', Plan.Region);
  Assert.AreEqual(NativeUInt(RU), NativeUInt(Plan.ForcedSource));
  Assert.AreEqual(NativeUInt(EN), NativeUInt(Plan.ForcedTarget));
end;

procedure TConversionChainTests.EmptyBufferHasNoPlan;
begin
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laConvert, '').Mode));
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laConvert, '   ').Mode));
  Assert.AreEqual(Ord(bmNone), Ord(FChain.Plan(laNone, 'abc').Mode));
end;

initialization
  TDUnitX.RegisterTestFixture(TConversionChainTests);

end.
