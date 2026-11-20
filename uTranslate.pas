unit uTranslate;

// "Replace text with translation": the text is sent to an online
// translator only when the user asks for it (gesture).
//
// * DeepL API (https://www.deepl.com/pro-api) when the user entered a key;
//   keys ending with ":fx" belong to the free plan (api-free.deepl.com).
//   If DeepL fails (key, quota, HTTP 451 in some regions), Google is used.
// * Otherwise the free Google Translate endpoint used by browser
//   extensions (translate.googleapis.com, client=gtx): no key, but not an
//   official API, so it may be limited.
//
// Russian text is translated into English, any other text into Russian.
// The request and response helpers are pure functions covered by tests;
// TranslateOnline does the HTTP call and must not run on the UI thread.

interface

const
  MAX_TRANSLATE_LENGTH = 5000;

// 'en' for text with Cyrillic letters, otherwise 'ru'.
function ChooseTranslationTarget(const Text: string): string;

function GoogleTranslateBody(const Text, Target: string): string;
function ParseGoogleTranslate(const Json: string; out Translated: string): Boolean;

function DeepLEndpoint(const ApiKey: string): string;
function DeepLBody(const Text, Target: string): string;
function ParseDeepL(const Json: string; out Translated: string): Boolean;

// Leading and trailing white space of Original kept around Translated.
function KeepOuterSpaces(const Original, Translated: string): string;

// Service is 'deepl', 'google' or 'google_after_deepl_<error>'; Error is a short description for the log
// and the notification (no text from the user).
function TranslateOnline(const Text, Target, DeepLApiKey: string;
  out Translated, Service, Error: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.Character,
  System.Generics.Collections, System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
  uTextTools, uWinUtils;

const
  GOOGLE_URL = 'https://translate.googleapis.com/translate_a/single';
  CONNECT_TIMEOUT_MS = 5000;
  RESPONSE_TIMEOUT_MS = 10000;

function ChooseTranslationTarget(const Text: string): string;
begin
  if ContainsCyrillic(Text) then
    Result := 'en'
  else
    Result := 'ru';
end;

function GoogleTranslateBody(const Text, Target: string): string;
begin
  // "dt=t": only the translated sentences.
  Result := 'client=gtx&sl=auto&tl=' + Target + '&dt=t&q=' + PercentEncode(Text);
end;

function ParseGoogleTranslate(const Json: string; out Translated: string): Boolean;
var
  Root: TJSONValue;
  Sentences, Sentence: TJSONArray;
  I: Integer;
begin
  // [[["Hello world","Привет мир",null,null,10], ...], null, "ru", ...]
  Result := False;
  Translated := '';
  Root := TJSONObject.ParseJSONValue(Json);
  try
    if not (Root is TJSONArray) or (TJSONArray(Root).Count = 0) or
       not (TJSONArray(Root).Items[0] is TJSONArray) then
      Exit;
    Sentences := TJSONArray(TJSONArray(Root).Items[0]);
    for I := 0 to Sentences.Count - 1 do
      if (Sentences.Items[I] is TJSONArray) then
      begin
        Sentence := TJSONArray(Sentences.Items[I]);
        if (Sentence.Count > 0) and (Sentence.Items[0] is TJSONString) then
          Translated := Translated + TJSONString(Sentence.Items[0]).Value;
      end;
    Result := Translated <> '';
  finally
    Root.Free;
  end;
end;

function DeepLEndpoint(const ApiKey: string): string;
begin
  if Trim(ApiKey).EndsWith(':fx') then
    Result := 'https://api-free.deepl.com/v2/translate'
  else
    Result := 'https://api.deepl.com/v2/translate';
end;

function DeepLBody(const Text, Target: string): string;
var
  Lang: string;
begin
  // DeepL wants a regional variant for English.
  if Target = 'en' then
    Lang := 'EN-US'
  else
    Lang := UpperCase(Target);
  Result := 'text=' + PercentEncode(Text) + '&target_lang=' + Lang;
end;

function ParseDeepL(const Json: string; out Translated: string): Boolean;
var
  Root, Item: TJSONValue;
  Translations: TJSONArray;
begin
  // {"translations":[{"detected_source_language":"RU","text":"Hello"}]}
  Result := False;
  Translated := '';
  Root := TJSONObject.ParseJSONValue(Json);
  try
    if not (Root is TJSONObject) then
      Exit;
    Item := TJSONObject(Root).GetValue('translations');
    if not (Item is TJSONArray) then
      Exit;
    Translations := TJSONArray(Item);
    if (Translations.Count = 0) or not (Translations.Items[0] is TJSONObject) then
      Exit;
    Item := TJSONObject(Translations.Items[0]).GetValue('text');
    if Item is TJSONString then
      Translated := TJSONString(Item).Value;
    Result := Translated <> '';
  finally
    Root.Free;
  end;
end;

function KeepOuterSpaces(const Original, Translated: string): string;
var
  Lead, Trail: Integer;
begin
  Lead := 0;
  while (Lead < Length(Original)) and Original[Lead + 1].IsWhiteSpace do
    Inc(Lead);
  Trail := 0;
  while (Trail < Length(Original) - Lead) and
        Original[Length(Original) - Trail].IsWhiteSpace do
    Inc(Trail);
  Result := Copy(Original, 1, Lead) + Trim(Translated) +
    Copy(Original, Length(Original) - Trail + 1, Trail);
end;

function Post(Client: THTTPClient; const Url, Body: string; const Headers: TNetHeaders;
  out Response: string; out Error: string): Boolean;
var
  Source: TStringStream;
  Reply: IHTTPResponse;
begin
  Result := False;
  Response := '';
  Source := TStringStream.Create(Body, TEncoding.UTF8);
  try
    try
      Reply := Client.Post(Url, Source, nil, Headers);
      if Reply.StatusCode <> 200 then
      begin
        Error := Format('http_%d', [Reply.StatusCode]);
        Exit;
      end;
      Response := Reply.ContentAsString(TEncoding.UTF8);
      Result := True;
    except
      on E: Exception do
        Error := E.ClassName;
    end;
  finally
    Source.Free;
  end;
end;

function TranslateOnline(const Text, Target, DeepLApiKey: string;
  out Translated, Service, Error: string): Boolean;
var
  Client: THTTPClient;
  Response, Source: string;
  Headers: TNetHeaders;
begin
  Result := False;
  Translated := '';
  Service := '';
  Error := '';
  Source := Trim(Text);
  if Source = '' then
  begin
    Error := 'empty';
    Exit;
  end;
  if Length(Source) > MAX_TRANSLATE_LENGTH then
  begin
    Error := 'too_long';
    Exit;
  end;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := CONNECT_TIMEOUT_MS;
    Client.ResponseTimeout := RESPONSE_TIMEOUT_MS;
    Client.UserAgent := 'LayoutSwitcher/' + GetExecutableVersion;
    Client.ContentType := 'application/x-www-form-urlencoded; charset=utf-8';
    if Trim(DeepLApiKey) <> '' then
    begin
      Service := 'deepl';
      Headers := [TNetHeader.Create('Authorization', 'DeepL-Auth-Key ' + Trim(DeepLApiKey))];
      if Post(Client, DeepLEndpoint(DeepLApiKey), DeepLBody(Source, Target), Headers,
           Response, Error) and not ParseDeepL(Response, Translated) then
        Error := 'bad_response';
    end;
    // No key, or DeepL failed (wrong key, quota, not available in the
    // region - HTTP 451): Google Translate.
    if Translated = '' then
    begin
      if Service = 'deepl' then
        Service := 'google_after_deepl_' + Error
      else
        Service := 'google';
      Error := '';
      Headers := nil;
      if Post(Client, GOOGLE_URL, GoogleTranslateBody(Source, Target), Headers,
           Response, Error) and not ParseGoogleTranslate(Response, Translated) then
        Error := 'bad_response';
    end;
  finally
    Client.Free;
  end;
  Result := (Error = '') and (Translated <> '');
  if Result then
    Translated := KeepOuterSpaces(Text, Translated);
end;

end.
