unit TestSpeech;

// Dictation: the model catalogue, the mirrored sherpa-onnx structures, text
// post-processing, WAV encoding, the cloud response, settings and the
// Scroll Lock gesture.  No microphone, network or model files.

interface

uses
  DUnitX.TestFramework,
  uSpeechModels, uSherpaOnnx, uAudioRecorder, uSpeechCloud, uSettings, uGestureDetector;

type
  [TestFixture]
  TSpeechTests = class
  public
    [Test]
    procedure SherpaStructuresMatchCHeader;
    [Test]
    procedure Catalogue;
    [Test]
    procedure ModelFiles;
    [Test]
    procedure FinishText;
    [Test]
    procedure Wav;
    [Test]
    procedure Cloud;
    [Test]
    procedure SettingsAndMigration;
    [Test]
    procedure ScrollLockGesture;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils;

procedure TSpeechTests.SherpaStructuresMatchCHeader;
var
  Config: TSherpaOfflineRecognizerConfig;

  function Offset(const Field): Integer;
  begin
    Result := PByte(@Field) - PByte(@Config);
  end;

begin
  // Reference values: ctypes (MSVC layout) over c-api.h of sherpa-onnx 2.0.3.
{$IFDEF WIN64}
  Assert.AreEqual(624, SherpaConfigSize);
  Assert.AreEqual(8, Offset(Config.model_config));
  Assert.AreEqual(8 + 96, Offset(Config.model_config.tokens));
  Assert.AreEqual(8 + 104, Offset(Config.model_config.num_threads));
  Assert.AreEqual(8 + 120, Offset(Config.model_config.model_type));
  Assert.AreEqual(8 + 152, Offset(Config.model_config.sense_voice));
  Assert.AreEqual(8 + 408, Offset(Config.model_config.qwen3_asr));
  Assert.AreEqual(8 + 472, Offset(Config.model_config.cohere_transcribe));
  Assert.AreEqual(512, Offset(Config.lm_config));
  Assert.AreEqual(528, Offset(Config.decoding_method));
  Assert.AreEqual(552, Offset(Config.hotwords_score));
  Assert.AreEqual(576, Offset(Config.blank_penalty));
  Assert.AreEqual(584, Offset(Config.hr));
  Assert.AreEqual(608, Offset(Config.ctc_fst_decoder_config));
{$ENDIF}
end;

procedure TSpeechTests.Catalogue;
var
  I, J: Integer;
  Model: TSpeechModel;
begin
  Assert.IsTrue(FindSpeechModel(DEFAULT_SPEECH_MODEL) >= 0);
  Assert.AreEqual(-1, FindSpeechModel('nope'));
  Assert.IsTrue(SpeechModels[FindSpeechModel(SPEECH_CLOUD_MODEL)].IsCloud);
  for I := Low(SpeechModels) to High(SpeechModels) do
  begin
    Model := SpeechModels[I];
    for J := I + 1 to High(SpeechModels) do
      Assert.AreNotEqual(Model.Id, SpeechModels[J].Id);
    Assert.IsTrue(Model.Name <> '');
    Assert.IsTrue(Model.Pros <> '', Model.Id);
    Assert.IsTrue(Model.Cons <> '', Model.Id);
    if not Model.IsCloud then
    begin
      // Every download is checked.
      Assert.AreEqual(64, Length(Model.Sha256), Model.Id);
      Assert.IsTrue(Model.DownloadMB > 0);
      Assert.IsTrue(SpeechModelUrl(Model).StartsWith(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'));
      Assert.IsTrue(SpeechModelUrl(Model).EndsWith('.tar.bz2'));
    end;
  end;
  Assert.AreEqual(64, Length(SpeechEngineSha256));
  Assert.IsTrue(SpeechEngineUrl.Contains('/v' + SHERPA_VERSION + '/'));
  Assert.IsTrue(SpeechEngineUrl.Contains('-MT-'));   // no VC++ runtime needed
  Assert.IsTrue(SpeechEngineDir.StartsWith(SpeechRootDir));
end;

procedure TSpeechTests.ModelFiles;
var
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'ls-speech-test');
  ForceDirectories(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'encoder.onnx'), 'x');
    TFile.WriteAllText(TPath.Combine(Dir, 'encoder.int8.onnx'), 'x');
    TFile.WriteAllText(TPath.Combine(Dir, 'decoder.onnx'), 'x');
    Assert.AreEqual('encoder.int8.onnx', ExtractFileName(FindModelFile(Dir, 'encoder')));
    Assert.AreEqual('decoder.onnx', ExtractFileName(FindModelFile(Dir, 'decoder')));
    Assert.AreEqual('', FindModelFile(Dir, 'joiner'));
    Assert.AreEqual('', FindModelFile(Dir + 'missing', 'encoder'));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TSpeechTests.FinishText;
begin
  // Models without punctuation: a capital at the start.
  Assert.AreEqual('Привет как дела', FinishDictatedText(' привет как дела ', False, ''));
  // Models with punctuation are left alone.
  Assert.AreEqual('привет.', FinishDictatedText('привет.', True, ''));
  // After a word: a space, as if typed; not after a space or a bracket.
  Assert.AreEqual(' Да.', FinishDictatedText('Да.', True, 'Ответ'));
  Assert.AreEqual('Да.', FinishDictatedText('Да.', True, 'Ответ '));
  Assert.AreEqual('Да.', FinishDictatedText('Да.', True, 'Ответ ('));
  Assert.AreEqual('Да.', FinishDictatedText('Да.', True, '«'));
  Assert.AreEqual('', FinishDictatedText('   ', False, 'x'));
end;

procedure TSpeechTests.Wav;
var
  Data: TBytes;
  Samples: TArray<SmallInt>;
  Floats: TArray<Single>;
begin
  Data := EncodeWav([0, 0.5, -1, 2], 16000);
  Assert.AreEqual<Integer>(44 + 8, Length(Data));
  Assert.AreEqual('RIFF', string(AnsiString(PAnsiChar(@Data[0]))).Substring(0, 4));
  Assert.AreEqual<Cardinal>(16000, PCardinal(@Data[24])^);
  Assert.AreEqual<Cardinal>(8, PCardinal(@Data[40])^);
  Assert.AreEqual<SmallInt>(16384, PSmallInt(@Data[46])^);
  Assert.AreEqual<SmallInt>(-32768, PSmallInt(@Data[48])^);
  Assert.AreEqual<SmallInt>(32767, PSmallInt(@Data[50])^);   // clipped
  Samples := [0, 16384, -32768];
  Floats := SamplesToFloat(Samples, 3);
  Assert.AreEqual<Single>(0.5, Floats[1]);
  Assert.AreEqual<Single>(-1, Floats[2]);
  Assert.AreEqual(100, PeakLevel(@Samples[0], 3));
  Assert.AreEqual(50, PeakLevel(@Samples[0], 2));
end;

procedure TSpeechTests.Cloud;
var
  Text, Error: string;
begin
  Assert.AreEqual('https://api.groq.com/openai/v1/audio/transcriptions', TranscriptionUrl(''));
  Assert.AreEqual('https://api.openai.com/v1/audio/transcriptions',
    TranscriptionUrl('https://api.openai.com/v1/'));
  Assert.AreEqual('http://localhost:8000/v1/audio/transcriptions',
    TranscriptionUrl('http://localhost:8000/v1/audio/transcriptions'));
  Assert.IsTrue(ParseTranscriptionResponse('{"text":" Привет, мир. ","x_groq":{}}', Text, Error));
  Assert.AreEqual('Привет, мир.', Text);
  Assert.IsFalse(ParseTranscriptionResponse('{"error":{"message":"Invalid API Key"}}', Text, Error));
  Assert.AreEqual('Invalid API Key', Error);
  Assert.IsFalse(ParseTranscriptionResponse('<html>', Text, Error));
  Assert.AreEqual('bad_response', Error);
end;

procedure TSpeechTests.SettingsAndMigration;
var
  S, Loaded: TLSSettings;
  G: TLSActionGestures;
  FileName, Content: string;
  Diagnostics: Boolean;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(Ord(lgScrollLock), Ord(S.GestureForAction(laDictate)));
  Assert.AreEqual(DEFAULT_SPEECH_MODEL, S.DictationModel);
  Assert.AreEqual('dictate', ActionKeys[laDictate]);
  Assert.AreEqual('Scroll Lock', GestureName(lgScrollLock));
  // Settings of 2.4 get Scroll Lock, unless it is taken.
  G := S.ActionGestures;
  G[laDictate] := lgNone;
  MigrateActionGestures(G, 6);
  Assert.AreEqual(Ord(lgScrollLock), Ord(G[laDictate]));
  G := S.ActionGestures;
  G[laDictate] := lgNone;
  G[laExplain] := lgScrollLock;
  MigrateActionGestures(G, 6);
  Assert.AreEqual(Ord(lgNone), Ord(G[laDictate]));
  // The cloud key is saved but never exported; an unknown model falls back.
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-speech.ini');
  try
    S.DictationModel := 'ru-compact';
    S.DictationCloudKey := 'gsk_secret';
    S.DictationCloudModel := 'whisper-1';
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Content := TFile.ReadAllText(FileName);
    Assert.IsFalse(Content.Contains('secret'));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual('ru-compact', Loaded.DictationModel);
    Assert.AreEqual('whisper-1', Loaded.DictationCloudModel);
    Assert.AreEqual('', Loaded.DictationCloudKey);
    TFile.WriteAllText(FileName, Content.Replace('ru-compact', 'removed-model'));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual(DEFAULT_SPEECH_MODEL, Loaded.DictationModel);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TSpeechTests.ScrollLockGesture;
var
  D: TGestureDetector;
  T: Cardinal;
begin
  D := TGestureDetector.Create;
  try
    T := 1000;
    Assert.AreEqual(Ord(lgScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, T)));
    // Auto-repeat while held is not another press.
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_SCROLL, False, T + 500)));
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_SCROLL, True, T + 600)));
    // Ctrl + Scroll Lock (Break on some keyboards) is not the gesture.
    D.KeyEvent(VK_LCONTROL, False, T + 1000);
    Assert.AreEqual(Ord(lgNone), Ord(D.KeyEvent(VK_SCROLL, False, T + 1050)));
    D.KeyEvent(VK_SCROLL, True, T + 1100);
    D.KeyEvent(VK_LCONTROL, True, T + 1150);
    Assert.AreEqual(Ord(lgScrollLock), Ord(D.KeyEvent(VK_SCROLL, False, T + 2000)));
  finally
    D.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSpeechTests);

end.
