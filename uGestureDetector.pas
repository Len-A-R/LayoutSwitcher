unit uGestureDetector;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

// Pure state machine that turns physical key transitions into gestures:
// double Shift, double Left Ctrl, double Right Ctrl, Left Ctrl + Right Ctrl.
// It has no Win32 calls besides VK_* constants, so it is fully unit-testable.
//
// A "tap" is a modifier pressed and released within the double-tap interval
// while no other key was involved.  Any other key going down (including Alt,
// Win or the other modifier) disqualifies the tap and cancels a pending first
// tap, so shortcuts such as Alt+Shift or Ctrl+C never trigger an action.
//
// Raw Input is not delivered while the secure desktop is active (lock screen,
// Ctrl+Alt+Del, UAC, resume from sleep).  A key pressed before the switch
// (Win+L, Ctrl+Alt+Del) therefore never reports its release and would block
// every tap afterwards.  ReleaseStaleKeys reconciles the tracked state with
// the physical keyboard state supplied by the caller.

interface

uses
  System.SysUtils,
  uSettings;

type
  TKeyStateQuery = TFunc<Cardinal, Boolean>;

  TGestureDetector = class
  private
    FKeyDown: array[0..255] of Boolean;
    FKeyDownTime: array[0..255] of Cardinal;
    FInterval: Cardinal;

    FShiftDownTime: Cardinal;
    FShiftEligible: Boolean;
    FShiftPending: Boolean;
    FShiftPendingTime: Cardinal;

    FLCtrlDownTime: Cardinal;
    FLCtrlEligible: Boolean;
    FLCtrlPending: Boolean;
    FLCtrlPendingTime: Cardinal;

    FRCtrlDownTime: Cardinal;
    FRCtrlEligible: Boolean;
    FRCtrlPending: Boolean;
    FRCtrlPendingTime: Cardinal;

    FChordActive: Boolean;
    FChordValid: Boolean;

    function OtherKeysDown(ExceptA, ExceptB, ExceptC: Cardinal): Boolean;
    function CompleteTap(var Pending: Boolean; var PendingTime: Cardinal;
      Time: Cardinal): Boolean;
    procedure CancelPending;
  public
    constructor Create;
    // Forget pending taps (window change, mouse click).  Key states are kept.
    procedure ResetTaps;
    // Forget everything, including which keys are held.
    procedure ResetAll;
    // VK must be side-specific for Shift/Ctrl/Alt (VK_LSHIFT, VK_RCONTROL...).
    // Returns the recognised gesture or lgNone.
    function KeyEvent(VK: Cardinal; IsKeyUp: Boolean; Time: Cardinal): TLSGesture;
    // Marks as released every key tracked as held for at least MinAgeMS that
    // IsPhysicallyDown reports as up.  Returns the number of released keys.
    function ReleaseStaleKeys(const IsPhysicallyDown: TKeyStateQuery;
      Time, MinAgeMS: Cardinal): Integer;
    function HeldKeyCount: Integer;
    function IsDown(VK: Cardinal): Boolean;
    function ShiftDown: Boolean;
    function CtrlDown: Boolean;
    function AltDown: Boolean;
    function WinDown: Boolean;
    property Interval: Cardinal read FInterval write FInterval;
  end;

function IsShiftKey(VK: Cardinal): Boolean;
function IsCtrlKey(VK: Cardinal): Boolean;
function IsAltKey(VK: Cardinal): Boolean;
function IsWinKey(VK: Cardinal): Boolean;
function IsModifierKey(VK: Cardinal): Boolean;

implementation

uses
  Winapi.Windows;

function IsShiftKey(VK: Cardinal): Boolean;
begin
  Result := (VK = VK_SHIFT) or (VK = VK_LSHIFT) or (VK = VK_RSHIFT);
end;

function IsCtrlKey(VK: Cardinal): Boolean;
begin
  Result := (VK = VK_CONTROL) or (VK = VK_LCONTROL) or (VK = VK_RCONTROL);
end;

function IsAltKey(VK: Cardinal): Boolean;
begin
  Result := (VK = VK_MENU) or (VK = VK_LMENU) or (VK = VK_RMENU);
end;

function IsWinKey(VK: Cardinal): Boolean;
begin
  Result := (VK = VK_LWIN) or (VK = VK_RWIN);
end;

function IsModifierKey(VK: Cardinal): Boolean;
begin
  Result := IsShiftKey(VK) or IsCtrlKey(VK) or IsAltKey(VK) or IsWinKey(VK);
end;

{ TGestureDetector }

constructor TGestureDetector.Create;
begin
  inherited Create;
  FInterval := DEFAULT_DOUBLE_TAP_INTERVAL;
  ResetAll;
end;

procedure TGestureDetector.CancelPending;
begin
  FShiftPending := False;
  FLCtrlPending := False;
  FRCtrlPending := False;
end;

procedure TGestureDetector.ResetTaps;
begin
  CancelPending;
  FShiftEligible := False;
  FLCtrlEligible := False;
  FRCtrlEligible := False;
  FChordValid := False;
end;

procedure TGestureDetector.ResetAll;
begin
  FillChar(FKeyDown, SizeOf(FKeyDown), 0);
  ResetTaps;
  FChordActive := False;
end;

function TGestureDetector.ReleaseStaleKeys(const IsPhysicallyDown: TKeyStateQuery;
  Time, MinAgeMS: Cardinal): Integer;
var
  I: Cardinal;
begin
  Result := 0;
  if not Assigned(IsPhysicallyDown) then
    Exit;
  for I := Low(FKeyDown) to High(FKeyDown) do
    if FKeyDown[I] and (Time - FKeyDownTime[I] >= MinAgeMS) and
       not IsPhysicallyDown(I) then
    begin
      FKeyDown[I] := False;
      Inc(Result);
    end;
  if Result > 0 then
  begin
    // State built on top of the lost key-ups is unreliable.
    ResetTaps;
    FChordActive := False;
  end;
end;

function TGestureDetector.HeldKeyCount: Integer;
var
  I: Cardinal;
begin
  Result := 0;
  for I := Low(FKeyDown) to High(FKeyDown) do
    if FKeyDown[I] then
      Inc(Result);
end;

function TGestureDetector.IsDown(VK: Cardinal): Boolean;
begin
  Result := (VK <= High(FKeyDown)) and FKeyDown[VK];
end;

function TGestureDetector.ShiftDown: Boolean;
begin
  Result := FKeyDown[VK_SHIFT] or FKeyDown[VK_LSHIFT] or FKeyDown[VK_RSHIFT];
end;

function TGestureDetector.CtrlDown: Boolean;
begin
  Result := FKeyDown[VK_CONTROL] or FKeyDown[VK_LCONTROL] or FKeyDown[VK_RCONTROL];
end;

function TGestureDetector.AltDown: Boolean;
begin
  Result := FKeyDown[VK_MENU] or FKeyDown[VK_LMENU] or FKeyDown[VK_RMENU];
end;

function TGestureDetector.WinDown: Boolean;
begin
  Result := FKeyDown[VK_LWIN] or FKeyDown[VK_RWIN];
end;

function TGestureDetector.OtherKeysDown(ExceptA, ExceptB,
  ExceptC: Cardinal): Boolean;
var
  I: Cardinal;
begin
  for I := Low(FKeyDown) to High(FKeyDown) do
    if FKeyDown[I] and (I <> ExceptA) and (I <> ExceptB) and (I <> ExceptC) then
      Exit(True);
  Result := False;
end;

function TGestureDetector.CompleteTap(var Pending: Boolean;
  var PendingTime: Cardinal; Time: Cardinal): Boolean;
begin
  Result := Pending and (Time - PendingTime <= FInterval);
  if Result then
    Pending := False
  else
  begin
    Pending := True;
    PendingTime := Time;
  end;
end;

function TGestureDetector.KeyEvent(VK: Cardinal; IsKeyUp: Boolean;
  Time: Cardinal): TLSGesture;
var
  WasDown: Boolean;
begin
  Result := lgNone;
  if VK > High(FKeyDown) then
    Exit;

  if IsKeyUp then
  begin
    FKeyDown[VK] := False;

    if IsShiftKey(VK) and not ShiftDown then
    begin
      if FShiftEligible and (Time - FShiftDownTime <= FInterval) then
      begin
        if CompleteTap(FShiftPending, FShiftPendingTime, Time) then
          Result := lgDoubleShift;
      end
      else
        FShiftPending := False;
      FShiftEligible := False;
    end;

    if VK = VK_LCONTROL then
    begin
      if FLCtrlEligible and not FChordActive and
         (Time - FLCtrlDownTime <= FInterval) then
      begin
        if CompleteTap(FLCtrlPending, FLCtrlPendingTime, Time) then
          Result := lgDoubleLCtrl;
      end
      else if not FChordActive then
        FLCtrlPending := False;
      FLCtrlEligible := False;
    end;

    if VK = VK_RCONTROL then
    begin
      if FRCtrlEligible and not FChordActive and
         (Time - FRCtrlDownTime <= FInterval) then
      begin
        if CompleteTap(FRCtrlPending, FRCtrlPendingTime, Time) then
          Result := lgDoubleRCtrl;
      end
      else if not FChordActive then
        FRCtrlPending := False;
      FRCtrlEligible := False;
    end;

    if FChordActive and not FKeyDown[VK_LCONTROL] and
       not FKeyDown[VK_RCONTROL] then
    begin
      FChordActive := False;
      if FChordValid then
        Result := lgBothCtrl;
      FChordValid := False;
      CancelPending;
    end;
    Exit;
  end;

  WasDown := FKeyDown[VK];
  FKeyDownTime[VK] := Time;
  if WasDown then
    Exit; // Auto-repeat does not change gesture state.

  // Any new key disqualifies taps of other held modifiers and cancels
  // pending first taps of other gestures.
  if not IsShiftKey(VK) then
  begin
    FShiftEligible := False;
    FShiftPending := False;
  end;
  if VK <> VK_LCONTROL then
  begin
    if not ((VK = VK_RCONTROL) and FKeyDown[VK_LCONTROL]) then
      FLCtrlPending := False;
    FLCtrlEligible := False;
  end;
  if VK <> VK_RCONTROL then
  begin
    if not ((VK = VK_LCONTROL) and FKeyDown[VK_RCONTROL]) then
      FRCtrlPending := False;
    FRCtrlEligible := False;
  end;
  if FChordActive and not IsCtrlKey(VK) then
    FChordValid := False;

  if IsShiftKey(VK) then
  begin
    // A second Shift while one is held is not a tap.
    FShiftEligible := not OtherKeysDown(VK, VK, VK);
    FShiftDownTime := Time;
  end
  else if VK = VK_LCONTROL then
  begin
    if FKeyDown[VK_RCONTROL] then
    begin
      FChordActive := True;
      FChordValid := not OtherKeysDown(VK_RCONTROL, VK_LCONTROL, VK_LCONTROL);
    end
    else
      FLCtrlEligible := not OtherKeysDown(VK, VK, VK);
    FLCtrlDownTime := Time;
  end
  else if VK = VK_RCONTROL then
  begin
    if FKeyDown[VK_LCONTROL] then
    begin
      FChordActive := True;
      FChordValid := not OtherKeysDown(VK_LCONTROL, VK_RCONTROL, VK_RCONTROL);
    end
    else
      FRCtrlEligible := not OtherKeysDown(VK, VK, VK);
    FRCtrlDownTime := Time;
  end;

  FKeyDown[VK] := True;
end;

end.
