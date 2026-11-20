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

  // Automatic replacement of a word ("word=replacement"); with a trailing
  // * the pattern matches any word starting with it.
  TAutoReplace = record
    Pattern: string;      // lower case, ё as е, without the *
    AnyEnding: Boolean;
    Replacement: string;
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

  // Auto-censor list; the feature is off by default.
  DEFAULT_AUTO_REPLACE =
    '# слово=замена; * в конце слова — любое окончание'#13#10 +
    'пиздец=офигеть'#13#10 +
    'бля=блин'#13#10 +
    'блять=блин'#13#10 +
    'блядь=блин'#13#10 +
    'охуеть=офигеть'#13#10 +
    'охуенно=офигенно'#13#10 +
    'хуйня=фигня'#13#10 +
    'нахуй=нафиг'#13#10 +
    'пиздат*=круто'#13#10 +
    'ура=🎉';

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
function ExpandSnippet(const Template: string; Moment: TDateTime): string; overload;
// Also {clipboard} (ClipboardText), escapes \n (line break), \t (tab) and
// \\ (backslash), and {cursor}: CaretBack is the number of Left key presses
// that put the caret there after typing (a line break counts once), 0 when
// the template has no {cursor}.
function ExpandSnippet(const Template: string; Moment: TDateTime;
  const ClipboardText: string; out CaretBack: Integer): string; overload;
function SnippetUsesClipboard(const Template: string): Boolean;

// "word=replacement" per line, # starts a comment.  The word cannot
// contain spaces; a trailing * means "any ending".
function ParseAutoReplace(const Text: string): TArray<TAutoReplace>;
// Word as typed (punctuation around it allowed): the replacement with the
// punctuation kept and the case of the word applied ("Чёрт!" -> "Ой!",
// "ЧЁРТ" -> "ОЙ").  An exact pattern wins over an
// "any ending" one, a longer "any ending" pattern over a shorter one.
function ApplyAutoReplace(const Items: TArray<TAutoReplace>; const Word: string;
  out Replaced: string): Boolean;

// The converted word is a plain word worth checking with the spell checker:
// at least three letters, only letters inside (hyphens and apostrophes
// allowed between letters), no digits.
function IsAutoSwitchCandidate(const Converted: string): Boolean;

// Typo correction: Candidate is Typed with two neighbouring, different
// letters swapped (case-insensitive): "teh" / "the".
function IsAdjacentTransposition(const Typed, Candidate: string): Boolean;
// Candidate written with the case of Typed: lower case keeps the candidate
// as is (proper names stay capitalised), "Teh" -> "The", "TEH" -> "THE".
// False for a mixed case such as "tEh".
function ApplyWordCase(const Typed, Candidate: string; out Fixed: string): Boolean;
// The only spelling suggestion that differs from Word by swapped
// neighbouring letters; False when there is none or more than one, or the
// word is too short (less than 4 letters) to be corrected safely.
// Extended: also one missing, extra or replaced letter ("превет" ->
// "привет"), only in words of at least 5 letters.  Suggestions are in the
// order of the spell checker (most likely first): the best one-letter
// candidate must be among the first two suggestions, and is refused when
// another candidate of the same kind is near (привт: приват / привет) or
// when it adds a letter while a replacement is possible (хорошл: хорошел /
// хорошо).
function ChooseTypoFix(const Word: string; const Suggestions: TArray<string>;
  out Fixed: string; Extended: Boolean = False): Boolean;
// Exactly one inserted, deleted or replaced letter (case-insensitive).
function IsSingleEdit(const Typed, Candidate: string): Boolean;

// Head is the text before a word: True when it ends with ". ", "! " or "? "
// after a real sentence (not "т.е. ", "г. ", "e.g. ", "А. ", "10. ", "...").
function IsSentenceStart(const Head: string): Boolean;
// The word starts with a lower case letter and is not an address or a path.
function CanCapitalize(const Word: string): Boolean;
function CapitalizeFirst(const Word: string): string;
// "word  " (exactly two spaces after a non-space): an accidental double space.
function EndsWithDoubleSpace(const Text: string): Boolean;

// Manual conversions per word, "word=count" items (at most 100, the oldest
// dropped).  Adds Delta and returns the new count; an item reaching 0 is
// removed.  Words are compared case-insensitively and stored lower case.
function BumpLearnCount(var Counts: TArray<string>; const Word: string;
  Delta: Integer): Integer;

// Release description (GitHub Markdown) as plain text for a dialog.
function CleanReleaseNotes(const Markdown: string): string;

function PercentEncode(const Text: string): string;
function ContainsCyrillic(const Text: string): Boolean;
function BuildTranslateUrl(Service: Integer; const Text: string): string;
function BuildSearchUrl(Engine: Integer; const Text: string): string;

implementation

uses
  System.Character, System.Math;

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

function SnippetUsesClipboard(const Template: string): Boolean;
begin
  Result := Pos('{clipboard}', LowerCase(Template)) > 0;
end;

function ExpandSnippet(const Template: string; Moment: TDateTime;
  const ClipboardText: string; out CaretBack: Integer): string;
const
  CURSOR_MARK = #1;
  // Typed character by character outside standard edit boxes.
  MAX_CLIPBOARD = 2000;
var
  Text, Clip: string;
  I, Mark: Integer;
begin
  CaretBack := 0;
  // Escapes first, so that the clipboard text is inserted literally.
  Text := '';
  I := 1;
  while I <= Length(Template) do
  begin
    if (Template[I] = '\') and (I < Length(Template)) then
      case Template[I + 1] of
        'n', 'N':
          begin
            Text := Text + #13#10;
            Inc(I, 2);
            Continue;
          end;
        't', 'T':
          begin
            Text := Text + #9;
            Inc(I, 2);
            Continue;
          end;
        '\':
          begin
            Text := Text + '\';
            Inc(I, 2);
            Continue;
          end;
      end;
    if (Template[I] <> #13) and (Template[I] <> #10) and (Template[I] <> CURSOR_MARK) then
      Text := Text + Template[I];
    Inc(I);
  end;
  Text := Text
    .Replace('{datetime}', FormatDateTime('dd.mm.yyyy hh:nn', Moment), [rfIgnoreCase])
    .Replace('{date}', FormatDateTime('dd.mm.yyyy', Moment), [rfIgnoreCase])
    .Replace('{time}', FormatDateTime('hh:nn', Moment), [rfIgnoreCase]);
  // Only the first {cursor} counts.
  Mark := Pos('{cursor}', LowerCase(Text));
  if Mark > 0 then
    Text := Copy(Text, 1, Mark - 1) + CURSOR_MARK +
      Copy(Text, Mark + Length('{cursor}'), MaxInt).Replace('{cursor}', '',
        [rfIgnoreCase, rfReplaceAll]);
  Clip := ClipboardText;
  if Length(Clip) > MAX_CLIPBOARD then
  begin
    SetLength(Clip, MAX_CLIPBOARD);
    // Do not cut a surrogate pair in half.
    if Clip[Length(Clip)].IsHighSurrogate then
      SetLength(Clip, Length(Clip) - 1);
  end;
  Clip := Clip.Replace(#13#10, #10).Replace(#13, #10).Replace(#10, #13#10)
    .Replace(CURSOR_MARK, '');
  Result := Text.Replace('{clipboard}', Clip, [rfIgnoreCase, rfReplaceAll]);
  Mark := Pos(CURSOR_MARK, Result);
  if Mark > 0 then
  begin
    I := Mark + 1;
    while I <= Length(Result) do
    begin
      // A line break and a surrogate pair (emoji) are one caret step.
      if (Result[I] = #13) and (I < Length(Result)) and (Result[I + 1] = #10) then
        Inc(I)
      else if Result[I].IsHighSurrogate and (I < Length(Result)) and
         Result[I + 1].IsLowSurrogate then
        Inc(I);
      Inc(CaretBack);
      Inc(I);
    end;
    Delete(Result, Mark, 1);
  end;
end;

function NormalizeReplaceWord(const Text: string): string;
begin
  Result := AnsiLowerCase(Text).Replace('ё', 'е');
end;

function ParseAutoReplace(const Text: string): TArray<TAutoReplace>;
var
  Line, Pattern: string;
  Separator: Integer;
  Item: TAutoReplace;
begin
  Result := nil;
  for Line in Text.Split([#13#10, #10, #13]) do
  begin
    if (Trim(Line) = '') or Line.TrimLeft.StartsWith('#') then
      Continue;
    Separator := Pos('=', Line);
    if Separator <= 1 then
      Continue;
    Pattern := Trim(Copy(Line, 1, Separator - 1));
    Item.AnyEnding := Pattern.EndsWith('*');
    if Item.AnyEnding then
      Pattern := Copy(Pattern, 1, Length(Pattern) - 1);
    if (Pattern = '') or (Pos(' ', Pattern) > 0) or (Pos('*', Pattern) > 0) then
      Continue;
    Item.Pattern := NormalizeReplaceWord(Pattern);
    Item.Replacement := Trim(Copy(Line, Separator + 1, MaxInt));
    Result := Result + [Item];
  end;
end;

function ApplyAutoReplace(const Items: TArray<TAutoReplace>; const Word: string;
  out Replaced: string): Boolean;
var
  First, Last, Best, BestLength, I, Upper, Lower: Integer;
  Core, Key, Replacement: string;
begin
  Result := False;
  Replaced := '';
  // The word itself without the punctuation around it.
  First := 1;
  while (First <= Length(Word)) and not Word[First].IsLetterOrDigit do
    Inc(First);
  Last := Length(Word);
  while (Last >= First) and not Word[Last].IsLetterOrDigit do
    Dec(Last);
  if Last < First then
    Exit;
  Core := Copy(Word, First, Last - First + 1);
  Key := NormalizeReplaceWord(Core);
  Best := -1;
  BestLength := -1;
  for I := 0 to High(Items) do
    if not Items[I].AnyEnding and (Items[I].Pattern = Key) then
    begin
      Best := I;
      Break;
    end
    else if Items[I].AnyEnding and Key.StartsWith(Items[I].Pattern) and
       (Length(Items[I].Pattern) > BestLength) then
    begin
      Best := I;
      BestLength := Length(Items[I].Pattern);
    end;
  if Best < 0 then
    Exit;
  Replacement := Items[Best].Replacement;
  if Replacement = '' then
    Exit;
  LetterCount(Core, Upper, Lower);
  if (Lower = 0) and (Upper > 1) then
    Replacement := AnsiUpperCase(Replacement)
  else if (Upper > 0) and Core[1].IsUpper then
    Replacement := AnsiUpperCase(Copy(Replacement, 1, 1)) + Copy(Replacement, 2, MaxInt);
  Replaced := Copy(Word, 1, First - 1) + Replacement + Copy(Word, Last + 1, MaxInt);
  Result := Replaced <> Word;
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

function IsAdjacentTransposition(const Typed, Candidate: string): Boolean;
var
  A, B: string;
  I: Integer;
begin
  Result := False;
  A := AnsiLowerCase(Typed);
  B := AnsiLowerCase(Candidate);
  if (Length(A) <> Length(B)) or (Length(A) < 2) or (A = B) then
    Exit;
  I := 1;
  while A[I] = B[I] do
    Inc(I);
  if (I >= Length(A)) or (A[I] = A[I + 1]) or (A[I] <> B[I + 1]) or
     (A[I + 1] <> B[I]) then
    Exit;
  Result := Copy(A, I + 2, MaxInt) = Copy(B, I + 2, MaxInt);
end;

function ApplyWordCase(const Typed, Candidate: string; out Fixed: string): Boolean;
var
  Upper, Lower: Integer;
begin
  Result := True;
  LetterCount(Typed, Upper, Lower);
  if Upper = 0 then
    Fixed := Candidate
  else if (Lower = 0) and (Upper > 1) then
    Fixed := AnsiUpperCase(Candidate)
  else if (Upper = 1) and Typed[1].IsUpper then
    Fixed := AnsiUpperCase(Copy(Candidate, 1, 1)) + Copy(Candidate, 2, MaxInt)
  else
  begin
    Fixed := '';
    Result := False;
  end;
end;

type
  TEditKind = (ekNone, ekReplace, ekInsert, ekDelete);

function SingleEditKind(const Typed, Candidate: string): TEditKind;
begin
  if not IsSingleEdit(Typed, Candidate) then
    Result := ekNone
  else if Length(Candidate) > Length(Typed) then
    Result := ekInsert
  else if Length(Candidate) < Length(Typed) then
    Result := ekDelete
  else
    Result := ekReplace;
end;

function IsSingleEdit(const Typed, Candidate: string): Boolean;
var
  A, B: string;
  I: Integer;
begin
  A := AnsiLowerCase(Typed);
  B := AnsiLowerCase(Candidate);
  Result := False;
  if (A = B) or (Abs(Length(A) - Length(B)) > 1) then
    Exit;
  I := 1;
  while (I <= Length(A)) and (I <= Length(B)) and (A[I] = B[I]) do
    Inc(I);
  if Length(A) = Length(B) then
    Result := Copy(A, I + 1, MaxInt) = Copy(B, I + 1, MaxInt)   // replaced
  else if Length(A) > Length(B) then
    Result := Copy(A, I + 1, MaxInt) = Copy(B, I, MaxInt)       // extra letter
  else
    Result := Copy(A, I, MaxInt) = Copy(B, I + 1, MaxInt);      // missing letter
end;

function ChooseTypoFix(const Word: string; const Suggestions: TArray<string>;
  out Fixed: string; Extended: Boolean): Boolean;
const
  // One-letter candidates are looked for among the first suggestions only.
  CANDIDATE_WINDOW = 5;
var
  Upper, Lower, Letters, I, BestIndex: Integer;
  Item, Found: string;
  Ambiguous, HasReplace: Boolean;
  Kind, BestKind: TEditKind;
begin
  Result := False;
  Fixed := '';
  Letters := LetterCount(Word, Upper, Lower);
  if not IsAutoSwitchCandidate(Word) or (Letters < 4) then
    Exit;
  Extended := Extended and (Letters >= 5);
  // 1. Swapped neighbours: the only such suggestion.
  Found := '';
  Ambiguous := False;
  for Item in Suggestions do
    if IsAdjacentTransposition(Word, Item) then
    begin
      // "Москва" and "москва" are one candidate, two different words are not.
      if (Found <> '') and not AnsiSameText(Found, Item) then
        Ambiguous := True;
      if Found = '' then
        Found := Item;
    end;
  if Ambiguous then
    Exit;
  if Found <> '' then
    Exit(ApplyWordCase(Word, Found, Fixed));
  if not Extended then
    Exit;

  // 2. One missing, extra or replaced letter, by the spell checker's order.
  BestIndex := -1;
  BestKind := ekNone;
  HasReplace := False;
  for I := 0 to Min(High(Suggestions), CANDIDATE_WINDOW - 1) do
  begin
    Item := Suggestions[I];
    if not IsAutoSwitchCandidate(Item) then
      Continue;
    Kind := SingleEditKind(Word, Item);
    if Kind = ekNone then
      Continue;
    // A replacement among the first three suggestions beats an added letter.
    if (Kind = ekReplace) and (I <= 2) then
      HasReplace := True;
    if BestIndex < 0 then
    begin
      BestIndex := I;
      BestKind := Kind;
    end
    else if (Kind = BestKind) and not AnsiSameText(Item, Suggestions[BestIndex]) then
      Exit; // two candidates of the same kind: not sure which one
  end;
  if (BestIndex < 0) or (BestIndex > 1) then
    Exit;
  if (BestKind = ekInsert) and HasReplace then
    Exit;
  Result := ApplyWordCase(Word, Suggestions[BestIndex], Fixed);
end;

function IsSentenceStart(const Head: string): Boolean;
const
  Abbreviations: array[0..27] of string = (
    'г', 'гг', 'см', 'стр', 'ул', 'д', 'им', 'др', 'пр', 'тыс', 'млн', 'млрд',
    'руб', 'коп', 'т', 'рис', 'табл', 'mr', 'mrs', 'ms', 'dr', 'vs', 'etc', 'st',
    'jr', 'sr', 'no', 'p');
var
  Text, Token, Bare: string;
  I, Start: Integer;
begin
  Result := False;
  // At least one space after the punctuation.
  if (Head = '') or (Head[Length(Head)] <> ' ') then
    Exit;
  Text := TrimRight(Head);
  if Text = '' then
    Exit;
  if not CharInSet(Text[Length(Text)], ['.', '!', '?']) then
    Exit;
  // "..." and "…" do not always end a sentence.
  if Text.EndsWith('..') or Text.EndsWith('…') then
    Exit;
  Start := Length(Text);
  while (Start > 1) and (Text[Start - 1] <> ' ') do
    Dec(Start);
  Token := Copy(Text, Start, MaxInt);
  if Text[Length(Text)] = '.' then
  begin
    Bare := Copy(Token, 1, Length(Token) - 1);
    Bare := Bare.TrimLeft(['(', '"', '«', '''']);
    if Bare = '' then
      Exit;
    // "т.е.", "e.g.": a dot inside; "А.", "10.": an initial or a number.
    if Pos('.', Bare) > 0 then
      Exit;
    if Length(Bare) = 1 then
      Exit;
    for I := 1 to Length(Bare) do
      if Bare[I].IsDigit then
        Exit;
    for I := Low(Abbreviations) to High(Abbreviations) do
      if AnsiSameText(Bare, Abbreviations[I]) then
        Exit;
  end;
  Result := True;
end;

function CanCapitalize(const Word: string): Boolean;
var
  Inner: string;
begin
  Result := (Word <> '') and Word[1].IsLetter and Word[1].IsLower;
  if not Result then
    Exit;
  Inner := Word.TrimRight([',', '.', ';', ':', '!', '?', ')', '"', '»', '''']);
  Result := (Pos('.', Inner) = 0) and (Pos('/', Inner) = 0) and (Pos('@', Inner) = 0) and
    (Pos('\', Inner) = 0) and (Pos('_', Inner) = 0);
end;

function CapitalizeFirst(const Word: string): string;
begin
  Result := Word;
  if Result <> '' then
    Result[1] := Result[1].ToUpper;
end;

function EndsWithDoubleSpace(const Text: string): Boolean;
var
  Len: Integer;
begin
  Len := Length(Text);
  Result := (Len >= 3) and (Text[Len] = ' ') and (Text[Len - 1] = ' ') and
    (Text[Len - 2] <> ' ') and (Text[Len - 2] <> #9);
end;

function BumpLearnCount(var Counts: TArray<string>; const Word: string;
  Delta: Integer): Integer;
const
  MAX_ITEMS = 100;
var
  Key: string;
  I, Separator: Integer;
begin
  Key := AnsiLowerCase(Word);
  Result := 0;
  for I := 0 to High(Counts) do
  begin
    Separator := Counts[I].LastIndexOf('=') + 1;
    if (Separator > 1) and (Copy(Counts[I], 1, Separator - 1) = Key) then
    begin
      Result := StrToIntDef(Copy(Counts[I], Separator + 1, MaxInt), 0);
      Delete(Counts, I, 1);
      Break;
    end;
  end;
  Inc(Result, Delta);
  if Result <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  Counts := Counts + [Key + '=' + IntToStr(Result)];
  while Length(Counts) > MAX_ITEMS do
    Delete(Counts, 0, 1);
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
