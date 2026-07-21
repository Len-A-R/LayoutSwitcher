program LS;

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  uDiagnostics in 'uDiagnostics.pas',
  uUIAutomation in 'uUIAutomation.pas',
  uMain in 'uMain.pas' {Form1};

{$R *.res}

const
  INSTANCE_MUTEX_NAME = 'Local\LayoutSwitcher.{7D419F5E-2D00-46CB-B50E-48D7F8A070C1}';

var
  InstanceMutex: THandle;

begin
  InstanceMutex := CreateMutex(nil, True, INSTANCE_MUTEX_NAME);
  if (InstanceMutex = 0) or (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    if InstanceMutex <> 0 then
      CloseHandle(InstanceMutex);
    Exit;
  end;

  try
    Application.Initialize;
    InitializeDiagnostics;
    try
      try
        Application.MainFormOnTaskbar := False;
        Application.ShowMainForm := False;
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
