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
  Slim.Proxy.Config,
  Slim.Proxy.Core.Fixture,
  Slim.Proxy.Host.Fixture,
  Slim.Proxy.Interfaces,
  Slim.Proxy.Mcp.Fixture in 'Slim.Proxy.Mcp.Fixture.pas',
  Slim.Proxy.Process.Fixture,
  Slim.Proxy.StringTester.Fixture,
  Slim.Proxy.VirtualBox.Fixture,
  Slim.Proxy.Watchdog,
  Slim.Proxy.WinTools,
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

/// <summary>True if AParam is "--AName=<value>"; AValue then carries the value.</summary>
function TryGetSwitch(const AParam, AName: String; out AValue: String): Boolean;
begin
  Result := AParam.StartsWith('--' + AName + '=', True);
  if Result then
    AValue := AParam.Substring(Length(AName) + 3);
end;

procedure WriteUsage;
begin
  Writeln('Usage: SlimProxy.exe [options]');
  Writeln;
  Writeln('  --SlimPort=<port>          Port the proxy itself listens on (default 9000).');
  Writeln('  --Target=Name=Host:Port    Target to forward to, may be given more than once.');
  Writeln('                             The first one is active. Connected lazily, so the');
  Writeln('                             target host may still be starting.');
  Writeln('  --ConnectTimeout=<ms>      Wait window for connecting to a target.');
  Writeln('  --ReadTimeout=<ms>         Time limit for reading an answer, 0 = unlimited.');
  Writeln('  --Watchdog[=on|off]        Watch the target windows while a call is pending.');
  Writeln('  --PostStartDismiss=<ms>    Keep dismissing dialogs after the Slim port came up.');
  Writeln('  --DismissButtons=<list>    Button captions that may be clicked away.');
  Writeln('  --ButtonClasses=<list>     Window classes that count as a push button.');
  Writeln('  --ButtonClassContains=<l>  Substrings that mark a class as a push button.');
  Writeln('  --AbortWindows=<list>      Classes/titles that prove Slim will never come up.');
  Writeln('  --ErrorPatterns=<list>     Wordings that mark a message window as an error.');
  Writeln('  --FatalPatterns=<list>     Wordings that mean: abort the run.');
  Writeln('  --ExemptWindows=<list>     Windows the watchdog never touches.');
  Writeln('  --Help                     This text.');
  Writeln;
  Writeln('Lists are semicolon separated. Every default lives as a named constant in');
  Writeln('Slim.Proxy.Config.pas - the proxy knows nothing about a particular application.');
  Flush(Output);
end;

procedure ParseProxyParams;
var
  LNum   : Integer;
  LParam : String;
  LTarget: TSlimProxyStartupTarget;
  LValue : String;
begin
  for var I: Integer := 1 to ParamCount do
  begin
    LParam := ParamStr(I);

    if SameText(LParam, '--Help') or SameText(LParam, '-h') or SameText(LParam, '/?') then
      WriteUsage
    else if TryGetSwitch(LParam, 'Target', LValue) then
    begin
      var LEq: Integer := LValue.IndexOf('=');
      if LEq < 0 then
        raise Exception.CreateFmt('Invalid --Target (expected Name=Host:Port): "%s"', [LValue]);
      LTarget.Name := LValue.Substring(0, LEq);
      var LHostPort: String := LValue.Substring(LEq + 1);
      var LColon: Integer := LHostPort.LastIndexOf(':');
      if (LColon < 0) or not TryStrToInt(LHostPort.Substring(LColon + 1), LTarget.Port) then
        raise Exception.CreateFmt('Invalid --Target (expected Name=Host:Port): "%s"', [LValue]);
      LTarget.Host := LHostPort.Substring(0, LColon);
      SlimProxyStartupTargets := SlimProxyStartupTargets + [LTarget];
      Writeln(Format('Startup target: %s -> %s:%d', [LTarget.Name, LTarget.Host, LTarget.Port]));
    end
    else if TryGetSwitch(LParam, 'ConnectTimeout', LValue) then
    begin
      if TryStrToInt(LValue, LNum) then
        SlimProxyConnectTimeout := LNum;
      Writeln('ConnectTimeout: ', SlimProxyConnectTimeout, ' ms');
    end
    else if TryGetSwitch(LParam, 'ReadTimeout', LValue) then
    begin
      if TryStrToInt(LValue, LNum) then
        SlimProxyReadTimeout := LNum;
      Writeln('ReadTimeout: ', SlimProxyReadTimeout, ' ms (0 = unlimited)');
    end
    else if TryGetSwitch(LParam, 'PostStartDismiss', LValue) then
    begin
      if TryStrToInt(LValue, LNum) then
        SlimProxyPostStartDismissMs := LNum;
      Writeln('PostStartDismiss: ', SlimProxyPostStartDismissMs, ' ms');
    end
    else if TryGetSwitch(LParam, 'Watchdog', LValue) then
    begin
      SlimProxyWatchdogEnabled := not (SameText(LValue, 'off') or SameText(LValue, '0') or
                                       SameText(LValue, 'false'));
      Writeln('Watchdog: ', BoolToStr(SlimProxyWatchdogEnabled, True));
    end
    else if SameText(LParam, '--Watchdog') then
    begin
      SlimProxyWatchdogEnabled := True;
      Writeln('Watchdog: enabled');
    end
    else if TryGetSwitch(LParam, 'DismissButtons', LValue) then
      SlimProxyDismissButtons := LValue
    else if TryGetSwitch(LParam, 'ButtonClasses', LValue) then
      SlimProxyButtonClasses := LValue
    else if TryGetSwitch(LParam, 'ButtonClassContains', LValue) then
      SlimProxyButtonClassContains := LValue
    else if TryGetSwitch(LParam, 'AbortWindows', LValue) then
      SlimProxyAbortWindows := LValue
    else if TryGetSwitch(LParam, 'ErrorPatterns', LValue) then
      SlimProxyErrorPatterns := LValue
    else if TryGetSwitch(LParam, 'FatalPatterns', LValue) then
      SlimProxyFatalPatterns := LValue
    else if TryGetSwitch(LParam, 'ExemptWindows', LValue) then
      SlimProxyExemptWindows := LValue;
  end;
  Flush(Output);
end;

var
  LPort  : Integer;
  LServer: TSlimServer;
begin
  try
    ReportMemoryLeaksOnShutdown := True;

    Writeln('SlimProxy starting...');

    if not HasSlimPortParam(LPort) then
      LPort := 9000; // Default port if no --SlimPort=X is provided

    ParseProxyParams;

    Writeln('Using Port: ', LPort);

    // Start the server with the proxy executor
    LServer := TSlimServer.Create;
    try
      LServer.DefaultPort := LPort;
      LServer.Logger := TSlimFileLogger.Create(Format('Logs\SlimProxy_%s.log',
        [FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now)]));
      LServer.OnConnect := TLogger.OnConnect;
      LServer.OnException := TLogger.OnException;
      LServer.ExecutorClass := TSlimProxyExecutor;
      LServer.Active := True;

      Writeln('SlimProxy running on port ', LPort, '. Press Ctrl+C to exit. IsConsole=', IsConsole);
      Flush(Output);

      // Wait loop - simply sleep until terminated. Polled in short slices, so a
      // "Stop Proxy" from a SuiteTearDown page ends the process promptly: a
      // launcher script cannot clean up the host behind us before we are gone,
      // and FitNesse already starts the next test system.
      while LServer.Active do
      begin
        if SlimProxyStopRequested then
        begin
          LServer.Active := False;
          Break;
        end;
        Sleep(100);
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
