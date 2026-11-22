unit uGestureDetector;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

// Pure state machine that turns physical key transitions into gestures:
// double Shift, double Left Ctrl, double Right Ctrl, Left Ctrl + Right Ctrl,
// Left Shift + Right Shift, double Caps Lock, double left/right Alt,
// Right Ctrl + Right Alt, Pause/Break, Scroll Lock.  A double
// Alt opens and closes the menu of classic applications.  A double Caps Lock toggles the
// Caps Lock state twice and so leaves it unchanged.
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

  // Everything the detector knows about the keyboard, kept in one record so
  // that the effect of a key event can be rolled back (see AltGr below).
  TGestureState = record
    KeyDown: array[0..255] of Boolean;
    KeyDownTime: array[0..255] of Cardinal;
    ShiftDownTime: Cardinal;
    ShiftEligible: Boolean;
    ShiftPending: Boolean;
    ShiftPendingTime: Cardinal;
    LCtrlDownTime: Cardinal;
    LCtrlEligible: Boolean;
    LCtrlPending: Boolean;
    LCtrlPendingTime: Cardinal;
    RCtrlDownTime: Cardinal;
    RCtrlEligible: Boolean;
    RCtrlPending: Boolean;
    RCtrlPendingTime: Cardinal;
    // Double Alt taps: index 0 = left Alt, 1 = right Alt.
    AltDownTime: array[0..1] of Cardinal;
    AltEligible: array[0..1] of Boolean;
    AltPending: array[0..1] of Boolean;
    AltPendingTime: array[0..1] of Cardinal;
    CapsDownTime: Cardinal;
    CapsEligible: Boolean;
    CapsPending: Boolean;
    CapsPendingTime: Cardinal;
    ChordActive: Boolean;
    ChordValid: Boolean;
    ShiftChordActive: Boolean;
    ShiftChordValid: Boolean;
    // Right Ctrl + Right Alt pressed together and released.
    CtrlAltChordActive: Boolean;
    CtrlAltChordValid: Boolean;
    CtrlAltChordStart: Cardinal;
  end;

  TGestureDetector = class
  private
    FS: TGestureState;
    FInterval: Cardinal;
    // AltGr: Windows inserts a fake Ctrl right before Right Alt on layouts
    // with AltGr (the Russian one has ₽ on AltGr+8).  Raw Input reports it
    // as Left or Right Ctrl depending on the keyboard driver.
    FBeforeCtrl: TGestureState;
    FLastCtrlDownVK: Cardinal;   // Ctrl pressed by the previous event, or 0.
    FCtrlDownAt: Cardinal;
    FFakeCtrlVK: Cardinal;       // Fake Ctrl whose events are ignored, or 0.

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

const
  // The fake Ctrl of AltGr arrives together with Right Alt.
  ALTGR_MAX_GAP_MS = 20;

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
  FS.ShiftPending := False;
  FS.LCtrlPending := False;
  FS.RCtrlPending := False;
  FS.CapsPending := False;
  FS.AltPending[0] := False;
  FS.AltPending[1] := False;
end;

procedure TGestureDetector.ResetTaps;
begin
  CancelPending;
  FS.ShiftEligible := False;
  FS.LCtrlEligible := False;
  FS.RCtrlEligible := False;
  FS.ChordValid := False;
  FS.ShiftChordValid := False;
  FS.CtrlAltChordValid := False;
  FS.CapsEligible := False;
  FS.AltEligible[0] := False;
  FS.AltEligible[1] := False;
end;

procedure TGestureDetector.ResetAll;
begin
  FillChar(FS.KeyDown, SizeOf(FS.KeyDown), 0);
  FLastCtrlDownVK := 0;
  FFakeCtrlVK := 0;
  ResetTaps;
  FS.ChordActive := False;
  FS.ShiftChordActive := False;
  FS.CtrlAltChordActive := False;
end;

function TGestureDetector.ReleaseStaleKeys(const IsPhysicallyDown: TKeyStateQuery;
  Time, MinAgeMS: Cardinal): Integer;
var
  I: Cardinal;
begin
  Result := 0;
  if not Assigned(IsPhysicallyDown) then
    Exit;
  for I := Low(FS.KeyDown) to High(FS.KeyDown) do
    if FS.KeyDown[I] and (Time - FS.KeyDownTime[I] >= MinAgeMS) and
       not IsPhysicallyDown(I) then
    begin
      FS.KeyDown[I] := False;
      Inc(Result);
    end;
  if Result > 0 then
  begin
    // State built on top of the lost key-ups is unreliable.
    ResetTaps;
    FS.ChordActive := False;
    FS.ShiftChordActive := False;
    FS.CtrlAltChordActive := False;
  end;
end;

function TGestureDetector.HeldKeyCount: Integer;
var
  I: Cardinal;
begin
  Result := 0;
  for I := Low(FS.KeyDown) to High(FS.KeyDown) do
    if FS.KeyDown[I] then
      Inc(Result);
end;

function TGestureDetector.IsDown(VK: Cardinal): Boolean;
begin
  Result := (VK <= High(FS.KeyDown)) and FS.KeyDown[VK];
end;

function TGestureDetector.ShiftDown: Boolean;
begin
  Result := FS.KeyDown[VK_SHIFT] or FS.KeyDown[VK_LSHIFT] or FS.KeyDown[VK_RSHIFT];
end;

function TGestureDetector.CtrlDown: Boolean;
begin
  Result := FS.KeyDown[VK_CONTROL] or FS.KeyDown[VK_LCONTROL] or FS.KeyDown[VK_RCONTROL];
end;

function TGestureDetector.AltDown: Boolean;
begin
  Result := FS.KeyDown[VK_MENU] or FS.KeyDown[VK_LMENU] or FS.KeyDown[VK_RMENU];
end;

function TGestureDetector.WinDown: Boolean;
begin
  Result := FS.KeyDown[VK_LWIN] or FS.KeyDown[VK_RWIN];
end;

function TGestureDetector.OtherKeysDown(ExceptA, ExceptB,
  ExceptC: Cardinal): Boolean;
var
  I: Cardinal;
begin
  for I := Low(FS.KeyDown) to High(FS.KeyDown) do
    if FS.KeyDown[I] and (I <> ExceptA) and (I <> ExceptB) and (I <> ExceptC) then
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
  I: Integer;
begin
  Result := lgNone;
  if VK > High(FS.KeyDown) then
    Exit;

  // AltGr = fake Ctrl + Right Alt with (practically) the same time.  Undo
  // everything the fake Ctrl did and ignore its further events.
  if (VK = VK_RMENU) and not IsKeyUp and (FLastCtrlDownVK <> 0) and
     (Time - FCtrlDownAt <= ALTGR_MAX_GAP_MS) then
  begin
    FS := FBeforeCtrl;
    FFakeCtrlVK := FLastCtrlDownVK;
  end;
  // Drivers that report the fake Ctrl as Right Ctrl: a real Right Ctrl
  // pressed while AltGr is held (Right Ctrl + Right Alt in that order) comes
  // as the same key, but not together with Right Alt.
  if (FFakeCtrlVK <> 0) and (VK = FFakeCtrlVK) and not IsKeyUp and
     FS.KeyDown[VK_RMENU] and not FS.KeyDown[VK] and
     (Time - FS.KeyDownTime[VK_RMENU] > ALTGR_MAX_GAP_MS) then
    FFakeCtrlVK := 0;
  if (FFakeCtrlVK <> 0) and (VK = FFakeCtrlVK) then
  begin
    if IsKeyUp then
      FFakeCtrlVK := 0;
    FLastCtrlDownVK := 0;
    Exit;
  end;
  if ((VK = VK_LCONTROL) or (VK = VK_RCONTROL)) and not IsKeyUp and
     not FS.KeyDown[VK] then
  begin
    FBeforeCtrl := FS;
    FLastCtrlDownVK := VK;
    FCtrlDownAt := Time;
  end
  else
    FLastCtrlDownVK := 0;

  if IsKeyUp then
  begin
    FS.KeyDown[VK] := False;

    if IsShiftKey(VK) and not ShiftDown then
    begin
      if FS.ShiftEligible and (Time - FS.ShiftDownTime <= FInterval) then
      begin
        if CompleteTap(FS.ShiftPending, FS.ShiftPendingTime, Time) then
          Result := lgDoubleShift;
      end
      else
        FS.ShiftPending := False;
      FS.ShiftEligible := False;
    end;

    if VK = VK_LCONTROL then
    begin
      if FS.LCtrlEligible and not FS.ChordActive and
         (Time - FS.LCtrlDownTime <= FInterval) then
      begin
        if CompleteTap(FS.LCtrlPending, FS.LCtrlPendingTime, Time) then
          Result := lgDoubleLCtrl;
      end
      else if not FS.ChordActive then
        FS.LCtrlPending := False;
      FS.LCtrlEligible := False;
    end;

    if VK = VK_RCONTROL then
    begin
      if FS.RCtrlEligible and not FS.ChordActive and
         (Time - FS.RCtrlDownTime <= FInterval) then
      begin
        if CompleteTap(FS.RCtrlPending, FS.RCtrlPendingTime, Time) then
          Result := lgDoubleRCtrl;
      end
      else if not FS.ChordActive then
        FS.RCtrlPending := False;
      FS.RCtrlEligible := False;
    end;

    if (VK = VK_LMENU) or (VK = VK_RMENU) then
    begin
      I := Ord(VK = VK_RMENU);
      if FS.AltEligible[I] and (Time - FS.AltDownTime[I] <= FInterval) then
      begin
        if CompleteTap(FS.AltPending[I], FS.AltPendingTime[I], Time) then
          if I = 0 then
            Result := lgDoubleLAlt
          else
            Result := lgDoubleRAlt;
      end
      else
        FS.AltPending[I] := False;
      FS.AltEligible[I] := False;
    end;

    if VK = VK_CAPITAL then
    begin
      if FS.CapsEligible and (Time - FS.CapsDownTime <= FInterval) then
      begin
        if CompleteTap(FS.CapsPending, FS.CapsPendingTime, Time) then
          Result := lgDoubleCapsLock;
      end
      else
        FS.CapsPending := False;
      FS.CapsEligible := False;
    end;

    if FS.ChordActive and not FS.KeyDown[VK_LCONTROL] and
       not FS.KeyDown[VK_RCONTROL] then
    begin
      FS.ChordActive := False;
      if FS.ChordValid then
        Result := lgBothCtrl;
      FS.ChordValid := False;
      CancelPending;
    end;

    if FS.ShiftChordActive and not FS.KeyDown[VK_LSHIFT] and
       not FS.KeyDown[VK_RSHIFT] then
    begin
      FS.ShiftChordActive := False;
      if FS.ShiftChordValid then
        Result := lgBothShift;
      FS.ShiftChordValid := False;
      CancelPending;
    end;

    // A quick press of both keys, like the other gestures: holding AltGr
    // alone longer could make its auto-repeat look like a Right Ctrl.
    if FS.CtrlAltChordActive and not FS.KeyDown[VK_RCONTROL] and
       not FS.KeyDown[VK_RMENU] then
    begin
      FS.CtrlAltChordActive := False;
      if FS.CtrlAltChordValid and (Time - FS.CtrlAltChordStart <= FInterval) then
        Result := lgRCtrlRAlt;
      FS.CtrlAltChordValid := False;
      CancelPending;
    end;
    Exit;
  end;

  WasDown := FS.KeyDown[VK];
  FS.KeyDownTime[VK] := Time;
  if WasDown then
    Exit; // Auto-repeat does not change gesture state.

  // Any new key disqualifies taps of other held modifiers and cancels
  // pending first taps of other gestures.
  if not IsShiftKey(VK) then
  begin
    FS.ShiftEligible := False;
    FS.ShiftPending := False;
  end;
  if VK <> VK_LCONTROL then
  begin
    if not ((VK = VK_RCONTROL) and FS.KeyDown[VK_LCONTROL]) then
      FS.LCtrlPending := False;
    FS.LCtrlEligible := False;
  end;
  if VK <> VK_RCONTROL then
  begin
    if not ((VK = VK_LCONTROL) and FS.KeyDown[VK_RCONTROL]) then
      FS.RCtrlPending := False;
    FS.RCtrlEligible := False;
  end;
  if VK <> VK_CAPITAL then
  begin
    FS.CapsEligible := False;
    FS.CapsPending := False;
  end;
  if VK <> VK_LMENU then
  begin
    FS.AltEligible[0] := False;
    FS.AltPending[0] := False;
  end;
  if VK <> VK_RMENU then
  begin
    FS.AltEligible[1] := False;
    FS.AltPending[1] := False;
  end;
  if FS.ChordActive and not IsCtrlKey(VK) then
    FS.ChordValid := False;
  if FS.ShiftChordActive and not IsShiftKey(VK) then
    FS.ShiftChordValid := False;
  if FS.CtrlAltChordActive and (VK <> VK_RCONTROL) and (VK <> VK_RMENU) then
    FS.CtrlAltChordValid := False;
  // Pause/Break sends its press and release together when pressed, so it
  // is a gesture on the press, alone (Ctrl+Pause is VK_CANCEL).  Its scan
  // code sequence (E1 1D 45) can also be reported partly as Num Lock.
  if (VK = VK_PAUSE) and not OtherKeysDown(VK_PAUSE, VK_NUMLOCK, VK_PAUSE) then
    Result := lgPause;
  // Scroll Lock alone, on the press (dictation); its light toggles twice
  // per dictation (start and stop), so the state comes back.
  if (VK = VK_SCROLL) and not OtherKeysDown(VK_SCROLL, VK_SCROLL, VK_SCROLL) then
    Result := lgScrollLock;
  // Right Ctrl + Right Alt in either order.
  if ((VK = VK_RMENU) and FS.KeyDown[VK_RCONTROL]) or
     ((VK = VK_RCONTROL) and FS.KeyDown[VK_RMENU]) then
  begin
    FS.CtrlAltChordActive := True;
    FS.CtrlAltChordValid := not OtherKeysDown(VK_RCONTROL, VK_RMENU, VK_RMENU);
    if VK = VK_RMENU then
      FS.CtrlAltChordStart := FS.KeyDownTime[VK_RCONTROL]
    else
      FS.CtrlAltChordStart := FS.KeyDownTime[VK_RMENU];
  end;

  if IsShiftKey(VK) then
  begin
    // A second Shift while one is held is not a tap, but both Shift keys
    // together form the Left Shift + Right Shift chord.
    FS.ShiftEligible := not OtherKeysDown(VK, VK, VK);
    FS.ShiftDownTime := Time;
    if ((VK = VK_LSHIFT) and FS.KeyDown[VK_RSHIFT]) or
       ((VK = VK_RSHIFT) and FS.KeyDown[VK_LSHIFT]) then
    begin
      FS.ShiftChordActive := True;
      FS.ShiftChordValid := not OtherKeysDown(VK_LSHIFT, VK_RSHIFT, VK_SHIFT);
    end;
  end
  else if VK = VK_LCONTROL then
  begin
    if FS.KeyDown[VK_RCONTROL] then
    begin
      FS.ChordActive := True;
      FS.ChordValid := not OtherKeysDown(VK_RCONTROL, VK_LCONTROL, VK_LCONTROL);
    end
    else
      FS.LCtrlEligible := not OtherKeysDown(VK, VK, VK);
    FS.LCtrlDownTime := Time;
  end
  else if VK = VK_RCONTROL then
  begin
    if FS.KeyDown[VK_LCONTROL] then
    begin
      FS.ChordActive := True;
      FS.ChordValid := not OtherKeysDown(VK_LCONTROL, VK_RCONTROL, VK_RCONTROL);
    end
    else
      FS.RCtrlEligible := not OtherKeysDown(VK, VK, VK);
    FS.RCtrlDownTime := Time;
  end
  else if VK = VK_CAPITAL then
  begin
    FS.CapsEligible := not OtherKeysDown(VK, VK, VK);
    FS.CapsDownTime := Time;
  end
  else if (VK = VK_LMENU) or (VK = VK_RMENU) then
  begin
    // AltGr arrives as Left Ctrl + Right Alt and is therefore never a tap.
    I := Ord(VK = VK_RMENU);
    FS.AltEligible[I] := not OtherKeysDown(VK, VK, VK);
    FS.AltDownTime[I] := Time;
  end;

  FS.KeyDown[VK] := True;
end;

end.
