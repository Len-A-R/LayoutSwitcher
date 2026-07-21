unit uUIAutomation;

interface

uses
  Winapi.Windows;

function TryGetUIAutomationSelection(out Text: WideString;
  out FailureStage: string; out ErrorCode: HRESULT): Boolean;

implementation

uses
  Winapi.ActiveX,
  System.SysUtils;

const
  UIA_TEXT_PATTERN_ID = 10014;
  MAX_UIA_SELECTION_LENGTH = 1024 * 1024;
  CLASS_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';

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

  ILSUIAutomationElement = interface(IUnknown)
  ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function Reserved01: HRESULT; stdcall;
    function Reserved02: HRESULT; stdcall;
    function Reserved03: HRESULT; stdcall;
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

function TryGetUIAutomationSelection(out Text: WideString;
  out FailureStage: string; out ErrorCode: HRESULT): Boolean;
var
  ComResult: HRESULT;
  UninitializeCOM: Boolean;
  Automation: ILSUIAutomation;
  Element: ILSUIAutomationElement;
  PatternObject: IUnknown;
  TextPattern: ILSUIAutomationTextPattern;
  Ranges: ILSUIAutomationTextRangeArray;
  TextRange: ILSUIAutomationTextRange;
  RangeCount: Integer;
begin
  Result := False;
  Text := '';
  FailureStage := 'com_initialize';
  ErrorCode := E_FAIL;
  UninitializeCOM := False;

  ComResult := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  if Succeeded(ComResult) then
    UninitializeCOM := True
  else if ComResult <> RPC_E_CHANGED_MODE then
  begin
    ErrorCode := ComResult;
    Exit;
  end;

  try
    try
      FailureStage := 'create_automation';
      ErrorCode := CoCreateInstance(CLASS_CUIAutomation, nil,
        CLSCTX_INPROC_SERVER, ILSUIAutomation, Automation);
      if Failed(ErrorCode) or not Assigned(Automation) then
        Exit;

      FailureStage := 'focused_element';
      ErrorCode := Automation.GetFocusedElement(Element);
      if Failed(ErrorCode) or not Assigned(Element) then
        Exit;

      FailureStage := 'text_pattern';
      ErrorCode := Element.GetCurrentPattern(UIA_TEXT_PATTERN_ID, PatternObject);
      if Failed(ErrorCode) or not Assigned(PatternObject) then
        Exit;
      if not Supports(PatternObject, ILSUIAutomationTextPattern, TextPattern) then
      begin
        ErrorCode := E_NOINTERFACE;
        Exit;
      end;

      FailureStage := 'selection_ranges';
      ErrorCode := TextPattern.GetSelection(Ranges);
      if Failed(ErrorCode) or not Assigned(Ranges) then
        Exit;
      ErrorCode := Ranges.GetLength(RangeCount);
      if Failed(ErrorCode) then
        Exit;
      if RangeCount <> 1 then
      begin
        FailureStage := 'selection_count';
        ErrorCode := S_FALSE;
        Exit;
      end;

      FailureStage := 'selection_range';
      ErrorCode := Ranges.GetElement(0, TextRange);
      if Failed(ErrorCode) or not Assigned(TextRange) then
        Exit;

      FailureStage := 'selection_text';
      ErrorCode := TextRange.GetText(MAX_UIA_SELECTION_LENGTH + 1, Text);
      if Failed(ErrorCode) then
      begin
        Text := '';
        Exit;
      end;
      if (Text = '') or (Length(Text) > MAX_UIA_SELECTION_LENGTH) then
      begin
        Text := '';
        ErrorCode := S_FALSE;
        Exit;
      end;

      FailureStage := '';
      ErrorCode := S_OK;
      Result := True;
    except
      on E: Exception do
      begin
        Text := '';
        FailureStage := FailureStage + ':' + E.ClassName;
        ErrorCode := E_UNEXPECTED;
        Result := False;
      end;
    end;
  finally
    TextRange := nil;
    Ranges := nil;
    TextPattern := nil;
    PatternObject := nil;
    Element := nil;
    Automation := nil;
    if UninitializeCOM then
      CoUninitialize;
  end;
end;

end.
