program LSTests;

// DUnitX console runner for the platform-independent parts of LayoutSwitcher:
// layout conversion, case changes, the gesture state machine and settings.
// Build and run with Tests\run-tests.cmd.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  uSettings in '..\uSettings.pas',
  uGestureDetector in '..\uGestureDetector.pas',
  uLayoutConverter in '..\uLayoutConverter.pas',
  uConversionChain in '..\uConversionChain.pas',
  TestLayoutConverter in 'TestLayoutConverter.pas',
  TestGestureDetector in 'TestGestureDetector.pas',
  TestConversionChain in 'TestConversionChain.pas',
  TestFeatures21 in 'TestFeatures21.pas',
  TestFeatures22 in 'TestFeatures22.pas',
  TestFeatures23 in 'TestFeatures23.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 2;
    end;
  end;
end.
