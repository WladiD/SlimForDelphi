program SlimProxy;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  IdContext,
  Slim.Server,
  Slim.Proxy,
  Slim.Proxy.Fixtures,
  Slim.Common,
  Slim.Exec,
  Slim.CmdUtils;

type
  TLogger = class
    class procedure OnConnect(AContext: TIdContext);
    class procedure OnException(AContext: TIdContext; AException: Exception);
  end;

class procedure TLogger.OnConnect(AContext: TIdContext);
begin
  Writeln('Incoming connection from: ' + AContext.Binding.PeerIP);
  Flush(Output);
end;

class procedure TLogger.OnException(AContext: TIdContext; AException: Exception);
begin
  Writeln('Server Exception: ' + AException.Message);
  Flush(Output);
end;

var
  LPort: Integer = 8085;
  LServer: TSlimServer;
begin
  try
    ReportMemoryLeaksOnShutdown := True;

    Writeln('SlimProxy starting...');

    if not HasSlimPortParam(LPort) then
      LPort := 8085; // Default port if no --SlimPort=X is provided

    Writeln('Using Port: ', LPort);

    // Start the server with the proxy executor
    LServer := TSlimServer.Create;
    try
      LServer.DefaultPort := LPort;
      LServer.OnConnect := TLogger.OnConnect;
      LServer.OnException := TLogger.OnException;

      LServer.ExecutorClass := TSlimProxyExecutor;
      LServer.Active := True;

      Writeln('SlimProxy running on port ', LPort, '. Press Ctrl+C to exit. IsConsole=', IsConsole);

      // Wait loop - simply sleep until terminated
      while LServer.Active do
      begin
        Sleep(1000);
      end;
    finally
      Writeln('SlimProxy shutting down...');
      LServer.Free;
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
