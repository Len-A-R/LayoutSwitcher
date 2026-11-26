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

const
  // SAPI rates of the speed choices 0.75x, 1x, 1.25x, 1.5x, 2x (the rate
  // is about 3^(rate/10) times the normal speed).
  READ_ALOUD_RATES: array[0..4] of Integer = (-3, 0, 2, 4, 6);
  READ_ALOUD_SPEED_NAMES: array[0..4] of string = ('0,75×', '1×', '1,25×', '1,5×', '2×');

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.Win.ComObj, uLocale;

const
  SVSF_ASYNC = 1;
  SVSF_PURGE_BEFORE_SPEAK = 2;
  SVSF_IS_NOT_XML = 16;
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
    FVoice.Speak(Text, SVSF_ASYNC or SVSF_PURGE_BEFORE_SPEAK or SVSF_IS_NOT_XML);
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
