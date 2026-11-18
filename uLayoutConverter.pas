unit uLayoutConverter;

// Layout conversion based on the keyboard layouts actually installed in
// Windows instead of hard-coded EN/RU tables.
//
// A layout is described by a TLayoutKeyChars table: for every physical key
// (scan code) and Shift state the character that the layout produces.  Text
// typed in the wrong layout is converted by looking each character up in the
// source table and taking the character at the same position in the target
// table.  The pure functions in this unit do not call Windows and are covered
// by unit tests; TKeyboardLayoutCatalog builds the tables with ToUnicodeEx.

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Generics.Collections;

type
  // Index = KeyIndex * 2 + ShiftState (0 = no Shift, 1 = Shift).  #0 means
  // the key produces nothing (dead key, AltGr-only, missing key).
  TLayoutKeyChars = TArray<Char>;

  TLayoutPair = record
    Source: HKL;
    Target: HKL;
  end;

// Physical keys of the alphanumeric block in a stable order.  Keys earlier in
// the list win when a layout produces the same character on several keys.
function LayoutScanCodes: TArray<Word>;

// Converts every character found in SourceChars to the character on the same
// key in TargetChars.  Characters that only exist in TargetChars (letters of
// the other alphabet in mixed text) are converted back the other way, the
// rest stays unchanged.
function ConvertTextBetweenLayouts(const Text: string;
  const SourceChars, TargetChars: TLayoutKeyChars): string;

// Number of letters in Text that layout A can type and layout B cannot.
function CountUniqueLetters(const Text: string;
  const A, B: TLayoutKeyChars): Integer;

// Index of the layout the text was most likely typed in.  WindowIndex is
// returned on a tie (e.g. digits only or two Latin layouts).
function ChooseSourceLayout(const Text: string;
  const Layouts: TArray<TLayoutKeyChars>; WindowIndex: Integer): Integer;

function InvertTextCase(const Text: string): string;
function ChangeTextCase(const Text: string; ToUpper: Boolean): string;

type
  TKeyboardLayoutCatalog = class
  private
    FCache: TDictionary<HKL, TLayoutKeyChars>;
    function BuildKeyChars(Layout: HKL): TLayoutKeyChars;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function KeyChars(Layout: HKL): TLayoutKeyChars;
    class function InstalledLayouts: TArray<HKL>; static;
    // Chooses source and target layouts for Text.  PreviousLayout is the
    // layout the user had before the current one (0 if unknown).
    function ChoosePair(const Text: string; WindowLayout,
      PreviousLayout: HKL; out Pair: TLayoutPair): Boolean;
  end;

implementation

uses
  System.Character;

const
  TO_UNICODE_NO_STATE_CHANGE = 4;

function LayoutScanCodes: TArray<Word>;
var
  Code: Word;
begin
  Result := [$29];                       // ` ~  /  ё Ё
  for Code := $02 to $0D do              // 1 .. =
    Result := Result + [Code];
  for Code := $10 to $1B do              // Q .. ]
    Result := Result + [Code];
  for Code := $1E to $28 do              // A .. '
    Result := Result + [Code];
  Result := Result + [$2B];              // \
  for Code := $2C to $35 do              // Z .. /
    Result := Result + [Code];
  Result := Result + [$56];              // ISO key between LShift and Z
end;

function IndexOfChar(const Chars: TLayoutKeyChars; Ch: Char): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Chars) do
    if Chars[I] = Ch then
      Exit(I);
  Result := -1;
end;

function ConvertTextBetweenLayouts(const Text: string;
  const SourceChars, TargetChars: TLayoutKeyChars): string;
var
  I, Index: Integer;
  Ch: Char;
begin
  SetLength(Result, Length(Text));
  for I := 1 to Length(Text) do
  begin
    Ch := Text[I];
    Index := IndexOfChar(SourceChars, Ch);
    if (Index >= 0) and (Index <= High(TargetChars)) and
       (TargetChars[Index] <> #0) then
      Ch := TargetChars[Index]
    else
    begin
      Index := IndexOfChar(TargetChars, Ch);
      if (Index >= 0) and (Index <= High(SourceChars)) and
         (SourceChars[Index] <> #0) then
        Ch := SourceChars[Index];
    end;
    Result[I] := Ch;
  end;
end;

function CountUniqueLetters(const Text: string;
  const A, B: TLayoutKeyChars): Integer;
var
  Ch: Char;
begin
  Result := 0;
  for Ch in Text do
    if Ch.IsLetter and (IndexOfChar(A, Ch) >= 0) and (IndexOfChar(B, Ch) < 0) then
      Inc(Result);
end;

function ChooseSourceLayout(const Text: string;
  const Layouts: TArray<TLayoutKeyChars>; WindowIndex: Integer): Integer;
var
  I, J, Score, BestScore: Integer;
  Ch: Char;
  InOthers: Boolean;
begin
  Result := WindowIndex;
  BestScore := 0;
  for I := 0 to High(Layouts) do
  begin
    // Letters this layout can type and no other candidate can.
    Score := 0;
    for Ch in Text do
    begin
      if not Ch.IsLetter or (IndexOfChar(Layouts[I], Ch) < 0) then
        Continue;
      InOthers := False;
      for J := 0 to High(Layouts) do
        if (J <> I) and (IndexOfChar(Layouts[J], Ch) >= 0) then
        begin
          InOthers := True;
          Break;
        end;
      if not InOthers then
        Inc(Score);
    end;
    if (Score > BestScore) or ((Score = BestScore) and (Score > 0) and
       (I = WindowIndex)) then
    begin
      BestScore := Score;
      Result := I;
    end;
  end;
end;

function InvertTextCase(const Text: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := Text;
  for I := 1 to Length(Result) do
  begin
    Ch := Result[I];
    if Ch.IsSurrogate then
      Continue;
    if Ch.IsLower then
      Result[I] := Ch.ToUpper
    else if Ch.IsUpper then
      Result[I] := Ch.ToLower;
  end;
end;

function ChangeTextCase(const Text: string; ToUpper: Boolean): string;
begin
  if ToUpper then
    Result := Text.ToUpper
  else
    Result := Text.ToLower;
end;

{ TKeyboardLayoutCatalog }

constructor TKeyboardLayoutCatalog.Create;
begin
  inherited Create;
  FCache := TDictionary<HKL, TLayoutKeyChars>.Create;
end;

destructor TKeyboardLayoutCatalog.Destroy;
begin
  FCache.Free;
  inherited;
end;

procedure TKeyboardLayoutCatalog.Clear;
begin
  FCache.Clear;
end;

function TKeyboardLayoutCatalog.BuildKeyChars(Layout: HKL): TLayoutKeyChars;
var
  ScanCodes: TArray<Word>;
  KeyState: TKeyboardState;
  Buffer: array[0..7] of WideChar;
  I, ShiftState, Count: Integer;
  VK: UINT;
begin
  ScanCodes := LayoutScanCodes;
  SetLength(Result, Length(ScanCodes) * 2);
  for I := 0 to High(ScanCodes) do
  begin
    VK := MapVirtualKeyEx(ScanCodes[I], MAPVK_VSC_TO_VK_EX, Layout);
    for ShiftState := 0 to 1 do
    begin
      Result[I * 2 + ShiftState] := #0;
      if VK = 0 then
        Continue;
      FillChar(KeyState, SizeOf(KeyState), 0);
      if ShiftState = 1 then
        KeyState[VK_SHIFT] := $80;
      if VK <= High(KeyState) then
        KeyState[VK] := $80;
      FillChar(Buffer, SizeOf(Buffer), 0);
      // Flag 4 keeps the kernel dead-key state untouched (Windows 10 1607+).
      Count := ToUnicodeEx(VK, ScanCodes[I], KeyState, Buffer, Length(Buffer),
        TO_UNICODE_NO_STATE_CHANGE, Layout);
      if (Count = 1) and (Ord(Buffer[0]) >= 32) then
        Result[I * 2 + ShiftState] := Buffer[0];
    end;
  end;
end;

function TKeyboardLayoutCatalog.KeyChars(Layout: HKL): TLayoutKeyChars;
begin
  if not FCache.TryGetValue(Layout, Result) then
  begin
    Result := BuildKeyChars(Layout);
    FCache.Add(Layout, Result);
  end;
end;

class function TKeyboardLayoutCatalog.InstalledLayouts: TArray<HKL>;
var
  Count: Integer;
  Layouts: array[0..63] of HKL;
begin
  Count := GetKeyboardLayoutList(Length(Layouts), Layouts[0]);
  if Count <= 0 then
    Exit(nil);
  SetLength(Result, Count);
  Move(Layouts[0], Result[0], Count * SizeOf(HKL));
end;

function TKeyboardLayoutCatalog.ChoosePair(const Text: string; WindowLayout,
  PreviousLayout: HKL; out Pair: TLayoutPair): Boolean;
var
  Layouts: TArray<HKL>;
  Tables: TArray<TLayoutKeyChars>;
  I, WindowIndex, SourceIndex, TargetIndex: Integer;
begin
  Result := False;
  Pair.Source := 0;
  Pair.Target := 0;
  Layouts := InstalledLayouts;
  if Length(Layouts) < 2 then
    Exit;

  WindowIndex := 0;
  for I := 0 to High(Layouts) do
    if Layouts[I] = WindowLayout then
    begin
      WindowIndex := I;
      Break;
    end;

  SetLength(Tables, Length(Layouts));
  for I := 0 to High(Layouts) do
    Tables[I] := KeyChars(Layouts[I]);
  SourceIndex := ChooseSourceLayout(Text, Tables, WindowIndex);

  // Text typed in a layout other than the current one is converted into the
  // current one.  Otherwise prefer the layout used before the current one,
  // then simply the next installed layout.
  TargetIndex := -1;
  if SourceIndex <> WindowIndex then
    TargetIndex := WindowIndex
  else
  begin
    for I := 0 to High(Layouts) do
      if (Layouts[I] = PreviousLayout) and (I <> SourceIndex) then
      begin
        TargetIndex := I;
        Break;
      end;
    if TargetIndex < 0 then
      TargetIndex := (SourceIndex + 1) mod Length(Layouts);
  end;

  Pair.Source := Layouts[SourceIndex];
  Pair.Target := Layouts[TargetIndex];
  Result := Pair.Source <> Pair.Target;
end;

end.
