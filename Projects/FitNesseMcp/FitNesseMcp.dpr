program FitNesseMcp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  FitNesseMcp.Server in 'Source\FitNesseMcp.Server.pas',
  FitNesseMcp.Config in 'Source\FitNesseMcp.Config.pas',
  FitNesseMcp.FitNesseClient in 'Source\FitNesseMcp.FitNesseClient.pas';

var
  Server: TFitNesseMcpServer;
begin
  try
    // Keinerlei mORMot-Logs auf stdout!
    Server := TFitNesseMcpServer.Create;
    try
      Server.Run;
    finally
      Server.Free;
    end;
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.
