unit uUIAutomation;

interface

uses
  Winapi.Windows;

type
  TUIAFocusInfo = record
    ElementFound: Boolean;
    IsPassword: Boolean;
    HasSelection: Boolean;
    SelectionText: WideString;
    FailureStage: string;
    ErrorCode: HRESULT;
    // TextPattern of the focused element, kept for UIAGetTextBeforeCaret.
    TextPattern: IUnknown;
  end;

// Queries the focused UI Automation element once: whether it is a password
// field and, if it supports TextPattern, its single selected range.
// Must be called from a thread that has initialised COM.
function QueryUIAutomationFocus: TUIAFocusInfo;

// Text immediately before the caret (TextPattern2, Windows 8+): the last
// word, extended over punctuation glued to it ("vbh," typed in the wrong
// layout is one word).  Range is an opaque text range for UIASelectRange.
function UIAGetTextBeforeCaret(const Info: TUIAFocusInfo; MaxLength: Integer;
  out Text: WideString; out Range: IUnknown): Boolean;
function UIASelectRange(const Range: IUnknown): Boolean;
// The selected text of the document of the window (a page in a browser or an
// Electron application), even when the focus is not in a text field.
// Must be called from a thread that has initialised COM.
function UIAGetDocumentSelection(Wnd: HWND; out Text: string): Boolean;

implementation

uses
  Winapi.ActiveX,
  System.SysUtils, System.Variants;

const
  UIA_TEXT_PATTERN_ID = 10014;
  UIA_IS_PASSWORD_PROPERTY_ID = 30019;
  UIA_ENDPOINT_START = 0;
  UIA_TEXTUNIT_CHARACTER = 0;
  UIA_TEXTUNIT_WORD = 2;
  MAX_CARET_WORD_STEPS = 8;
  MAX_UIA_SELECTION_LENGTH = 1024 * 1024;
  CLASS_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  CLASS_CUIAutomation8: TGUID = '{E22AD333-B25F-460C-83D0-0581107395C9}';
  // Defaults are 2 s / 20 s.  An application that stops responding (typical
  // right after resume from sleep) would otherwise block the worker that long.
  UIA_CONNECTION_TIMEOUT_MS = 1000;
  UIA_TRANSACTION_TIMEOUT_MS = 2000;

type
  ILSUIAutomationElement = interface;
  ILSUIAutomationTextRange = interface;
  ILSUIAutomationTextRangeArray = interface;

  // Only the vtable entries needed by LayoutSwitcher are named. Reserved
  // entries retain the exact order from UIAutomationClient.h.
  ILSUIAutomation = interface(IUnknown)
  ['{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function GetFocusedElement(
      out Element: ILSUIAutomationElement): HRESULT; stdcall;
  end;

  // IUIAutomation2 (Windows 8+): only the timeout properties are used.  Slot
  // numbers verified against the UIAutomationCore.dll type library.
  ILSUIAutomation2 = interface(ILSUIAutomation)
  ['{34723AFF-0C9D-49D0-9896-7AB52DF8CD8A}']
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
    function Reserved21: HRESULT; stdcall;
    function Reserved22: HRESULT; stdcall;
    function Reserved23: HRESULT; stdcall;
    function Reserved24: HRESULT; stdcall;
    function Reserved25: HRESULT; stdcall;
    function Reserved26: HRESULT; stdcall;
    function Reserved27: HRESULT; stdcall;
    function Reserved28: HRESULT; stdcall;
    function Reserved29: HRESULT; stdcall;
    function Reserved30: HRESULT; stdcall;
    function Reserved31: HRESULT; stdcall;
    function Reserved32: HRESULT; stdcall;
    function Reserved33: HRESULT; stdcall;
    function Reserved34: HRESULT; stdcall;
    function Reserved35: HRESULT; stdcall;
    function Reserved36: HRESULT; stdcall;
    function Reserved37: HRESULT; stdcall;
    function Reserved38: HRESULT; stdcall;
    function Reserved39: HRESULT; stdcall;
    function Reserved40: HRESULT; stdcall;
    function Reserved41: HRESULT; stdcall;
    function Reserved42: HRESULT; stdcall;
    function Reserved43: HRESULT; stdcall;
    function Reserved44: HRESULT; stdcall;
    function Reserved45: HRESULT; stdcall;
    function Reserved46: HRESULT; stdcall;
    function Reserved47: HRESULT; stdcall;
    function Reserved48: HRESULT; stdcall;
    function Reserved49: HRESULT; stdcall;
    function Reserved50: HRESULT; stdcall;
    function Reserved51: HRESULT; stdcall;
    function Reserved52: HRESULT; stdcall;
    function Reserved53: HRESULT; stdcall;
    function Reserved54: HRESULT; stdcall;
    function Reserved55: HRESULT; stdcall;
    function GetAutoSetFocus(out Value: BOOL): HRESULT; stdcall;
    function PutAutoSetFocus(Value: BOOL): HRESULT; stdcall;
    function GetConnectionTimeout(out Value: DWORD): HRESULT; stdcall;
    function PutConnectionTimeout(Value: DWORD): HRESULT; stdcall;
    function GetTransactionTimeout(out Value: DWORD): HRESULT; stdcall;
    function PutTransactionTimeout(Value: DWORD): HRESULT; stdcall;
  end;

  ILSUIAutomationElement = interface(IUnknown)
  ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
    function Reserved07: HRESULT; stdcall;
    function GetCurrentPropertyValue(PropertyID: Integer;
      out Value: OleVariant): HRESULT; stdcall;
    function Reserved09: HRESULT; stdcall;
    function Reserved10: HRESULT; stdcall;
    function Reserved11: HRESULT; stdcall;
    function Reserved12: HRESULT; stdcall;
    function Reserved13: HRESULT; stdcall;
    function GetCurrentPattern(PatternID: Integer;
      out PatternObject: IUnknown): HRESULT; stdcall;
  end;

  ILSUIAutomationTextPattern = interface(IUnknown)
  ['{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function GetSelection(
      out Ranges: ILSUIAutomationTextRangeArray): HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
  end;

  ILSUIAutomationTextPattern2 = interface(ILSUIAutomationTextPattern)
  ['{506A921A-FCC9-409F-B23B-37EB74106872}']
    function Reserved07: HRESULT; stdcall;
    function GetCaretRange(out IsActive: BOOL;
      out Range: ILSUIAutomationTextRange): HRESULT; stdcall;
  end;

  ILSUIAutomationTextRangeArray = interface(IUnknown)
  ['{CE4AE76A-E717-4C98-81EA-47371D028EB6}']
    function GetLength(out Length: Integer): HRESULT; stdcall;
    function GetElement(Index: Integer;
      out Element: ILSUIAutomationTextRange): HRESULT; stdcall;
  end;

  ILSUIAutomationTextRange = interface(IUnknown)
  ['{A543CC6A-F4AE-494B-8239-C814481187A8}']
    function Clone(out Range: ILSUIAutomationTextRange): HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function Reserved04: HRESULT; stdcall;
    function Reserved05: HRESULT; stdcall;
    function Reserved06: HRESULT; stdcall;
    function Reserved07: HRESULT; stdcall;
    function Reserved08: HRESULT; stdcall;
    function Reserved09: HRESULT; stdcall;
    function GetText(MaxLength: Integer;
      out Text: WideString): HRESULT; stdcall;
    function Reserved11: HRESULT; stdcall;
    function MoveEndpointByUnit(Endpoint, TextUnit, Count: Integer;
      out Moved: Integer): HRESULT; stdcall;
    function Reserved13: HRESULT; stdcall;
    function Select: HRESULT; stdcall;
  end;

type
  ILSDocElement = interface;

  // IUIAutomation: ElementFromHandle (slot 4) and CreatePropertyCondition
  // (slot 21) only.
  ILSDocAutomation = interface(IUnknown)
  ['{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
    function ElementFromHandle(Wnd: HWND; out Element: ILSDocElement): HRESULT; stdcall;
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

  // IUIAutomationElement: FindFirst (slot 3) and GetCurrentPattern (14).
  ILSDocElement = interface(IUnknown)
  ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function FindFirst(Scope: Integer; const Condition: IUnknown;
      out Found: ILSDocElement): HRESULT; stdcall;
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

function UIAGetDocumentSelection(Wnd: HWND; out Text: string): Boolean;
const
  UIA_CONTROL_TYPE_PROPERTY_ID = 30003;
  UIA_DOCUMENT_CONTROL_TYPE_ID = 50030;
  TREE_SCOPE_DESCENDANTS = 4;
var
  Automation: ILSDocAutomation;
  Automation2: ILSUIAutomation2;
  Root, Document: ILSDocElement;
  Condition, PatternObject: IUnknown;
  TextPattern: ILSUIAutomationTextPattern;
  Ranges: ILSUIAutomationTextRangeArray;
  Range: ILSUIAutomationTextRange;
  Count, I: Integer;
  Part: WideString;
begin
  Result := False;
  Text := '';
  if Wnd = 0 then
    Exit;
  try
    if Failed(CoCreateInstance(CLASS_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
         ILSDocAutomation, Automation)) or (Automation = nil) then
      Exit;
    if Supports(Automation, ILSUIAutomation2, Automation2) then
    begin
      Automation2.PutConnectionTimeout(UIA_CONNECTION_TIMEOUT_MS);
      Automation2.PutTransactionTimeout(UIA_TRANSACTION_TIMEOUT_MS);
    end;
    if Failed(Automation.ElementFromHandle(Wnd, Root)) or (Root = nil) then
      Exit;
    if Failed(Automation.CreatePropertyCondition(UIA_CONTROL_TYPE_PROPERTY_ID,
         UIA_DOCUMENT_CONTROL_TYPE_ID, Condition)) then
      Exit;
    Document := nil;
    if Failed(Root.FindFirst(TREE_SCOPE_DESCENDANTS, Condition, Document)) or (Document = nil) then
      Exit;
    if Failed(Document.GetCurrentPattern(UIA_TEXT_PATTERN_ID, PatternObject)) or
       (PatternObject = nil) or not Supports(PatternObject, ILSUIAutomationTextPattern, TextPattern) then
      Exit;
    if Failed(TextPattern.GetSelection(Ranges)) or (Ranges = nil) or
       Failed(Ranges.GetLength(Count)) then
      Exit;
    // Several ranges (a selection over table cells): one text.
    for I := 0 to Count - 1 do
      if Succeeded(Ranges.GetElement(I, Range)) and (Range <> nil) and
         Succeeded(Range.GetText(MAX_UIA_SELECTION_LENGTH, Part)) and (Part <> '') then
      begin
        if Text <> '' then
          Text := Text + sLineBreak;
        Text := Text + Part;
      end;
    Result := Trim(Text) <> '';
  except
    Result := False;
    Text := '';
  end;
end;

function QueryUIAutomationFocus: TUIAFocusInfo;
var
  Automation: ILSUIAutomation;
  Automation2: ILSUIAutomation2;
  Element: ILSUIAutomationElement;
  PatternObject: IUnknown;
  TextPattern: ILSUIAutomationTextPattern;
  Ranges: ILSUIAutomationTextRangeArray;
  TextRange: ILSUIAutomationTextRange;
  RangeCount: Integer;
  PasswordValue: OleVariant;
begin
  Result.ElementFound := False;
  Result.IsPassword := False;
  Result.HasSelection := False;
  Result.SelectionText := '';
  Result.FailureStage := 'create_automation';
  Result.ErrorCode := E_FAIL;
  try
    Result.ErrorCode := CoCreateInstance(CLASS_CUIAutomation8, nil,
      CLSCTX_INPROC_SERVER, ILSUIAutomation, Automation);
    if Failed(Result.ErrorCode) or not Assigned(Automation) then
      Result.ErrorCode := CoCreateInstance(CLASS_CUIAutomation, nil,
        CLSCTX_INPROC_SERVER, ILSUIAutomation, Automation);
    if Failed(Result.ErrorCode) or not Assigned(Automation) then
      Exit;
    if Supports(Automation, ILSUIAutomation2, Automation2) then
    begin
      Automation2.PutConnectionTimeout(UIA_CONNECTION_TIMEOUT_MS);
      Automation2.PutTransactionTimeout(UIA_TRANSACTION_TIMEOUT_MS);
    end;

    Result.FailureStage := 'focused_element';
    Result.ErrorCode := Automation.GetFocusedElement(Element);
    if Failed(Result.ErrorCode) or not Assigned(Element) then
      Exit;
    Result.ElementFound := True;

    Result.FailureStage := 'is_password';
    if Succeeded(Element.GetCurrentPropertyValue(UIA_IS_PASSWORD_PROPERTY_ID,
         PasswordValue)) and (VarType(PasswordValue) = varBoolean) then
      Result.IsPassword := Boolean(PasswordValue);
    if Result.IsPassword then
    begin
      Result.FailureStage := '';
      Result.ErrorCode := S_OK;
      Exit;
    end;

    Result.FailureStage := 'text_pattern';
    Result.ErrorCode := Element.GetCurrentPattern(UIA_TEXT_PATTERN_ID,
      PatternObject);
    if Failed(Result.ErrorCode) or not Assigned(PatternObject) then
      Exit;
    if not Supports(PatternObject, ILSUIAutomationTextPattern, TextPattern) then
    begin
      Result.ErrorCode := E_NOINTERFACE;
      Exit;
    end;
    Result.TextPattern := TextPattern;

    Result.FailureStage := 'selection_ranges';
    Result.ErrorCode := TextPattern.GetSelection(Ranges);
    if Failed(Result.ErrorCode) or not Assigned(Ranges) then
      Exit;
    Result.ErrorCode := Ranges.GetLength(RangeCount);
    if Failed(Result.ErrorCode) then
      Exit;
    if RangeCount <> 1 then
    begin
      Result.FailureStage := 'selection_count';
      Result.ErrorCode := S_FALSE;
      Exit;
    end;

    Result.FailureStage := 'selection_range';
    Result.ErrorCode := Ranges.GetElement(0, TextRange);
    if Failed(Result.ErrorCode) or not Assigned(TextRange) then
      Exit;

    Result.FailureStage := 'selection_text';
    Result.ErrorCode := TextRange.GetText(MAX_UIA_SELECTION_LENGTH + 1,
      Result.SelectionText);
    if Failed(Result.ErrorCode) or (Result.SelectionText = '') or
       (Length(Result.SelectionText) > MAX_UIA_SELECTION_LENGTH) then
    begin
      Result.SelectionText := '';
      if Succeeded(Result.ErrorCode) then
        Result.ErrorCode := S_FALSE;
      Exit;
    end;

    Result.HasSelection := True;
    Result.FailureStage := '';
    Result.ErrorCode := S_OK;
  except
    on E: Exception do
    begin
      Result.HasSelection := False;
      Result.SelectionText := '';
      Result.FailureStage := Result.FailureStage + ':' + E.ClassName;
      Result.ErrorCode := E_UNEXPECTED;
    end;
  end;
end;

function IsBlank(Ch: WideChar): Boolean;
begin
  Result := (Ord(Ch) <= 32) or (Ch = #$00A0);
end;

function UIAGetTextBeforeCaret(const Info: TUIAFocusInfo; MaxLength: Integer;
  out Text: WideString; out Range: IUnknown): Boolean;
var
  Pattern2: ILSUIAutomationTextPattern2;
  Caret, Candidate, Probe: ILSUIAutomationTextRange;
  IsActive: BOOL;
  Moved, Step: Integer;
  Previous: WideString;
  Ch: WideChar;
begin
  Result := False;
  Text := '';
  Range := nil;
  if not Assigned(Info.TextPattern) or
     not Supports(Info.TextPattern, ILSUIAutomationTextPattern2, Pattern2) then
    Exit;
  try
    if Failed(Pattern2.GetCaretRange(IsActive, Caret)) or not Assigned(Caret) then
      Exit;
    if Failed(Caret.Clone(Candidate)) or not Assigned(Candidate) then
      Exit;

    for Step := 1 to MAX_CARET_WORD_STEPS do
    begin
      Moved := 0;
      if Failed(Candidate.MoveEndpointByUnit(UIA_ENDPOINT_START,
           UIA_TEXTUNIT_WORD, -1, Moved)) or (Moved = 0) then
        Break;
      // Stop at whitespace or at the start of the text; otherwise the word
      // unit split on punctuation and the previous piece belongs to it.
      Probe := nil;
      if Failed(Candidate.Clone(Probe)) or not Assigned(Probe) then
        Break;
      Moved := 0;
      if Failed(Probe.MoveEndpointByUnit(UIA_ENDPOINT_START,
           UIA_TEXTUNIT_CHARACTER, -1, Moved)) or (Moved = 0) then
        Break;
      Previous := '';
      if Failed(Probe.GetText(1, Previous)) or (Previous = '') or
         IsBlank(Previous[1]) then
        Break;
    end;

    if Failed(Candidate.GetText(MaxLength + 1, Text)) then
      Text := '';
    if (Text = '') or (Length(Text) > MaxLength) then
    begin
      Text := '';
      Exit;
    end;
    for Ch in Text do
      if (Ch = #13) or (Ch = #10) then
      begin
        Text := '';
        Exit;
      end;
    if Trim(Text) = '' then
    begin
      Text := '';
      Exit;
    end;
    Range := Candidate;
    Result := True;
  except
    Text := '';
    Range := nil;
    Result := False;
  end;
end;

function UIASelectRange(const Range: IUnknown): Boolean;
var
  TextRange: ILSUIAutomationTextRange;
begin
  try
    Result := Supports(Range, ILSUIAutomationTextRange, TextRange) and
      Succeeded(TextRange.Select);
  except
    Result := False;
  end;
end;

end.
