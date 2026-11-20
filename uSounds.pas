unit uSounds;

// Short, soft feedback sounds played after a correction.  They are
// synthesised (16-bit mono PCM) instead of using the Windows sound scheme:
// MessageBeep sounds like an error on Windows 10/11, and a program sound
// must be the same and quiet everywhere.  A WAV file of the user's choice
// can be used instead.

interface

uses
  System.SysUtils;

const
  SOUND_CLICK = 0;
  SOUND_KNOCK = 1;
  SOUND_DROP = 2;
  SOUND_BELL = 3;
  SOUND_BUBBLE = 4;
  SOUND_FILE = 5;   // SoundFile setting
  SOUND_LAST_BUILTIN = SOUND_BUBBLE;
  SOUND_SAMPLE_RATE = 22050;

// A complete WAV file (RIFF, PCM 16-bit mono) for a built-in sound.
function BuildFeedbackSound(Kind: Integer): TBytes;

// Plays asynchronously; returns at once.  FileName is used for SOUND_FILE.
procedure PlayFeedbackSound(Kind: Integer; const FileName: string);

implementation

uses
  Winapi.Windows, Winapi.MMSystem, System.Math;

var
  // PlaySound(SND_MEMORY or SND_ASYNC) reads the buffer while it plays:
  // the sounds stay allocated until the program ends.
  GSounds: array[SOUND_CLICK..SOUND_LAST_BUILTIN] of TBytes;

function WavFromSamples(const Samples: TArray<Single>): TBytes;
var
  DataSize, I: Integer;
  Value: SmallInt;

  procedure PutU32(Offset: Integer; V: Cardinal);
  begin
    Move(V, Result[Offset], 4);
  end;

  procedure PutU16(Offset: Integer; V: Word);
  begin
    Move(V, Result[Offset], 2);
  end;

begin
  DataSize := Length(Samples) * 2;
  SetLength(Result, 44 + DataSize);
  Move(AnsiString('RIFF')[1], Result[0], 4);
  PutU32(4, 36 + DataSize);
  Move(AnsiString('WAVEfmt ')[1], Result[8], 8);
  PutU32(16, 16);                        // fmt chunk size
  PutU16(20, 1);                         // PCM
  PutU16(22, 1);                         // mono
  PutU32(24, SOUND_SAMPLE_RATE);
  PutU32(28, SOUND_SAMPLE_RATE * 2);     // bytes per second
  PutU16(32, 2);                         // block align
  PutU16(34, 16);                        // bits per sample
  Move(AnsiString('data')[1], Result[36], 4);
  PutU32(40, DataSize);
  for I := 0 to High(Samples) do
  begin
    Value := SmallInt(Round(EnsureRange(Samples[I], -1, 1) * 32767));
    Move(Value, Result[44 + I * 2], 2);
  end;
end;

// A tone whose frequency glides from F1 to F2, with an exponential decay
// (time constant Tau seconds) and a short attack against clicks.
procedure AddTone(var Samples: TArray<Single>; StartSec, LengthSec, F1, F2, Tau,
  Amplitude: Double; Attack: Double = 0.002);
var
  Start, Count, I: Integer;
  T, Phase, Freq, Envelope: Double;
begin
  Start := Round(StartSec * SOUND_SAMPLE_RATE);
  Count := Round(LengthSec * SOUND_SAMPLE_RATE);
  if Length(Samples) < Start + Count then
    SetLength(Samples, Start + Count);
  Phase := 0;
  for I := 0 to Count - 1 do
  begin
    T := I / SOUND_SAMPLE_RATE;
    Freq := F1 + (F2 - F1) * (I / Count);
    Phase := Phase + 2 * Pi * Freq / SOUND_SAMPLE_RATE;
    Envelope := Exp(-T / Tau);
    if (Attack > 0) and (T < Attack) then
      Envelope := Envelope * (T / Attack);
    // Fade out the last 2 ms so that the sound ends at zero.
    if Count - I < SOUND_SAMPLE_RATE div 500 then
      Envelope := Envelope * (Count - I) / (SOUND_SAMPLE_RATE div 500);
    Samples[Start + I] := Samples[Start + I] + Amplitude * Envelope * Sin(Phase);
  end;
end;

function BuildFeedbackSound(Kind: Integer): TBytes;
var
  Samples: TArray<Single>;
begin
  Samples := nil;
  case Kind of
    SOUND_CLICK:
      begin
        // A short dry tick.
        AddTone(Samples, 0, 0.018, 3200, 2600, 0.003, 0.30, 0.0005);
        AddTone(Samples, 0, 0.018, 1600, 1400, 0.004, 0.15, 0.0005);
      end;
    SOUND_KNOCK:
      // Wooden "tok": a low tone falling in pitch.
      AddTone(Samples, 0, 0.070, 620, 360, 0.016, 0.45);
    SOUND_DROP:
      // A water drop: a short rising glide.
      AddTone(Samples, 0, 0.090, 900, 1900, 0.025, 0.35);
    SOUND_BELL:
      begin
        // A small bell: fundamental with an octave above.
        AddTone(Samples, 0, 0.300, 1318.5, 1318.5, 0.080, 0.28, 0.003);
        AddTone(Samples, 0, 0.300, 2637, 2637, 0.045, 0.10, 0.003);
      end;
    SOUND_BUBBLE:
      begin
        // Two quick rising blips.
        AddTone(Samples, 0, 0.045, 700, 1000, 0.020, 0.32);
        AddTone(Samples, 0.055, 0.050, 1000, 1500, 0.022, 0.32);
      end;
  else
    Exit(nil);
  end;
  Result := WavFromSamples(Samples);
end;

procedure PlayFeedbackSound(Kind: Integer; const FileName: string);
begin
  if Kind = SOUND_FILE then
  begin
    if (FileName <> '') and FileExists(FileName) then
      PlaySound(PChar(FileName), 0, SND_FILENAME or SND_ASYNC or SND_NODEFAULT)
    else
      Kind := SOUND_CLICK;  // the file is gone: the default sound
  end;
  if (Kind < Low(GSounds)) or (Kind > High(GSounds)) then
    Exit;
  if GSounds[Kind] = nil then
    GSounds[Kind] := BuildFeedbackSound(Kind);
  PlaySound(PChar(@GSounds[Kind][0]), 0, SND_MEMORY or SND_ASYNC or SND_NODEFAULT);
end;

initialization

finalization
  // Stop a sound that may still read one of the buffers.
  PlaySound(nil, 0, 0);

end.
