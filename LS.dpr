program LS;

uses
  Winapi.Windows,
  Vcl.Forms,
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
    Application.MainFormOnTaskbar := False;
    Application.ShowMainForm := False;
    Application.CreateForm(TFormMain, FormMain);
    Application.Run;
  finally
    CloseHandle(InstanceMutex);
  end;
end.
