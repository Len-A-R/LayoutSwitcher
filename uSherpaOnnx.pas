unit uSherpaOnnx;

// Offline speech recognition with the sherpa-onnx C API (c-api.h of
// sherpa-onnx v2.0.3, see SHERPA_VERSION in uSpeechModels).  The library is
// loaded at run time from the downloaded engine folder.  The records below
// mirror the C structures field by field: they must change together with
// the pinned version (TestSpeech checks their sizes).

{$ALIGN 8}
{$MINENUMSIZE 4}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  uSpeechModels;

type
  PSherpaChar = PAnsiChar;   // UTF-8

  TSherpaFeatureConfig = record
    sample_rate: Int32;
    feature_dim: Int32;
  end;

  TSherpaTransducer = record
    encoder, decoder, joiner: PSherpaChar;
  end;

  TSherpaOneModel = record
    model: PSherpaChar;
  end;

  TSherpaWhisper = record
    encoder, decoder, language, task: PSherpaChar;
    tail_paddings, enable_token_timestamps, enable_segment_timestamps: Int32;
  end;

  TSherpaSenseVoice = record
    model, language: PSherpaChar;
    use_itn: Int32;
  end;

  TSherpaMoonshine = record
    preprocessor, encoder, uncached_decoder, cached_decoder, merged_decoder: PSherpaChar;
  end;

  TSherpaEncDec = record
    encoder, decoder: PSherpaChar;
  end;

  TSherpaCanary = record
    encoder, decoder, src_lang, tgt_lang: PSherpaChar;
    use_pnc: Int32;
  end;

  TSherpaFunAsrNano = record
    encoder_adaptor, llm, embedding, tokenizer, system_prompt, user_prompt: PSherpaChar;
    max_new_tokens: Int32;
    temperature, top_p: Single;
    seed: Int32;
    language: PSherpaChar;
    itn: Int32;
    hotwords: PSherpaChar;
  end;

  TSherpaQwen3Asr = record
    conv_frontend, encoder, decoder, tokenizer: PSherpaChar;
    max_total_len, max_new_tokens: Int32;
    temperature, top_p: Single;
    seed: Int32;
    hotwords: PSherpaChar;
  end;

  TSherpaCohere = record
    encoder, decoder, language: PSherpaChar;
    use_punct, use_itn: Int32;
  end;

  TSherpaOfflineModelConfig = record
    transducer: TSherpaTransducer;
    paraformer: TSherpaOneModel;
    nemo_ctc: TSherpaOneModel;
    whisper: TSherpaWhisper;
    tdnn: TSherpaOneModel;
    tokens: PSherpaChar;
    num_threads: Int32;
    debug: Int32;
    provider: PSherpaChar;
    model_type: PSherpaChar;
    modeling_unit: PSherpaChar;
    bpe_vocab: PSherpaChar;
    telespeech_ctc: PSherpaChar;
    sense_voice: TSherpaSenseVoice;
    moonshine: TSherpaMoonshine;
    fire_red_asr: TSherpaEncDec;
    dolphin: TSherpaOneModel;
    zipformer_ctc: TSherpaOneModel;
    canary: TSherpaCanary;
    wenet_ctc: TSherpaOneModel;
    omnilingual: TSherpaOneModel;
    medasr: TSherpaOneModel;
    funasr_nano: TSherpaFunAsrNano;
    fire_red_asr_ctc: TSherpaOneModel;
    qwen3_asr: TSherpaQwen3Asr;
    cohere_transcribe: TSherpaCohere;
  end;

  TSherpaLMConfig = record
    model: PSherpaChar;
    scale: Single;
  end;

  TSherpaHomophoneReplacer = record
    dict_dir, lexicon, rule_fsts: PSherpaChar;
  end;

  TSherpaCtcFstDecoder = record
    graph: PSherpaChar;
    max_active: Int32;
  end;

  TSherpaOfflineRecognizerConfig = record
    feat_config: TSherpaFeatureConfig;
    model_config: TSherpaOfflineModelConfig;
    lm_config: TSherpaLMConfig;
    decoding_method: PSherpaChar;
    max_active_paths: Int32;
    hotwords_file: PSherpaChar;
    hotwords_score: Single;
    rule_fsts: PSherpaChar;
    rule_fars: PSherpaChar;
    blank_penalty: Single;
    hr: TSherpaHomophoneReplacer;
    ctc_fst_decoder_config: TSherpaCtcFstDecoder;
  end;
  PSherpaOfflineRecognizerConfig = ^TSherpaOfflineRecognizerConfig;

  // Only the first field is read.
  TSherpaOfflineRecognizerResult = record
    text: PSherpaChar;
  end;
  PSherpaOfflineRecognizerResult = ^TSherpaOfflineRecognizerResult;

  // One loaded model.  Not thread-safe: use it from one thread at a time.
  TSpeechRecognizer = class
  private
    FRecognizer: Pointer;
    FModelId: string;
  public
    // Raises an exception with a readable message when the engine or the
    // model cannot be loaded.
    constructor Create(const Model: TSpeechModel; Threads: Integer);
    destructor Destroy; override;
    // 16 kHz mono samples in -1..1.
    function Recognize(const Samples: TArray<Single>): string;
    property ModelId: string read FModelId;
  end;

  // Offline text-to-speech (only the VITS/Piper part is used).
  TSherpaTtsVits = record
    model, lexicon, tokens, data_dir: PSherpaChar;
    noise_scale, noise_scale_w, length_scale: Single;
    dict_dir: PSherpaChar;
  end;

  TSherpaTtsMatcha = record
    acoustic_model, vocoder, lexicon, tokens, data_dir: PSherpaChar;
    noise_scale, length_scale: Single;
    dict_dir: PSherpaChar;
  end;

  TSherpaTtsKokoro = record
    model, voices, tokens, data_dir: PSherpaChar;
    length_scale: Single;
    dict_dir, lexicon, lang: PSherpaChar;
  end;

  TSherpaTtsKitten = record
    model, voices, tokens, data_dir: PSherpaChar;
    length_scale: Single;
    lexicon: PSherpaChar;
  end;

  TSherpaTtsZipvoice = record
    tokens, encoder, decoder, vocoder, data_dir, lexicon: PSherpaChar;
    feat_scale, t_shift, target_rms, guidance_scale: Single;
  end;

  TSherpaTtsPocket = record
    lm_flow, lm_main, encoder, decoder, text_conditioner, vocab_json,
      token_scores_json: PSherpaChar;
    voice_embedding_cache_capacity: Int32;
  end;

  TSherpaTtsSupertonic = record
    duration_predictor, text_encoder, vector_estimator, vocoder, tts_json,
      unicode_indexer, voice_style: PSherpaChar;
  end;

  TSherpaTtsModelConfig = record
    vits: TSherpaTtsVits;
    num_threads: Int32;
    debug: Int32;
    provider: PSherpaChar;
    matcha: TSherpaTtsMatcha;
    kokoro: TSherpaTtsKokoro;
    kitten: TSherpaTtsKitten;
    zipvoice: TSherpaTtsZipvoice;
    pocket: TSherpaTtsPocket;
    supertonic: TSherpaTtsSupertonic;
  end;

  TSherpaTtsConfig = record
    model: TSherpaTtsModelConfig;
    rule_fsts: PSherpaChar;
    max_num_sentences: Int32;
    rule_fars: PSherpaChar;
    silence_scale: Single;
  end;
  PSherpaTtsConfig = ^TSherpaTtsConfig;

  TSherpaGenerationConfig = record
    silence_scale: Single;
    speed: Single;
    sid: Int32;
    reference_audio: PSingle;
    reference_audio_len: Int32;
    reference_sample_rate: Int32;
    reference_text: PSherpaChar;
    num_steps: Int32;
    extra: PSherpaChar;
    phoneme_codepoints: PInteger;
    phoneme_codepoints_lens: PInteger;
    phoneme_codepoints_num_sentences: Int32;
    tokens: Pointer;
    tokens_lens: PInteger;
    tokens_num_sentences: Int32;
  end;
  PSherpaGenerationConfig = ^TSherpaGenerationConfig;

  TSherpaGeneratedAudio = record
    samples: PSingle;
    n: Int32;
    sample_rate: Int32;
  end;
  PSherpaGeneratedAudio = ^TSherpaGeneratedAudio;

  // One loaded voice (a Piper VITS model).  Not thread-safe.
  TSpeechSynthesizer = class
  private
    FTts: Pointer;
    FSampleRate: Integer;
  public
    // ModelFile: the .onnx; Tokens: tokens.txt; the scales come from the
    // .onnx.json of the voice.  Raises an exception with a readable message
    // when it cannot load.
    constructor Create(const ModelFile, Tokens: string; Threads: Integer;
      NoiseScale, NoiseScaleW, LengthScale: Single);
    destructor Destroy; override;
    // Mono samples in -1..1 at SampleRate for one sentence given as phoneme
    // codepoints (espeak-ng IPA, see uNeuralVoice); Speed 1 is normal.
    function GeneratePhonemes(const Codepoints: TArray<Integer>; Speed: Single): TArray<Single>;
    property SampleRate: Integer read FSampleRate;
  end;

// For the tests: sizes of the mirrored C structures.
function SherpaConfigSize: Integer;
function SherpaTtsConfigSize: Integer;
function SherpaGenerationConfigSize: Integer;

implementation

uses
  System.IOUtils, uLocale;

type
  TCreateOfflineRecognizer = function(Config: PSherpaOfflineRecognizerConfig): Pointer; cdecl;
  TDestroyOfflineRecognizer = procedure(Recognizer: Pointer); cdecl;
  TCreateOfflineStream = function(Recognizer: Pointer): Pointer; cdecl;
  TDestroyOfflineStream = procedure(Stream: Pointer); cdecl;
  TAcceptWaveformOffline = procedure(Stream: Pointer; SampleRate: Int32;
    Samples: PSingle; Count: Int32); cdecl;
  TDecodeOfflineStream = procedure(Recognizer, Stream: Pointer); cdecl;
  TGetOfflineStreamResult = function(Stream: Pointer): PSherpaOfflineRecognizerResult; cdecl;
  TDestroyOfflineRecognizerResult = procedure(Result: PSherpaOfflineRecognizerResult); cdecl;
  TCreateOfflineTts = function(Config: PSherpaTtsConfig): Pointer; cdecl;
  TDestroyOfflineTts = procedure(Tts: Pointer); cdecl;
  TOfflineTtsSampleRate = function(Tts: Pointer): Int32; cdecl;
  TOfflineTtsGenerateWithConfig = function(Tts: Pointer; Text: PSherpaChar;
    Config: PSherpaGenerationConfig; Callback, Arg: Pointer): PSherpaGeneratedAudio; cdecl;
  TDestroyGeneratedAudio = procedure(Audio: PSherpaGeneratedAudio); cdecl;

var
  GLibrary: HMODULE;
  CreateOfflineRecognizer: TCreateOfflineRecognizer;
  DestroyOfflineRecognizer: TDestroyOfflineRecognizer;
  CreateOfflineStream: TCreateOfflineStream;
  DestroyOfflineStream: TDestroyOfflineStream;
  AcceptWaveformOffline: TAcceptWaveformOffline;
  DecodeOfflineStream: TDecodeOfflineStream;
  GetOfflineStreamResult: TGetOfflineStreamResult;
  DestroyOfflineRecognizerResult: TDestroyOfflineRecognizerResult;
  // Bound separately: an engine without text-to-speech still recognizes.
  CreateOfflineTts: TCreateOfflineTts;
  DestroyOfflineTts: TDestroyOfflineTts;
  OfflineTtsSampleRate: TOfflineTtsSampleRate;
  OfflineTtsGenerateWithConfig: TOfflineTtsGenerateWithConfig;
  DestroyGeneratedAudio: TDestroyGeneratedAudio;

function SherpaConfigSize: Integer;
begin
  Result := SizeOf(TSherpaOfflineRecognizerConfig);
end;

function SherpaTtsConfigSize: Integer;
begin
  Result := SizeOf(TSherpaTtsConfig);
end;

function SherpaGenerationConfigSize: Integer;
begin
  Result := SizeOf(TSherpaGenerationConfig);
end;

procedure LoadEngine;
var
  Dir, FileName: string;

  function Bind(const Name: string): Pointer;
  begin
    Result := GetProcAddress(GLibrary, PChar(Name));
    if Result = nil then
      raise Exception.CreateFmt(T('В движке распознавания нет функции %s',
        'The recognition engine lacks the function %s'), [Name]);
  end;

begin
  if GLibrary <> 0 then
    Exit;
  Dir := TPath.Combine(SpeechEngineDir, 'lib');
  FileName := TPath.Combine(Dir, 'sherpa-onnx-c-api.dll');
  if not FileExists(FileName) then
    raise Exception.Create(T('Движок распознавания речи не установлен',
      'The speech recognition engine is not installed'));
  // onnxruntime.dll lies next to it.
  GLibrary := LoadLibraryEx(PChar(FileName), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  if GLibrary = 0 then
    raise Exception.CreateFmt(T('Не удалось загрузить движок распознавания (%s)',
      'Could not load the recognition engine (%s)'), [SysErrorMessage(GetLastError)]);
  try
    @CreateOfflineRecognizer := Bind('SherpaOnnxCreateOfflineRecognizer');
    @DestroyOfflineRecognizer := Bind('SherpaOnnxDestroyOfflineRecognizer');
    @CreateOfflineStream := Bind('SherpaOnnxCreateOfflineStream');
    @DestroyOfflineStream := Bind('SherpaOnnxDestroyOfflineStream');
    @AcceptWaveformOffline := Bind('SherpaOnnxAcceptWaveformOffline');
    @DecodeOfflineStream := Bind('SherpaOnnxDecodeOfflineStream');
    @GetOfflineStreamResult := Bind('SherpaOnnxGetOfflineStreamResult');
    @DestroyOfflineRecognizerResult := Bind('SherpaOnnxDestroyOfflineRecognizerResult');
    @CreateOfflineTts := GetProcAddress(GLibrary, 'SherpaOnnxCreateOfflineTts');
    @DestroyOfflineTts := GetProcAddress(GLibrary, 'SherpaOnnxDestroyOfflineTts');
    @OfflineTtsSampleRate := GetProcAddress(GLibrary, 'SherpaOnnxOfflineTtsSampleRate');
    @OfflineTtsGenerateWithConfig := GetProcAddress(GLibrary, 'SherpaOnnxOfflineTtsGenerateWithConfig');
    @DestroyGeneratedAudio := GetProcAddress(GLibrary, 'SherpaOnnxDestroyOfflineTtsGeneratedAudio');
  except
    FreeLibrary(GLibrary);
    GLibrary := 0;
    raise;
  end;
end;

// The engine opens files with narrow paths: a user name in Cyrillic would
// not survive.  The short 8.3 form of a path is ASCII.
function EnginePath(const FileName: string): UTF8String;
var
  Buffer: array[0..MAX_PATH] of Char;
  Len: DWORD;
begin
  Len := GetShortPathName(PChar(FileName), Buffer, Length(Buffer));
  if (Len > 0) and (Len < DWORD(Length(Buffer))) then
    Result := UTF8String(string(Buffer))
  else
    Result := UTF8String(FileName);
end;

{ TSpeechRecognizer }

constructor TSpeechRecognizer.Create(const Model: TSpeechModel; Threads: Integer);
var
  Config: TSherpaOfflineRecognizerConfig;
  Dir: string;
  Encoder, Decoder, Joiner, CtcModel, Tokens, Provider, Method, ModelType: UTF8String;

  function Need(const Prefix: string): UTF8String;
  var
    FileName: string;
  begin
    FileName := FindModelFile(Dir, Prefix);
    if FileName = '' then
      raise Exception.CreateFmt(T('Файлы модели повреждены (нет %s). Скачайте модель заново.',
        'The model files are damaged (%s is missing). Download the model again.'), [Prefix]);
    Result := EnginePath(FileName);
  end;

begin
  inherited Create;
  FModelId := Model.Id;
  LoadEngine;
  Dir := SpeechModelDir(Model);
  if not FileExists(TPath.Combine(Dir, 'tokens.txt')) then
    raise Exception.Create(T('Модель не установлена', 'The model is not installed'));
  FillChar(Config, SizeOf(Config), 0);
  Config.feat_config.sample_rate := 16000;
  Config.feat_config.feature_dim := 80;
  Tokens := EnginePath(TPath.Combine(Dir, 'tokens.txt'));
  Provider := 'cpu';
  Method := 'greedy_search';
  case Model.Kind of
    smkNemoCtc:
      begin
        CtcModel := Need('model');
        Config.model_config.nemo_ctc.model := PSherpaChar(CtcModel);
      end;
    smkTransducer, smkNemoTransducer:
      begin
        Encoder := Need('encoder');
        Decoder := Need('decoder');
        Joiner := Need('joiner');
        Config.model_config.transducer.encoder := PSherpaChar(Encoder);
        Config.model_config.transducer.decoder := PSherpaChar(Decoder);
        Config.model_config.transducer.joiner := PSherpaChar(Joiner);
        if Model.Kind = smkNemoTransducer then
        begin
          ModelType := 'nemo_transducer';
          Config.model_config.model_type := PSherpaChar(ModelType);
        end;
      end;
  else
    raise Exception.Create('Not a local model');
  end;
  Config.model_config.tokens := PSherpaChar(Tokens);
  Config.model_config.num_threads := Threads;
  Config.model_config.provider := PSherpaChar(Provider);
  Config.decoding_method := PSherpaChar(Method);
  FRecognizer := CreateOfflineRecognizer(@Config);
  if FRecognizer = nil then
    raise Exception.Create(T('Не удалось загрузить модель распознавания',
      'Could not load the recognition model'));
end;

destructor TSpeechRecognizer.Destroy;
begin
  if FRecognizer <> nil then
    DestroyOfflineRecognizer(FRecognizer);
  inherited;
end;

function TSpeechRecognizer.Recognize(const Samples: TArray<Single>): string;
var
  Stream: Pointer;
  Res: PSherpaOfflineRecognizerResult;
begin
  Result := '';
  if Length(Samples) = 0 then
    Exit;
  Stream := CreateOfflineStream(FRecognizer);
  if Stream = nil then
    raise Exception.Create('sherpa-onnx: no stream');
  try
    AcceptWaveformOffline(Stream, 16000, @Samples[0], Length(Samples));
    DecodeOfflineStream(FRecognizer, Stream);
    Res := GetOfflineStreamResult(Stream);
    if Res <> nil then
    try
      if Res.text <> nil then
        Result := UTF8ToString(Res.text);
    finally
      DestroyOfflineRecognizerResult(Res);
    end;
  finally
    DestroyOfflineStream(Stream);
  end;
end;

{ TSpeechSynthesizer }

constructor TSpeechSynthesizer.Create(const ModelFile, Tokens: string;
  Threads: Integer; NoiseScale, NoiseScaleW, LengthScale: Single);
var
  Config: TSherpaTtsConfig;
  Model, TokensPath, Provider: UTF8String;
begin
  inherited Create;
  LoadEngine;
  if not Assigned(CreateOfflineTts) or not Assigned(OfflineTtsGenerateWithConfig) or
     not Assigned(DestroyGeneratedAudio) then
  begin
    // Dictation loaded the old build in this session; the new one is on
    // the disk already.
    if IsSpeechTtsEngineInstalled then
      raise Exception.Create(T('Перезапустите LayoutSwitcher: после обновления движка голос ' +
        'заработает со следующего запуска.', 'Restart LayoutSwitcher: after the engine update ' +
        'the voice works from the next start.'));
    raise Exception.Create(T('Установленный движок не умеет синтезировать речь. Скачайте голос ' +
      'заново: движок обновится.', 'The installed engine cannot synthesize speech. Download ' +
      'the voice again: the engine will be updated.'));
  end;
  if not FileExists(ModelFile) or not FileExists(Tokens) then
    raise Exception.Create(T('Файлы голоса повреждены. Скачайте голос заново.',
      'The voice files are damaged. Download the voice again.'));
  FillChar(Config, SizeOf(Config), 0);
  Model := EnginePath(ModelFile);
  TokensPath := EnginePath(Tokens);
  Provider := 'cpu';
  Config.model.vits.model := PSherpaChar(Model);
  Config.model.vits.tokens := PSherpaChar(TokensPath);
  Config.model.vits.noise_scale := NoiseScale;
  Config.model.vits.noise_scale_w := NoiseScaleW;
  Config.model.vits.length_scale := LengthScale;
  Config.model.num_threads := Threads;
  Config.model.provider := PSherpaChar(Provider);
  Config.max_num_sentences := 1;
  Config.silence_scale := 0.2;
  FTts := CreateOfflineTts(@Config);
  if FTts = nil then
    raise Exception.Create(T('Не удалось загрузить голос', 'Could not load the voice'));
  FSampleRate := OfflineTtsSampleRate(FTts);
end;

destructor TSpeechSynthesizer.Destroy;
begin
  if FTts <> nil then
    DestroyOfflineTts(FTts);
  inherited;
end;

function TSpeechSynthesizer.GeneratePhonemes(const Codepoints: TArray<Integer>;
  Speed: Single): TArray<Single>;
var
  Config: TSherpaGenerationConfig;
  Len: Integer;
  Empty: UTF8String;
  Audio: PSherpaGeneratedAudio;
begin
  Result := nil;
  if Length(Codepoints) = 0 then
    Exit;
  FillChar(Config, SizeOf(Config), 0);
  Config.silence_scale := 0.2;
  Config.speed := Speed;
  Len := Length(Codepoints);
  Config.phoneme_codepoints := @Codepoints[0];
  Config.phoneme_codepoints_lens := @Len;
  Config.phoneme_codepoints_num_sentences := 1;
  Empty := '';
  Audio := OfflineTtsGenerateWithConfig(FTts, PSherpaChar(Empty), @Config, nil, nil);
  if Audio = nil then
    Exit;
  try
    if (Audio.samples <> nil) and (Audio.n > 0) then
    begin
      SetLength(Result, Audio.n);
      Move(Audio.samples^, Result[0], Audio.n * SizeOf(Single));
    end;
  finally
    DestroyGeneratedAudio(Audio);
  end;
end;

end.
