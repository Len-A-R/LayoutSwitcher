unit uTextTools;

// Pure text helpers for the automatic corrections, templates and web
// lookups.  No Win32 calls; covered by unit tests.

interface

uses
  System.SysUtils;

type
  TSnippet = record
    Abbreviation: string;
    Template: string;
  end;

const
  TRANSLATOR_YANDEX = 0;
  TRANSLATOR_GOOGLE = 1;
  TRANSLATOR_DEEPL = 2;
  SEARCH_YANDEX = 0;
  SEARCH_GOOGLE = 1;
  SEARCH_BING = 2;
  SEARCH_DUCKDUCKGO = 3;

  DefaultTwoCapitalsExceptions: array[0..11] of string = (
    'VMware', 'OAuth', 'IPsec', 'MBps', 'KBps', 'GBps', 'TBps', 'GHz',
    'МБайт', 'КБайт', 'ГБайт', 'ТБайт');

  DEFAULT_SNIPPETS = ';дата={date}'#13#10';время={time}';

// "пРИВЕТ" -> "Привет": typed with Caps Lock on while holding Shift for the
// first letter.  Requires at least three letters.
function IsCapsLockMistake(const Word: string): Boolean;
function FixCapsLockMistake(const Word: string): string;

// "ПРивет" -> "Привет": two capitals at the start of a word of at least four
// letters, the rest lower case.  Exceptions are compared case-sensitively.
function FixTwoCapitals(const Word: string; const Exceptions: TArray<string>;
  out Fixed: string): Boolean;

// "abbreviation=text" per line; empty lines and lines starting with # are
// skipped.  Abbreviations cannot contain spaces.
function ParseSnippets(const Text: string): TArray<TSnippet>;
function FindSnippet(const Snippets: TArray<TSnippet>; const Word: string;
  out Template: string): Boolean;
// {date} {time} {datetime} placeholders; line breaks are removed.
function ExpandSnippet(const Template: string; Moment: TDateTime): string;

// The converted word is a plain word worth checking with the spell checker:
// at least three letters, only letters inside (hyphens and apostrophes
// allowed between letters), no digits.
function IsAutoSwitchCandidate(const Converted: string): Boolean;

// Release description (GitHub Markdown) as plain text for a dialog.
function CleanReleaseNotes(const Markdown: string): string;

function PercentEncode(const Text: string): string;
function ContainsCyrillic(const Text: string): Boolean;
function BuildTranslateUrl(Service: Integer; const Text: string): string;
function BuildSearchUrl(Engine: Integer; const Text: string): string;

implementation

uses
  System.Character;

function LetterCount(const Word: string; out Upper, Lower: Integer): Integer;
var
  Ch: Char;
begin
  Upper := 0;
  Lower := 0;
  for Ch in Word do
    if Ch.IsUpper then
      Inc(Upper)
    else if Ch.IsLower then
      Inc(Lower);
  Result := Upper + Lower;
end;

function HasDigit(const Word: string): Boolean;
var
  Ch: Char;
begin
  for Ch in Word do
    if Ch.IsDigit then
      Exit(True);
  Result := False;
end;

function FirstLetterIndex(const Word: string): Integer;
var
  I: Integer;
begin
  for I := 1 to Length(Word) do
    if Word[I].IsLetter then
      Exit(I);
  Result := 0;
end;

function IsCapsLockMistake(const Word: string): Boolean;
var
  Upper, Lower, First: Integer;
begin
  Result := False;
  if HasDigit(Word) or (LetterCount(Word, Upper, Lower) < 3) then
    Exit;
  First := FirstLetterIndex(Word);
  Result := (Lower = 1) and Word[First].IsLower;
end;

function FixCapsLockMistake(const Word: string): string;
var
  I: Integer;
begin
  Result := Word;
  for I := 1 to Length(Result) do
    if Result[I].IsUpper then
      Result[I] := Result[I].ToLower
    else if Result[I].IsLower then
      Result[I] := Result[I].ToUpper;
end;

function FixTwoCapitals(const Word: string; const Exceptions: TArray<string>;
  out Fixed: string): Boolean;
var
  Upper, Lower, First, Second, I: Integer;
  Exception: string;
begin
  Result := False;
  Fixed := Word;
  if HasDigit(Word) or (LetterCount(Word, Upper, Lower) < 4) or (Upper <> 2) then
    Exit;
  First := FirstLetterIndex(Word);
  if not Word[First].IsUpper then
    Exit;
  Second := 0;
  for I := First + 1 to Length(Word) do
    if Word[I].IsLetter then
    begin
      Second := I;
      Break;
    end;
  // The two capitals must be adjacent letters at the very start.
  if (Second <> First + 1) or not Word[Second].IsUpper then
    Exit;
  for Exception in Exceptions do
    if Exception = Word.Trim([',', '.', ';', ':', '!', '?', ')', '"', '''']) then
      Exit;
  Fixed[Second] := Fixed[Second].ToLower;
  Result := True;
end;

function ParseSnippets(const Text: string): TArray<TSnippet>;
var
  Line, Abbreviation: string;
  Separator: Integer;
  Item: TSnippet;
begin
  Result := nil;
  for Line in Text.Split([#13#10, #10, #13]) do
  begin
    if (Trim(Line) = '') or Line.TrimLeft.StartsWith('#') then
      Continue;
    Separator := Pos('=', Line);
    if Separator <= 1 then
      Continue;
    Abbreviation := Trim(Copy(Line, 1, Separator - 1));
    if (Abbreviation = '') or (Pos(' ', Abbreviation) > 0) then
      Continue;
    Item.Abbreviation := Abbreviation;
    Item.Template := Copy(Line, Separator + 1, MaxInt);
    Result := Result + [Item];
  end;
end;

function FindSnippet(const Snippets: TArray<TSnippet>; const Word: string;
  out Template: string): Boolean;
var
  Item: TSnippet;
begin
  for Item in Snippets do
    if Item.Abbreviation = Word then
    begin
      Template := Item.Template;
      Exit(True);
    end;
  Template := '';
  Result := False;
end;

function ExpandSnippet(const Template: string; Moment: TDateTime): string;
begin
  Result := Template
    .Replace('{datetime}', FormatDateTime('dd.mm.yyyy hh:nn', Moment), [rfIgnoreCase])
    .Replace('{date}', FormatDateTime('dd.mm.yyyy', Moment), [rfIgnoreCase])
    .Replace('{time}', FormatDateTime('hh:nn', Moment), [rfIgnoreCase])
    .Replace(#13, '').Replace(#10, '');
end;

function IsAutoSwitchCandidate(const Converted: string): Boolean;
var
  I, Letters: Integer;
  Ch: Char;
begin
  Result := False;
  if Converted = '' then
    Exit;
  if not Converted[1].IsLetter or not Converted[Length(Converted)].IsLetter then
    Exit;
  Letters := 0;
  for I := 1 to Length(Converted) do
  begin
    Ch := Converted[I];
    if Ch.IsLetter then
      Inc(Letters)
    else if (Ch <> '-') and (Ch <> '''') and (Ch <> #$2019) then
      Exit;
  end;
  Result := Letters >= 3;
end;

function CleanReleaseNotes(const Markdown: string): string;
const
  MAX_LENGTH = 4000;
var
  Line, Clean: string;
  Lines: TArray<string>;
  Blank: Boolean;
begin
  Result := '';
  Blank := False;
  Lines := Markdown.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for Line in Lines do
  begin
    Clean := Line.Trim;
    while Clean.StartsWith('#') do
      Clean := Clean.Substring(1);
    Clean := Clean.Trim.Replace('**', '').Replace('__', '').Replace('`', '');
    if Clean.StartsWith('- ') or Clean.StartsWith('* ') then
      Clean := '• ' + Clean.Substring(2).Trim;
    if Clean = '' then
    begin
      // Collapse runs of empty lines.
      if (Result <> '') and not Blank then
        Result := Result + sLineBreak;
      Blank := True;
      Continue;
    end;
    Blank := False;
    Result := Result + Clean + sLineBreak;
  end;
  Result := Result.TrimRight;
  if Length(Result) > MAX_LENGTH then
    Result := Copy(Result, 1, MAX_LENGTH) + '…';
end;

function PercentEncode(const Text: string): string;
const
  Hex = '0123456789ABCDEF';
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(Text);
  for B in Bytes do
    if CharInSet(Char(B), ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~']) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + Hex[(B shr 4) + 1] + Hex[(B and $F) + 1];
end;

function ContainsCyrillic(const Text: string): Boolean;
var
  Ch: Char;
begin
  for Ch in Text do
    if (Ch >= #$0400) and (Ch <= #$04FF) then
      Exit(True);
  Result := False;
end;

function BuildTranslateUrl(Service: Integer; const Text: string): string;
var
  Source, Target, Encoded: string;
begin
  // Russian text is translated into English, anything else into Russian.
  if ContainsCyrillic(Text) then
  begin
    Source := 'ru';
    Target := 'en';
  end
  else
  begin
    Source := 'en';
    Target := 'ru';
  end;
  Encoded := PercentEncode(Text);
  case Service of
    TRANSLATOR_GOOGLE:
      Result := Format('https://translate.google.com/?sl=auto&tl=%s&text=%s&op=translate',
        [Target, Encoded]);
    TRANSLATOR_DEEPL:
      Result := Format('https://www.deepl.com/translator#%s/%s/%s',
        [Source, Target, Encoded]);
  else
    Result := Format('https://translate.yandex.ru/?source_lang=%s&target_lang=%s&text=%s',
      [Source, Target, Encoded]);
  end;
end;

function BuildSearchUrl(Engine: Integer; const Text: string): string;
var
  Encoded: string;
begin
  Encoded := PercentEncode(Text);
  case Engine of
    SEARCH_GOOGLE: Result := 'https://www.google.com/search?q=' + Encoded;
    SEARCH_BING: Result := 'https://www.bing.com/search?q=' + Encoded;
    SEARCH_DUCKDUCKGO: Result := 'https://duckduckgo.com/?q=' + Encoded;
  else
    Result := 'https://yandex.ru/search/?text=' + Encoded;
  end;
end;

end.
