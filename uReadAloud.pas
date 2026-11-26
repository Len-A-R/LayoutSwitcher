unit uReadAloud;

// Reading the selected text aloud with the voices of Windows (SAPI 5): the
// classic voices and the newer ones of the Narrator (OneCore: Irina, Pavel,
// David...), found in their own registry category.  Nothing is downloaded,
// nothing leaves the computer.  Speech runs asynchronously in SAPI's own
// thread; the object lives in the main (STA) thread.

interface

uses
  System.SysUtils, System.Variants;

type
  TReadAloudVoice = record
    Id: string;          // registry path of the voice token
    Name: string;
    Language: Word;      // LANGID: $0419 Russian, $0409 English...
  end;

  TReadAloud = class
  private
    FVoice: OleVariant;
    FVoices: TArray<TReadAloudVoice>;
    FTokens: TArray<OleVariant>;
    FLoaded: Boolean;
    procedure EnsureVoices;
  public
    destructor Destroy; override;
    // All installed voices, Narrator voices first.
    function Voices: TArray<TReadAloudVoice>;
    // Reads Text with the voice VoiceId ('' or not found: a voice of the
    // language of the text).  Rate: -10..10, 0 is normal.  False with
    // ErrorText when no voice can speak.
    function Speak(const Text, VoiceId: string; Rate: Integer; out ErrorText: string): Boolean;
    procedure Stop;
    function Speaking: Boolean;
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
// The text as SAPI XML with pauses the voices of Windows hardly make by
// themselves: after a sentence, a comma, a dash, at the end of a line
// without punctuation (a heading, a list item) and between paragraphs.
// Russian abbreviations are spelled out ("т. е." - "то есть"), list
// markers and Markdown symbols are dropped.
function PrepareSpeech(const Text: string; Russian: Boolean): string;

const
  // SAPI rates of the speed choices 0.75x, 1x, 1.25x, 1.5x, 2x (the rate
  // is about 3^(rate/10) times the normal speed).
  READ_ALOUD_RATES: array[0..4] of Integer = (-3, 0, 2, 4, 6);
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

function PrepareSpeech(const Text: string; Russian: Boolean): string;
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
      if not InChars(Body[Length(Body)], '.!?…:;,")»') then
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

{ TReadAloud }

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

function TReadAloud.Speak(const Text, VoiceId: string; Rate: Integer;
  out ErrorText: string): Boolean;
var
  I, Index: Integer;
  Language: Word;
begin
  Result := False;
  ErrorText := '';
  EnsureVoices;
  Index := -1;
  if VoiceId <> '' then
    for I := 0 to High(FVoices) do
      if SameText(FVoices[I].Id, VoiceId) then
        Index := I;
  if Index < 0 then
  begin
    Language := TextLanguage(Text);
    Index := FindVoiceForLanguage(FVoices, Language);
    // A Russian text read by an English voice is gibberish.
    if (Index < 0) and (Language = $0419) then
    begin
      ErrorText := T('В Windows нет русского голоса. Добавьте: Параметры → Время и язык → ' +
        'Язык и регион → Русский → Языковые параметры → Речь.',
        'Windows has no Russian voice. Add one: Settings → Time & language → Language & ' +
        'region → Russian → Language options → Speech.');
      Exit;
    end;
  end;
  if (Index < 0) and (Length(FVoices) > 0) then
    Index := 0;
  if Index < 0 then
  begin
    ErrorText := T('В Windows нет ни одного голоса. Добавьте: Параметры → Время и язык → ' +
      'Речь → Добавить голоса.', 'Windows has no voice. Add one: Settings → Time & ' +
      'language → Speech → Add voices.');
    Exit;
  end;
  try
    if VarIsEmpty(FVoice) then
      FVoice := CreateOleObject('SAPI.SpVoice');
    PutRef(FVoice, 'Voice', FTokens[Index]);
    FVoice.Rate := Rate;
    FVoice.Speak(PrepareSpeech(Text, FVoices[Index].Language = $0419),
      SVSF_ASYNC or SVSF_PURGE_BEFORE_SPEAK or SVSF_IS_XML);
    Result := True;
  except
    on E: Exception do
      ErrorText := T('Не удалось прочитать текст: ', 'Could not read the text: ') + E.Message;
  end;
end;

procedure TReadAloud.Stop;
begin
  if VarIsEmpty(FVoice) then
    Exit;
  try
    FVoice.Speak('', SVSF_ASYNC or SVSF_PURGE_BEFORE_SPEAK);
  except
    // Nothing to stop.
  end;
end;

function TReadAloud.Speaking: Boolean;
begin
  Result := False;
  if VarIsEmpty(FVoice) then
    Exit;
  try
    Result := FVoice.Status.RunningState <> SRSE_DONE;
  except
    Result := False;
  end;
end;

end.
