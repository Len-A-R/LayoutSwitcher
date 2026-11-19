unit TestTypos;

// Typo correction: swapped neighbouring letters after a space.

interface

uses
  DUnitX.TestFramework,
  uTextTools, uSpellCheck, uConversionChain, uSettings;

type
  [TestFixture]
  TTypoTests = class
  public
    [Test]
    procedure DetectsAdjacentTransposition;
    [Test]
    procedure KeepsCase;
    [Test]
    procedure ChoosesOnlyUnambiguousFix;
    [Test]
    procedure UndoRestoresTypedWord;
    [Test]
    procedure SettingIsOffByDefaultAndSurvivesExport;
    [Test]
    procedure WindowsSuggestsTransposition;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.IOUtils;

procedure TTypoTests.DetectsAdjacentTransposition;
begin
  Assert.IsTrue(IsAdjacentTransposition('teh', 'the'));
  Assert.IsTrue(IsAdjacentTransposition('пирвет', 'привет'));
  Assert.IsTrue(IsAdjacentTransposition('порядко', 'порядок'));   // last two
  Assert.IsTrue(IsAdjacentTransposition('Пирвет', 'привет'));     // case-insensitive
  Assert.IsFalse(IsAdjacentTransposition('привет', 'привет'));
  Assert.IsFalse(IsAdjacentTransposition('превет', 'привет'));    // replaced letter
  Assert.IsFalse(IsAdjacentTransposition('пиврет', 'привет'));    // not neighbours
  Assert.IsFalse(IsAdjacentTransposition('прриве', 'привет'));
  Assert.IsFalse(IsAdjacentTransposition('привет', 'приветы'));
  Assert.IsFalse(IsAdjacentTransposition('', ''));
end;

procedure TTypoTests.KeepsCase;
var
  Fixed: string;
begin
  Assert.IsTrue(ApplyWordCase('пирвет', 'привет', Fixed));
  Assert.AreEqual('привет', Fixed);
  Assert.IsTrue(ApplyWordCase('Пирвет', 'привет', Fixed));
  Assert.AreEqual('Привет', Fixed);
  Assert.IsTrue(ApplyWordCase('ПИРВЕТ', 'привет', Fixed));
  Assert.AreEqual('ПРИВЕТ', Fixed);
  Assert.IsTrue(ApplyWordCase('мсоква', 'Москва', Fixed));        // proper name
  Assert.AreEqual('Москва', Fixed);
  Assert.IsFalse(ApplyWordCase('пИрвет', 'привет', Fixed));
end;

procedure TTypoTests.ChoosesOnlyUnambiguousFix;
var
  Fixed: string;
begin
  Assert.IsTrue(ChooseTypoFix('Пирвет', ['привет', 'привит', 'пирует'], Fixed));
  Assert.AreEqual('Привет', Fixed);
  Assert.IsTrue(ChooseTypoFix('mkae', ['make', 'Make', 'mike'], Fixed));
  Assert.AreEqual('make', Fixed);
  // Only "form" is "fomr" with swapped neighbours ("from" is not).
  Assert.IsTrue(ChooseTypoFix('fomr', ['from', 'form'], Fixed));
  Assert.AreEqual('form', Fixed);
  // Two different words are possible: nothing is changed.
  Assert.IsFalse(ChooseTypoFix('abdc', ['abcd', 'badc'], Fixed));
  // No suggestion with swapped letters.
  Assert.IsFalse(ChooseTypoFix('превет', ['привет'], Fixed));
  // Too short to be sure.
  Assert.IsFalse(ChooseTypoFix('teh', ['the'], Fixed));
  Assert.IsFalse(ChooseTypoFix('abc1', ['ab1c'], Fixed));
  Assert.IsFalse(ChooseTypoFix('пирвет', [], Fixed));
end;

procedure TTypoTests.UndoRestoresTypedWord;
var
  Chain: TConversionChain;
  Plan, Undo: TBufferPlan;
begin
  Chain := TConversionChain.Create;
  try
    Plan := TConversionChain.PlanWord('скажи пирвет ', 7, 6);
    Assert.AreEqual('пирвет', Plan.Region);
    Chain.Completed(Plan, laNone, 'скажи привет ', 0, 0);
    Undo := Chain.Plan(laUndo, 'скажи привет ');
    Assert.AreEqual(Ord(bmUndo), Ord(Undo.Mode));
    Assert.AreEqual('скажи пирвет ', Undo.Head + Undo.Replacement + Undo.Tail);
    Assert.AreEqual(NativeUInt(0), NativeUInt(Undo.ForcedTarget));
    // Double Shift right after a typo fix converts the word, not reverts it.
    Assert.AreEqual(Ord(bmWord), Ord(Chain.Plan(laConvert, 'скажи привет ').Mode));
  finally
    Chain.Free;
  end;
end;

procedure TTypoTests.SettingIsOffByDefaultAndSurvivesExport;
var
  FileName: string;
  Source, Loaded: TLSSettings;
  Diagnostics: Boolean;
begin
  Assert.IsFalse(TLSSettings.Defaults.FixTypos);
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-typos.ini');
  try
    Source := TLSSettings.Defaults;
    Source.FixTypos := True;
    Assert.IsTrue(ExportSettings(Source, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsTrue(Loaded.FixTypos);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TTypoTests.WindowsSuggestsTransposition;
var
  Spell: TSpellCheck;
  Initialized: Boolean;
  Fixed: string;
begin
  Initialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
  try
    Spell := TSpellCheck.Create;
    try
      if (Spell.CheckWord('en-US', 'hello') = scUnknown) or
         (Spell.CheckWord('ru-RU', 'привет') = scUnknown) then
      begin
        Assert.Pass('en-US/ru-RU spelling dictionaries are not available');
        Exit;
      end;
      Assert.IsTrue(ChooseTypoFix('пирвет', Spell.Suggest('ru-RU', 'пирвет'), Fixed));
      Assert.AreEqual('привет', Fixed);
      Assert.IsTrue(ChooseTypoFix('Woudl', Spell.Suggest('en-US', 'Woudl'), Fixed));
      Assert.AreEqual('Would', Fixed);
      Assert.AreEqual<Integer>(0, Length(Spell.Suggest('xx-XX', 'test')));
    finally
      Spell.Free;
    end;
  finally
    if Initialized then
      CoUninitialize;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypoTests);

end.
