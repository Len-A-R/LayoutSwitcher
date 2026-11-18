unit uConversionChain;

// Decides which part of the tracked phrase an action applies to.
//
// The UI thread keeps every character typed since the last caret jump
// (Enter, arrows, mouse click, focus change), spaces included.  Repeating
// the same action without typing anything in between widens its scope:
//
//   1st press  - the last word ("ghbdtn vbh" -> "ghbdtn мир")
//   2nd press  - the rest of the phrase    ("ghbdtn мир" -> "привет мир")
//   3rd press  - layout conversion only: everything back to the original
//
// The separate Undo action restores the text as it was before the last step
// of any action, as long as nothing has been typed since.
//
// A phrase of a single word goes straight from step 1 to step 3, which keeps
// the classic "press again to undo" behaviour.  Pure logic, unit-tested.

interface

uses
  Winapi.Windows,
  uSettings;

type
  TBufferMode = (bmNone, bmWord, bmPhrase, bmRevert, bmUndo);

  TBufferPlan = record
    Mode: TBufferMode;
    Text: string;          // Tracked text; the caret is at its end.
    RegionStart: Integer;  // 1-based start of the part to transform.
    RegionLength: Integer;
    ForcedSource: HKL;     // 0 = let the converter choose the layouts.
    ForcedTarget: HKL;
    // bmUndo: text that replaces Region (no transformation is applied).
    Replacement: string;
    function Region: string;
    function Head: string;
    function Tail: string;
    // Characters to erase with Backspace: from the region start to the caret.
    function DeleteCount: Integer;
  end;

  TConversionChain = class
  private
    FActive: Boolean;
    FAction: TLSAction;
    FMode: TBufferMode;
    FBuffer: string;
    FSource: HKL;
    FTarget: HKL;
    FUndoAvailable: Boolean;
    FPrevious: string;      // Text before the last step.
    FUndoLayout: HKL;       // Layout before the last conversion, 0 if none.
    function PlanUndo(const Buffer: string): TBufferPlan;
  public
    procedure Reset;
    function Plan(Action: TLSAction; const Buffer: string): TBufferPlan;
    // Call after the plan was applied successfully.  NewBuffer is the text
    // now in front of the caret; Source/Target are the layouts used.
    procedure Completed(const APlan: TBufferPlan; Action: TLSAction;
      const NewBuffer: string; Source, Target: HKL);
    // A selection (or the text before the caret) was replaced by NewBuffer
    // and the caret is now right after it: the next layout conversion
    // restores the whole text, as with a converted phrase.
    procedure CompletedWhole(Action: TLSAction; const NewBuffer,
      Original: string; Source, Target: HKL);
    property UndoAvailable: Boolean read FUndoAvailable;
  end;

// Last run of non-space characters, ignoring trailing spaces.
function FindLastWord(const Text: string; out WordStart,
  WordLength: Integer): Boolean;

implementation

function IsSpace(Ch: Char): Boolean;
begin
  Result := (Ch = ' ') or (Ch = #9) or (Ch = #$00A0);
end;

function FindLastWord(const Text: string; out WordStart,
  WordLength: Integer): Boolean;
var
  WordEnd: Integer;
begin
  WordStart := 0;
  WordLength := 0;
  WordEnd := Length(Text);
  while (WordEnd > 0) and IsSpace(Text[WordEnd]) do
    Dec(WordEnd);
  if WordEnd = 0 then
    Exit(False);
  WordStart := WordEnd;
  while (WordStart > 1) and not IsSpace(Text[WordStart - 1]) do
    Dec(WordStart);
  WordLength := WordEnd - WordStart + 1;
  Result := True;
end;

function HasNonSpace(const Text: string): Boolean;
var
  Ch: Char;
begin
  for Ch in Text do
    if not IsSpace(Ch) then
      Exit(True);
  Result := False;
end;

{ TBufferPlan }

function TBufferPlan.Region: string;
begin
  Result := Copy(Text, RegionStart, RegionLength);
end;

function TBufferPlan.Head: string;
begin
  Result := Copy(Text, 1, RegionStart - 1);
end;

function TBufferPlan.Tail: string;
begin
  Result := Copy(Text, RegionStart + RegionLength, MaxInt);
end;

function TBufferPlan.DeleteCount: Integer;
begin
  Result := Length(Text) - RegionStart + 1;
end;

{ TConversionChain }

procedure TConversionChain.Reset;
begin
  FActive := False;
  FAction := laNone;
  FMode := bmNone;
  FBuffer := '';
  FSource := 0;
  FTarget := 0;
  FUndoAvailable := False;
  FPrevious := '';
  FUndoLayout := 0;
end;

function TConversionChain.PlanUndo(const Buffer: string): TBufferPlan;
var
  Common, MaxCommon: Integer;
begin
  Result.Mode := bmNone;
  Result.Text := Buffer;
  Result.RegionStart := 1;
  Result.RegionLength := 0;
  Result.ForcedSource := 0;
  Result.ForcedTarget := 0;
  Result.Replacement := '';
  if not FUndoAvailable or (Buffer <> FBuffer) or (Buffer = FPrevious) then
    Exit;
  // Keep the unchanged beginning to send as few Backspaces as possible.
  MaxCommon := Length(Buffer);
  if Length(FPrevious) < MaxCommon then
    MaxCommon := Length(FPrevious);
  Common := 0;
  while (Common < MaxCommon) and (Buffer[Common + 1] = FPrevious[Common + 1]) do
    Inc(Common);
  Result.Mode := bmUndo;
  Result.RegionStart := Common + 1;
  Result.RegionLength := Length(Buffer) - Common;
  Result.Replacement := Copy(FPrevious, Common + 1, MaxInt);
  // Only used to switch the keyboard layout back.
  Result.ForcedTarget := FUndoLayout;
end;

function TConversionChain.Plan(Action: TLSAction;
  const Buffer: string): TBufferPlan;
var
  WordStart, WordLength: Integer;
  HasWord: Boolean;
begin
  Result.Mode := bmNone;
  Result.Text := Buffer;
  Result.RegionStart := 1;
  Result.RegionLength := 0;
  Result.ForcedSource := 0;
  Result.ForcedTarget := 0;
  Result.Replacement := '';
  if Action = laUndo then
    Exit(PlanUndo(Buffer));
  if (Action = laNone) or not HasNonSpace(Buffer) then
    Exit;

  HasWord := FindLastWord(Buffer, WordStart, WordLength);

  // Continue the chain only if nothing was typed since the last step.
  if FActive and (Action = FAction) and (Buffer = FBuffer) then
    case FMode of
      bmWord:
        if HasWord and HasNonSpace(Copy(Buffer, 1, WordStart - 1)) then
        begin
          Result.Mode := bmPhrase;
          Result.RegionStart := 1;
          Result.RegionLength := WordStart - 1;
          if Action = laConvert then
          begin
            // Same direction as the word that was just converted.
            Result.ForcedSource := FSource;
            Result.ForcedTarget := FTarget;
          end;
          Exit;
        end
        else if Action = laConvert then
        begin
          Result.Mode := bmRevert;
          Result.RegionStart := 1;
          Result.RegionLength := Length(Buffer);
          Result.ForcedSource := FTarget;
          Result.ForcedTarget := FSource;
          Exit;
        end;
      bmPhrase:
        if Action = laConvert then
        begin
          Result.Mode := bmRevert;
          Result.RegionStart := 1;
          Result.RegionLength := Length(Buffer);
          Result.ForcedSource := FTarget;
          Result.ForcedTarget := FSource;
          Exit;
        end;
    end;

  if not HasWord then
    Exit;
  Result.Mode := bmWord;
  Result.RegionStart := WordStart;
  Result.RegionLength := WordLength;
end;

procedure TConversionChain.Completed(const APlan: TBufferPlan;
  Action: TLSAction; const NewBuffer: string; Source, Target: HKL);
begin
  if (APlan.Mode = bmNone) or (APlan.Mode = bmUndo) then
  begin
    Reset; // No redo.
    Exit;
  end;
  FUndoAvailable := True;
  FPrevious := APlan.Text;
  if Action = laConvert then
    FUndoLayout := Source
  else
    FUndoLayout := 0;
  FActive := True;
  FAction := Action;
  FMode := APlan.Mode;
  FBuffer := NewBuffer;
  if APlan.Mode = bmWord then
  begin
    FSource := Source;
    FTarget := Target;
  end;
end;

procedure TConversionChain.CompletedWhole(Action: TLSAction; const NewBuffer,
  Original: string; Source, Target: HKL);
begin
  FActive := NewBuffer <> '';
  FUndoAvailable := FActive and (Original <> '');
  FPrevious := Original;
  if Action = laConvert then
    FUndoLayout := Source
  else
    FUndoLayout := 0;
  FAction := Action;
  FMode := bmPhrase;
  FBuffer := NewBuffer;
  FSource := Source;
  FTarget := Target;
end;

end.
