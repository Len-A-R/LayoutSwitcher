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
  end;

// Queries the focused UI Automation element once: whether it is a password
// field and, if it supports TextPattern, its single selected range.
// Must be called from a thread that has initialised COM.
function QueryUIAutomationFocus: TUIAFocusInfo;

implementation

uses
  Winapi.ActiveX,
  System.SysUtils, System.Variants;

const
  UIA_TEXT_PATTERN_ID = 10014;
  UIA_IS_PASSWORD_PROPERTY_ID = 30019;
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
  end;

  ILSUIAutomationTextRangeArray = interface(IUnknown)
  ['{CE4AE76A-E717-4C98-81EA-47371D028EB6}']
    function GetLength(out Length: Integer): HRESULT; stdcall;
    function GetElement(Index: Integer;
      out Element: ILSUIAutomationTextRange): HRESULT; stdcall;
  end;

  ILSUIAutomationTextRange = interface(IUnknown)
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
    function GetText(MaxLength: Integer;
      out Text: WideString): HRESULT; stdcall;
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

end.
