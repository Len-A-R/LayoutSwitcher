program LS;

uses
  Winapi.Windows,
  Vcl.Forms,
  uMain in 'uMain.pas' {Form1};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := False;
  Application.ShowMainForm := False;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
