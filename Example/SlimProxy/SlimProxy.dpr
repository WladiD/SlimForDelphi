program SlimProxy;

{$APPTYPE CONSOLE}


uses
  System.SysUtils,
  Slim.Server,
  Slim.Proxy,
  Slim.Proxy.Fixtures,
  Slim.Common,
  Slim.Exec;

var
  LPort: Integer = 8085;
  LServer: TSlimServer;
  I: Integer;
  LArg: string;
begin
  try
    ReportMemoryLeaksOnShutdown := True;

    Writeln('SlimProxy starting...');

    // Parse command line arguments
    for I := 1 to ParamCount do
    begin
      LArg := ParamStr(I);
      if SameText(LArg, '-port') and (I + 1 <= ParamCount) then
      begin
        LPort := StrToIntDef(ParamStr(I + 1), LPort);
      end;
    end;

    Writeln('Using Port: ', LPort);

    // Start the server with the proxy executor
    LServer := TSlimServer.Create;
    try
      LServer.DefaultPort := LPort;
      LServer.ExecutorClass := TSlimProxyExecutor;
      LServer.Active := True;

      Writeln('SlimProxy running on port ', LPort, '. Press Enter to exit.');
      // Wait for user input to terminate
      Readln;
    finally
      Writeln('SlimProxy shutting down...');
      LServer.Free;
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
