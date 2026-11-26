unit uWindowWatch;

// Reading aloud what appears in a window: an answer of ChatGPT or Claude, a
// log, a terminal.  The text of the window comes from UI Automation (the
// document of a browser or of an Electron application; the text of a
// window with TextPattern otherwise) once in WATCH_INTERVAL_MS.  What was
// added between two snapshots (anywhere in the text: in a chat the answer
// grows above the input box) is cut into sentences; finished sentences are
// read at once, the rest when the text has not changed for STABLE_MS.
// A sentence is read as many times as it occurs in the text: a chat
// re-renders its last answer as it grows, and that must not read it again,
// but the same sentence in a new answer is read.
//
// A minimized Chromium window does not update its accessibility tree: the
// owner restores it behind the other windows (OnMinimized).

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections;

type
  // Snapshots in, sentences to read out.  Pure logic, covered by tests.
  TTextChangeTracker = class
  private
    FPrev: string;
    FStable: string;
    FHasBaseline: Boolean;
    FLastChange: Cardinal;
    // How many times each sentence (its key) was read or was there.
    FSpoken: TDictionary<string, Integer>;
    procedure Remember(const Text: string);
    function Counts(const Text: string): TDictionary<string, Integer>;
    function Collect(const Old, New: string; OnlyFinished: Boolean): TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    // The next snapshot of the text at the time Now (ms); the first one is
    // the baseline and nothing of it is read.
    function Update(const Text: string; Now: Cardinal): TArray<string>;
    procedure Reset;
  end;

  TWatchSentencesEvent = procedure(Sender: TObject; const Sentences: TArray<string>) of object;
  TWatchStoppedEvent = procedure(Sender: TObject; const Reason: string) of object;

  TWindowWatcher = class
  private
    FThread: TThread;
    FTarget: HWND;
    FTitle: string;
    FOnSentences: TWatchSentencesEvent;
    FOnStopped: TWatchStoppedEvent;
    FOnMinimized: TNotifyEvent;
  public
    destructor Destroy; override;
    procedure Start(Target: HWND);
    procedure Stop;
    function Watching: Boolean;
    property Target: HWND read FTarget;
    // The window title when the watch started.
    property Title: string read FTitle;
    property OnSentences: TWatchSentencesEvent read FOnSentences write FOnSentences;
    // The window was closed or gives no text; the watch has ended.
    property OnStopped: TWatchStoppedEvent read FOnStopped write FOnStopped;
    property OnMinimized: TNotifyEvent read FOnMinimized write FOnMinimized;
  end;

const
  WATCH_INTERVAL_MS = 700;
  STABLE_MS = 1500;
  // A change this large (a new page, another chat) is not read.
  PAGE_CHANGE_CHARS = 3000;

// Sentences of a text: a piece ends after ".", "!", "?" or "…" followed by a
// space, or at a line break.  Finished: it ends with such a mark.
procedure SplitWatchSentences(const Text: string; out Pieces: TArray<string>;
  out Finished: TArray<Boolean>);
// The key under which a sentence counts as read: trimmed, single spaces,
// lower case.
function WatchSentenceKey(const Sentence: string): string;
// Code and other symbol soup is not read.
function IsReadableSentence(const Sentence: string): Boolean;

implementation

uses
  Winapi.ActiveX, System.Variants, System.Character, uLocale;

function IsEndMark(Ch: Char): Boolean;
begin
  Result := (Ch = '.') or (Ch = '!') or (Ch = '?') or (Ch = '…');
end;

function IsClosing(Ch: Char): Boolean;
begin
  Result := (Ch = '"') or (Ch = ')') or (Ch = '»') or (Ch = '''') or (Ch = '”');
end;

procedure SplitWatchSentences(const Text: string; out Pieces: TArray<string>;
  out Finished: TArray<Boolean>);
var
  I, Start, Last: Integer;

  procedure Add(StopAt: Integer);
  var
    Piece: string;
    J: Integer;
  begin
    Piece := Trim(Copy(Text, Start, StopAt - Start + 1));
    Start := StopAt + 1;
    if Piece = '' then
      Exit;
    J := Length(Piece);
    while (J > 1) and IsClosing(Piece[J]) do
      Dec(J);
    Pieces := Pieces + [Piece];
    Finished := Finished + [IsEndMark(Piece[J])];
  end;

begin
  Pieces := nil;
  Finished := nil;
  Start := 1;
  I := 1;
  while I <= Length(Text) do
  begin
    if (Text[I] = #10) or (Text[I] = #13) then
      Add(I - 1)
    else if IsEndMark(Text[I]) then
    begin
      Last := I;
      while (Last < Length(Text)) and (IsEndMark(Text[Last + 1]) or IsClosing(Text[Last + 1])) do
        Inc(Last);
      if (Last = Length(Text)) or Text[Last + 1].IsWhiteSpace then
      begin
        Add(Last);
        I := Last;
      end;
    end;
    Inc(I);
  end;
  Add(Length(Text));
end;

function WatchSentenceKey(const Sentence: string): string;
var
  Ch: Char;
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    for Ch in AnsiLowerCase(Trim(Sentence)) do
      if Ch.IsWhiteSpace then
      begin
        if (B.Length > 0) and (B.Chars[B.Length - 1] <> ' ') then
          B.Append(' ');
      end
      else
        B.Append(Ch);
    Result := Trim(B.ToString);
  finally
    B.Free;
  end;
end;

function IsReadableSentence(const Sentence: string): Boolean;
var
  Ch: Char;
  Letters, Others: Integer;
begin
  Letters := 0;
  Others := 0;
  for Ch in Sentence do
    if Ch.IsLetter then
      Inc(Letters)
    else if not Ch.IsWhiteSpace and not Ch.IsDigit and not IsEndMark(Ch) and (Ch <> ',') then
      Inc(Others);
  // "OK" is fine, "{ x = y; }" is not.
  Result := (Letters >= 2) and ((Length(Sentence) < 16) or (Letters >= 2 * Others));
end;

{ TTextChangeTracker }

constructor TTextChangeTracker.Create;
begin
  inherited;
  FSpoken := TDictionary<string, Integer>.Create;
end;

destructor TTextChangeTracker.Destroy;
begin
  FSpoken.Free;
  inherited;
end;

procedure TTextChangeTracker.Reset;
begin
  FHasBaseline := False;
  FPrev := '';
  FStable := '';
  FSpoken.Clear;
end;

function TTextChangeTracker.Counts(const Text: string): TDictionary<string, Integer>;
var
  Pieces: TArray<string>;
  Finished: TArray<Boolean>;
  Piece, Key: string;
  Count: Integer;
begin
  Result := TDictionary<string, Integer>.Create;
  SplitWatchSentences(Text, Pieces, Finished);
  for Piece in Pieces do
  begin
    Key := WatchSentenceKey(Piece);
    if not Result.TryGetValue(Key, Count) then
      Count := 0;
    Result.AddOrSetValue(Key, Count + 1);
  end;
end;

// Everything in Text counts as read (at least as often as it occurs there).
procedure TTextChangeTracker.Remember(const Text: string);
var
  Present: TDictionary<string, Integer>;
  Pair: TPair<string, Integer>;
  Count: Integer;
begin
  Present := Counts(Text);
  try
    for Pair in Present do
      if not FSpoken.TryGetValue(Pair.Key, Count) or (Count < Pair.Value) then
        FSpoken.AddOrSetValue(Pair.Key, Pair.Value);
  finally
    Present.Free;
  end;
end;

function TTextChangeTracker.Collect(const Old, New: string; OnlyFinished: Boolean): TArray<string>;
var
  Prefix, Suffix, MaxCommon, First, Last, I: Integer;
  Pieces: TArray<string>;
  Finished: TArray<Boolean>;
  Key: string;
  Present: TDictionary<string, Integer>;
  Spoken, InText: Integer;
begin
  Result := nil;
  if Old = New then
    Exit;
  // The changed part of New: between the common start and the common end.
  MaxCommon := Length(Old);
  if Length(New) < MaxCommon then
    MaxCommon := Length(New);
  Prefix := 0;
  while (Prefix < MaxCommon) and (Old[Prefix + 1] = New[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < MaxCommon - Prefix) and
        (Old[Length(Old) - Suffix] = New[Length(New) - Suffix]) do
    Inc(Suffix);
  First := Prefix + 1;
  Last := Length(New) - Suffix;
  // Another page or chat: what is there now counts as read.
  if (Last - First + 1 > PAGE_CHANGE_CHARS) and (Last - First + 1 > Length(New) * 4 div 5) then
  begin
    Remember(New);
    Exit;
  end;
  if Last < First then
    // Only removed text.
    Exit;
  // Whole sentences around the change.
  while (First > 1) and not ((New[First - 1] = #10) or
    (IsEndMark(New[First - 1]) and (First <= Length(New)) and New[First].IsWhiteSpace)) do
    Dec(First);
  while (Last < Length(New)) and (New[Last] <> #10) and
    not (IsEndMark(New[Last]) and New[Last + 1].IsWhiteSpace) do
    Inc(Last);
  SplitWatchSentences(Copy(New, First, Last - First + 1), Pieces, Finished);
  Present := nil;
  try
    for I := 0 to High(Pieces) do
    begin
      if OnlyFinished and not Finished[I] then
        Continue;
      Key := WatchSentenceKey(Pieces[I]);
      if Key = '' then
        Continue;
      if not FSpoken.TryGetValue(Key, Spoken) then
        Spoken := 0;
      // Read before: new only if the text now has it more often.
      if Spoken > 0 then
      begin
        if Present = nil then
          Present := Counts(New);
        if not Present.TryGetValue(Key, InText) or (InText <= Spoken) then
          Continue;
      end;
      FSpoken.AddOrSetValue(Key, Spoken + 1);
      if IsReadableSentence(Pieces[I]) then
        Result := Result + [Pieces[I]];
    end;
  finally
    Present.Free;
  end;
end;

function TTextChangeTracker.Update(const Text: string; Now: Cardinal): TArray<string>;
begin
  Result := nil;
  if not FHasBaseline then
  begin
    FHasBaseline := True;
    FPrev := Text;
    FStable := Text;
    FLastChange := Now;
    Remember(Text);
    Exit;
  end;
  if Text <> FPrev then
  begin
    // While the text grows: only finished sentences.
    Result := Collect(FPrev, Text, True);
    FPrev := Text;
    FLastChange := Now;
    Exit;
  end;
  // Quiet for a while: the rest of what changed since the last quiet moment
  // (the last sentence, headings and list items without a final mark).
  if (FPrev <> FStable) and (Now - FLastChange >= STABLE_MS) then
  begin
    Result := Collect(FStable, FPrev, False);
    FStable := FPrev;
  end;
end;

{ UI Automation }

const
  CLASS_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  UIA_TEXT_PATTERN_ID = 10014;
  UIA_CONTROL_TYPE_PROPERTY_ID = 30003;
  UIA_DOCUMENT_CONTROL_TYPE_ID = 50030;
  TREE_SCOPE_DESCENDANTS = 4;
  MAX_WATCH_TEXT = 2000000;

type
  IWatchElement = interface;
  IWatchRange = interface;

  // Only the vtable entries used here are named (UIAutomationClient.h order).
  IWatchAutomation = interface(IUnknown)
  ['{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function ElementFromHandle(Wnd: HWND; out Element: IWatchElement): HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
    function Reserved07: HRESULT; stdcall;
    function Reserved08: HRESULT; stdcall;
    function Reserved09: HRESULT; stdcall;
    function Reserved10: HRESULT; stdcall;
    function Reserved11: HRESULT; stdcall;
    function Reserved12: HRESULT; stdcall;
    function Reserved13: HRESULT; stdcall;
    function Reserved14: HRESULT; stdcall;
    function Reserved15: HRESULT; stdcall;
    function Reserved16: HRESULT; stdcall;
    function Reserved17: HRESULT; stdcall;
    function Reserved18: HRESULT; stdcall;
    function Reserved19: HRESULT; stdcall;
    function Reserved20: HRESULT; stdcall;
    function CreatePropertyCondition(PropertyId: Integer; Value: OleVariant;
      out Condition: IUnknown): HRESULT; stdcall;
  end;

  IWatchElement = interface(IUnknown)
  ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function FindFirst(Scope: Integer; const Condition: IUnknown;
      out Found: IWatchElement): HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
    function Reserved07: HRESULT; stdcall;
    function Reserved08: HRESULT; stdcall;
    function Reserved09: HRESULT; stdcall;
    function Reserved10: HRESULT; stdcall;
    function Reserved11: HRESULT; stdcall;
    function Reserved12: HRESULT; stdcall;
    function Reserved13: HRESULT; stdcall;
    function GetCurrentPattern(PatternId: Integer; out Pattern: IUnknown): HRESULT; stdcall;
  end;

  IWatchTextPattern = interface(IUnknown)
  ['{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function GetDocumentRange(out Range: IWatchRange): HRESULT; stdcall;
  end;

  IWatchRange = interface(IUnknown)
  ['{A543CC6A-F4AE-494B-8239-C814481187A8}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
    function Reserved07: HRESULT; stdcall;
    function Reserved08: HRESULT; stdcall;
    function Reserved09: HRESULT; stdcall;
    function GetText(MaxLength: Integer; out Text: WideString): HRESULT; stdcall;
  end;

  TWatchThread = class(TThread)
  private
    FOwner: TWindowWatcher;
    FTarget: HWND;
    FAutomation: IWatchAutomation;
    FPattern: IWatchTextPattern;
    FTracker: TTextChangeTracker;
    function FindText: Boolean;
    function ReadText(out Text: string): Boolean;
    procedure Stopped(const Reason: string);
    // Each call captures its own copy (an anonymous method captures
    // variables, not values).
    procedure Deliver(const Sentences: TArray<string>);
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TWindowWatcher; Target: HWND);
    destructor Destroy; override;
  end;

constructor TWatchThread.Create(Owner: TWindowWatcher; Target: HWND);
begin
  FOwner := Owner;
  FTarget := Target;
  FTracker := TTextChangeTracker.Create;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TWatchThread.Destroy;
begin
  FTracker.Free;
  inherited;
end;

// The document of a browser or an Electron application, else the window
// itself when it has TextPattern.
function TWatchThread.FindText: Boolean;
var
  Root, Document: IWatchElement;
  Condition, Pattern: IUnknown;
begin
  Result := False;
  FPattern := nil;
  if Failed(FAutomation.ElementFromHandle(FTarget, Root)) or (Root = nil) then
    Exit;
  Document := nil;
  if Succeeded(FAutomation.CreatePropertyCondition(UIA_CONTROL_TYPE_PROPERTY_ID,
       UIA_DOCUMENT_CONTROL_TYPE_ID, Condition)) then
    Root.FindFirst(TREE_SCOPE_DESCENDANTS, Condition, Document);
  if Document = nil then
    Document := Root;
  if Succeeded(Document.GetCurrentPattern(UIA_TEXT_PATTERN_ID, Pattern)) and (Pattern <> nil) then
    Result := Supports(Pattern, IWatchTextPattern, FPattern);
end;

function TWatchThread.ReadText(out Text: string): Boolean;
var
  Range: IWatchRange;
  Value: WideString;
begin
  Result := False;
  Text := '';
  if FPattern = nil then
    Exit;
  try
    if Succeeded(FPattern.GetDocumentRange(Range)) and (Range <> nil) and
       Succeeded(Range.GetText(MAX_WATCH_TEXT, Value)) then
    begin
      Text := Value;
      Result := True;
    end;
  except
    Result := False;
  end;
end;

procedure TWatchThread.Stopped(const Reason: string);
var
  Owner: TWindowWatcher;
begin
  Owner := FOwner;
  Queue(
    procedure
    begin
      if Assigned(Owner.FOnStopped) then
        Owner.FOnStopped(Owner, Reason);
    end);
end;

procedure TWatchThread.Deliver(const Sentences: TArray<string>);
var
  Owner: TWindowWatcher;
  Copy_: TArray<string>;
begin
  Owner := FOwner;
  Copy_ := Sentences;
  Queue(
    procedure
    begin
      if Assigned(Owner.FOnSentences) then
        Owner.FOnSentences(Owner, Copy_);
    end);
end;

procedure TWatchThread.Execute;
var
  Text: string;
  Sentences: TArray<string>;
  Tries, Failures: Integer;
  WasMinimized: Boolean;
  Owner: TWindowWatcher;
  Started: Cardinal;
begin
  NameThreadForDebugging('LayoutSwitcher.WindowWatch');
  Owner := FOwner;
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    try
      if Failed(CoCreateInstance(CLASS_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
           IWatchAutomation, FAutomation)) then
      begin
        Stopped(T('UI Automation недоступна', 'UI Automation is not available'));
        Exit;
      end;
      // A browser builds its accessibility tree on the first request.
      Tries := 0;
      while not Terminated and not FindText and (Tries < 20) do
      begin
        Inc(Tries);
        Sleep(500);
      end;
      if Terminated then
        Exit;
      if FPattern = nil then
      begin
        Stopped(T('Это окно не отдаёт свой текст. Подходят браузеры, ChatGPT, Claude, ' +
          'редакторы и терминал Windows.', 'This window does not expose its text. Browsers, ' +
          'ChatGPT, Claude, editors and Windows Terminal work.'));
        Exit;
      end;
      Failures := 0;
      WasMinimized := False;
      while not Terminated do
      begin
        if not IsWindow(FTarget) then
        begin
          Stopped(T('Окно закрыто', 'The window was closed'));
          Exit;
        end;
        // A minimized Chromium window keeps its text as it was.
        if IsIconic(FTarget) then
        begin
          if not WasMinimized then
            Queue(
              procedure
              begin
                if Assigned(Owner.FOnMinimized) then
                  Owner.FOnMinimized(Owner);
              end);
          WasMinimized := True;
        end
        else
          WasMinimized := False;
        if ReadText(Text) then
        begin
          Failures := 0;
          Sentences := FTracker.Update(Text, GetTickCount);
          if Length(Sentences) > 0 then
            Deliver(Sentences);
        end
        else
        begin
          // The page was replaced: its document is a new element.
          Inc(Failures);
          if not FindText and (Failures > 20) then
          begin
            Stopped(T('Окно перестало отдавать текст', 'The window no longer exposes its text'));
            Exit;
          end;
        end;
        Started := GetTickCount;
        while not Terminated and (GetTickCount - Started < WATCH_INTERVAL_MS) do
          Sleep(50);
      end;
    except
      on E: Exception do
        Stopped(E.Message);
    end;
  finally
    FPattern := nil;
    FAutomation := nil;
    CoUninitialize;
  end;
end;

{ TWindowWatcher }

destructor TWindowWatcher.Destroy;
begin
  Stop;
  inherited;
end;

procedure TWindowWatcher.Start(Target: HWND);
var
  Buffer: array[0..255] of Char;
begin
  Stop;
  FTarget := Target;
  GetWindowText(Target, Buffer, Length(Buffer));
  FTitle := Buffer;
  FThread := TWatchThread.Create(Self, Target);
end;

procedure TWindowWatcher.Stop;
begin
  if FThread = nil then
    Exit;
  FThread.Terminate;
  FThread.WaitFor;
  // Events it queued and not yet delivered go with it.
  FreeAndNil(FThread);
end;

function TWindowWatcher.Watching: Boolean;
begin
  Result := (FThread <> nil) and not FThread.Finished;
end;

end.
