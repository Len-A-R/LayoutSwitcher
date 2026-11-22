unit uSpeechCloud;

// Dictation through a cloud service with the OpenAI-compatible
// /audio/transcriptions endpoint (Groq, OpenAI, local servers such as
// faster-whisper-server).  The recording is sent as a WAV file.

interface

uses
  System.SysUtils;

type
  TSpeechCloudConfig = record
    BaseUrl: string;
    ApiKey: string;
    Model: string;
    Language: string;   // 'ru', 'en' or '' for detection
  end;

function TranscriptionUrl(const BaseUrl: string): string;
// The text of a response; False with ErrorText for an error object.
function ParseTranscriptionResponse(const Body: string; out Text, ErrorText: string): Boolean;
function TranscribeCloud(const Config: TSpeechCloudConfig; const Samples: TArray<Single>;
  out Text, ErrorText: string): Boolean;

implementation

uses
  Winapi.Windows, System.Classes, System.JSON, System.IOUtils, System.Net.HttpClient,
  System.Net.Mime, System.Net.URLClient,
  uAudioRecorder, uLocale;

function TranscriptionUrl(const BaseUrl: string): string;
begin
  Result := Trim(BaseUrl);
  if Result = '' then
    Result := 'https://api.groq.com/openai/v1';
  while Result.EndsWith('/') do
    SetLength(Result, Length(Result) - 1);
  if not Result.EndsWith('/audio/transcriptions', True) then
    Result := Result + '/audio/transcriptions';
end;

function ParseTranscriptionResponse(const Body: string; out Text, ErrorText: string): Boolean;
var
  Root: TJSONValue;
  Value: TJSONValue;
begin
  Result := False;
  Text := '';
  ErrorText := '';
  Root := TJSONObject.ParseJSONValue(Body);
  try
    if not (Root is TJSONObject) then
    begin
      ErrorText := 'bad_response';
      Exit;
    end;
    Value := TJSONObject(Root).GetValue('error');
    if Value <> nil then
    begin
      if (Value is TJSONObject) and (TJSONObject(Value).GetValue('message') <> nil) then
        ErrorText := TJSONObject(Value).GetValue('message').Value
      else
        ErrorText := Value.Value;
      if ErrorText = '' then
        ErrorText := 'error';
      Exit;
    end;
    Value := TJSONObject(Root).GetValue('text');
    if Value = nil then
    begin
      ErrorText := 'bad_response';
      Exit;
    end;
    Text := Trim(Value.Value);
    Result := True;
  finally
    Root.Free;
  end;
end;

function TranscribeCloud(const Config: TSpeechCloudConfig; const Samples: TArray<Single>;
  out Text, ErrorText: string): Boolean;
var
  Client: THTTPClient;
  Form: TMultipartFormData;
  Response: IHTTPResponse;
  FileName, Body: string;
begin
  Result := False;
  Text := '';
  ErrorText := '';
  if Trim(Config.ApiKey) = '' then
  begin
    ErrorText := T('Укажите ключ API облачного сервиса на вкладке «Диктовка».',
      'Enter the API key of the cloud service on the Dictation tab.');
    Exit;
  end;
  FileName := TPath.Combine(TPath.GetTempPath, Format('ls-dictation-%d.wav', [GetCurrentThreadId]));
  try
    TFile.WriteAllBytes(FileName, EncodeWav(Samples, RECORD_SAMPLE_RATE));
    Client := THTTPClient.Create;
    Form := TMultipartFormData.Create;
    try
      Client.ConnectionTimeout := 15000;
      Client.ResponseTimeout := 60000;
      Client.UserAgent := 'LayoutSwitcher';
      Client.CustomHeaders['Authorization'] := 'Bearer ' + Trim(Config.ApiKey);
      Form.AddFile('file', FileName, 'audio/wav');
      Form.AddField('model', Config.Model);
      Form.AddField('response_format', 'json');
      if Config.Language <> '' then
        Form.AddField('language', Config.Language);
      Response := Client.Post(TranscriptionUrl(Config.BaseUrl), Form);
      Body := Response.ContentAsString(TEncoding.UTF8);
      Result := ParseTranscriptionResponse(Body, Text, ErrorText);
      if not Result and (ErrorText = 'bad_response') then
        ErrorText := Format('HTTP %d', [Response.StatusCode]);
    finally
      Form.Free;
      Client.Free;
    end;
  except
    on E: Exception do
      ErrorText := E.Message;
  end;
  System.SysUtils.DeleteFile(FileName);
end;

end.
