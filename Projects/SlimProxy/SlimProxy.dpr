// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

program SlimProxy;

{$APPTYPE CONSOLE}

uses

  System.SysUtils,

  IdContext,

  Slim.CmdUtils,
  Slim.Common,
  Slim.Exec,
  Slim.Logger,
  Slim.Proxy,
  Slim.Proxy.Core.Fixture,
  Slim.Proxy.Process.Fixture,
  Slim.Proxy.VirtualBox.Fixture,
  Slim.Proxy.Interfaces,
  Slim.Server;

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
  LPort: Integer;
  LServer: TSlimServer;
begin
  try
    ReportMemoryLeaksOnShutdown := True;

    Writeln('SlimProxy starting...');

    if not HasSlimPortParam(LPort) then
      LPort := 9000; // Default port if no --SlimPort=X is provided

    Writeln('Using Port: ', LPort);

    // Start the server with the proxy executor
    LServer := TSlimServer.Create;
    try
      LServer.DefaultPort := LPort;
      LServer.Logger := TSlimFileLogger.Create(Format('Logs\SlimProxy_%s.log', [FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now)]));
      LServer.OnConnect := TLogger.OnConnect;
      LServer.OnException := TLogger.OnException;
      LServer.ExecutorClass := TSlimProxyExecutor;
      LServer.Active := True;

      Writeln('SlimProxy running on port ', LPort, '. Press Ctrl+C to exit. IsConsole=', IsConsole);

      // Wait loop - simply sleep until terminated
      while LServer.Active do
      begin
        if SlimProxyStopRequested then
        begin
          LServer.Active := False;
          Break;
        end;
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
