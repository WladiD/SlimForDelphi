// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   SlimProxy.Core - targets, routing and time limits.
///
///   Everything that has to do with starting, watching and closing a GUI host
///   lives in SlimProxy.Host, so that Core does not become the place where
///   everything is dumped.
/// </summary>
unit Slim.Proxy.Core.Fixture;

interface

uses

  Winapi.Windows,

  System.SysUtils,

  Slim.Common,
  Slim.Fixture,
  Slim.Proxy.Base,
  Slim.Proxy.Config,
  Slim.Proxy.Interfaces;

type

  [SlimFixture('Core', 'SlimProxy')]
  TSlimProxyCoreFixture = class(TSlimProxyBaseFixture)
  private
    function CheckedExecutor: ISlimProxyExecutor;
  public // Targets
    procedure ConnectToTarget(const AName, AHost: String; APort: Integer);
    procedure RegisterTarget(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    procedure ReconnectTarget(const AName: String);
    procedure SwitchToTarget(const AName: String);
    function  ActiveTarget: String;
    function  PingTarget(const AName: String): String;
    function  TargetStatus: String;
    procedure SetTargetProcessId(const AName: String; APid: Integer);
    function  TargetProcessId(const AName: String): Integer;
  public // Time limits
    procedure SetConnectTimeout(AMilliseconds: Integer);
    procedure SetReadTimeout(AMilliseconds: Integer);
    procedure SetReadTimeoutForNextCall(AMilliseconds: Integer);
    function  ConnectTimeout: Integer;
    function  ReadTimeout: Integer;
  public // Diagnostics and process control
    function  LastWatchdogReport: String;
    procedure StartProcess(const APath, AArgs: String);
    procedure StartProcessIn(const APath, AArgs, AWorkingDir: String);
    procedure StopProxy;
  end;

implementation

{ TSlimProxyCoreFixture }

function TSlimProxyCoreFixture.CheckedExecutor: ISlimProxyExecutor;
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  Result := FExecutor;
end;

/// <summary>Registers a target and connects right away.</summary>
procedure TSlimProxyCoreFixture.ConnectToTarget(const AName, AHost: String; APort: Integer);
begin
  CheckedExecutor.AddTarget(AName, AHost, APort);
end;

/// <summary>
///   Registers a target WITHOUT connecting. The connection is established with
///   the first forwarded command, so the host may still be starting.
/// </summary>
procedure TSlimProxyCoreFixture.RegisterTarget(const AName, AHost: String; APort: Integer);
begin
  CheckedExecutor.AddTargetDeferred(AName, AHost, APort);
end;

procedure TSlimProxyCoreFixture.DisconnectTarget(const AName: String);
begin
  CheckedExecutor.DisconnectTarget(AName);
end;

/// <summary>Takes a target that was marked broken back into service.</summary>
procedure TSlimProxyCoreFixture.ReconnectTarget(const AName: String);
begin
  CheckedExecutor.ReconnectTarget(AName);
end;

procedure TSlimProxyCoreFixture.SwitchToTarget(const AName: String);
begin
  CheckedExecutor.SwitchToTarget(AName);
end;

function TSlimProxyCoreFixture.ActiveTarget: String;
begin
  Result := CheckedExecutor.ActiveTargetName;
end;

/// <summary>
///   Sends a harmless round trip to a target and answers 'OK', or the diagnosis
///   if it failed - it does NOT raise. Use it to assert the state of a target
///   from a test page instead of letting the page just go red.
/// </summary>
function TSlimProxyCoreFixture.PingTarget(const AName: String): String;
begin
  Result := CheckedExecutor.PingTarget(AName);
end;

/// <summary>Name, address, process id and broken cause of every target.</summary>
function TSlimProxyCoreFixture.TargetStatus: String;
begin
  Result := CheckedExecutor.TargetStatus;
end;

/// <summary>
///   Binds a target to the process id of its host so the watchdog knows whose
///   windows to observe. For a target on this machine the proxy determines this
///   itself from the owner of the listening socket.
/// </summary>
procedure TSlimProxyCoreFixture.SetTargetProcessId(const AName: String; APid: Integer);
begin
  CheckedExecutor.SetTargetProcessId(AName, Cardinal(APid));
end;

function TSlimProxyCoreFixture.TargetProcessId(const AName: String): Integer;
begin
  Result := Integer(CheckedExecutor.GetTargetProcessId(AName));
end;

/// <summary>Wait window for establishing a connection to a target, in ms.</summary>
procedure TSlimProxyCoreFixture.SetConnectTimeout(AMilliseconds: Integer);
begin
  SlimProxyConnectTimeout := AMilliseconds;
  CheckedExecutor.SetConnectTimeout(AMilliseconds);
end;

/// <summary>
///   Time limit for reading an answer, in ms. 0 = unlimited. Without a limit a
///   modal dialog in the host blocks the whole run, and FitNesse has no read
///   timeout of its own either - the proxy is the only place where this can be
///   fixed.
/// </summary>
procedure TSlimProxyCoreFixture.SetReadTimeout(AMilliseconds: Integer);
begin
  SlimProxyReadTimeout := AMilliseconds;
  CheckedExecutor.SetReadTimeout(AMilliseconds);
end;

/// <summary>
///   Raises the read timeout for the NEXT call only. A long but legitimate
///   calculation must not be cut off by the limit that exists to catch a blocked
///   host.
/// </summary>
procedure TSlimProxyCoreFixture.SetReadTimeoutForNextCall(AMilliseconds: Integer);
begin
  CheckedExecutor.SetReadTimeoutForNextCall(AMilliseconds);
end;

function TSlimProxyCoreFixture.ConnectTimeout: Integer;
begin
  Result := CheckedExecutor.GetConnectTimeout;
end;

function TSlimProxyCoreFixture.ReadTimeout: Integer;
begin
  Result := CheckedExecutor.GetReadTimeout;
end;

/// <summary>Findings of the watchdog during the last forwarded call.</summary>
function TSlimProxyCoreFixture.LastWatchdogReport: String;
begin
  Result := CheckedExecutor.LastWatchdogReport;
  if Result = '' then
    Result := '(no findings)';
end;

/// <summary>
///   Starts a process and returns immediately. It does NOT wait for a Slim port,
///   does not check who owns it and does not dismiss any dialog - use
///   SlimProxy.Host "Start Host And Wait For Slim" for a GUI host.
///   The working directory is the directory of the executable, because GUI
///   applications look for configuration and logs relative to it.
/// </summary>
procedure TSlimProxyCoreFixture.StartProcess(const APath, AArgs: String);
begin
  StartProcessIn(APath, AArgs, '');
end;

/// <summary>Like Start Process, but with an explicit working directory.</summary>
procedure TSlimProxyCoreFixture.StartProcessIn(const APath, AArgs, AWorkingDir: String);
var
  LCmd       : String;
  LPi        : TProcessInformation;
  LSi        : TStartupInfo;
  LWorkingDir: String;
begin
  ZeroMemory(@LSi, SizeOf(LSi));
  LSi.cb := SizeOf(LSi);
  ZeroMemory(@LPi, SizeOf(LPi));

  LCmd := '"' + APath + '" ' + AArgs;

  LWorkingDir := AWorkingDir;
  if LWorkingDir = '' then
    LWorkingDir := ExcludeTrailingPathDelimiter(ExtractFilePath(APath));

  if not CreateProcess(nil, PChar(LCmd), nil, nil, False, 0, nil, PChar(LWorkingDir), LSi, LPi) then
    RaiseLastOSError;

  CloseHandle(LPi.hProcess);
  CloseHandle(LPi.hThread);
end;

procedure TSlimProxyCoreFixture.StopProxy;
begin
  SlimProxyStopRequested := True;
end;

initialization

RegisterSlimFixture(TSlimProxyCoreFixture);

end.
