unit uSpeechModels;

// Dictation: the catalogue of speech recognition models, where they are
// installed and how they are downloaded.
//
// Local models run on sherpa-onnx (https://github.com/k2-fsa/sherpa-onnx,
// Apache 2.0).  Neither the engine nor the models ship with the installer:
// they are downloaded when the user picks a model, checked against the
// SHA-256 below and unpacked with the tar.exe of Windows.  The engine
// version is pinned because uSherpaOnnx mirrors its C structures.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes;

type
  TSpeechModelKind = (smkNemoCtc, smkTransducer, smkNemoTransducer, smkCloud);

  TSpeechModel = record
    Id: string;             // stored in the settings
    Kind: TSpeechModelKind;
    Archive: string;        // sherpa-onnx asr-models release asset, without .tar.bz2
    Sha256: string;
    DownloadMB: Integer;    // size of the archive
    Punctuation: Boolean;   // the model writes punctuation and capitals
    Recommended: Boolean;
    function Name: string;
    function Languages: string;
    function Pros: string;
    function Cons: string;
    function IsCloud: Boolean;
  end;

  TSpeechInstallStage = (sisDownloadEngine, sisDownloadModel, sisVerify, sisUnpack);

const
  SHERPA_VERSION = '2.0.3';
  SPEECH_DOWNLOAD_BASE = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/';
  // The default model of a new installation.
  DEFAULT_SPEECH_MODEL = 'ru-gigaam';
  SPEECH_CLOUD_MODEL = 'cloud';
  DEFAULT_SPEECH_CLOUD_URL = 'https://api.groq.com/openai/v1';
  DEFAULT_SPEECH_CLOUD_MODEL = 'whisper-large-v3-turbo';

  SpeechModels: array[0..3] of TSpeechModel = (
    (Id: 'ru-gigaam'; Kind: smkNemoCtc;
     Archive: 'sherpa-onnx-nemo-ctc-punct-giga-am-v3-russian-2025-12-16';
     Sha256: '20e41e160efa6f2460a7ef6554cdbbb9e8fffb2b92e6bc708e9406bd8b9256ea';
     DownloadMB: 164; Punctuation: True; Recommended: True),
    (Id: 'ru-compact'; Kind: smkTransducer;
     Archive: 'sherpa-onnx-zipformer-ru-int8-2025-04-20';
     Sha256: 'd6a651569aacc9a177259fa54705dd76acae23f6a4d62ea6797bd220d4b57163';
     DownloadMB: 61; Punctuation: False; Recommended: False),
    (Id: 'multi-parakeet'; Kind: smkNemoTransducer;
     Archive: 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8';
     Sha256: '1495e91b59d7fc53ddca91f3431758ec99f8fa253fdb0e1e851be0f72b14b0f9';
     DownloadMB: 488; Punctuation: True; Recommended: False),
    (Id: 'cloud'; Kind: smkCloud; Archive: ''; Sha256: ''; DownloadMB: 0;
     Punctuation: True; Recommended: False));

// Index in SpeechModels, -1 when unknown.
function FindSpeechModel(const Id: string): Integer;

function SpeechRootDir: string;
function SpeechEngineDir: string;
function SpeechModelDir(const Model: TSpeechModel): string;
function IsSpeechEngineInstalled: Boolean;
function IsSpeechModelInstalled(const Model: TSpeechModel): Boolean;
// Megabytes the installed model takes on disk.
function SpeechModelDiskMB(const Model: TSpeechModel): Integer;
function DeleteSpeechModel(const Model: TSpeechModel): Boolean;
// The model file with the given name start; int8 versions are preferred.
function FindModelFile(const Dir, Prefix: string): string;

// SPEECH_DOWNLOAD_BASE, or a mirror with the same layout from the
// LS_SPEECH_MIRROR environment variable (networks without GitHub access).
function SpeechDownloadBase: string;
function SpeechEngineArchive: string;
function SpeechEngineSha256: string;
function SpeechEngineUrl: string;
function SpeechModelUrl(const Model: TSpeechModel): string;
// Parts of a download of Total bytes: up to MaxParts ranges of at least
// MinPart bytes, as start/end pairs (inclusive).
function SplitDownload(Total: Int64; MaxParts: Integer; MinPart: Int64): TArray<Int64>;
// The total size from a Content-Range header ("bytes 0-0/12345"), -1 if none.
function ParseContentRangeTotal(const Value: string): Int64;

// Capital letter at the start of a phrase from a model without punctuation,
// and a space in front when the text continues a word.
function FinishDictatedText(const Text: string; Punctuation: Boolean;
  const TextBefore: string): string;

type
  // Downloads the engine (when missing) and a model, checks and unpacks them.
  // Posts ProgressMsg (WParam = stage + speed in KB/s shl 8, LParam = percent
  // or -1) and finally
  // DoneMsg (WParam = 1 on success, LParam = PChar error text to be freed
  // with StrDispose, or 0).
  TSpeechInstallThread = class(TThread)
  private
    FModel: TSpeechModel;
    FNotifyWnd: HWND;
    FProgressMsg, FDoneMsg: UINT;
    FStage: TSpeechInstallStage;
    FLastReport: Cardinal;
    FSpeedKB: Integer;
    procedure Report(Percent: Integer);
    procedure ReceiveData(const Sender: TObject; ContentLength, ReadCount: Int64;
      var Abort: Boolean);
    procedure Download(const Url, FileName: string);
    procedure DownloadSingle(const Url, FileName: string);
    procedure Install(const Url, Sha256, TargetDir, InnerDir: string;
      const Members: TArray<string>; DownloadStage: TSpeechInstallStage);
  protected
    procedure Execute; override;
  public
    constructor Create(const Model: TSpeechModel; NotifyWnd: HWND;
      ProgressMsg, DoneMsg: UINT);
  end;

implementation

uses
  System.IOUtils, System.Hash, System.Net.HttpClient, System.Net.URLClient,
  System.Character, System.Math, uLocale;

const
  MARKER_FILE = 'installed.ok';
  ENGINE_SHA256_X64 = 'fd776a611aca0d088947da7e635c25a02e2b42ace00fc70b960af61059a727e6';
  ENGINE_SHA256_X86 = '1f0a055781e2408af21eef40d0cda6e677ad0ea0aea407f404124b2662be8f1f';

{ TSpeechModel }

function TSpeechModel.IsCloud: Boolean;
begin
  Result := Kind = smkCloud;
end;

function TSpeechModel.Name: string;
begin
  if Id = 'ru-gigaam' then
    Result := T('GigaAM v3 — русский, с пунктуацией', 'GigaAM v3 — Russian, with punctuation')
  else if Id = 'ru-compact' then
    Result := T('Компактная — русский', 'Compact — Russian')
  else if Id = 'multi-parakeet' then
    Result := T('Parakeet v3 — 25 языков', 'Parakeet v3 — 25 languages')
  else if Id = 'cloud' then
    Result := T('Облачный сервис (по ключу API)', 'Cloud service (API key)')
  else
    Result := Id;
end;

function TSpeechModel.Languages: string;
begin
  if Id = 'multi-parakeet' then
    Result := T('русский, английский, украинский и ещё 22 европейских языка',
      'Russian, English, Ukrainian and 22 more European languages')
  else if Id = 'cloud' then
    Result := T('зависит от сервиса', 'depends on the service')
  else
    Result := T('русский', 'Russian');
end;

function TSpeechModel.Pros: string;
begin
  if Id = 'ru-gigaam' then
    Result := T(
      'Одна из лучших моделей для русской речи (Сбер, открытая лицензия MIT). ' +
      'Сама расставляет знаки препинания и заглавные буквы. Быстрая: фраза ' +
      'распознаётся за доли секунды. Работает без интернета.',
      'One of the best models for Russian speech (Sber, open MIT license). ' +
      'Adds punctuation and capital letters itself. Fast: a phrase is recognized ' +
      'in a fraction of a second. Works offline.')
  else if Id = 'ru-compact' then
    Result := T(
      'Самая маленькая загрузка и меньше всего памяти. Подходит для слабых ' +
      'компьютеров. Работает без интернета (модель Vosk от Alpha Cephei).',
      'The smallest download and memory use. Suits slow computers. ' +
      'Works offline (Vosk model by Alpha Cephei).')
  else if Id = 'multi-parakeet' then
    Result := T(
      'Понимает смешанную речь: русский с английскими терминами. Сама определяет ' +
      'язык, ставит знаки препинания и заглавные буквы. Высокая точность ' +
      '(NVIDIA, лицензия CC BY 4.0). Работает без интернета.',
      'Understands mixed speech: Russian with English terms. Detects the ' +
      'language itself, adds punctuation and capitals. High accuracy ' +
      '(NVIDIA, CC BY 4.0 license). Works offline.')
  else if Id = 'cloud' then
    Result := T(
      'Ничего не нужно скачивать, не нагружает компьютер. Высокое качество ' +
      '(Whisper large). У Groq есть бесплатный тариф; подходят также OpenAI ' +
      'и любой сервис с совместимым API.',
      'Nothing to download, no load on the computer. High quality (Whisper ' +
      'large). Groq has a free tier; OpenAI and any service with a compatible ' +
      'API work too.')
  else
    Result := '';
end;

function TSpeechModel.Cons: string;
begin
  if Id = 'ru-gigaam' then
    Result := T(
      'Только русский: английские слова записывает русскими буквами.',
      'Russian only: English words come out in Cyrillic.')
  else if Id = 'ru-compact' then
    Result := T(
      'Без знаков препинания (LayoutSwitcher ставит только заглавную букву в ' +
      'начале). Точность ниже, чем у GigaAM. Только русский.',
      'No punctuation (LayoutSwitcher only capitalizes the first letter). ' +
      'Less accurate than GigaAM. Russian only.')
  else if Id = 'multi-parakeet' then
    Result := T(
      'Большая загрузка и около 1 ГБ памяти во время работы. На русском ' +
      'чуть уступает GigaAM. Распознаёт медленнее, особенно на старых процессорах.',
      'A large download and about 1 GB of memory while working. Slightly ' +
      'behind GigaAM on Russian. Slower, especially on older processors.')
  else if Id = 'cloud' then
    Result := T(
      'Запись голоса отправляется в интернет. Нужен ключ API и подключение. ' +
      'Платные сервисы берут плату за минуты.',
      'The voice recording is sent over the internet. Needs an API key and a ' +
      'connection. Paid services charge per minute.')
  else
    Result := '';
end;

{ Catalogue and paths }

function FindSpeechModel(const Id: string): Integer;
var
  I: Integer;
begin
  for I := Low(SpeechModels) to High(SpeechModels) do
    if SameText(SpeechModels[I].Id, Id) then
      Exit(I);
  Result := -1;
end;

function SpeechRootDir: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then
    Base := TPath.GetHomePath;
  Result := TPath.Combine(TPath.Combine(Base, 'LayoutSwitcher'), 'Speech');
end;

function SpeechEngineArchive: string;
begin
{$IFDEF WIN64}
  Result := 'sherpa-onnx-v' + SHERPA_VERSION + '-win-x64-shared-MT-Release-no-tts';
{$ELSE}
  Result := 'sherpa-onnx-v' + SHERPA_VERSION + '-win-x86-shared-MT-Release-no-tts';
{$ENDIF}
end;

function SpeechEngineSha256: string;
begin
{$IFDEF WIN64}
  Result := ENGINE_SHA256_X64;
{$ELSE}
  Result := ENGINE_SHA256_X86;
{$ENDIF}
end;

function SpeechDownloadBase: string;
begin
  Result := Trim(GetEnvironmentVariable('LS_SPEECH_MIRROR'));
  if Result = '' then
    Result := SPEECH_DOWNLOAD_BASE
  else if not Result.EndsWith('/') then
    Result := Result + '/';
end;

function SpeechEngineUrl: string;
begin
  Result := SpeechDownloadBase + 'v' + SHERPA_VERSION + '/' + SpeechEngineArchive + '.tar.bz2';
end;

function SpeechModelUrl(const Model: TSpeechModel): string;
begin
  Result := SpeechDownloadBase + 'asr-models/' + Model.Archive + '.tar.bz2';
end;

function SpeechEngineDir: string;
begin
  Result := TPath.Combine(SpeechRootDir, SpeechEngineArchive);
end;

function SpeechModelDir(const Model: TSpeechModel): string;
begin
  Result := TPath.Combine(TPath.Combine(SpeechRootDir, 'models'), Model.Archive);
end;

function IsSpeechEngineInstalled: Boolean;
begin
  Result := FileExists(TPath.Combine(SpeechEngineDir, MARKER_FILE));
end;

function IsSpeechModelInstalled(const Model: TSpeechModel): Boolean;
begin
  if Model.IsCloud then
    Exit(True);
  Result := FileExists(TPath.Combine(SpeechModelDir(Model), MARKER_FILE));
end;

function SpeechModelDiskMB(const Model: TSpeechModel): Integer;
var
  Total: Int64;
  FileName: string;
begin
  Total := 0;
  if not Model.IsCloud and TDirectory.Exists(SpeechModelDir(Model)) then
    for FileName in TDirectory.GetFiles(SpeechModelDir(Model), '*',
        TSearchOption.soAllDirectories) do
      Total := Total + TFile.GetSize(FileName);
  Result := (Total + 512 * 1024) div (1024 * 1024);
end;

function DeleteSpeechModel(const Model: TSpeechModel): Boolean;
begin
  Result := True;
  if Model.IsCloud or not TDirectory.Exists(SpeechModelDir(Model)) then
    Exit;
  try
    TDirectory.Delete(SpeechModelDir(Model), True);
  except
    Result := False;
  end;
end;

function FindModelFile(const Dir, Prefix: string): string;
var
  FileName, Name: string;
begin
  Result := '';
  if not TDirectory.Exists(Dir) then
    Exit;
  for FileName in TDirectory.GetFiles(Dir, '*.onnx') do
  begin
    Name := LowerCase(ExtractFileName(FileName));
    if not Name.StartsWith(LowerCase(Prefix)) then
      Continue;
    if (Result = '') or (Pos('int8', Name) > 0) then
      Result := FileName;
  end;
end;

function FinishDictatedText(const Text: string; Punctuation: Boolean;
  const TextBefore: string): string;
var
  Last: Char;
begin
  Result := Trim(Text);
  if Result = '' then
    Exit;
  if not Punctuation then
    Result := AnsiUpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt);
  // Dictating on after a word: separated by a space, as if typed.
  if TextBefore <> '' then
  begin
    Last := TextBefore[Length(TextBefore)];
    if not Last.IsWhiteSpace and (Pos(Last, '([{"''«„') = 0) then
      Result := ' ' + Result;
  end;
end;

{ TSpeechInstallThread }

constructor TSpeechInstallThread.Create(const Model: TSpeechModel; NotifyWnd: HWND;
  ProgressMsg, DoneMsg: UINT);
begin
  FModel := Model;
  FNotifyWnd := NotifyWnd;
  FProgressMsg := ProgressMsg;
  FDoneMsg := DoneMsg;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TSpeechInstallThread.Report(Percent: Integer);
begin
  PostMessage(FNotifyWnd, FProgressMsg, WPARAM(Ord(FStage) or (FSpeedKB shl 8)),
    LPARAM(Percent));
end;

procedure TSpeechInstallThread.ReceiveData(const Sender: TObject;
  ContentLength, ReadCount: Int64; var Abort: Boolean);
begin
  Abort := Terminated;
  if Abort or (GetTickCount - FLastReport < 150) then
    Exit;
  FLastReport := GetTickCount;
  if ContentLength > 0 then
    Report(Integer(ReadCount * 100 div ContentLength))
  else
    Report(-1);
end;

// GitHub limits the speed of one connection (a few hundred KB/s from some
// networks); eight ranges downloaded at once are about ten times faster.
// A broken range continues from where it stopped.

const
  DOWNLOAD_PARTS = 8;
  MIN_PART_BYTES = 4 * 1024 * 1024;
  PART_ATTEMPTS = 5;

function SplitDownload(Total: Int64; MaxParts: Integer; MinPart: Int64): TArray<Int64>;
var
  Parts, I: Integer;
  Size, Start: Int64;
begin
  Result := nil;
  if Total <= 0 then
    Exit;
  Parts := Integer(EnsureRange(Total div Max(MinPart, 1), 1, Max(MaxParts, 1)));
  Size := Total div Parts;
  Start := 0;
  for I := 0 to Parts - 1 do
  begin
    Result := Result + [Start];
    if I = Parts - 1 then
      Result := Result + [Total - 1]
    else
      Result := Result + [Start + Size - 1];
    Start := Start + Size;
  end;
end;

function ParseContentRangeTotal(const Value: string): Int64;
var
  Slash: Integer;
begin
  Slash := Pos('/', Value);
  if (Slash = 0) or not TryStrToInt64(Trim(Copy(Value, Slash + 1, MaxInt)), Result) then
    Result := -1;
end;

type
  // Writes what a range request receives at its place in the file.
  TPartWriter = class(TStream)
  private
    FFile: TFileStream;
    FDone: PInt64;
    FAbort: PBoolean;
    FPos: Int64;
  public
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TPartThread = class(TThread)
  private
    FUrl, FFileName: string;
    FFirst, FLast: Int64;
    FDone: Int64;
    FAbort: PBoolean;
    FError: string;
  protected
    procedure Execute; override;
  end;

function TPartWriter.Write(const Buffer; Count: Longint): Longint;
begin
  if FAbort^ then
    Abort;
  FFile.WriteBuffer(Buffer, Count);
  AtomicIncrement(FDone^, Count);
  Inc(FPos, Count);
  Result := Count;
end;

function TPartWriter.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TPartWriter.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FPos;
end;

// The address after redirects (GitHub answers with a signed link to its
// file storage, valid for a while), and the size from a one-byte range.
function ResolveDownload(const Url: string; out FinalUrl: string; out Total: Int64): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Hop: Integer;
  Location: string;
  Base: TURI;
begin
  Result := False;
  Total := -1;
  FinalUrl := Url;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 30000;
    Client.ResponseTimeout := 30000;
    Client.UserAgent := 'LayoutSwitcher';
    Client.HandleRedirects := False;
    Client.CustomHeaders['Range'] := 'bytes=0-0';
    for Hop := 1 to 6 do
    begin
      Response := Client.Get(FinalUrl);
      if (Response.StatusCode >= 300) and (Response.StatusCode < 400) then
      begin
        Location := Response.HeaderValue['Location'];
        if Location = '' then
          Exit;
        if Location.StartsWith('/') then
        begin
          Base := TURI.Create(FinalUrl);
          Location := Base.Scheme + '://' + Base.Host + Location;
        end;
        FinalUrl := Location;
        Continue;
      end;
      if Response.StatusCode = 206 then
      begin
        Total := ParseContentRangeTotal(Response.HeaderValue['Content-Range']);
        Result := Total > 0;
      end;
      Exit;
    end;
  finally
    Client.Free;
  end;
end;

procedure TPartThread.Execute;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Writer: TPartWriter;
  Stream: TFileStream;
  Attempt: Integer;
  Url: string;
  Total: Int64;
begin
  NameThreadForDebugging('LayoutSwitcher.SpeechDownloadPart');
  Url := FUrl;
  Attempt := 0;
  while (FFirst + FDone <= FLast) and not FAbort^ do
  begin
    try
      Stream := TFileStream.Create(FFileName, fmOpenWrite or fmShareDenyNone);
      Writer := TPartWriter.Create;
      Client := THTTPClient.Create;
      try
        Stream.Position := FFirst + FDone;
        Writer.FFile := Stream;
        Writer.FDone := @FDone;
        Writer.FAbort := FAbort;
        Client.ConnectionTimeout := 30000;
        Client.ResponseTimeout := 30000;
        Client.UserAgent := 'LayoutSwitcher';
        Client.HandleRedirects := True;
        Client.CustomHeaders['Range'] := Format('bytes=%d-%d', [FFirst + FDone, FLast]);
        Response := Client.Get(Url, Writer);
        if Response.StatusCode <> 206 then
          raise Exception.CreateFmt('HTTP %d', [Response.StatusCode]);
      finally
        Client.Free;
        Writer.Free;
        Stream.Free;
      end;
    except
      on E: Exception do
      begin
        if FAbort^ then
          Exit;
        Inc(Attempt);
        if Attempt >= PART_ATTEMPTS then
        begin
          FError := E.Message;
          Exit;
        end;
        Sleep(1000 * Attempt);
        // The signed link may have expired meanwhile.
        if not ResolveDownload(FUrl, Url, Total) then
          Url := FUrl;
      end;
    end;
  end;
end;

procedure TSpeechInstallThread.Download(const Url, FileName: string);
var
  FinalUrl, Error: string;
  Total, Received, LastReceived: Int64;
  Ranges: TArray<Int64>;
  Parts: array of TPartThread;
  AbortFlag, Running: Boolean;
  I: Integer;
  Stream: TFileStream;
  LastTick, Tick: Cardinal;
begin
  if not ResolveDownload(Url, FinalUrl, Total) or (Total < 2 * MIN_PART_BYTES) then
  begin
    // No ranges (some mirrors) or a small file: one connection.
    DownloadSingle(Url, FileName);
    Exit;
  end;
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.Size := Total;
  finally
    Stream.Free;
  end;
  Ranges := SplitDownload(Total, DOWNLOAD_PARTS, MIN_PART_BYTES);
  AbortFlag := False;
  SetLength(Parts, Length(Ranges) div 2);
  for I := 0 to High(Parts) do
  begin
    Parts[I] := TPartThread.Create(True);
    Parts[I].FUrl := FinalUrl;
    Parts[I].FFileName := FileName;
    Parts[I].FFirst := Ranges[I * 2];
    Parts[I].FLast := Ranges[I * 2 + 1];
    Parts[I].FAbort := @AbortFlag;
    Parts[I].Start;
  end;
  try
    LastTick := GetTickCount;
    LastReceived := 0;
    repeat
      Sleep(200);
      if Terminated then
        AbortFlag := True;
      Received := 0;
      Running := False;
      for I := 0 to High(Parts) do
      begin
        Received := Received + AtomicCmpExchange(Parts[I].FDone, 0, 0);
        if not Parts[I].Finished then
          Running := True;
      end;
      Tick := GetTickCount;
      if Tick - LastTick >= 1000 then
      begin
        // Smoothed speed for the status line.
        FSpeedKB := (FSpeedKB + Integer((Received - LastReceived) * 1000 div
          Max(Int64(Tick - LastTick), 1) div 1024)) div 2;
        LastTick := Tick;
        LastReceived := Received;
      end;
      Report(Integer(Received * 100 div Total));
    until not Running;
  finally
    Error := '';
    for I := 0 to High(Parts) do
    begin
      Parts[I].WaitFor;
      if (Error = '') and (Parts[I].FError <> '') then
        Error := Parts[I].FError;
      Parts[I].Free;
    end;
    FSpeedKB := 0;
  end;
  if Terminated then
    Abort;
  if Error <> '' then
    raise Exception.Create(Error);
end;

procedure TSpeechInstallThread.DownloadSingle(const Url, FileName: string);
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Stream: TFileStream;
begin
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 30000;
    Client.ResponseTimeout := 60000;
    Client.UserAgent := 'LayoutSwitcher';
    Client.HandleRedirects := True;
    Client.OnReceiveData := ReceiveData;
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Response := Client.Get(Url, Stream);
    finally
      Stream.Free;
    end;
    if Terminated then
      Abort;
    if Response.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d', [Response.StatusCode]);
  finally
    Client.Free;
  end;
end;

function RunTar(const Archive, TargetDir: string;
  const Members: TArray<string>): Boolean;
var
  Tar, Command, Member: string;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  ExitCode: DWORD;
begin
  Tar := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\tar.exe');
  if not FileExists(Tar) then
    raise Exception.Create(T('В Windows нет tar.exe (нужна Windows 10 версии 1803 или новее)',
      'Windows has no tar.exe (Windows 10 version 1803 or later is needed)'));
  Command := Format('"%s" -xf "%s" -C "%s"', [Tar, Archive, TargetDir]);
  for Member in Members do
    Command := Command + ' "' + Member + '"';
  FillChar(Startup, SizeOf(Startup), 0);
  Startup.cb := SizeOf(Startup);
  Startup.dwFlags := STARTF_USESHOWWINDOW;
  Startup.wShowWindow := SW_HIDE;
  UniqueString(Command);
  if not CreateProcess(nil, PChar(Command), nil, nil, False, CREATE_NO_WINDOW, nil,
       PChar(TargetDir), Startup, Info) then
    RaiseLastOSError;
  try
    WaitForSingleObject(Info.hProcess, INFINITE);
    Result := GetExitCodeProcess(Info.hProcess, ExitCode) and (ExitCode = 0);
  finally
    CloseHandle(Info.hThread);
    CloseHandle(Info.hProcess);
  end;
end;

procedure TSpeechInstallThread.Install(const Url, Sha256, TargetDir, InnerDir: string;
  const Members: TArray<string>; DownloadStage: TSpeechInstallStage);
var
  Temp, ArchiveFile, Unpacked: string;
begin
  // Everything happens next to the target, so that the final move is a
  // rename on the same disk.
  Temp := TargetDir + '.download';
  if TDirectory.Exists(Temp) then
    TDirectory.Delete(Temp, True);
  ForceDirectories(Temp);
  try
    ArchiveFile := TPath.Combine(Temp, 'archive.tar.bz2');
    FStage := DownloadStage;
    Report(0);
    Download(Url, ArchiveFile);
    if Sha256 <> '' then
    begin
      FStage := sisVerify;
      Report(-1);
      if not SameText(THashSHA2.GetHashStringFromFile(ArchiveFile), Sha256) then
        raise Exception.Create(T('Контрольная сумма файла не совпадает: загрузка повреждена',
          'The checksum does not match: the download is damaged'));
    end;
    if Terminated then
      Abort;
    FStage := sisUnpack;
    Report(-1);
    if not RunTar(ArchiveFile, Temp, Members) then
      raise Exception.Create(T('Не удалось распаковать архив', 'Could not unpack the archive'));
    System.SysUtils.DeleteFile(ArchiveFile);
    Unpacked := TPath.Combine(Temp, InnerDir);
    if not TDirectory.Exists(Unpacked) then
      raise Exception.Create(T('В архиве нет ожидаемой папки', 'The archive lacks the expected folder'));
    TFile.WriteAllText(TPath.Combine(Unpacked, MARKER_FILE), Url);
    if TDirectory.Exists(TargetDir) then
      TDirectory.Delete(TargetDir, True);
    ForceDirectories(ExtractFileDir(TargetDir));
    if not MoveFile(PChar(Unpacked), PChar(TargetDir)) then
      RaiseLastOSError;
  finally
    if TDirectory.Exists(Temp) then
      try
        TDirectory.Delete(Temp, True);
      except
      end;
  end;
end;

procedure TSpeechInstallThread.Execute;
var
  Error: string;
begin
  NameThreadForDebugging('LayoutSwitcher.SpeechInstall');
  Error := '';
  try
    if not IsSpeechEngineInstalled then
      // Only the libraries: the archive also holds 60 MB of tools.
      Install(SpeechEngineUrl, SpeechEngineSha256, SpeechEngineDir, SpeechEngineArchive,
        [SpeechEngineArchive + '/lib/sherpa-onnx-c-api.dll',
         SpeechEngineArchive + '/lib/onnxruntime.dll',
         SpeechEngineArchive + '/lib/onnxruntime_providers_shared.dll'],
        sisDownloadEngine);
    if not Terminated and not IsSpeechModelInstalled(FModel) then
      Install(SpeechModelUrl(FModel), FModel.Sha256, SpeechModelDir(FModel), FModel.Archive,
        nil, sisDownloadModel);
  except
    on E: EAbort do
      Error := '';
    on E: Exception do
      Error := E.Message;
  end;
  if Terminated then
    Error := '';
  if Error <> '' then
    PostMessage(FNotifyWnd, FDoneMsg, 0, LPARAM(StrNew(PChar(Error))))
  else
    PostMessage(FNotifyWnd, FDoneMsg, WPARAM(Ord(not Terminated)), 0);
end;

end.
