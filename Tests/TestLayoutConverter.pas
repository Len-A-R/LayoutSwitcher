unit TestLayoutConverter;

interface

uses
  DUnitX.TestFramework,
  uLayoutConverter;

type
  [TestFixture]
  TLayoutConverterTests = class
  private
    FEn, FRu: TLayoutKeyChars;
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure TablesMatchScanCodeCount;
    [Test]
    [TestCase('word', 'ghbdtn,привет')]
    [TestCase('capitals', 'Ghbdtn,Привет')]
    [TestCase('caps lock', 'GHBDTN,ПРИВЕТ')]
    [TestCase('yo and hard sign', '`]`,ёъё')]
    procedure ConvertsEnglishToRussian(const Input, Expected: string);
    [Test]
    [TestCase('word', 'привет,ghbdtn')]
    procedure ConvertsRussianToEnglish(const Input, Expected: string);
    [Test]
    procedure ConvertsPunctuationByPhysicalKey;
    [Test]
    procedure KeepsDigitsSpacesAndUnknownChars;
    [Test]
    procedure ConvertsMixedTextBothWays;
    [Test]
    procedure RoundTripRestoresText;

    [Test]
    procedure ChoosesLayoutByUniqueLetters;
    [Test]
    procedure TieFallsBackToWindowLayout;
    [Test]
    procedure CountsOnlyUniqueLetters;

    [Test]
    [TestCase('mixed', 'Привет World,пРИВЕТ wORLD')]
    [TestCase('yo', 'ёЁ,Ёё')]
    [TestCase('latin extended', 'ÉcoLE,éCOle')]
    [TestCase('ukrainian', 'Їжак,їЖАК')]
    [TestCase('greek', 'Ωmega,ωMEGA')]
    [TestCase('digits', '123-abc,123-ABC')]
    procedure InvertsCase(const Input, Expected: string);
    [Test]
    procedure ChangesCase;

    [Test]
    procedure SystemCatalogMatchesFixtureWhenEnRuInstalled;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  EnLower = '`1234567890-=qwertyuiop[]asdfghjkl;''\zxcvbnm,./';
  EnUpper = '~!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:"|ZXCVBNM<>?';
  RuLower = 'ё1234567890-=йцукенгшщзхъфывапролджэ\ячсмитьбю.';
  RuUpper = 'Ё!"№;%:?*()_+ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭ/ЯЧСМИТЬБЮ,';

function MakeTable(const Lower, Upper: string; IsoLower, IsoUpper: Char): TLayoutKeyChars;
var
  I: Integer;
begin
  // Same key order as LayoutScanCodes; the last key is the ISO key ($56).
  SetLength(Result, (Length(Lower) + 1) * 2);
  for I := 1 to Length(Lower) do
  begin
    Result[(I - 1) * 2] := Lower[I];
    Result[(I - 1) * 2 + 1] := Upper[I];
  end;
  Result[Length(Lower) * 2] := IsoLower;
  Result[Length(Lower) * 2 + 1] := IsoUpper;
end;

procedure TLayoutConverterTests.Setup;
begin
  FEn := MakeTable(EnLower, EnUpper, '\', '|');
  FRu := MakeTable(RuLower, RuUpper, '\', '/');
end;

procedure TLayoutConverterTests.TablesMatchScanCodeCount;
begin
  Assert.AreEqual(Length(LayoutScanCodes) * 2, Length(FEn));
  Assert.AreEqual(Length(EnLower), Length(RuLower));
  Assert.AreEqual(Length(EnUpper), Length(RuUpper));
end;

procedure TLayoutConverterTests.ConvertsEnglishToRussian(const Input,
  Expected: string);
begin
  Assert.AreEqual(Expected, ConvertTextBetweenLayouts(Input, FEn, FRu));
end;

procedure TLayoutConverterTests.ConvertsRussianToEnglish(const Input,
  Expected: string);
begin
  Assert.AreEqual(Expected, ConvertTextBetweenLayouts(Input, FRu, FEn));
end;

procedure TLayoutConverterTests.ConvertsPunctuationByPhysicalKey;
begin
  // Data contains commas, so it cannot be passed through TestCase.
  Assert.AreEqual('даБ', ConvertTextBetweenLayouts('lf<', FEn, FRu));
  Assert.AreEqual(',/.', ConvertTextBetweenLayouts('б.ю', FRu, FEn));
  Assert.AreEqual('#$^&', ConvertTextBetweenLayouts('№;:?', FRu, FEn));
  Assert.AreEqual('Привет, мир!', ConvertTextBetweenLayouts('Ghbdtn? vbh!', FEn, FRu));
end;

procedure TLayoutConverterTests.KeepsDigitsSpacesAndUnknownChars;
begin
  Assert.AreEqual('123 ' + #$2014 + ' ' + #$20AC,
    ConvertTextBetweenLayouts('123 ' + #$2014 + ' ' + #$20AC, FEn, FRu));
end;

procedure TLayoutConverterTests.ConvertsMixedTextBothWays;
begin
  // Latin letters go EN->RU, Cyrillic letters (absent in EN) go back RU->EN.
  Assert.AreEqual('Вудзрш ghbvth', ConvertTextBetweenLayouts('Delphi пример', FEn, FRu));
end;

procedure TLayoutConverterTests.RoundTripRestoresText;
const
  Sample = 'Ghbdtn, vbh! [jxe ,snm ghjuhfvvbcnjv? "Да" 2026';
var
  Converted: string;
begin
  Converted := ConvertTextBetweenLayouts(Sample, FEn, FRu);
  Assert.AreEqual(Sample, ConvertTextBetweenLayouts(Converted, FRu, FEn));
end;

procedure TLayoutConverterTests.ChoosesLayoutByUniqueLetters;
begin
  Assert.AreEqual(0, ChooseSourceLayout('ghbdtn', [FEn, FRu], 1));
  Assert.AreEqual(1, ChooseSourceLayout('привет', [FEn, FRu], 0));
  Assert.AreEqual(1, ChooseSourceLayout('привet', [FEn, FRu], 0));
end;

procedure TLayoutConverterTests.TieFallsBackToWindowLayout;
begin
  Assert.AreEqual(1, ChooseSourceLayout('12345', [FEn, FRu], 1));
  Assert.AreEqual(0, ChooseSourceLayout('abc где', [FEn, FRu], 0));
  Assert.AreEqual(1, ChooseSourceLayout('abc где', [FEn, FRu], 1));
end;

procedure TLayoutConverterTests.CountsOnlyUniqueLetters;
begin
  Assert.AreEqual(3, CountUniqueLetters('abc123', FEn, FRu));
  Assert.AreEqual(0, CountUniqueLetters('abc123', FRu, FEn));
end;

procedure TLayoutConverterTests.InvertsCase(const Input, Expected: string);
begin
  Assert.AreEqual(Expected, InvertTextCase(Input));
end;

procedure TLayoutConverterTests.ChangesCase;
begin
  Assert.AreEqual('ПРИВЕТ, WORLD ЁЇ', ChangeTextCase('Привет, World ёї', True));
  Assert.AreEqual('привет, world ёї', ChangeTextCase('ПРИВЕТ, World ЁЇ', False));
end;

procedure TLayoutConverterTests.SystemCatalogMatchesFixtureWhenEnRuInstalled;
var
  Layouts: TArray<HKL>;
  Layout, EnLayout, RuLayout: HKL;
  Catalog: TKeyboardLayoutCatalog;
begin
  EnLayout := 0;
  RuLayout := 0;
  Layouts := TKeyboardLayoutCatalog.InstalledLayouts;
  for Layout in Layouts do
    // Standard layouts only: the low and high words are both the language.
    if NativeUInt(Layout) and $FFFFFFFF = $04090409 then
      EnLayout := Layout
    else if NativeUInt(Layout) and $FFFFFFFF = $04190419 then
      RuLayout := Layout;
  if (EnLayout = 0) or (RuLayout = 0) then
  begin
    Assert.Pass('US English and Russian layouts are not both installed');
    Exit;
  end;

  Catalog := TKeyboardLayoutCatalog.Create;
  try
    Assert.AreEqual('Привет, мир!',
      ConvertTextBetweenLayouts('Ghbdtn? vbh!', Catalog.KeyChars(EnLayout),
        Catalog.KeyChars(RuLayout)));
    Assert.AreEqual('Ghbdtn? vbh/',
      ConvertTextBetweenLayouts('Привет, мир.', Catalog.KeyChars(RuLayout),
        Catalog.KeyChars(EnLayout)));
  finally
    Catalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLayoutConverterTests);

end.
