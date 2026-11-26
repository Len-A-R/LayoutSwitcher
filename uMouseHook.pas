unit uMouseHook;

// The middle mouse button for the radial menu.  A low-level mouse hook in a
// thread of its own (it must answer at once, whatever the main thread does)
// decides about each press of the middle button and posts what happened to
// the main window; everything else passes through untouched.
//
// Hold mode: the press is held back.  Released at once, it is replayed as an
// ordinary click (links in new tabs, autoscroll); held still for HOLD_MS the
// menu opens and the release over a slice runs it; a quick flick to a side
// and release runs the slice of that direction without waiting for the
// menu; held and dragged longer than FLICK_MS, the press is replayed and the
// drag goes to the program (panning).  While the menu is open, the buttons
// are the menu's: left click selects, right click closes.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes;

const
  // WParam of the message posted to the main window; LParam: the screen
  // point (x, y as signed 16-bit halves).
  RM_OPEN = 1;      // show the menu centred at the point
  RM_MOVE = 2;      // the pointer moved while the menu is open
  RM_RELEASE = 3;   // the middle button released over the point (hold mode)
  RM_CLICK = 4;     // left click at the point
  RM_CANCEL = 5;    // right click
  RM_FLICK = 6;     // a flick from the press point (Start) to the point

  RADIAL_OFF = 0;
  RADIAL_HOLD = 1;
  RADIAL_CLICK = 2;
  RADIAL_CTRL_CLICK = 3;

type
  TMouseHookThread = class(TThread)
  private
    FNotifyWnd: HWND;
    FMessage: UINT;
  protected
    procedure Execute; override;
  public
    constructor Create(NotifyWnd: HWND; Msg: UINT);
    procedure Stop;
  end;

var
  // Set by the main thread.
  RadialMode: Integer = RADIAL_HOLD;
  // The window in front may be used (not paused, not excluded, not an
  // administrator window, not a full-screen game).
  RadialAllowed: Boolean = True;
  // The menu is on the screen: the buttons belong to it.
  RadialMenuOpen: Boolean = False;
  // The press point of the last flick (RM_FLICK).
  RadialFlickStart: TPoint;
  // Tests drive the mouse with SendInput: synthetic input is taken then
  // (our own replays still pass).
  RadialAcceptInjected: Boolean = False;

function PackPoint(const P: TPoint): LPARAM;
function UnpackPoint(Value: LPARAM): TPoint;

implementation

uses
  uWinUtils;

const
  HOLD_MS = 250;
  FLICK_MS = 500;
  FLICK_MIN_DISTANCE = 40;
  MOVE_TOLERANCE = 8;
  WM_REPLAY = WM_APP + 1;
  REPLAY_CLICK = 1;
  REPLAY_DOWN = 2;
  TIMER_HOLD = 1;

type
  TPressState = (psIdle, psPending, psMoving, psPassThrough, psMenu);

  // MSLLHOOKSTRUCT (not declared in Winapi.Windows).
  TLowLevelMouse = record
    pt: TPoint;
    mouseData: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;
  PLowLevelMouse = ^TLowLevelMouse;

const
  LLMHF_INJECTED = $00000001;

var
  GThread: TMouseHookThread;
  GThreadId: DWORD;
  GHook: HHOOK;
  GState: TPressState;
  GDownPoint: TPoint;
  GDownTime: DWORD;
  GTimer: UINT_PTR;

function PackPoint(const P: TPoint): LPARAM;
begin
  Result := LPARAM(Cardinal(Word(SmallInt(P.X))) or (Cardinal(Word(SmallInt(P.Y))) shl 16));
end;

function UnpackPoint(Value: LPARAM): TPoint;
begin
  Result.X := SmallInt(Word(Value and $FFFF));
  Result.Y := SmallInt(Word((Value shr 16) and $FFFF));
end;

procedure Notify(Kind: Integer; const P: TPoint);
begin
  if GThread <> nil then
    PostMessage(GThread.FNotifyWnd, GThread.FMessage, WPARAM(Kind), PackPoint(P));
end;

function Distance(const A, B: TPoint): Integer;
begin
  Result := Round(Sqrt(Sqr(Int64(A.X - B.X)) + Sqr(Int64(A.Y - B.Y))));
end;

procedure SendMiddle(Down, Up: Boolean);
var
  Inputs: array[0..1] of TInput;
  Count: Integer;
begin
  FillChar(Inputs, SizeOf(Inputs), 0);
  Count := 0;
  if Down then
  begin
    Inputs[Count].Itype := INPUT_MOUSE;
    Inputs[Count].mi.dwFlags := MOUSEEVENTF_MIDDLEDOWN;
    Inputs[Count].mi.dwExtraInfo := LS_INPUT_TAG;
    Inc(Count);
  end;
  if Up then
  begin
    Inputs[Count].Itype := INPUT_MOUSE;
    Inputs[Count].mi.dwFlags := MOUSEEVENTF_MIDDLEUP;
    Inputs[Count].mi.dwExtraInfo := LS_INPUT_TAG;
    Inc(Count);
  end;
  if Count > 0 then
    SendInput(Count, Inputs[0], SizeOf(TInput));
end;

procedure StopHoldTimer;
begin
  if GTimer <> 0 then
  begin
    KillTimer(0, GTimer);
    GTimer := 0;
  end;
end;

// Replays are sent after the hook has returned, not from inside it.
procedure Replay(Kind: Integer);
begin
  PostThreadMessage(GThreadId, WM_REPLAY, WPARAM(Kind), 0);
end;

function LowLevelMouseProc(Code: Integer; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Info: PLowLevelMouse;
  P: TPoint;
begin
  if Code <> HC_ACTION then
    Exit(CallNextHookEx(GHook, Code, WParam, LParam));
  Info := PLowLevelMouse(LParam);
  // Our own replays and other synthetic input pass.
  if (Info.dwExtraInfo = LS_INPUT_TAG) or
     (((Info.flags and LLMHF_INJECTED) <> 0) and not RadialAcceptInjected) then
    Exit(CallNextHookEx(GHook, Code, WParam, LParam));
  P := Info.pt;

  // The menu is open: its buttons.
  if RadialMenuOpen then
  begin
    case WParam of
      WM_MOUSEMOVE:
        begin
          Notify(RM_MOVE, P);
          Exit(CallNextHookEx(GHook, Code, WParam, LParam));
        end;
      WM_LBUTTONDOWN, WM_RBUTTONUP, WM_MBUTTONDOWN, WM_MOUSEWHEEL, WM_MOUSEHWHEEL:
        Exit(1);
      WM_LBUTTONUP:
        begin
          Notify(RM_CLICK, P);
          Exit(1);
        end;
      WM_RBUTTONDOWN:
        begin
          Notify(RM_CANCEL, P);
          Exit(1);
        end;
      WM_MBUTTONUP:
        begin
          GState := psIdle;
          Notify(RM_RELEASE, P);
          Exit(1);
        end;
    end;
    Exit(CallNextHookEx(GHook, Code, WParam, LParam));
  end;

  case WParam of
    WM_MBUTTONDOWN:
      begin
        if not RadialAllowed or (RadialMode = RADIAL_OFF) then
          Exit(CallNextHookEx(GHook, Code, WParam, LParam));
        if (RadialMode = RADIAL_CTRL_CLICK) and (GetAsyncKeyState(VK_CONTROL) >= 0) then
          Exit(CallNextHookEx(GHook, Code, WParam, LParam));
        GDownPoint := P;
        GDownTime := Info.time;
        if RadialMode = RADIAL_HOLD then
        begin
          GState := psPending;
          StopHoldTimer;
          GTimer := SetTimer(0, TIMER_HOLD, HOLD_MS, nil);
        end
        else
        begin
          // Click modes: the menu at once, chosen with the left button.
          GState := psMenu;
          RadialMenuOpen := True;
          Notify(RM_OPEN, P);
        end;
        Exit(1);
      end;
    WM_MOUSEMOVE:
      if (GState = psPending) and (Distance(P, GDownPoint) > MOVE_TOLERANCE) then
      begin
        StopHoldTimer;
        GState := psMoving;
      end
      else if (GState = psMoving) and (Info.time - GDownTime > FLICK_MS) then
      begin
        // Too slow for a flick: a drag of the program (panning).
        GState := psPassThrough;
        Replay(REPLAY_DOWN);
      end;
    WM_MBUTTONUP:
      case GState of
        psPending:
          begin
            StopHoldTimer;
            GState := psIdle;
            Replay(REPLAY_CLICK);
            Exit(1);
          end;
        psMoving:
          begin
            GState := psIdle;
            if (Info.time - GDownTime <= FLICK_MS) and
               (Distance(P, GDownPoint) >= FLICK_MIN_DISTANCE) then
            begin
              RadialFlickStart := GDownPoint;
              Notify(RM_FLICK, P);
            end
            else
              Replay(REPLAY_CLICK);
            Exit(1);
          end;
        psPassThrough:
          GState := psIdle;
        psMenu:
          begin
            // The release of the opening click (the menu closed meanwhile).
            GState := psIdle;
            Exit(1);
          end;
      end;
  end;
  Result := CallNextHookEx(GHook, Code, WParam, LParam);
end;

{ TMouseHookThread }

constructor TMouseHookThread.Create(NotifyWnd: HWND; Msg: UINT);
begin
  FNotifyWnd := NotifyWnd;
  FMessage := Msg;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TMouseHookThread.Execute;
var
  Msg: TMsg;
  P: TPoint;
begin
  NameThreadForDebugging('LayoutSwitcher.MouseHook');
  GThread := Self;
  GThreadId := GetCurrentThreadId;
  GState := psIdle;
  // The message queue exists before the hook can post to it.
  PeekMessage(Msg, 0, WM_USER, WM_USER, PM_NOREMOVE);
  GHook := SetWindowsHookEx(WH_MOUSE_LL, @LowLevelMouseProc, HInstance, 0);
  try
    while not Terminated and GetMessage(Msg, 0, 0, 0) do
    begin
      if (Msg.message = WM_TIMER) and (Msg.hwnd = 0) and (UINT_PTR(Msg.wParam) = GTimer) then
      begin
        StopHoldTimer;
        // Held still long enough: the menu.
        if GState = psPending then
        begin
          GState := psMenu;
          // At once: a release right now already belongs to the menu.
          RadialMenuOpen := True;
          Notify(RM_OPEN, GDownPoint);
        end;
      end
      else if Msg.message = WM_REPLAY then
      begin
        GetCursorPos(P);
        if Msg.wParam = REPLAY_CLICK then
          SendMiddle(True, True)
        else
          SendMiddle(True, False);
      end
      else
      begin
        TranslateMessage(Msg);
        DispatchMessage(Msg);
      end;
    end;
  finally
    StopHoldTimer;
    if GHook <> 0 then
      UnhookWindowsHookEx(GHook);
    GHook := 0;
    GThread := nil;
  end;
end;

procedure TMouseHookThread.Stop;
begin
  Terminate;
  PostThreadMessage(ThreadID, WM_QUIT, 0, 0);
  WaitFor;
end;

end.
