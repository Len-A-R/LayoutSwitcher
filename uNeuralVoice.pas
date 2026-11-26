unit uNeuralVoice;

// Neural voices (Piper, https://github.com/rhasspy/piper, MIT) for reading
// aloud: espeak-ng turns the text into IPA phonemes the way Piper does it
// (piper-phonemize), sherpa-onnx (uSherpaOnnx) turns them into speech.
//
// sherpa-onnx 2.x has no phonemizer of its own: espeak-ng.dll of the Windows
// build of piper-phonemize is loaded at run time with its espeak-ng-data.
// espeak-ng is GPL-3.0; it is downloaded by the user, not shipped.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs,
  uSpeechModels, uSherpaOnnx;

type
  TPhonemeSentences = TArray<TArray<Integer>>;

  TNeuralVoiceInfo = record
    Id: string;             // stored in the settings as "piper:" + Id
    Archive: string;        // sherpa-onnx tts-models release asset, without .tar.bz2
    Sha256: string;
    DownloadMB: Integer;
    Language: Word;         // LANGID
    Male: Boolean;
    function Name: string;
    // The license of the voice data, from its MODEL_CARD.
    function License: string;
    function Recommended: Boolean;
  end;

  // A piece of the text and the voice to read it with.
  TNeuralSegment = record
    Text: string;
    VoiceIndex: Integer;
    ParagraphEnd: Boolean;  // a longer pause after it
  end;

const
  NEURAL_VOICE_PREFIX = 'piper:';
  // The full-precision models: on a CPU they are faster than the int8 ones
  // (0.5 s for 9 s of speech) and the fp16 ones do not load in this
  // onnxruntime.
  // The recommended voice of a language first: the automatic choice takes
  // the first installed one.
  NeuralVoices: array[0..4] of TNeuralVoiceInfo = (
    (Id: 'ru-ruslan'; Archive: 'vits-piper-ru_RU-ruslan-medium';
     Sha256: '0690b1cad01f86e8db9ba988af24898bdc1af774e23cb2e46b9c730269b6fd83';
     DownloadMB: 64; Language: $0419; Male: True),
    (Id: 'ru-denis'; Archive: 'vits-piper-ru_RU-denis-medium';
     Sha256: 'efa4c18e0b5e32b81d1b6df36b9d312831e5d545200e27848ef926a4cd930300';
     DownloadMB: 64; Language: $0419; Male: True),
    (Id: 'ru-dmitri'; Archive: 'vits-piper-ru_RU-dmitri-medium';
     Sha256: 'c86d0803737de13d441923ff3b3f309482fab8d7af3ec85949942809eb9a3660';
     DownloadMB: 64; Language: $0419; Male: True),
    (Id: 'ru-irina'; Archive: 'vits-piper-ru_RU-irina-medium';
     Sha256: '1fc0f54e5e084fe287c07909f2f6e0ba6d857864cf800e3ab80286a4e8233008';
     DownloadMB: 64; Language: $0419; Male: False),
    (Id: 'en-ljspeech'; Archive: 'vits-piper-en_US-ljspeech-medium';
     Sha256: '3dfb4b759d8be032a4903a9538d128b0fda2a06ab1de6cbc2d93a97e2dd83dba';
     DownloadMB: 64; Language: $0409; Male: False));
  // espeak-ng.dll and espeak-ng-data of the Windows build of piper-phonemize.
  PHONEMIZER_RELEASE = '2023.11.14-4';
  PHONEMIZER_ARCHIVE = 'piper-phonemize_windows_amd64.zip';
  PHONEMIZER_SHA256 = 'a6f1a3f80eba222c1b8eb3904a9c18781f3c21827bd2dc36bd85b216a306d945';
  PHONEMIZER_DOWNLOAD_MB = 59;

// piper-phonemize has a Windows build for x64 only.
function NeuralVoicesSupported: Boolean;
// Index in NeuralVoices by Id or by a "piper:" setting; -1 when unknown.
function FindNeuralVoice(const Id: string): Integer;
function NeuralVoiceDir(const Voice: TNeuralVoiceInfo): string;
function PhonemizerDir: string;
// The voice, the phonemizer and the engine with text-to-speech are there.
function IsNeuralVoiceInstalled(const Voice: TNeuralVoiceInfo): Boolean;
// What to download for the voice (the engine is added by the installer).
function NeuralVoicePackages(const Voice: TNeuralVoiceInfo): TArray<TSpeechPackage>;
// Megabytes to download for the voice now (with the phonemizer and the
// engine when they are missing).
function NeuralVoiceDownloadMB(const Voice: TNeuralVoiceInfo): Integer;
function NeuralVoiceDiskMB(const Voice: TNeuralVoiceInfo): Integer;
// Deletes the voice; the phonemizer goes with the last voice.
function DeleteNeuralVoice(const Voice: TNeuralVoiceInfo): Boolean;

type
  // Reads paragraphs with a neural voice in a background thread: one
  // sentence is synthesized while the previous one plays.  The voice stays
  // loaded between calls (Unload frees it).
  TLoadedVoice = record
    Id: string;
    Synth: TSpeechSynthesizer;
    EspeakVoice: string;
  end;

  TNeuralSpeaker = class
  private
    FThread: TThread;
    // Up to two loaded voices (one per language of a mixed text).
    FLoaded: TArray<TLoadedVoice>;
    FLock: TCriticalSection;
    FError: string;
    procedure SetError(const Text: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Speak(const Segments: TArray<TNeuralSegment>; Speed: Single);
    // Stops and waits for the thread.
    procedure Stop;
    function Speaking: Boolean;
    // The error of the last reading ('' if none), once.
    function TakeError: string;
    procedure Unload;
  end;

// Loads espeak-ng.dll; DataParent is the folder that contains espeak-ng-data.
// False with ErrorText when it cannot (missing Visual C++ runtime...).
function LoadPhonemizer(const DllFile, DataParent: string; out ErrorText: string): Boolean;
function PhonemizerLoaded: Boolean;
// The text as sentences of phoneme codepoints for a Piper voice;
// EspeakVoice is "espeak.voice" of the .onnx.json ("ru", "en-us").
// Not thread-safe: espeak-ng has a global state.
function PhonemizeText(const Text, EspeakVoice: string): TPhonemeSentences;

// For the tests: the codepoints of a phoneme string with the punctuation of
// a clause terminator, the way piper-phonemize adds them.
function ClausePunctuation(Terminator: Integer): Char;
function IsSentenceEnd(Terminator: Integer): Boolean;
// "(en)" language switch marks removed.
function RemoveLanguageFlags(const Phonemes: string): string;

implementation

uses
  Winapi.MMSystem, System.IOUtils, System.JSON, System.Math, uLocale;

const
  AUDIO_OUTPUT_SYNCHRONOUS = 2;
  ESPEAK_CHARS_AUTO = 0;
  ESPEAK_PHONEMES_IPA = $02;
  CLAUSE_INTONATION_FULL_STOP = $00000000;
  CLAUSE_INTONATION_COMMA = $00001000;
  CLAUSE_INTONATION_QUESTION = $00002000;
  CLAUSE_INTONATION_EXCLAMATION = $00003000;
  CLAUSE_TYPE_CLAUSE = $00040000;
  CLAUSE_TYPE_SENTENCE = $00080000;
  CLAUSE_PERIOD = 40 or CLAUSE_INTONATION_FULL_STOP or CLAUSE_TYPE_SENTENCE;
  CLAUSE_COMMA = 20 or CLAUSE_INTONATION_COMMA or CLAUSE_TYPE_CLAUSE;
  CLAUSE_QUESTION = 40 or CLAUSE_INTONATION_QUESTION or CLAUSE_TYPE_SENTENCE;
  CLAUSE_EXCLAMATION = 45 or CLAUSE_INTONATION_EXCLAMATION or CLAUSE_TYPE_SENTENCE;
  CLAUSE_COLON = 30 or CLAUSE_INTONATION_FULL_STOP or CLAUSE_TYPE_CLAUSE;
  CLAUSE_SEMICOLON = 30 or CLAUSE_INTONATION_COMMA or CLAUSE_TYPE_CLAUSE;
  NORMALIZATION_D = 2;

type
  TEspeakInitialize = function(Output, BufLength: Integer; Path: PAnsiChar;
    Options: Integer): Integer; cdecl;
  TEspeakSetVoiceByName = function(Name: PAnsiChar): Integer; cdecl;
  TEspeakTextToPhonemesWithTerminator = function(var TextPtr: PAnsiChar; TextMode,
    PhonemeMode: Integer; Terminator: PInteger): PAnsiChar; cdecl;

var
  GEspeak: HMODULE;
  EspeakInitialize: TEspeakInitialize;
  EspeakSetVoiceByName: TEspeakSetVoiceByName;
  EspeakTextToPhonemes: TEspeakTextToPhonemesWithTerminator;
  GVoice: string;

function NormalizeString(NormForm: Integer; Src: PWideChar; SrcLength: Integer;
  Dst: PWideChar; DstLength: Integer): Integer; stdcall; external 'normaliz.dll';

function ShortPath(const FileName: string): AnsiString;
var
  Buffer: array[0..MAX_PATH] of Char;
  Len: DWORD;
begin
  Len := GetShortPathName(PChar(FileName), Buffer, Length(Buffer));
  if (Len > 0) and (Len < DWORD(Length(Buffer))) then
    Result := AnsiString(string(Buffer))
  else
    Result := AnsiString(FileName);
end;

function PhonemizerLoaded: Boolean;
begin
  Result := GEspeak <> 0;
end;

function LoadPhonemizer(const DllFile, DataParent: string; out ErrorText: string): Boolean;
var
  Code: DWORD;
begin
  ErrorText := '';
  if GEspeak <> 0 then
    Exit(True);
  Result := False;
  if not FileExists(DllFile) then
  begin
    ErrorText := T('Нет файла espeak-ng.dll. Скачайте голос заново.',
      'espeak-ng.dll is missing. Download the voice again.');
    Exit;
  end;
  GEspeak := LoadLibraryEx(PChar(DllFile), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  if GEspeak = 0 then
  begin
    Code := GetLastError;
    if Code = ERROR_MOD_NOT_FOUND then
      ErrorText := T('Для нейросетевых голосов нужен Microsoft Visual C++ Redistributable ' +
        '(x64): https://aka.ms/vs/17/release/vc_redist.x64.exe',
        'Neural voices need the Microsoft Visual C++ Redistributable (x64): ' +
        'https://aka.ms/vs/17/release/vc_redist.x64.exe')
    else
      ErrorText := Format(T('Не удалось загрузить espeak-ng.dll (%s)',
        'Could not load espeak-ng.dll (%s)'), [SysErrorMessage(Code)]);
    Exit;
  end;
  @EspeakInitialize := GetProcAddress(GEspeak, 'espeak_Initialize');
  @EspeakSetVoiceByName := GetProcAddress(GEspeak, 'espeak_SetVoiceByName');
  @EspeakTextToPhonemes := GetProcAddress(GEspeak, 'espeak_TextToPhonemesWithTerminator');
  if not Assigned(EspeakInitialize) or not Assigned(EspeakSetVoiceByName) or
     not Assigned(EspeakTextToPhonemes) or
     (EspeakInitialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, PAnsiChar(ShortPath(DataParent)), 0) <= 0) then
  begin
    FreeLibrary(GEspeak);
    GEspeak := 0;
    ErrorText := T('Не удалось запустить espeak-ng. Скачайте голос заново.',
      'Could not start espeak-ng. Download the voice again.');
    Exit;
  end;
  GVoice := '';
  Result := True;
end;

function ClausePunctuation(Terminator: Integer): Char;
begin
  case Terminator and $000FFFFF of
    CLAUSE_PERIOD: Result := '.';
    CLAUSE_QUESTION: Result := '?';
    CLAUSE_EXCLAMATION: Result := '!';
    CLAUSE_COMMA: Result := ',';
    CLAUSE_COLON: Result := ':';
    CLAUSE_SEMICOLON: Result := ';';
  else
    Result := #0;
  end;
end;

function IsSentenceEnd(Terminator: Integer): Boolean;
begin
  Result := (Terminator and CLAUSE_TYPE_SENTENCE) = CLAUSE_TYPE_SENTENCE;
end;

function RemoveLanguageFlags(const Phonemes: string): string;
var
  I: Integer;
  InFlag: Boolean;
begin
  Result := '';
  InFlag := False;
  for I := 1 to Length(Phonemes) do
    if Phonemes[I] = '(' then
      InFlag := True
    else if Phonemes[I] = ')' then
      InFlag := False
    else if not InFlag then
      Result := Result + Phonemes[I];
end;

// Piper decomposes the phonemes (NFD) before looking them up.
function Decompose(const S: string): string;
var
  Len: Integer;
begin
  Result := S;
  if S = '' then
    Exit;
  Len := NormalizeString(NORMALIZATION_D, PWideChar(S), Length(S), nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Result, Len);
  Len := NormalizeString(NORMALIZATION_D, PWideChar(S), Length(S), PWideChar(Result), Len);
  if Len > 0 then
    SetLength(Result, Len)
  else
    Result := S;
end;

function PhonemizeText(const Text, EspeakVoice: string): TPhonemeSentences;
var
  Utf8: UTF8String;
  P, Phonemes: PAnsiChar;
  Terminator: Integer;
  Sentence: TArray<Integer>;
  Clause: string;
  Ch, Mark: Char;

  procedure Flush;
  begin
    if Length(Sentence) > 0 then
      Result := Result + [Sentence];
    Sentence := nil;
  end;

begin
  Result := nil;
  if (GEspeak = 0) or (Trim(Text) = '') then
    Exit;
  if GVoice <> EspeakVoice then
  begin
    EspeakSetVoiceByName(PAnsiChar(AnsiString(EspeakVoice)));
    GVoice := EspeakVoice;
  end;
  Utf8 := UTF8String(Text);
  P := PAnsiChar(Utf8);
  Sentence := nil;
  while P <> nil do
  begin
    Terminator := 0;
    Phonemes := EspeakTextToPhonemes(P, ESPEAK_CHARS_AUTO, ESPEAK_PHONEMES_IPA, @Terminator);
    if Phonemes <> nil then
    begin
      Clause := Decompose(RemoveLanguageFlags(UTF8ToString(Phonemes)));
      for Ch in Clause do
        Sentence := Sentence + [Ord(Ch)];
    end;
    Mark := ClausePunctuation(Terminator);
    if Mark <> #0 then
      Sentence := Sentence + [Ord(Mark)];
    if IsSentenceEnd(Terminator) then
      Flush
    else
      Sentence := Sentence + [Ord(' ')];
  end;
  Flush;
end;

{ Catalogue }

function TNeuralVoiceInfo.Name: string;
begin
  if Id = 'ru-irina' then
    Result := T('Ирина', 'Irina')
  else if Id = 'ru-denis' then
    Result := T('Денис', 'Denis')
  else if Id = 'ru-dmitri' then
    Result := T('Дмитрий', 'Dmitri')
  else if Id = 'ru-ruslan' then
    Result := T('Руслан', 'Ruslan')
  else
    Result := 'LJSpeech';
end;

function TNeuralVoiceInfo.Recommended: Boolean;
begin
  Result := (Id = 'ru-ruslan') or (Id = 'en-ljspeech');
end;

function TNeuralVoiceInfo.License: string;
begin
  if (Id = 'ru-denis') or (Id = 'ru-dmitri') then
    Result := T('свободная лицензия (CC0)', 'free license (CC0)')
  else if Id = 'ru-ruslan' then
    Result := T('только некоммерческое использование (CC BY-NC-SA 4.0)',
      'non-commercial use only (CC BY-NC-SA 4.0)')
  else if Id = 'ru-irina' then
    Result := T('лицензия данных не указана (RHVoice)', 'data license not stated (RHVoice)')
  else
    Result := T('общественное достояние', 'public domain');
end;

function NeuralVoicesSupported: Boolean;
begin
{$IFDEF WIN64}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function FindNeuralVoice(const Id: string): Integer;
var
  Key: string;
  I: Integer;
begin
  Key := Id;
  if Key.StartsWith(NEURAL_VOICE_PREFIX) then
    Key := Copy(Key, Length(NEURAL_VOICE_PREFIX) + 1, MaxInt);
  for I := Low(NeuralVoices) to High(NeuralVoices) do
    if SameText(NeuralVoices[I].Id, Key) then
      Exit(I);
  Result := -1;
end;

function NeuralVoiceDir(const Voice: TNeuralVoiceInfo): string;
begin
  Result := TPath.Combine(TPath.Combine(SpeechRootDir, 'voices'), Voice.Archive);
end;

function PhonemizerDir: string;
begin
  Result := TPath.Combine(SpeechRootDir, 'phonemizer');
end;

function IsNeuralVoiceInstalled(const Voice: TNeuralVoiceInfo): Boolean;
begin
  Result := NeuralVoicesSupported and IsSpeechPackageInstalled(NeuralVoiceDir(Voice)) and
    IsSpeechPackageInstalled(PhonemizerDir) and IsSpeechTtsEngineInstalled;
end;

function PhonemizerUrl: string;
begin
  // A mirror (LS_SPEECH_MIRROR) keeps it under piper-phonemize/<release>/.
  if Trim(GetEnvironmentVariable('LS_SPEECH_MIRROR')) <> '' then
    Result := SpeechDownloadBase + 'piper-phonemize/' + PHONEMIZER_RELEASE + '/' + PHONEMIZER_ARCHIVE
  else
    Result := 'https://github.com/rhasspy/piper-phonemize/releases/download/' +
      PHONEMIZER_RELEASE + '/' + PHONEMIZER_ARCHIVE;
end;

function NeuralVoicePackages(const Voice: TNeuralVoiceInfo): TArray<TSpeechPackage>;
var
  Phonemizer, Model: TSpeechPackage;
  Base: string;
begin
  // Only the library and its data: the archive also holds onnxruntime and
  // tools.
  Phonemizer.Url := PhonemizerUrl;
  Phonemizer.Sha256 := PHONEMIZER_SHA256;
  Phonemizer.TargetDir := PhonemizerDir;
  Phonemizer.InnerDir := 'piper-phonemize';
  Phonemizer.Members := ['piper-phonemize/bin/espeak-ng.dll',
    'piper-phonemize/share/espeak-ng-data'];
  Phonemizer.Stage := sisDownloadPhonemizer;
  // The model, its settings and tokens; espeak-ng-data comes with the
  // phonemizer (the same for every voice).
  Base := Copy(Voice.Archive, Length('vits-piper-') + 1, MaxInt);
  Model.Url := SpeechDownloadBase + 'tts-models/' + Voice.Archive + '.tar.bz2';
  Model.Sha256 := Voice.Sha256;
  Model.TargetDir := NeuralVoiceDir(Voice);
  Model.InnerDir := Voice.Archive;
  Model.Members := [Voice.Archive + '/' + Base + '.onnx', Voice.Archive + '/' + Base + '.onnx.json',
    Voice.Archive + '/tokens.txt', Voice.Archive + '/MODEL_CARD'];
  Model.Stage := sisDownloadVoice;
  Result := [Phonemizer, Model];
end;

function NeuralVoiceDownloadMB(const Voice: TNeuralVoiceInfo): Integer;
begin
  Result := 0;
  if not IsSpeechPackageInstalled(NeuralVoiceDir(Voice)) then
    Inc(Result, Voice.DownloadMB);
  if not IsSpeechPackageInstalled(PhonemizerDir) then
    Inc(Result, PHONEMIZER_DOWNLOAD_MB);
  if not IsSpeechTtsEngineInstalled then
    Inc(Result, 31);
end;

function NeuralVoiceDiskMB(const Voice: TNeuralVoiceInfo): Integer;
var
  Total: Int64;
  FileName: string;
begin
  Total := 0;
  if TDirectory.Exists(NeuralVoiceDir(Voice)) then
    for FileName in TDirectory.GetFiles(NeuralVoiceDir(Voice), '*', TSearchOption.soAllDirectories) do
      Total := Total + TFile.GetSize(FileName);
  Result := (Total + 512 * 1024) div (1024 * 1024);
end;

function DeleteNeuralVoice(const Voice: TNeuralVoiceInfo): Boolean;
var
  Other: TNeuralVoiceInfo;
  Any: Boolean;
begin
  Result := True;
  try
    if TDirectory.Exists(NeuralVoiceDir(Voice)) then
      TDirectory.Delete(NeuralVoiceDir(Voice), True);
    Any := False;
    for Other in NeuralVoices do
      if TDirectory.Exists(NeuralVoiceDir(Other)) then
        Any := True;
    // espeak-ng.dll stays loaded until the program exits: then it is left.
    if not Any and TDirectory.Exists(PhonemizerDir) and not PhonemizerLoaded then
      TDirectory.Delete(PhonemizerDir, True);
  except
    Result := False;
  end;
end;

{ Playback }

type
  // waveOut with a queue of buffers: written ones play one after another.
  TWavePlayer = class
  private
    FWave: HWAVEOUT;
    FHeaders: TList;
    procedure Collect;
  public
    constructor Create(SampleRate: Integer);
    destructor Destroy; override;
    procedure Write(const Samples: TArray<Single>);
    // Buffers still playing.
    function Pending: Integer;
  end;

constructor TWavePlayer.Create(SampleRate: Integer);
var
  Format: TWaveFormatEx;
  Code: MMRESULT;
begin
  inherited Create;
  FHeaders := TList.Create;
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM;
  Format.nChannels := 1;
  Format.nSamplesPerSec := SampleRate;
  Format.wBitsPerSample := 16;
  Format.nBlockAlign := 2;
  Format.nAvgBytesPerSec := SampleRate * 2;
  Code := waveOutOpen(@FWave, WAVE_MAPPER, @Format, 0, 0, CALLBACK_NULL);
  if Code <> MMSYSERR_NOERROR then
  begin
    FWave := 0;
    raise Exception.CreateFmt(T('Не удалось открыть устройство вывода звука (код %d)',
      'Could not open the sound output (code %d)'), [Code]);
  end;
end;

destructor TWavePlayer.Destroy;
var
  I: Integer;
  Header: PWaveHdr;
begin
  if FWave <> 0 then
  begin
    waveOutReset(FWave);
    for I := 0 to FHeaders.Count - 1 do
    begin
      Header := FHeaders[I];
      waveOutUnprepareHeader(FWave, Header, SizeOf(TWaveHdr));
      FreeMem(Header.lpData);
      Dispose(Header);
    end;
    waveOutClose(FWave);
  end;
  FHeaders.Free;
  inherited;
end;

procedure TWavePlayer.Write(const Samples: TArray<Single>);
var
  Header: PWaveHdr;
  Data: PByte;
  I: Integer;
begin
  if Length(Samples) = 0 then
    Exit;
  New(Header);
  FillChar(Header^, SizeOf(TWaveHdr), 0);
  GetMem(Data, Length(Samples) * 2);
  for I := 0 to High(Samples) do
    PSmallInt(Data + I * 2)^ := Round(EnsureRange(Samples[I], -1.0, 1.0) * 32767);
  Header.lpData := PAnsiChar(Data);
  Header.dwBufferLength := Length(Samples) * 2;
  waveOutPrepareHeader(FWave, Header, SizeOf(TWaveHdr));
  waveOutWrite(FWave, Header, SizeOf(TWaveHdr));
  FHeaders.Add(Header);
end;

procedure TWavePlayer.Collect;
var
  I: Integer;
  Header: PWaveHdr;
begin
  for I := FHeaders.Count - 1 downto 0 do
  begin
    Header := FHeaders[I];
    if (Header.dwFlags and WHDR_DONE) <> 0 then
    begin
      waveOutUnprepareHeader(FWave, Header, SizeOf(TWaveHdr));
      FreeMem(Header.lpData);
      Dispose(Header);
      FHeaders.Delete(I);
    end;
  end;
end;

function TWavePlayer.Pending: Integer;
begin
  Collect;
  Result := FHeaders.Count;
end;

{ Speaker }

const
  SENTENCE_GAP_MS = 120;
  PARAGRAPH_GAP_MS = 450;

type
  TSpeakThread = class(TThread)
  private
    FOwner: TNeuralSpeaker;
    FSegments: TArray<TNeuralSegment>;
    FSpeed: Single;
    function LoadVoice(Index: Integer): TLoadedVoice;
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TNeuralSpeaker; const Segments: TArray<TNeuralSegment>;
      Speed: Single);
  end;

constructor TSpeakThread.Create(Owner: TNeuralSpeaker; const Segments: TArray<TNeuralSegment>;
  Speed: Single);
begin
  FOwner := Owner;
  FSegments := Segments;
  FSpeed := Speed;
  FreeOnTerminate := False;
  inherited Create(False);
end;

function Silence(SampleRate, MS: Integer): TArray<Single>;
begin
  SetLength(Result, SampleRate * MS div 1000);
  if Length(Result) > 0 then
    FillChar(Result[0], Length(Result) * SizeOf(Single), 0);
end;

// The voice from the loaded ones or loaded now (the oldest one goes when
// two are loaded already).
function TSpeakThread.LoadVoice(Index: Integer): TLoadedVoice;
var
  Voice: TNeuralVoiceInfo;
  Dir, JsonFile: string;
  Json, Value: TJSONValue;
  NoiseScale, NoiseW, LengthScale: Single;
  Files: TArray<string>;
  I: Integer;
begin
  Voice := NeuralVoices[Index];
  for I := 0 to High(FOwner.FLoaded) do
    if FOwner.FLoaded[I].Id = Voice.Id then
      Exit(FOwner.FLoaded[I]);
  Dir := NeuralVoiceDir(Voice);
  Files := TDirectory.GetFiles(Dir, '*.onnx.json');
  if Length(Files) = 0 then
    raise Exception.Create(T('Файлы голоса повреждены. Скачайте голос заново.',
      'The voice files are damaged. Download the voice again.'));
  JsonFile := Files[0];
  // The voice settings: the espeak-ng language and the noise scales.
  if Voice.Language = $0419 then
    Result.EspeakVoice := 'ru'
  else
    Result.EspeakVoice := 'en-us';
  NoiseScale := 0.667;
  NoiseW := 0.8;
  LengthScale := 1;
  Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(JsonFile, TEncoding.UTF8));
  if Json <> nil then
  try
    Value := Json.FindValue('espeak.voice');
    if Value <> nil then
      Result.EspeakVoice := Value.Value;
    Value := Json.FindValue('inference.noise_scale');
    if Value <> nil then
      NoiseScale := StrToFloatDef(Value.Value, NoiseScale, TFormatSettings.Invariant);
    Value := Json.FindValue('inference.noise_w');
    if Value <> nil then
      NoiseW := StrToFloatDef(Value.Value, NoiseW, TFormatSettings.Invariant);
    Value := Json.FindValue('inference.length_scale');
    if Value <> nil then
      LengthScale := StrToFloatDef(Value.Value, LengthScale, TFormatSettings.Invariant);
  finally
    Json.Free;
  end;
  if Length(FOwner.FLoaded) >= 2 then
  begin
    FOwner.FLoaded[0].Synth.Free;
    Delete(FOwner.FLoaded, 0, 1);
  end;
  Result.Id := Voice.Id;
  Result.Synth := TSpeechSynthesizer.Create(Copy(JsonFile, 1, Length(JsonFile) - Length('.json')),
    TPath.Combine(Dir, 'tokens.txt'), EnsureRange(TThread.ProcessorCount div 2, 1, 4),
    NoiseScale, NoiseW, LengthScale);
  FOwner.FLoaded := FOwner.FLoaded + [Result];
end;

procedure TSpeakThread.Execute;
var
  ErrorText: string;
  Player: TWavePlayer;
  PlayerRate: Integer;
  Segment: TNeuralSegment;
  Voice: TLoadedVoice;
  Sentence: TArray<Integer>;
  Samples: TArray<Single>;
begin
  NameThreadForDebugging('LayoutSwitcher.ReadAloud');
  Player := nil;
  PlayerRate := 0;
  try
    try
      if not LoadPhonemizer(TPath.Combine(PhonemizerDir, 'bin\espeak-ng.dll'),
           TPath.Combine(PhonemizerDir, 'share'), ErrorText) then
        raise Exception.Create(ErrorText);
      for Segment in FSegments do
      begin
        if Terminated then
          Break;
        Voice := LoadVoice(Segment.VoiceIndex);
        // Another sample rate: the queued sound plays out first.
        if Voice.Synth.SampleRate <> PlayerRate then
        begin
          if Player <> nil then
            while not Terminated and (Player.Pending > 0) do
              Sleep(20);
          FreeAndNil(Player);
          Player := TWavePlayer.Create(Voice.Synth.SampleRate);
          PlayerRate := Voice.Synth.SampleRate;
        end;
        for Sentence in PhonemizeText(Segment.Text, Voice.EspeakVoice) do
        begin
          if Terminated then
            Break;
          Samples := Voice.Synth.GeneratePhonemes(Sentence, FSpeed);
          Player.Write(Samples + Silence(PlayerRate, SENTENCE_GAP_MS));
        end;
        if Segment.ParagraphEnd then
          Player.Write(Silence(PlayerRate, PARAGRAPH_GAP_MS));
      end;
      // To the end of the last sentence.
      while not Terminated and (Player <> nil) and (Player.Pending > 0) do
        Sleep(20);
    except
      on E: Exception do
        FOwner.SetError(E.Message);
    end;
  finally
    Player.Free;
  end;
end;

constructor TNeuralSpeaker.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
end;

destructor TNeuralSpeaker.Destroy;
begin
  Stop;
  Unload;
  FLock.Free;
  inherited;
end;

procedure TNeuralSpeaker.SetError(const Text: string);
begin
  FLock.Enter;
  try
    FError := Text;
  finally
    FLock.Leave;
  end;
end;

function TNeuralSpeaker.TakeError: string;
begin
  FLock.Enter;
  try
    Result := FError;
    FError := '';
  finally
    FLock.Leave;
  end;
end;

procedure TNeuralSpeaker.Speak(const Segments: TArray<TNeuralSegment>; Speed: Single);
begin
  Stop;
  TakeError;
  FThread := TSpeakThread.Create(Self, Segments, Speed);
end;

procedure TNeuralSpeaker.Stop;
begin
  if FThread = nil then
    Exit;
  FThread.Terminate;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

function TNeuralSpeaker.Speaking: Boolean;
begin
  Result := (FThread <> nil) and not FThread.Finished;
end;

procedure TNeuralSpeaker.Unload;
var
  Voice: TLoadedVoice;
begin
  if Speaking then
    Exit;
  Stop;
  for Voice in FLoaded do
    Voice.Synth.Free;
  FLoaded := nil;
end;

end.
