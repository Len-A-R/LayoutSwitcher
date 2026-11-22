unit uAudioRecorder;

// Microphone recording for dictation: 16 kHz, mono, 16 bit through the
// waveIn API (default recording device).  A worker thread collects the
// buffers; Stop returns the samples as floats in -1..1.

interface

uses
  Winapi.Windows, Winapi.MMSystem,
  System.SysUtils, System.Classes, System.SyncObjs;

const
  RECORD_SAMPLE_RATE = 16000;

type
  TAudioRecorder = class
  private
    FWaveIn: HWAVEIN;
    FEvent: TEvent;
    FThread: TThread;
    FHeaders: array[0..7] of TWaveHdr;
    FBuffers: array[0..7] of TBytes;
    FLock: TCriticalSection;
    FSamples: TArray<SmallInt>;
    FCount: Integer;
    FLevel: Integer;         // 0..100, peak of the last buffer
    FStopping: Boolean;
    FMaxSamples: Integer;
    procedure Collect;
    procedure Append(const Header: TWaveHdr);
    function GetLevel: Integer;
    function GetSeconds: Double;
  public
    constructor Create;
    destructor Destroy; override;
    // False with ErrorText when no microphone can be opened.
    function Start(MaxSeconds: Integer; out ErrorText: string): Boolean;
    // Ends the recording and returns what was recorded.
    function Stop: TArray<Single>;
    function Recording: Boolean;
    property Level: Integer read GetLevel;
    property Seconds: Double read GetSeconds;
  end;

function SamplesToFloat(const Samples: TArray<SmallInt>; Count: Integer): TArray<Single>;
// The peak of the samples, 0..100.
function PeakLevel(Data: PSmallInt; Count: Integer): Integer;
// RIFF/WAVE file (16 bit mono) of float samples, for cloud services.
function EncodeWav(const Samples: TArray<Single>; SampleRate: Integer): TBytes;

implementation

uses
  uLocale;

const
  BUFFER_MS = 100;
  BUFFER_BYTES = RECORD_SAMPLE_RATE * 2 * BUFFER_MS div 1000;

type
  TCollectThread = class(TThread)
  private
    FOwner: TAudioRecorder;
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TAudioRecorder);
  end;

function SamplesToFloat(const Samples: TArray<SmallInt>; Count: Integer): TArray<Single>;
var
  I: Integer;
begin
  if Count > Length(Samples) then
    Count := Length(Samples);
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    Result[I] := Samples[I] / 32768;
end;

function PeakLevel(Data: PSmallInt; Count: Integer): Integer;
var
  I, Peak, Value: Integer;
begin
  Peak := 0;
  for I := 0 to Count - 1 do
  begin
    Value := Abs(Integer(Data^));
    if Value > Peak then
      Peak := Value;
    Inc(Data);
  end;
  Result := Peak * 100 div 32768;
end;

function EncodeWav(const Samples: TArray<Single>; SampleRate: Integer): TBytes;
var
  Stream: TBytesStream;
  DataSize, Value32: Cardinal;
  Value16: Word;
  Sample: Single;
  PCM: SmallInt;

  procedure Put(const Tag: AnsiString);
  begin
    Stream.WriteBuffer(Tag[1], 4);
  end;

begin
  Stream := TBytesStream.Create;
  try
    DataSize := Length(Samples) * 2;
    Put('RIFF');
    Value32 := 36 + DataSize; Stream.WriteBuffer(Value32, 4);
    Put('WAVE');
    Put('fmt ');
    Value32 := 16; Stream.WriteBuffer(Value32, 4);
    Value16 := 1; Stream.WriteBuffer(Value16, 2);            // PCM
    Value16 := 1; Stream.WriteBuffer(Value16, 2);            // mono
    Value32 := SampleRate; Stream.WriteBuffer(Value32, 4);
    Value32 := SampleRate * 2; Stream.WriteBuffer(Value32, 4);
    Value16 := 2; Stream.WriteBuffer(Value16, 2);            // block align
    Value16 := 16; Stream.WriteBuffer(Value16, 2);
    Put('data');
    Stream.WriteBuffer(DataSize, 4);
    for Sample in Samples do
    begin
      if Sample >= 1 then
        PCM := 32767
      else if Sample <= -1 then
        PCM := -32768
      else
        PCM := Round(Sample * 32767);
      Stream.WriteBuffer(PCM, 2);
    end;
    Result := Copy(Stream.Bytes, 0, Stream.Size);
  finally
    Stream.Free;
  end;
end;

{ TCollectThread }

constructor TCollectThread.Create(Owner: TAudioRecorder);
begin
  FOwner := Owner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TCollectThread.Execute;
begin
  NameThreadForDebugging('LayoutSwitcher.AudioRecorder');
  while not Terminated do
  begin
    FOwner.FEvent.WaitFor(200);
    FOwner.Collect;
  end;
  FOwner.Collect;
end;

{ TAudioRecorder }

constructor TAudioRecorder.Create;
begin
  inherited;
  FEvent := TEvent.Create(nil, False, False, '');
  FLock := TCriticalSection.Create;
end;

destructor TAudioRecorder.Destroy;
begin
  if Recording then
    Stop;
  FLock.Free;
  FEvent.Free;
  inherited;
end;

function TAudioRecorder.Recording: Boolean;
begin
  Result := FWaveIn <> 0;
end;

function TAudioRecorder.GetLevel: Integer;
begin
  Result := AtomicCmpExchange(FLevel, 0, 0);
end;

function TAudioRecorder.GetSeconds: Double;
begin
  FLock.Enter;
  try
    Result := FCount / RECORD_SAMPLE_RATE;
  finally
    FLock.Leave;
  end;
end;

procedure TAudioRecorder.Append(const Header: TWaveHdr);
var
  Count: Integer;
begin
  Count := Header.dwBytesRecorded div 2;
  if Count = 0 then
    Exit;
  AtomicExchange(FLevel, PeakLevel(PSmallInt(Header.lpData), Count));
  FLock.Enter;
  try
    if FCount + Count > FMaxSamples then
      Count := FMaxSamples - FCount;
    if Count <= 0 then
      Exit;
    if FCount + Count > Length(FSamples) then
      SetLength(FSamples, (FCount + Count) * 2);
    Move(Header.lpData^, FSamples[FCount], Count * 2);
    Inc(FCount, Count);
  finally
    FLock.Leave;
  end;
end;

procedure TAudioRecorder.Collect;
var
  I: Integer;
begin
  // Buffers come back in order; a finished one is saved and queued again.
  for I := Low(FHeaders) to High(FHeaders) do
    if (FHeaders[I].dwFlags and WHDR_DONE) <> 0 then
    begin
      Append(FHeaders[I]);
      FHeaders[I].dwFlags := FHeaders[I].dwFlags and not WHDR_DONE;
      FHeaders[I].dwBytesRecorded := 0;
      if not FStopping then
        waveInAddBuffer(FWaveIn, @FHeaders[I], SizeOf(TWaveHdr));
    end;
end;

function TAudioRecorder.Start(MaxSeconds: Integer; out ErrorText: string): Boolean;
var
  Format: TWaveFormatEx;
  Code: MMRESULT;
  I: Integer;
begin
  Result := False;
  ErrorText := '';
  if Recording then
    Exit(True);
  if waveInGetNumDevs = 0 then
  begin
    ErrorText := T('Микрофон не найден.', 'No microphone found.');
    Exit;
  end;
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM;
  Format.nChannels := 1;
  Format.nSamplesPerSec := RECORD_SAMPLE_RATE;
  Format.wBitsPerSample := 16;
  Format.nBlockAlign := 2;
  Format.nAvgBytesPerSec := RECORD_SAMPLE_RATE * 2;
  FEvent.ResetEvent;
  Code := waveInOpen(@FWaveIn, WAVE_MAPPER, @Format, FEvent.Handle, 0, CALLBACK_EVENT);
  if Code <> MMSYSERR_NOERROR then
  begin
    FWaveIn := 0;
    if Code = MMSYSERR_ALLOCATED then
      ErrorText := T('Микрофон занят другой программой.', 'The microphone is used by another program.')
    else
      ErrorText := System.SysUtils.Format(T(
        'Не удалось открыть микрофон (код %d). Проверьте, что доступ к микрофону ' +
        'разрешён: Параметры → Конфиденциальность → Микрофон.',
        'Could not open the microphone (code %d). Check that microphone access is ' +
        'allowed: Settings → Privacy → Microphone.'), [Code]);
    Exit;
  end;
  FStopping := False;
  FMaxSamples := MaxSeconds * RECORD_SAMPLE_RATE;
  FLock.Enter;
  try
    FCount := 0;
    SetLength(FSamples, RECORD_SAMPLE_RATE * 10);
  finally
    FLock.Leave;
  end;
  AtomicExchange(FLevel, 0);
  for I := Low(FHeaders) to High(FHeaders) do
  begin
    SetLength(FBuffers[I], BUFFER_BYTES);
    FillChar(FHeaders[I], SizeOf(TWaveHdr), 0);
    FHeaders[I].lpData := PAnsiChar(@FBuffers[I][0]);
    FHeaders[I].dwBufferLength := BUFFER_BYTES;
    waveInPrepareHeader(FWaveIn, @FHeaders[I], SizeOf(TWaveHdr));
    waveInAddBuffer(FWaveIn, @FHeaders[I], SizeOf(TWaveHdr));
  end;
  FThread := TCollectThread.Create(Self);
  if waveInStart(FWaveIn) <> MMSYSERR_NOERROR then
  begin
    Stop;
    ErrorText := T('Не удалось начать запись с микрофона.', 'Could not start recording.');
    Exit;
  end;
  Result := True;
end;

function TAudioRecorder.Stop: TArray<Single>;
var
  I: Integer;
begin
  Result := nil;
  if not Recording then
    Exit;
  FStopping := True;
  waveInStop(FWaveIn);
  // waveInReset returns the partly filled buffer as done.
  waveInReset(FWaveIn);
  FThread.Terminate;
  FEvent.SetEvent;
  FThread.WaitFor;
  FreeAndNil(FThread);
  for I := Low(FHeaders) to High(FHeaders) do
    waveInUnprepareHeader(FWaveIn, @FHeaders[I], SizeOf(TWaveHdr));
  waveInClose(FWaveIn);
  FWaveIn := 0;
  FLock.Enter;
  try
    Result := SamplesToFloat(FSamples, FCount);
    FSamples := nil;
    FCount := 0;
  finally
    FLock.Leave;
  end;
  AtomicExchange(FLevel, 0);
end;

end.
