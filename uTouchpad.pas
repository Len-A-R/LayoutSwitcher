unit uTouchpad;

// The radial menu from a precision touchpad, without the keyboard: three
// fingers held still for a moment open it.
//
// The touchpad is read with Raw Input (HID digitizer, usage page 0x0D,
// usage 0x05 "Touch Pad"), registered with RIDEV_INPUTSINK so that the
// reports come while other programs are in front.  Raw Input does not take
// anything away: the cursor, taps, scrolling and the gestures of Windows
// work as before.  A report holds one or more contacts (fingers); a device
// in "hybrid" mode spreads the contacts of one frame over several reports,
// the first carrying the contact count.  The fingers of each frame go to
// TThreeFingerHold.
//
// Windows uses three fingers for a tap and for swipes; both are quick or
// moving, so a still hold of TOUCH_HOLD_MS does not collide with them.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections;

const
  // Fingers on the pad held still this long open the menu.
  TOUCH_HOLD_FINGERS = 3;
  TOUCH_HOLD_MS = 400;
  // Movement allowed while holding, in TOUCH_SCALE units of the pad width
  // and height (4 %: a few millimetres).
  TOUCH_SCALE = 10000;
  TOUCH_MOVE_TOLERANCE = 400;
  // No report for this long: the fingers are gone (a touchpad reports
  // while it is touched).
  TOUCH_STALE_MS = 300;

type
  // A finger on the pad: X and Y from 0 to TOUCH_SCALE.
  TTouchContact = record
    Id: Integer;
    X: Integer;
    Y: Integer;
  end;

  TFingerHoldState = (fhIdle, fhHolding, fhDone);

  // Three fingers put down and held still: fires once; the next gesture
  // starts after all fingers are lifted.  A fourth finger, a lifted one or
  // movement (a swipe of Windows) cancel it.
  TThreeFingerHold = class
  private
    FState: TFingerHoldState;
    FStart: Cardinal;
    FLast: Cardinal;
    FSeen: Boolean;
    FFirst: TArray<TTouchContact>;
    function Moved(const Fingers: TArray<TTouchContact>): Boolean;
  public
    // The fingers touching the pad now; True when the gesture happens.
    function Feed(const Fingers: TArray<TTouchContact>; Tick: Cardinal): Boolean;
    property State: TFingerHoldState read FState;
  end;

  // HIDP_VALUE_CAPS (hidpi.h), 72 bytes.  For a single usage UsageMin is
  // NotRange.Usage.
  THidPValueCaps = packed record
    UsagePage: Word;
    ReportID: Byte;
    IsAlias: ByteBool;
    BitField: Word;
    LinkCollection: Word;
    LinkUsage: Word;
    LinkUsagePage: Word;
    IsRange: ByteBool;
    IsStringRange: ByteBool;
    IsDesignatorRange: ByteBool;
    IsAbsolute: ByteBool;
    HasNull: ByteBool;
    Reserved: Byte;
    BitSize: Word;
    ReportCount: Word;
    Reserved2: array[0..4] of Word;
    UnitsExp: Cardinal;
    Units: Cardinal;
    LogicalMin: Integer;
    LogicalMax: Integer;
    PhysicalMin: Integer;
    PhysicalMax: Integer;
    UsageMin: Word;
    UsageMax: Word;
    StringMin: Word;
    StringMax: Word;
    DesignatorMin: Word;
    DesignatorMax: Word;
    DataIndexMin: Word;
    DataIndexMax: Word;
  end;

  // HIDP_CAPS (hidpi.h), 64 bytes.
  THidPCaps = record
    Usage: Word;
    UsagePage: Word;
    InputReportByteLength: Word;
    OutputReportByteLength: Word;
    FeatureReportByteLength: Word;
    Reserved: array[0..16] of Word;
    NumberLinkCollectionNodes: Word;
    NumberInputButtonCaps: Word;
    NumberInputValueCaps: Word;
    NumberInputDataIndices: Word;
    NumberOutputButtonCaps: Word;
    NumberOutputValueCaps: Word;
    NumberOutputDataIndices: Word;
    NumberFeatureButtonCaps: Word;
    NumberFeatureValueCaps: Word;
    NumberFeatureDataIndices: Word;
  end;

  TTouchpadReader = class
  private type
    TContactLink = record
      Link: Word;
      MinX, MaxX, MinY, MaxY: Integer;
    end;
    TFrameContact = record
      Contact: TTouchContact;
      Tip: Boolean;
    end;
    TDevice = class
      Usable: Boolean;
      Preparsed: TBytes;
      CountLink: Integer;
      Links: TArray<TContactLink>;
      Expected: Integer;
      Frame: TArray<TFrameContact>;
    end;
  private
    FWnd: HWND;
    FActive: Boolean;
    FDevices: TObjectDictionary<THandle, TDevice>;
    FHold: TThreeFingerHold;
    FOnHold: TNotifyEvent;
    procedure WndMethod(var Message: TMessage);
    procedure HandleInput(Input: THandle);
    function DeviceFor(Handle: THandle): TDevice;
    procedure ParseReport(Device: TDevice; Report: PByte; Length: Cardinal);
    procedure SetActive(Value: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    // Reading the touchpad on or off.
    property Active: Boolean read FActive write SetActive;
    // Three fingers held: in the main thread.
    property OnHold: TNotifyEvent read FOnHold write FOnHold;
  end;

implementation

uses
  uDiagnostics;

const
  HIDP_INPUT = 0;
  HIDP_STATUS_SUCCESS = $00110000;
  PAGE_GENERIC = $01;
  PAGE_DIGITIZER = $0D;
  USAGE_TOUCH_PAD = $05;
  USAGE_X = $30;
  USAGE_Y = $31;
  USAGE_TIP_SWITCH = $42;
  USAGE_CONTACT_ID = $51;
  USAGE_CONTACT_COUNT = $54;

  // Raw Input (winuser.h): not declared in Winapi.Windows.
  RIDEV_REMOVE = $00000001;
  RIDEV_INPUTSINK = $00000100;
  RID_INPUT = $10000003;
  RIM_TYPEHID = 2;
  RIDI_PREPARSEDDATA = $20000005;

type
  TRawInputDevice = record
    usUsagePage: Word;
    usUsage: Word;
    dwFlags: DWORD;
    hwndTarget: HWND;
  end;

  TRawInputHeader = record
    dwType: DWORD;
    dwSize: DWORD;
    hDevice: THandle;
    wParam: WPARAM;
  end;
  PRawInputHeader = ^TRawInputHeader;

function RegisterRawInputDevices(Devices: Pointer; Count, Size: UINT): BOOL;
  stdcall; external user32;
function GetRawInputData(Input: THandle; Command: UINT; Data: Pointer; var Size: UINT;
  HeaderSize: UINT): UINT; stdcall; external user32;
function GetRawInputDeviceInfo(Device: THandle; Command: UINT; Data: Pointer;
  var Size: UINT): UINT; stdcall; external user32 name 'GetRawInputDeviceInfoW';

function HidP_GetCaps(PreparsedData: Pointer; var Capabilities: THidPCaps): Integer;
  stdcall; external 'hid.dll';
function HidP_GetValueCaps(ReportType: Integer; ValueCaps: Pointer; var ValueCapsLength: Word;
  PreparsedData: Pointer): Integer; stdcall; external 'hid.dll';
function HidP_GetUsageValue(ReportType: Integer; UsagePage: Word; LinkCollection: Word;
  Usage: Word; var UsageValue: Cardinal; PreparsedData: Pointer; Report: Pointer;
  ReportLength: Cardinal): Integer; stdcall; external 'hid.dll';
function HidP_GetUsages(ReportType: Integer; UsagePage: Word; LinkCollection: Word;
  UsageList: Pointer; var UsageLength: Cardinal; PreparsedData: Pointer; Report: Pointer;
  ReportLength: Cardinal): Integer; stdcall; external 'hid.dll';

{ TThreeFingerHold }

function TThreeFingerHold.Moved(const Fingers: TArray<TTouchContact>): Boolean;
var
  F, S: TTouchContact;
  Found: Boolean;
begin
  for F in Fingers do
  begin
    Found := False;
    for S in FFirst do
      if S.Id = F.Id then
      begin
        Found := True;
        if (Abs(F.X - S.X) > TOUCH_MOVE_TOLERANCE) or (Abs(F.Y - S.Y) > TOUCH_MOVE_TOLERANCE) then
          Exit(True);
        Break;
      end;
    // Another finger than the ones put down.
    if not Found then
      Exit(True);
  end;
  Result := False;
end;

function TThreeFingerHold.Feed(const Fingers: TArray<TTouchContact>; Tick: Cardinal): Boolean;
begin
  Result := False;
  // A pause in the reports: the fingers were lifted meanwhile.
  if FSeen and (Tick - FLast > TOUCH_STALE_MS) then
    FState := fhIdle;
  FSeen := True;
  FLast := Tick;
  case FState of
    fhIdle:
      if Length(Fingers) = TOUCH_HOLD_FINGERS then
      begin
        FState := fhHolding;
        FStart := Tick;
        FFirst := Copy(Fingers);
      end;
    fhHolding:
      if Length(Fingers) = 0 then
        FState := fhIdle
      else if (Length(Fingers) <> TOUCH_HOLD_FINGERS) or Moved(Fingers) then
        FState := fhDone
      else if Tick - FStart >= TOUCH_HOLD_MS then
      begin
        FState := fhDone;
        Result := True;
      end;
    fhDone:
      if Length(Fingers) = 0 then
        FState := fhIdle;
  end;
end;

{ TTouchpadReader }

constructor TTouchpadReader.Create;
begin
  inherited;
  FDevices := TObjectDictionary<THandle, TDevice>.Create([doOwnsValues]);
  FHold := TThreeFingerHold.Create;
  FWnd := AllocateHWnd(WndMethod);
end;

destructor TTouchpadReader.Destroy;
begin
  SetActive(False);
  DeallocateHWnd(FWnd);
  FHold.Free;
  FDevices.Free;
  inherited;
end;

procedure TTouchpadReader.SetActive(Value: Boolean);
var
  Device: TRawInputDevice;
begin
  if Value = FActive then
    Exit;
  Device.usUsagePage := PAGE_DIGITIZER;
  Device.usUsage := USAGE_TOUCH_PAD;
  if Value then
  begin
    Device.dwFlags := RIDEV_INPUTSINK;
    Device.hwndTarget := FWnd;
  end
  else
  begin
    Device.dwFlags := RIDEV_REMOVE;
    Device.hwndTarget := 0;
  end;
  if RegisterRawInputDevices(@Device, 1, SizeOf(Device)) then
    FActive := Value
  else
    DiagnosticsLogFmt('touchpad.register_failed on=%s error=%d',
      [BoolToStr(Value, True), GetLastError]);
  if not FActive then
    FDevices.Clear;
end;

procedure TTouchpadReader.WndMethod(var Message: TMessage);
begin
  if Message.Msg = WM_INPUT then
    try
      HandleInput(THandle(Message.LParam));
    except
      on E: Exception do
        DiagnosticsLogFmt('touchpad.error %s', [E.ClassName]);
    end;
  // WM_INPUT needs DefWindowProc to free the input.
  Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TTouchpadReader.HandleInput(Input: THandle);
var
  Size, SizeHid, Count, I: Cardinal;
  Buffer: TBytes;
  Header: PRawInputHeader;
  Device: TDevice;
  Data: PByte;
begin
  Size := 0;
  if (GetRawInputData(Input, RID_INPUT, nil, Size, SizeOf(TRawInputHeader)) <> 0) or
     (Size < SizeOf(TRawInputHeader) + 8) then
    Exit;
  SetLength(Buffer, Size);
  if GetRawInputData(Input, RID_INPUT, @Buffer[0], Size, SizeOf(TRawInputHeader)) <> Size then
    Exit;
  Header := PRawInputHeader(@Buffer[0]);
  if Header.dwType <> RIM_TYPEHID then
    Exit;
  Device := DeviceFor(Header.hDevice);
  if (Device = nil) or not Device.Usable then
    Exit;
  // RAWHID: dwSizeHid, dwCount, then dwCount reports.
  SizeHid := PCardinal(@Buffer[SizeOf(TRawInputHeader)])^;
  Count := PCardinal(@Buffer[SizeOf(TRawInputHeader) + 4])^;
  if (SizeHid = 0) or (UInt64(SizeOf(TRawInputHeader)) + 8 + UInt64(SizeHid) * Count > Size) then
    Exit;
  Data := @Buffer[SizeOf(TRawInputHeader) + 8];
  for I := 0 to Count - 1 do
  begin
    ParseReport(Device, Data, SizeHid);
    Inc(Data, SizeHid);
  end;
end;

function TTouchpadReader.DeviceFor(Handle: THandle): TDevice;

  function Covers(const Caps: THidPValueCaps; Usage: Word): Boolean;
  begin
    if Caps.IsRange then
      Result := (Usage >= Caps.UsageMin) and (Usage <= Caps.UsageMax)
    else
      Result := Caps.UsageMin = Usage;
  end;

  function LinkIndex(Device: TDevice; Link: Word): Integer;
  begin
    for Result := 0 to High(Device.Links) do
      if Device.Links[Result].Link = Link then
        Exit;
    SetLength(Device.Links, Length(Device.Links) + 1);
    Result := High(Device.Links);
    Device.Links[Result] := Default(TContactLink);
    Device.Links[Result].Link := Link;
  end;

var
  Size: UINT;
  Caps: THidPCaps;
  Values: TArray<THidPValueCaps>;
  Count: Word;
  I, L: Integer;
begin
  if FDevices.TryGetValue(Handle, Result) then
    Exit;
  Result := TDevice.Create;
  FDevices.Add(Handle, Result);
  Result.CountLink := -1;
  Size := 0;
  GetRawInputDeviceInfo(Handle, RIDI_PREPARSEDDATA, nil, Size);
  if Size = 0 then
    Exit;
  SetLength(Result.Preparsed, Size);
  if (GetRawInputDeviceInfo(Handle, RIDI_PREPARSEDDATA, @Result.Preparsed[0], Size) = UINT(-1)) or
     (HidP_GetCaps(@Result.Preparsed[0], Caps) <> HIDP_STATUS_SUCCESS) or
     (Caps.NumberInputValueCaps = 0) then
    Exit;
  Count := Caps.NumberInputValueCaps;
  SetLength(Values, Count);
  if HidP_GetValueCaps(HIDP_INPUT, @Values[0], Count, @Result.Preparsed[0]) <> HIDP_STATUS_SUCCESS then
    Exit;
  for I := 0 to Count - 1 do
  begin
    if (Values[I].UsagePage = PAGE_DIGITIZER) and Covers(Values[I], USAGE_CONTACT_COUNT) then
      Result.CountLink := Values[I].LinkCollection;
    if (Values[I].UsagePage = PAGE_GENERIC) and Covers(Values[I], USAGE_X) then
    begin
      L := LinkIndex(Result, Values[I].LinkCollection);
      Result.Links[L].MinX := Values[I].LogicalMin;
      Result.Links[L].MaxX := Values[I].LogicalMax;
    end;
    if (Values[I].UsagePage = PAGE_GENERIC) and Covers(Values[I], USAGE_Y) then
    begin
      L := LinkIndex(Result, Values[I].LinkCollection);
      Result.Links[L].MinY := Values[I].LogicalMin;
      Result.Links[L].MaxY := Values[I].LogicalMax;
    end;
  end;
  Result.Usable := (Result.CountLink >= 0) and (Length(Result.Links) > 0);
  // The shape of the device, never what is touched.
  DiagnosticsLogFmt('touchpad.device usable=%s contacts=%d',
    [BoolToStr(Result.Usable, True), Length(Result.Links)]);
end;

procedure TTouchpadReader.ParseReport(Device: TDevice; Report: PByte; Length: Cardinal);

  function Value(Page, Link, Usage: Word; out V: Cardinal): Boolean;
  begin
    Result := HidP_GetUsageValue(HIDP_INPUT, Page, Link, Usage, V, @Device.Preparsed[0],
      Report, Length) = HIDP_STATUS_SUCCESS;
  end;

  function TipOn(Link: Word): Boolean;
  var
    Usages: array[0..31] of Word;
    Count, I: Cardinal;
  begin
    Result := False;
    Count := System.Length(Usages);
    if HidP_GetUsages(HIDP_INPUT, PAGE_DIGITIZER, Link, @Usages[0], Count, @Device.Preparsed[0],
       Report, Length) <> HIDP_STATUS_SUCCESS then
      Exit;
    for I := 0 to Count - 1 do
      if Usages[I] = USAGE_TIP_SWITCH then
        Exit(True);
  end;

  function Scale(V: Cardinal; Min, Max: Integer): Integer;
  begin
    if Max <= Min then
      Exit(0);
    Result := Integer((Int64(V) - Min) * TOUCH_SCALE div (Int64(Max) - Min));
  end;

var
  ContactCount, V: Cardinal;
  Link: TContactLink;
  Item: TFrameContact;
  Fingers: TArray<TTouchContact>;
  I: Integer;
begin
  if Value(PAGE_DIGITIZER, Device.CountLink, USAGE_CONTACT_COUNT, ContactCount) and
     (ContactCount > 0) then
  begin
    // The first report of a frame.
    Device.Expected := ContactCount;
    Device.Frame := nil;
  end;
  if Device.Expected = 0 then
    Exit;
  for Link in Device.Links do
  begin
    if System.Length(Device.Frame) >= Device.Expected then
      Break;
    Item := Default(TFrameContact);
    Item.Tip := TipOn(Link.Link);
    if Value(PAGE_DIGITIZER, Link.Link, USAGE_CONTACT_ID, V) then
      Item.Contact.Id := V
    else
      Item.Contact.Id := System.Length(Device.Frame);
    if Value(PAGE_GENERIC, Link.Link, USAGE_X, V) then
      Item.Contact.X := Scale(V, Link.MinX, Link.MaxX);
    if Value(PAGE_GENERIC, Link.Link, USAGE_Y, V) then
      Item.Contact.Y := Scale(V, Link.MinY, Link.MaxY);
    Device.Frame := Device.Frame + [Item];
  end;
  if System.Length(Device.Frame) < Device.Expected then
    Exit;
  // A whole frame: the fingers touching.
  Fingers := nil;
  for I := 0 to High(Device.Frame) do
    if Device.Frame[I].Tip then
      Fingers := Fingers + [Device.Frame[I].Contact];
  Device.Expected := 0;
  Device.Frame := nil;
  if FHold.Feed(Fingers, GetTickCount) then
  begin
    DiagnosticsLog('touchpad.hold');
    if Assigned(FOnHold) then
      FOnHold(Self);
  end;
end;

end.
