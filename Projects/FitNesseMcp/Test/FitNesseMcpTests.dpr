program FitNesseMcpTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  FitNesseMcp.Config in '..\Source\FitNesseMcp.Config.pas',
  FitNesseMcp.FitNesseClient in '..\Source\FitNesseMcp.FitNesseClient.pas',
  FitNesseMcp.Server in '..\Source\FitNesseMcp.Server.pas',
  FitNesseMcp.Server.Tests in 'FitNesseMcp.Server.Tests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
begin
  try
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    logger := TDUnitXConsoleLogger.Create(True);
    runner.AddLogger(logger);

    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
