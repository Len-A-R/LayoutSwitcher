unit uReadAloud;

// Reading the selected text aloud with the voices of Windows (SAPI 5): the
// classic voices and the newer ones of the Narrator (OneCore: Irina, Pavel,
// David...), found in their own registry category.  Nothing is downloaded,
// nothing leaves the computer.  Speech runs asynchronously in SAPI's own
// thread; the object lives in the main (STA) thread.

interface

uses
  System.SysUtils, System.Variants, uNeuralVoice;

type
  TReadAloudVoice = record
    Id: string;          // registry path of the voice token
    Name: string;
    Language: Word;      // LANGID: $0419 Russian, $0409 English...
  end;

  // A piece of a paragraph in one language.
  TReadSegment = record
    Text: string;
    Language: Word;         // $0419 or $0409
    ParagraphEnd: Boolean;
  end;

  // Segments read one after another by one engine: a neural voice (or
  // several), or one voice of Windows.
  TReadRun = record
    Neural: Boolean;
    Segments: TArray<TNeuralSegment>;
    WindowsVoice: Integer;
    WindowsXml: string;
  end;

  TReadAloud = class
  private
    FVoice: OleVariant;
    FVoices: TArray<TReadAloudVoice>;
    FTokens: TArray<OleVariant>;
    FLoaded: Boolean;
    FNeural: TNeuralSpeaker;
    FRuns: TArray<TReadRun>;
    FRunIndex: Integer;
    FSpeedIndex: Integer;
    FWindowsError: string;
    procedure EnsureVoices;
    function WindowsVoiceFor(const VoiceId: string; Language: Word; out ErrorText: string): Integer;
    function StartRun(Index: Integer): Boolean;
    function RunActive: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // The voices of Windows, Narrator voices first.
    function Voices: TArray<TReadAloudVoice>;
    // Reads Text: Russian pieces with VoiceRu, English ones with VoiceEn
    // ("piper:<id>" a neural voice, a token id a voice of Windows; '' or
    // not installed: the neural voice of the language when downloaded,
    // otherwise a voice of Windows of the language).  SpeedIndex:
    // READ_ALOUD_SPEED_NAMES.  False with ErrorText when no voice can
    // speak; a neural voice may fail later (TakeError).
    function Speak(const Text, VoiceRu, VoiceEn: string; SpeedIndex: Integer;
      out ErrorText: string): Boolean;
    procedure Stop;
    function Speaking: Boolean;
    // An error of a neural voice that came up while reading, once.
    function TakeError: string;
    // Frees the loaded neural voice (it takes about 100 MB).
    procedure Unload;
  end;

// The language of a text by its letters: Cyrillic - Russian, otherwise English.
function TextLanguage(const Text: string): Word;
// "409;9" - $0409.
function ParseVoiceLanguage(const Value: string): Word;
// The voice for a language among Voices: the first one with the same
// primary language; -1 if none.
function FindVoiceForLanguage(const Voices: TArray<TReadAloudVoice>; Language: Word): Integer;
// A valid index of READ_ALOUD_RATES (1, normal speed, for anything else).
function ReadAloudSpeedIndex(Value: Integer): Integer;
// The text for a neural voice as paragraphs: abbreviations spelled out
// (Russian), list markers and Markdown dropped, a full stop after a line
// without a final mark, a dash between words read as a pause (a comma).
function PrepareNeuralText(const Text: string; Russian: Boolean): TArray<string>;
// The installed neural voice of a language, -1 if none.
function InstalledNeuralVoiceFor(Language: Word): Integer;
// Paths, links, hashes and identifiers the short way: "C:\work\uMain.pas"
// - "файл uMain точка pas", "https://github.com/..." - "ссылка на
// github.com", "uMain.pas:120" - "uMain точка pas, строка 120",
// "read_aloud" - "read aloud".  Russian or English words by Russian.
function NormalizeTechText(const Text: string; Russian: Boolean): string;
// A paragraph cut where the alphabet changes: Cyrillic is Russian, Latin is
// English.  In a mostly Russian sentence a Latin insert shorter than
// MIN_ENGLISH_WORDS words stays in the Russian piece (a term, a program
// name: one voice for the phrase).
function SplitByLanguage(const Paragraph: string): TArray<TReadSegment>;

const
  MIN_ENGLISH_WORDS = 3;
// The text as SAPI XML with pauses the voices of Windows hardly make by
// themselves: after a sentence, a comma, a dash, at the end of a line
// without punctuation (a heading, a list item) and between paragraphs.
// Russian abbreviations are spelled out ("т. е." - "то есть"), list
// markers and Markdown symbols are dropped.
function PrepareSpeech(const Text: string; Russian: Boolean; FinalStop: Boolean = True): string;

const
  // SAPI rates of the speed choices 0.75x, 1x, 1.25x, 1.5x, 2x (the rate
  // is about 3^(rate/10) times the normal speed).
  READ_ALOUD_RATES: array[0..4] of Integer = (-3, 0, 2, 4, 6);
  READ_ALOUD_SPEEDS: array[0..4] of Single = (0.75, 1, 1.25, 1.5, 2);
  READ_ALOUD_SPEED_NAMES: array[0..4] of string = ('0,75×', '1×', '1,25×', '1,5×', '2×');

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.Win.ComObj,
  System.Character, uLocale;

const
  SVSF_ASYNC = 1;
  SVSF_PURGE_BEFORE_SPEAK = 2;
  SVSF_IS_XML = 8;
  SVSF_IS_NOT_XML = 16;
  // Pauses, ms.
  PAUSE_SENTENCE = 380;
  PAUSE_ELLIPSIS = 550;
  PAUSE_COMMA = 140;
  PAUSE_COLON = 260;
  PAUSE_DASH = 200;
  PAUSE_BRACKET = 120;
  PAUSE_LINE = 450;
  PAUSE_PARAGRAPH = 750;
  SRSE_DONE = 1;
  ONECORE_VOICES = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices';
  CLASSIC_VOICES = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices';

function TextLanguage(const Text: string): Word;
var
  Ch: Char;
  Cyrillic, Latin: Integer;
begin
  Cyrillic := 0;
  Latin := 0;
  for Ch in Text do
    case Ch of
      'А'..'я', 'Ё', 'ё':
        Inc(Cyrillic);
      'A'..'Z', 'a'..'z':
        Inc(Latin);
    end;
  if Cyrillic >= Latin then
    Result := $0419
  else
    Result := $0409;
end;

function ParseVoiceLanguage(const Value: string): Word;
var
  Code: string;
  Number: Integer;
begin
  Code := Trim(Value);
  if Pos(';', Code) > 0 then
    Code := Copy(Code, 1, Pos(';', Code) - 1);
  if TryStrToInt('$' + Code, Number) then
    Result := Word(Number)
  else
    Result := 0;
end;

function FindVoiceForLanguage(const Voices: TArray<TReadAloudVoice>; Language: Word): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Voices) do
    if Voices[I].Language = Language then
      Exit(I);
  // en-GB for en-US and the like.
  for I := 0 to High(Voices) do
    if (Voices[I].Language and $3FF) = (Language and $3FF) then
      Exit(I);
  Result := -1;
end;

// Obj.Name := Value for an object value: late binding of Delphi uses
// DISPATCH_PROPERTYPUT, SAPI wants DISPATCH_PROPERTYPUTREF ("Set" in VB).
procedure PutRef(const Obj: OleVariant; const Name: string; const Value: OleVariant);
var
  Disp: IDispatch;
  WideName: WideString;
  NamePtr: PWideChar;
  DispId, NamedArg: TDispID;
  Params: TDispParams;
  Arg: OleVariant;
begin
  Disp := IDispatch(Obj);
  WideName := Name;
  NamePtr := PWideChar(WideName);
  OleCheck(Disp.GetIDsOfNames(GUID_NULL, @NamePtr, 1, LOCALE_USER_DEFAULT, @DispId));
  Arg := Value;
  NamedArg := DISPID_PROPERTYPUT;
  Params.rgvarg := @Arg;
  Params.rgdispidNamedArgs := @NamedArg;
  Params.cArgs := 1;
  Params.cNamedArgs := 1;
  OleCheck(Disp.Invoke(DispId, GUID_NULL, LOCALE_USER_DEFAULT, DISPATCH_PROPERTYPUTREF,
    Params, nil, nil, nil));
end;

function ReadAloudSpeedIndex(Value: Integer): Integer;
begin
  if (Value >= Low(READ_ALOUD_RATES)) and (Value <= High(READ_ALOUD_RATES)) then
    Result := Value
  else
    Result := 1;
end;

function InChars(Ch: Char; const Chars: string): Boolean;
begin
  Result := Pos(Ch, Chars) > 0;
end;

function Silence(MS: Integer): string;
begin
  Result := Format('<silence msec="%d"/>', [MS]);
end;

function EscapeXml(Ch: Char): string;
begin
  case Ch of
    '&': Result := '&amp;';
    '<': Result := '&lt;';
    '>': Result := '&gt;';
  else
    Result := Ch;
  end;
end;

// "т. е." and the like: spelled out.  In a pattern "." may be followed by
// spaces and " " stands for one or more spaces.  At the end of a sentence
// (a capital letter or the end of the line follows) the full stop stays.
function ExpandAbbreviations(const Text: string): string;
const
  Pairs: array[0..7, 0..1] of string = (
    ('т.е.', 'то есть'),
    ('т.к.', 'так как'),
    ('т.н.', 'так называемый'),
    ('и т.д.', 'и так далее'),
    ('и т.п.', 'и тому подобное'),
    ('и др.', 'и другие'),
    ('напр.', 'например'),
    ('см.', 'смотрите'));

  function IsSpace(Ch: Char): Boolean;
  begin
    Result := (Ch = ' ') or (Ch = #160);
  end;

  // The length of the pattern matched at Text[Index], 0 if none.
  function MatchAt(const Text, Pattern: string; Index: Integer): Integer;
  var
    I, J: Integer;
  begin
    Result := 0;
    J := Index;
    for I := 1 to Length(Pattern) do
    begin
      if Pattern[I] = ' ' then
      begin
        if (J > Length(Text)) or not IsSpace(Text[J]) then
          Exit;
        while (J <= Length(Text)) and IsSpace(Text[J]) do
          Inc(J);
        Continue;
      end;
      if (J > Length(Text)) or (AnsiLowerCase(Text[J]) <> Pattern[I]) then
        Exit;
      Inc(J);
      // Spaces after a full stop inside the pattern: "т. е.".
      if (Pattern[I] = '.') and (I < Length(Pattern)) and (Pattern[I + 1] <> ' ') then
        while (J <= Length(Text)) and IsSpace(Text[J]) do
          Inc(J);
    end;
    Result := J - Index;
  end;

var
  I, P, Len, Next: Integer;
  B: TStringBuilder;
  Found: Boolean;
begin
  B := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(Text) do
    begin
      Found := False;
      if (I = 1) or not Text[I - 1].IsLetter then
        for P := Low(Pairs) to High(Pairs) do
        begin
          Len := MatchAt(Text, Pairs[P, 0], I);
          if Len = 0 then
            Continue;
          B.Append(Pairs[P, 1]);
          Next := I + Len;
          while (Next <= Length(Text)) and IsSpace(Text[Next]) do
            Inc(Next);
          if (Next > Length(Text)) or (Text[Next] = #10) or Text[Next].IsUpper then
            B.Append('.');
          // The space before the next word stays.
          if (I + Len <= Length(Text)) and IsSpace(Text[I + Len - 1]) then
            B.Append(' ');
          Inc(I, Len);
          Found := True;
          Break;
        end;
      if not Found then
      begin
        B.Append(Text[I]);
        Inc(I);
      end;
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

// "# Заголовок", "- пункт", "* пункт", "• пункт": without the marker.
function StripLineMarker(const Line: string): string;
var
  I: Integer;
begin
  Result := Line;
  I := 1;
  while (I <= Length(Result)) and (Result[I] = '#') do
    Inc(I);
  if (I = 1) and (Result <> '') and InChars(Result[1], '-*•–—') then
    I := 2;
  if (I > 1) and (I <= Length(Result)) and (Result[I] = ' ') then
    Result := TrimLeft(Copy(Result, I, MaxInt));
end;

// Runs of spaces as one space.
function CollapseSpaces(const Line: string): string;
var
  Ch: Char;
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    for Ch in Line do
      if not ((Ch = ' ') and (B.Length > 0) and (B.Chars[B.Length - 1] = ' ')) then
        B.Append(Ch);
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

// The word that ends at Text[Index] (a full stop follows it).
function WordBefore(const Text: string; Index: Integer): string;
var
  Start: Integer;
begin
  Start := Index;
  while (Start >= 1) and Text[Start].IsLetter do
    Dec(Start);
  Result := Copy(Text, Start + 1, Index - Start);
end;

// A full stop after an initial ("А. С. Пушкин") or a short abbreviation
// ("2024 г.", "ул.", "Dr.") does not end a sentence.
function IsAbbreviation(const Word: string): Boolean;
const
  Known: array[0..13] of string = ('г', 'гг', 'ул', 'им', 'проф', 'акад', 'тыс', 'руб',
    'коп', 'млн', 'млрд', 'mr', 'mrs', 'dr');
var
  K: string;
begin
  if Length(Word) = 1 then
    Exit(True);
  for K in Known do
    if SameText(Word, K) then
      Exit(True);
  Result := False;
end;

function PrepareLine(const Line: string): string;
var
  I, N, Mark: Integer;
  Ch, Next: Char;
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    N := Length(Line);
    I := 1;
    while I <= N do
    begin
      Ch := Line[I];
      if I < N then
        Next := Line[I + 1]
      else
        Next := ' ';
      // "..." and "…"
      if ((Ch = '.') and (Copy(Line, I, 3) = '...')) or (Ch = '…') then
      begin
        B.Append('…');
        if Ch = '.' then
          Inc(I, 2);
        B.Append(Silence(PAUSE_ELLIPSIS));
      end
      else if InChars(Ch, '.!?') and ((Next = ' ') or (I = N) or
        InChars(Next, '")»')) then
      begin
        B.Append(Ch);
        Mark := I;
        // Several marks ("?!") make one pause.
        while (I < N) and InChars(Line[I + 1], '.!?")»') do
        begin
          Inc(I);
          B.Append(EscapeXml(Line[I]));
        end;
        if not ((Ch = '.') and IsAbbreviation(WordBefore(Line, Mark - 1))) then
          B.Append(Silence(PAUSE_SENTENCE));
      end
      else if (Ch = ',') and ((Next = ' ') or (I = N)) then
        B.Append(',').Append(Silence(PAUSE_COMMA))
      else if InChars(Ch, ':;') and ((Next = ' ') or (I = N)) then
        B.Append(Ch).Append(Silence(PAUSE_COLON))
      // A dash between words: " — ", " – ", " - ".
      else if InChars(Ch, '—–-') and (I > 1) and (Line[I - 1] = ' ') and
        (Next = ' ') then
        B.Append(Silence(PAUSE_DASH)).Append(Ch)
      else if Ch = '(' then
        B.Append(Silence(PAUSE_BRACKET)).Append(Ch)
      else if Ch = ')' then
        B.Append(Ch).Append(Silence(PAUSE_BRACKET))
      else
        B.Append(EscapeXml(Ch));
      Inc(I);
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function PrepareSpeech(const Text: string; Russian, FinalStop: Boolean): string;
var
  Lines: TArray<string>;
  Line, Body: string;
  B: TStringBuilder;
  Paragraph: Boolean;
begin
  Body := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Body := StringReplace(Body, #13, #10, [rfReplaceAll]);
  Body := StringReplace(Body, #9, ' ', [rfReplaceAll]);
  if Russian then
    Body := ExpandAbbreviations(Body);
  // Markdown emphasis and code marks are not read.
  Body := StringReplace(Body, '**', '', [rfReplaceAll]);
  Body := StringReplace(Body, '__', '', [rfReplaceAll]);
  Body := StringReplace(Body, '`', '', [rfReplaceAll]);
  Lines := Body.Split([#10]);
  B := TStringBuilder.Create;
  try
    Paragraph := False;
    for Line in Lines do
    begin
      Body := Trim(Line);
      // Headings and list markers: "# ", "- ", "* ", "• ".
      Body := CollapseSpaces(StripLineMarker(Body));
      if Body = '' then
      begin
        Paragraph := B.Length > 0;
        Continue;
      end;
      if B.Length > 0 then
      begin
        if Paragraph then
          B.Append(Silence(PAUSE_PARAGRAPH));
        B.Append(' ');
      end;
      Paragraph := False;
      // A line without a final mark (a heading, a list item) ends like a
      // sentence: with a falling tone and a pause.
      if FinalStop and not InChars(Body[Length(Body)], '.!?…:;,")»') then
        Body := Body + '.';
      B.Append(PrepareLine(Body));
      if not B.ToString.EndsWith('/>') then
        B.Append(Silence(PAUSE_LINE));
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function PrepareNeuralText(const Text: string; Russian: Boolean): TArray<string>;
var
  Body, Line, Paragraph: string;
  Lines: TArray<string>;

  procedure Flush;
  begin
    if Trim(Paragraph) <> '' then
      Result := Result + [Trim(Paragraph)];
    Paragraph := '';
  end;

begin
  Result := nil;
  Body := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Body := StringReplace(Body, #13, #10, [rfReplaceAll]);
  Body := StringReplace(Body, #9, ' ', [rfReplaceAll]);
  if Russian then
    Body := ExpandAbbreviations(Body);
  Body := StringReplace(Body, '**', '', [rfReplaceAll]);
  Body := StringReplace(Body, '__', '', [rfReplaceAll]);
  Body := StringReplace(Body, '`', '', [rfReplaceAll]);
  // espeak-ng skips a dash: a comma keeps the pause.
  Body := StringReplace(Body, ' — ', ', ', [rfReplaceAll]);
  Body := StringReplace(Body, ' – ', ', ', [rfReplaceAll]);
  Body := StringReplace(Body, ' - ', ', ', [rfReplaceAll]);
  Lines := Body.Split([#10]);
  Paragraph := '';
  for Line in Lines do
  begin
    Body := CollapseSpaces(StripLineMarker(Trim(Line)));
    if Body = '' then
    begin
      Flush;
      Continue;
    end;
    if not InChars(Body[Length(Body)], '.!?…:;,")»') then
      Body := Body + '.';
    Paragraph := Paragraph + ' ' + Body;
  end;
  Flush;
end;

// Technical tokens read the short human way.  Works on whitespace-separated
// tokens; punctuation around a token (brackets, quotes, a final comma or
// full stop) stays where it is.
function NormalizeTechText(const Text: string; Russian: Boolean): string;

  function W(const Ru, En: string): string;
  begin
    if Russian then
      Result := Ru
    else
      Result := En;
  end;

  function IsHex(const S: string): Boolean;
  var
    Ch: Char;
  begin
    Result := S <> '';
    for Ch in S do
      if not CharInSet(Ch, ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
  end;

  function IsLatinWord(const S: string): Boolean;
  var
    Ch: Char;
  begin
    Result := S <> '';
    for Ch in S do
      if not CharInSet(Ch, ['a'..'z', 'A'..'Z']) then
        Exit(False);
  end;

  function IsIdentifier(const S: string): Boolean;
  var
    Ch: Char;
  begin
    Result := S <> '';
    for Ch in S do
      if not CharInSet(Ch, ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
        Exit(False);
  end;

  // "uMain.pas" - "uMain точка pas"; '' when Name has no file extension.
  function SpokenFileName(const Name: string): string;
  var
    Dot: Integer;
    Base, Ext: string;
  begin
    Result := '';
    Dot := LastDelimiter('.', Name);
    if (Dot <= 1) or (Dot = Length(Name)) then
      Exit;
    Base := Copy(Name, 1, Dot - 1);
    Ext := Copy(Name, Dot + 1, MaxInt);
    if (Length(Ext) > 5) or not IsLatinWord(Ext) then
      Exit;
    Result := Base + W(' точка ', ' dot ') + Ext;
  end;

  // "file.pas:120" or "file.pas:120:5": the name and the line ('' if none).
  procedure SplitLine(const S: string; out Name, Line: string);
  var
    Parts: TArray<string>;
    N: Integer;
  begin
    Name := S;
    Line := '';
    Parts := S.Split([':']);
    if Length(Parts) < 2 then
      Exit;
    // "C:\..." keeps its drive colon.
    if (Length(Parts) >= 2) and TryStrToInt(Parts[1], N) and (Parts[0] <> '') and
       (Length(Parts[0]) > 1) then
    begin
      Name := Parts[0];
      Line := Parts[1];
    end
    else if (Length(Parts) >= 3) and TryStrToInt(Parts[High(Parts) - 1], N) then
    begin
      Name := string.Join(':', Copy(Parts, 0, Length(Parts) - 2));
      Line := Parts[High(Parts) - 1];
    end
    else if TryStrToInt(Parts[High(Parts)], N) then
    begin
      Name := string.Join(':', Copy(Parts, 0, Length(Parts) - 1));
      Line := Parts[High(Parts)];
    end;
  end;

  function WithLine(const Spoken, Line: string): string;
  begin
    Result := Spoken;
    if Line <> '' then
      Result := Result + W(', строка ', ', line ') + Line;
  end;

  function LooksLikePath(const S: string): Boolean;
  var
    Segments: TArray<string>;
    Clean, LastName, Line: string;
  begin
    if (Length(S) >= 3) and CharInSet(S[1], ['A'..'Z', 'a'..'z']) and (S[2] = ':') and
       CharInSet(S[3], ['\', '/']) then
      Exit(True);
    if S.StartsWith('\\') or S.StartsWith('./') or S.StartsWith('../') or S.StartsWith('~/') or
       S.StartsWith('.\') or S.StartsWith('..\') then
      Exit(True);
    Clean := StringReplace(S, '\', '/', [rfReplaceAll]);
    Segments := Clean.Split(['/'], TStringSplitOptions.ExcludeEmpty);
    if Clean.StartsWith('/') and (Length(Segments) >= 2) then
      Exit(True);
    // "src/app/main.ts", "docs/" : two segments with a file name or a final
    // slash ("и/или", "км/ч", "12/05" are not paths).
    if Length(Segments) > 0 then
      SplitLine(Segments[High(Segments)], LastName, Line);
    Result := (Length(Segments) >= 2) and
      ((SpokenFileName(LastName) <> '') or
       (Clean.EndsWith('/') and (Length(Segments) >= 2)) or (Length(Segments) >= 3));
    if Result then
      Result := not IsHex(StringReplace(Clean, '/', '', [rfReplaceAll]));
  end;

  function Convert(const Token: string): string;
  var
    Lower, Host, Name, Line, Last, Spoken, Clean: string;
    Segments: TArray<string>;
    I, Humps: Integer;
  begin
    Result := Token;
    Lower := LowerCase(Token);
    // A link: its site.
    if Lower.StartsWith('http://') or Lower.StartsWith('https://') or Lower.StartsWith('ftp://') or
       Lower.StartsWith('www.') then
    begin
      Host := Token;
      if Pos('://', Host) > 0 then
        Host := Copy(Host, Pos('://', Host) + 3, MaxInt);
      I := Pos('/', Host);
      if I > 0 then
        SetLength(Host, I - 1);
      I := Pos(':', Host);
      if I > 0 then
        SetLength(Host, I - 1);
      if LowerCase(Host).StartsWith('www.') then
        Delete(Host, 1, 4);
      Exit(W('ссылка на ', 'link to ') + Host);
    end;
    // {FF48DBA4-60EF-4201-AA87-54103EEF594E}
    Clean := Token;
    if (Clean <> '') and (Clean[1] = '{') and (Clean[Length(Clean)] = '}') then
      Clean := Copy(Clean, 2, Length(Clean) - 2);
    if (Length(Clean) = 36) and (Clean[9] = '-') and (Clean[14] = '-') and (Clean[19] = '-') and
       (Clean[24] = '-') and IsHex(StringReplace(Clean, '-', '', [rfReplaceAll])) then
      Exit(W('идентификатор', 'identifier'));
    // A hash: long hex with digits and letters.
    Clean := Token;
    if Pos(':', Clean) > 0 then
      Clean := Copy(Clean, Pos(':', Clean) + 1, MaxInt);
    if (Length(Clean) >= 16) and IsHex(Clean) and (LastDelimiter('0123456789', Clean) > 0) and
       (LastDelimiter('abcdefABCDEF', Clean) > 0) then
      Exit(W('хеш', 'hash'));
    // A path: the file or the folder at its end.
    if LooksLikePath(Token) then
    begin
      Clean := StringReplace(Token, '\', '/', [rfReplaceAll]);
      if Clean.EndsWith('/') then
      begin
        Segments := Clean.Split(['/'], TStringSplitOptions.ExcludeEmpty);
        if Length(Segments) = 0 then
          Exit;
        Exit(W('папка ', 'folder ') + Segments[High(Segments)]);
      end;
      Segments := Clean.Split(['/'], TStringSplitOptions.ExcludeEmpty);
      if Length(Segments) = 0 then
        Exit;
      SplitLine(Segments[High(Segments)], Last, Line);
      Spoken := SpokenFileName(Last);
      if Spoken = '' then
        Exit(WithLine(W('папка ', 'folder ') + Last, Line));
      Exit(WithLine(W('файл ', 'file ') + Spoken, Line));
    end;
    // A file name, maybe with a line: "uMain.pas:3747".
    SplitLine(Token, Name, Line);
    if IsIdentifier(StringReplace(Name, '.', '', [rfReplaceAll])) and (Pos('.', Name) > 0) then
    begin
      Spoken := SpokenFileName(Name);
      if Spoken <> '' then
        Exit(WithLine(Spoken, Line));
    end;
    // read_aloud - "read aloud"; ReadAloudVoiceRu - "Read Aloud Voice Ru".
    if IsIdentifier(Token) and (Pos('_', Token) > 1) and (Pos('_', Token) < Length(Token)) then
      Exit(Trim(StringReplace(Token, '_', ' ', [rfReplaceAll])));
    if IsIdentifier(Token) then
    begin
      Humps := 0;
      for I := 2 to Length(Token) do
        if CharInSet(Token[I - 1], ['a'..'z']) and CharInSet(Token[I], ['A'..'Z']) then
          Inc(Humps);
      if (Humps >= 2) or ((Humps = 1) and (Length(Token) >= 8)) then
      begin
        Result := Token[1];
        for I := 2 to Length(Token) do
        begin
          if CharInSet(Token[I - 1], ['a'..'z']) and CharInSet(Token[I], ['A'..'Z']) then
            Result := Result + ' ';
          Result := Result + Token[I];
        end;
      end;
    end;
  end;

const
  // Not braces: a GUID keeps them for its check.
  Leading = '([«"''`';
  Trailing = ')]»"''`,;!?';
var
  I, Start, Stop, Core1, Core2: Integer;
  B: TStringBuilder;
  Token, Core: string;
begin
  B := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(Text) do
    begin
      if Text[I].IsWhiteSpace then
      begin
        B.Append(Text[I]);
        Inc(I);
        Continue;
      end;
      Start := I;
      while (I <= Length(Text)) and not Text[I].IsWhiteSpace do
        Inc(I);
      Stop := I - 1;
      Token := Copy(Text, Start, Stop - Start + 1);
      // Wrapping punctuation; a final full stop or colon unless it ends a
      // folder path ("C:\").
      Core1 := 1;
      Core2 := Length(Token);
      while (Core1 <= Core2) and (Pos(Token[Core1], Leading) > 0) do
        Inc(Core1);
      while (Core2 >= Core1) and ((Pos(Token[Core2], Trailing) > 0) or
        (((Token[Core2] = '.') or (Token[Core2] = ':')) and (Core2 > Core1) and
         not CharInSet(Token[Core2 - 1], ['\', '/']))) do
        Dec(Core2);
      Core := Copy(Token, Core1, Core2 - Core1 + 1);
      if Core = '' then
        B.Append(Token)
      else
        B.Append(Copy(Token, 1, Core1 - 1)).Append(Convert(Core)).Append(Copy(Token, Core2 + 1, MaxInt));
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function InstalledNeuralVoiceFor(Language: Word): Integer;
var
  I: Integer;
begin
  for I := Low(NeuralVoices) to High(NeuralVoices) do
    if (NeuralVoices[I].Language = Language) and IsNeuralVoiceInstalled(NeuralVoices[I]) then
      Exit(I);
  Result := -1;
end;

{ TReadAloud }

constructor TReadAloud.Create;
begin
  inherited;
  FNeural := TNeuralSpeaker.Create;
end;

destructor TReadAloud.Destroy;
begin
  if FLoaded then
    try
      Stop;
    except
      // SAPI gone with the process: nothing to stop.
    end;
  FTokens := nil;
  FVoice := Unassigned;
  FNeural.Free;
  inherited;
end;

procedure TReadAloud.EnsureVoices;

  function VoiceKey(const Name: string): string;
  begin
    Result := Name;
    if Pos(' - ', Result) > 0 then
      Result := Copy(Result, 1, Pos(' - ', Result) - 1);
    Result := Trim(StringReplace(Result, ' Desktop', '', [rfIgnoreCase]));
  end;

  procedure AddCategory(const CategoryId: string);
  var
    Category, Tokens, Token: OleVariant;
    I, J: Integer;
    Voice: TReadAloudVoice;
    Known: Boolean;
  begin
    try
      Category := CreateOleObject('SAPI.SpObjectTokenCategory');
      Category.SetId(CategoryId, False);
      Tokens := Category.EnumerateTokens;
      for I := 0 to Tokens.Count - 1 do
      begin
        Token := Tokens.Item(I);
        Voice.Id := Token.Id;
        Voice.Name := Token.GetDescription;
        Voice.Language := ParseVoiceLanguage(Token.GetAttribute('Language'));
        // The same voice in both categories ("Microsoft Irina - Russian" and
        // "Microsoft Irina Desktop - Russian"): the Narrator one is kept.
        Known := False;
        for J := 0 to High(FVoices) do
          if SameText(VoiceKey(FVoices[J].Name), VoiceKey(Voice.Name)) then
            Known := True;
        if Known then
          Continue;
        FVoices := FVoices + [Voice];
        FTokens := FTokens + [Token];
      end;
    except
      // No such category (Windows without Narrator voices).
    end;
  end;

begin
  if FLoaded then
    Exit;
  FLoaded := True;
  FVoices := nil;
  FTokens := nil;
  AddCategory(ONECORE_VOICES);
  AddCategory(CLASSIC_VOICES);
end;

function TReadAloud.Voices: TArray<TReadAloudVoice>;
begin
  EnsureVoices;
  Result := FVoices;
end;

function SplitSentenceByLanguage(const Paragraph: string): TArray<TReadSegment>;
type
  TRun = record
    Language: Word;
    Start: Integer;         // index of its first word
    Words: Integer;
  end;
var
  Runs: TArray<TRun>;
  I, J, WordStart, Next: Integer;
  Language: Word;
  Ch: Char;
  Segment: TReadSegment;
  RussianWords, EnglishWords: Integer;

  procedure AddWord(Start: Integer; Lang: Word);
  var
    Run: TRun;
  begin
    if (Length(Runs) > 0) and (Runs[High(Runs)].Language = Lang) then
      Inc(Runs[High(Runs)].Words)
    else
    begin
      Run.Language := Lang;
      Run.Start := Start;
      Run.Words := 1;
      Runs := Runs + [Run];
    end;
  end;

begin
  Result := nil;
  Runs := nil;
  // Words and their alphabet; other letters and digits belong to the piece
  // they are in.
  I := 1;
  while I <= Length(Paragraph) do
  begin
    if not Paragraph[I].IsLetter then
    begin
      Inc(I);
      Continue;
    end;
    WordStart := I;
    Language := 0;
    while (I <= Length(Paragraph)) and Paragraph[I].IsLetter do
    begin
      Ch := Paragraph[I];
      case Ch of
        'А'..'я', 'Ё', 'ё': Language := $0419;
        'A'..'Z', 'a'..'z':
          if Language = 0 then
            Language := $0409;
      end;
      Inc(I);
    end;
    if Language <> 0 then
      AddWord(WordStart, Language);
  end;
  if Length(Runs) = 0 then
  begin
    Segment.Text := Trim(Paragraph);
    Segment.Language := TextLanguage(Paragraph);
    Segment.ParagraphEnd := False;
    if Segment.Text <> '' then
      Result := [Segment];
    Exit;
  end;
  // Short English inserts in a mostly Russian text join the Russian piece.
  RussianWords := 0;
  EnglishWords := 0;
  for I := 0 to High(Runs) do
    if Runs[I].Language = $0419 then
      Inc(RussianWords, Runs[I].Words)
    else
      Inc(EnglishWords, Runs[I].Words);
  if (RussianWords > 0) and (RussianWords >= EnglishWords) then
    for I := 0 to High(Runs) do
      if (Runs[I].Language = $0409) and (Runs[I].Words < MIN_ENGLISH_WORDS) then
        Runs[I].Language := $0419;
  // Neighbours of the same language become one piece.
  I := 0;
  while I < High(Runs) do
    if Runs[I + 1].Language = Runs[I].Language then
    begin
      Inc(Runs[I].Words, Runs[I + 1].Words);
      Delete(Runs, I + 1, 1);
    end
    else
      Inc(I);
  // A piece runs to the first word of the next one; the text before the
  // first word goes to the first piece.
  for J := 0 to High(Runs) do
  begin
    if J = 0 then
      WordStart := 1
    else
      WordStart := Runs[J].Start;
    if J < High(Runs) then
      Next := Runs[J + 1].Start
    else
      Next := Length(Paragraph) + 1;
    Segment.Text := Trim(Copy(Paragraph, WordStart, Next - WordStart));
    Segment.Language := Runs[J].Language;
    Segment.ParagraphEnd := False;
    if Segment.Text <> '' then
      Result := Result + [Segment];
  end;
end;

// Sentences end with ".", "!", "?" or "…" followed by a space.
function SplitSentences(const Text: string): TArray<string>;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(Text) - 1 do
    if InChars(Text[I], '.!?…') and (Text[I + 1] = ' ') then
    begin
      Result := Result + [Copy(Text, Start, I - Start + 1)];
      Start := I + 2;
    end;
  if Start <= Length(Text) then
    Result := Result + [Copy(Text, Start, MaxInt)];
end;

function SplitByLanguage(const Paragraph: string): TArray<TReadSegment>;
var
  Sentence: string;
  Segment: TReadSegment;
begin
  // The rule for short inserts looks at each sentence; neighbouring pieces
  // of one language become one again.
  Result := nil;
  for Sentence in SplitSentences(Paragraph) do
    for Segment in SplitSentenceByLanguage(Sentence) do
      if (Length(Result) > 0) and (Result[High(Result)].Language = Segment.Language) then
        Result[High(Result)].Text := Result[High(Result)].Text + ' ' + Segment.Text
      else
        Result := Result + [Segment];
end;

function TReadAloud.WindowsVoiceFor(const VoiceId: string; Language: Word;
  out ErrorText: string): Integer;
var
  I: Integer;
begin
  ErrorText := '';
  EnsureVoices;
  Result := -1;
  if (VoiceId <> '') and not VoiceId.StartsWith(NEURAL_VOICE_PREFIX) then
    for I := 0 to High(FVoices) do
      if SameText(FVoices[I].Id, VoiceId) then
        Result := I;
  if Result < 0 then
    Result := FindVoiceForLanguage(FVoices, Language);
  if Result >= 0 then
    Exit;
  // A Russian text read by an English voice is gibberish.
  if Language = $0419 then
    ErrorText := T('Нет русского голоса. Скачайте нейросетевой голос на вкладке «Чтение ' +
      'вслух» или добавьте голос Windows: Параметры → Время и язык → Язык и регион → ' +
      'Русский → Языковые параметры → Речь.', 'No Russian voice. Download a neural voice ' +
      'on the Read aloud tab or add a Windows voice: Settings → Time & language → Language & ' +
      'region → Russian → Language options → Speech.')
  else if Length(FVoices) > 0 then
    Result := 0
  else
    ErrorText := T('В Windows нет ни одного голоса. Скачайте нейросетевой голос на вкладке ' +
      '«Чтение вслух».', 'Windows has no voice. Download a neural voice on the Read aloud tab.');
end;

function TReadAloud.Speak(const Text, VoiceRu, VoiceEn: string; SpeedIndex: Integer;
  out ErrorText: string): Boolean;
var
  Paragraph, VoiceId: string;
  Segments, Part: TArray<TReadSegment>;
  Segment: TReadSegment;
  NeuralSegment: TNeuralSegment;
  Run: TReadRun;
  Neural, Windows: Integer;
  Last: Boolean;
begin
  Result := False;
  ErrorText := '';
  Stop;
  FSpeedIndex := ReadAloudSpeedIndex(SpeedIndex);
  Segments := nil;
  // Paths and links are not read character by character.
  for Paragraph in PrepareNeuralText(NormalizeTechText(Text, TextLanguage(Text) = $0419), True) do
  begin
    Part := SplitByLanguage(Paragraph);
    if Length(Part) > 0 then
      Part[High(Part)].ParagraphEnd := True;
    Segments := Segments + Part;
  end;
  if Length(Segments) = 0 then
    Exit(True);
  // Each piece to the voice of its language; neighbouring pieces of one
  // engine (and one Windows voice) make one run.
  FRuns := nil;
  for Segment in Segments do
  begin
    if Segment.Language = $0419 then
      VoiceId := VoiceRu
    else
      VoiceId := VoiceEn;
    Neural := -1;
    if VoiceId.StartsWith(NEURAL_VOICE_PREFIX) then
    begin
      Neural := FindNeuralVoice(VoiceId);
      if (Neural >= 0) and not IsNeuralVoiceInstalled(NeuralVoices[Neural]) then
        Neural := -1;
    end;
    if (Neural < 0) and ((VoiceId = '') or VoiceId.StartsWith(NEURAL_VOICE_PREFIX)) then
      Neural := InstalledNeuralVoiceFor(Segment.Language);
    Last := Length(FRuns) > 0;
    if Neural >= 0 then
    begin
      NeuralSegment.Text := Segment.Text;
      NeuralSegment.VoiceIndex := Neural;
      NeuralSegment.ParagraphEnd := Segment.ParagraphEnd;
      if Last and FRuns[High(FRuns)].Neural then
        FRuns[High(FRuns)].Segments := FRuns[High(FRuns)].Segments + [NeuralSegment]
      else
      begin
        Run := Default(TReadRun);
        Run.Neural := True;
        Run.Segments := [NeuralSegment];
        FRuns := FRuns + [Run];
      end;
    end
    else
    begin
      Windows := WindowsVoiceFor(VoiceId, Segment.Language, ErrorText);
      if Windows < 0 then
      begin
        FRuns := nil;
        Exit;
      end;
      if Last and not FRuns[High(FRuns)].Neural and (FRuns[High(FRuns)].WindowsVoice = Windows) then
        FRuns[High(FRuns)].WindowsXml := FRuns[High(FRuns)].WindowsXml + ' ' +
          PrepareSpeech(Segment.Text, Segment.Language = $0419, Segment.ParagraphEnd)
      else
      begin
        Run := Default(TReadRun);
        Run.WindowsVoice := Windows;
        Run.WindowsXml := PrepareSpeech(Segment.Text, Segment.Language = $0419,
          Segment.ParagraphEnd);
        FRuns := FRuns + [Run];
      end;
      if Segment.ParagraphEnd then
        FRuns[High(FRuns)].WindowsXml := FRuns[High(FRuns)].WindowsXml + Silence(PAUSE_PARAGRAPH);
    end;
  end;
  Result := StartRun(0);
  if not Result then
    ErrorText := TakeError;
end;

function TReadAloud.StartRun(Index: Integer): Boolean;
var
  Run: TReadRun;
begin
  Result := False;
  FRunIndex := Index;
  if Index > High(FRuns) then
    Exit;
  Run := FRuns[Index];
  if Run.Neural then
  begin
    FNeural.Speak(Run.Segments, READ_ALOUD_SPEEDS[FSpeedIndex]);
    Exit(True);
  end;
  try
    if VarIsEmpty(FVoice) then
      FVoice := CreateOleObject('SAPI.SpVoice');
    PutRef(FVoice, 'Voice', FTokens[Run.WindowsVoice]);
    FVoice.Rate := READ_ALOUD_RATES[FSpeedIndex];
    FVoice.Speak(Run.WindowsXml, SVSF_ASYNC or SVSF_PURGE_BEFORE_SPEAK or SVSF_IS_XML);
    Result := True;
  except
    on E: Exception do
      FWindowsError := T('Не удалось прочитать текст: ', 'Could not read the text: ') + E.Message;
  end;
end;

procedure TReadAloud.Stop;
begin
  FRuns := nil;
  FRunIndex := 0;
  FNeural.Stop;
  if VarIsEmpty(FVoice) then
    Exit;
  try
    FVoice.Speak('', SVSF_ASYNC or SVSF_PURGE_BEFORE_SPEAK);
  except
    // Nothing to stop.
  end;
end;

function TReadAloud.TakeError: string;
begin
  Result := FNeural.TakeError;
  if Result = '' then
    Result := FWindowsError;
  FWindowsError := '';
end;

procedure TReadAloud.Unload;
begin
  FNeural.Unload;
end;

function TReadAloud.Speaking: Boolean;
begin
  // The next run starts when one is done.
  Result := RunActive;
  while not Result and (FRunIndex < High(FRuns)) do
    Result := StartRun(FRunIndex + 1) and RunActive;
end;

function TReadAloud.RunActive: Boolean;
begin
  Result := FNeural.Speaking;
  if Result or VarIsEmpty(FVoice) then
    Exit;
  try
    Result := FVoice.Status.RunningState <> SRSE_DONE;
  except
    Result := False;
  end;
end;

end.
