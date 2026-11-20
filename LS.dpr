program LS;

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  Vcl.Forms,
  uSettingsStore in 'uSettingsStore.pas',
  uLocale in 'uLocale.pas',
  uDiagnostics in 'uDiagnostics.pas',
  uUIAutomation in 'uUIAutomation.pas',
  uTextTools in 'uTextTools.pas',
  uSettings in 'uSettings.pas',
  uWinUtils in 'uWinUtils.pas',
  uGestureDetector in 'uGestureDetector.pas',
  uLayoutConverter in 'uLayoutConverter.pas',
  uClipboardSnapshot in 'uClipboardSnapshot.pas',
  uConversionChain in 'uConversionChain.pas',
  uTaskAutorun in 'uTaskAutorun.pas',
  uLayoutIndicator in 'uLayoutIndicator.pas',
  uUpdateCheck in 'uUpdateCheck.pas',
  uUpdateProgress in 'uUpdateProgress.pas',
  uSignature in 'uSignature.pas',
  uSpellCheck in 'uSpellCheck.pas',
  uWordStarts in 'uWordStarts.pas',
  uInWordSwitch in 'uInWordSwitch.pas',
  uTrayIconData in 'uTrayIconData.pas',
  uOperationWorker in 'uOperationWorker.pas',
  uMain in 'uMain.pas' {FormMain};

{$R *.res}

const
  INSTANCE_MUTEX_NAME = 'Local\LayoutSwitcher.{7D419F5E-2D00-46CB-B50E-48D7F8A070C1}';
  MAIN_FORM_CLASS = 'TFormMain';
  MAIN_FORM_CAPTION_PREFIX = 'LayoutSwitcher';

type
  TInstanceScan = record
    CurrentWindow: HWND;
    LegacyWindows: TArray<HWND>;
  end;
  PInstanceScan = ^TInstanceScan;

function ScanWindow(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var
  Scan: PInstanceScan;
  ProcessID: DWORD;
  Caption: array[0..255] of Char;
begin
  Result := True;
  Scan := PInstanceScan(Param);
  GetWindowThreadProcessId(Wnd, @ProcessID);
  if ProcessID = GetCurrentProcessId then
    Exit;
  if not SameText(GetWindowClassName(Wnd), MAIN_FORM_CLASS) then
    Exit;
  if GetProp(Wnd, INSTANCE_WINDOW_PROP) <> 0 then
  begin
    Scan^.CurrentWindow := Wnd;
    Exit;
  end;
  // Versions before 2.0 have neither the window property nor (before July
  // 2026) the single-instance mutex, so they are recognised by the caption.
  FillChar(Caption, SizeOf(Caption), 0);
  GetWindowText(Wnd, Caption, Length(Caption));
  if Pos(MAIN_FORM_CAPTION_PREFIX, string(Caption)) = 1 then
    Scan^.LegacyWindows := Scan^.LegacyWindows + [Wnd];
end;

function TerminateWindowProcess(Wnd: HWND): Boolean;
var
  ProcessID: DWORD;
  Process: THandle;
begin
  Result := False;
  GetWindowThreadProcessId(Wnd, @ProcessID);
  Process := OpenProcess(PROCESS_TERMINATE or SYNCHRONIZE, False, ProcessID);
  if Process = 0 then
    Exit;
  try
    Result := TerminateProcess(Process, 0) and
      (WaitForSingleObject(Process, 5000) = WAIT_OBJECT_0);
  finally
    CloseHandle(Process);
  end;
end;

// Returns False when this launch must exit.
function ResolveOtherInstances: Boolean;
var
  Scan: TInstanceScan;
  Wnd: HWND;
  Paths: string;
  AllClosed: Boolean;
begin
  Scan.CurrentWindow := 0;
  Scan.LegacyWindows := nil;
  EnumWindows(@ScanWindow, LPARAM(@Scan));

  if Scan.CurrentWindow <> 0 then
  begin
    PostMessage(Scan.CurrentWindow, ShowSettingsMessage, 0, 0);
    Exit(False);
  end;

  if Length(Scan.LegacyWindows) = 0 then
    Exit(True);

  Paths := '';
  for Wnd in Scan.LegacyWindows do
    Paths := Paths + sLineBreak + '  ' + GetWindowProcessPath(Wnd);
  if MessageBox(0, PChar(
       T('Запущена устаревшая версия LayoutSwitcher:',
         'An outdated version of LayoutSwitcher is running:') + Paths + sLineBreak +
       sLineBreak +
       T('Две копии одновременно будут мешать друг другу и другим программам. ' +
         'Закрыть устаревшую версию и запустить эту?',
         'Two copies running at once interfere with each other and with other ' +
         'programs. Close the outdated version and start this one?')),
       'LayoutSwitcher', MB_YESNO or MB_ICONWARNING or MB_SETFOREGROUND) <> IDYES then
    Exit(False);

  AllClosed := True;
  for Wnd in Scan.LegacyWindows do
    AllClosed := TerminateWindowProcess(Wnd) and AllClosed;
  if not AllClosed then
    MessageBox(0, PChar(T('Не удалось закрыть устаревшую версию LayoutSwitcher. ' +
      'Закройте её через значок в трее («Выход») и запустите программу снова.',
      'Could not close the outdated version of LayoutSwitcher. Close it from ' +
      'the tray icon (Exit) and start the program again.')),
      'LayoutSwitcher', MB_OK or MB_ICONERROR);
  Result := AllClosed;
end;

var
  InstanceMutex: THandle;

begin
  {$IFDEF DEBUG}
  // Debug builds report leaked objects when the program exits.
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  if not ResolveOtherInstances then
    Exit;

  InstanceMutex := CreateMutex(nil, True, INSTANCE_MUTEX_NAME);
  if (InstanceMutex = 0) or (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    if InstanceMutex <> 0 then
      CloseHandle(InstanceMutex);
    MessageBox(0, PChar(T('LayoutSwitcher уже запущен.',
      'LayoutSwitcher is already running.')), 'LayoutSwitcher',
      MB_OK or MB_ICONINFORMATION);
    Exit;
  end;

  try
    Application.Initialize;
    InitializeDiagnostics;
    try
      try
        Application.MainFormOnTaskbar := False;
        Application.ShowMainForm := False;
        Application.Title := 'LayoutSwitcher';
        Application.CreateForm(TFormMain, FormMain);
        DiagnosticsLog('application.run enter');
        Application.Run;
        DiagnosticsLogFmt('application.run leave terminated=%s',
          [BoolToStr(Application.Terminated, True)]);
      except
        on E: Exception do
        begin
          DiagnosticsMarkAbnormal;
          DiagnosticsCaptureException('project.main', E, ExceptAddr);
          raise;
        end;
      end;
    finally
      try
        try
          if Assigned(FormMain) then
          begin
            DiagnosticsLog('application.free_main_form begin');
            FreeAndNil(FormMain);
            DiagnosticsLog('application.free_main_form end');
          end;
        except
          on E: Exception do
          begin
            DiagnosticsMarkAbnormal;
            DiagnosticsCaptureException('project.free_main_form', E, ExceptAddr);
            raise;
          end;
        end;
      finally
        ShutdownDiagnostics;
      end;
    end;
  finally
    CloseHandle(InstanceMutex);
  end;
end.
