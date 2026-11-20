unit uInWordSwitch;

// Switching the layout while a word is still being typed: no Russian word
// starts with "ghb", and "при" (the same keys in the Russian layout) is a
// common Russian start, so after the third letter the word is converted.
// The decision uses the first 3 or 4 letters of the dictionary words
// (uWordStarts); only Russian and English are known.

interface

type
  TWordStartLanguage = (wlUnknown, wlRussian, wlEnglish);

// "ru-RU" -> wlRussian, "en-GB" -> wlEnglish.
function WordStartLanguage(const LanguageTag: string): TWordStartLanguage;

// Prefix (3 or 4 characters) starts some dictionary word of the language.
function IsKnownWordStart(Language: TWordStartLanguage; const Prefix: string): Boolean;

// Typed: the beginning of the word as typed (3 or 4 characters) in the
// Source layout; Converted: the same keys in the Target layout.  True when
// the typed start is impossible in Source and a known start in Target.
function ShouldSwitchInWord(Source, Target: TWordStartLanguage;
  const Typed, Converted: string): Boolean;

implementation

uses
  System.SysUtils, System.Character, System.Generics.Collections,
  uWordStarts;

var
  GStarts: array[TWordStartLanguage, 3..4] of TDictionary<string, Boolean>;

function WordStartLanguage(const LanguageTag: string): TWordStartLanguage;
var
  Primary: string;
begin
  Primary := LowerCase(Copy(LanguageTag, 1, 2));
  if Primary = 'ru' then
    Result := wlRussian
  else if Primary = 'en' then
    Result := wlEnglish
  else
    Result := wlUnknown;
end;

function BuildSet(const Rows: array of string; Len: Integer): TDictionary<string, Boolean>;
var
  Row: string;
  I: Integer;
begin
  Result := TDictionary<string, Boolean>.Create(Length(Rows) * 60);
  for Row in Rows do
  begin
    I := 1;
    while I + Len - 1 <= Length(Row) do
    begin
      Result.AddOrSetValue(Copy(Row, I, Len), True);
      Inc(I, Len);
    end;
  end;
end;

function StartSet(Language: TWordStartLanguage; Len: Integer): TDictionary<string, Boolean>;
begin
  // Built on first use; only the main thread calls this.
  if GStarts[Language, Len] = nil then
    case Language of
      wlRussian:
        if Len = 3 then
          GStarts[Language, Len] := BuildSet(RuStarts3, 3)
        else
          GStarts[Language, Len] := BuildSet(RuStarts4, 4);
      wlEnglish:
        if Len = 3 then
          GStarts[Language, Len] := BuildSet(EnStarts3, 3)
        else
          GStarts[Language, Len] := BuildSet(EnStarts4, 4);
    end;
  Result := GStarts[Language, Len];
end;

function Normalize(const Text: string): string;
begin
  Result := AnsiLowerCase(Text).Replace('ё', 'е');
end;

function IsKnownWordStart(Language: TWordStartLanguage; const Prefix: string): Boolean;
var
  Starts: TDictionary<string, Boolean>;
begin
  Result := False;
  if (Language = wlUnknown) or (Length(Prefix) < 3) or (Length(Prefix) > 4) then
    Exit;
  Starts := StartSet(Language, Length(Prefix));
  Result := Assigned(Starts) and Starts.ContainsKey(Normalize(Prefix));
end;

function IsLetterOf(Language: TWordStartLanguage; Ch: Char): Boolean;
begin
  Ch := Ch.ToLower;
  case Language of
    wlRussian: Result := ((Ch >= 'а') and (Ch <= 'я')) or (Ch = 'ё');
    wlEnglish: Result := (Ch >= 'a') and (Ch <= 'z');
  else
    Result := False;
  end;
end;

function ShouldSwitchInWord(Source, Target: TWordStartLanguage;
  const Typed, Converted: string): Boolean;
var
  Ch: Char;
  Upper: Integer;
begin
  Result := False;
  if (Source = wlUnknown) or (Target = wlUnknown) or (Source = Target) or
     (Length(Typed) < 3) or (Length(Typed) > 4) or
     (Length(Converted) <> Length(Typed)) then
    Exit;
  Upper := 0;
  for Ch in Converted do
  begin
    if not IsLetterOf(Target, Ch) then
      Exit;
    if Ch.IsUpper then
      Inc(Upper);
  end;
  // "ВКС", "NASA": abbreviations are left alone.
  if Upper > 1 then
    Exit;
  for Ch in Typed do
    if Ch.IsDigit or Ch.IsWhiteSpace then
      Exit;
  Result := not IsKnownWordStart(Source, Typed) and IsKnownWordStart(Target, Converted);
end;

procedure FreeSets;
var
  Language: TWordStartLanguage;
  Len: Integer;
begin
  for Language := Low(TWordStartLanguage) to High(TWordStartLanguage) do
    for Len := 3 to 4 do
      FreeAndNil(GStarts[Language, Len]);
end;

initialization

finalization
  FreeSets;

end.
