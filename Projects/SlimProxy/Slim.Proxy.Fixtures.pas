// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.Fixtures;

interface

uses

  Winapi.Windows,

  System.SysUtils,

  Slim.Common,
  Slim.Fixture,
  Slim.Proxy.Base,
  Slim.Proxy.Interfaces;

type

  [SlimFixture('Core', 'SlimProxy')]
  TSlimProxyCoreFixture = class(TSlimProxyBaseFixture)
  public
    procedure ConnectToTarget(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    procedure StartProcess(const APath, AArgs: String);
    procedure SwitchToTarget(const AName: String);
  end;

implementation

{ TSlimProxyCoreFixture }

procedure TSlimProxyCoreFixture.StartProcess(const APath, AArgs: String);
var
  SI : TStartupInfo;
  PI : TProcessInformation;
  Cmd: String;
begin
  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  ZeroMemory(@PI, SizeOf(PI));

  Cmd := '"' + APath + '" ' + AArgs;

  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, nil, SI, PI) then
    RaiseLastOSError;

  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
end;

procedure TSlimProxyCoreFixture.ConnectToTarget(const AName, AHost: String; APort: Integer);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.AddTarget(AName, AHost, APort);
end;

procedure TSlimProxyCoreFixture.SwitchToTarget(const AName: String);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.SwitchToTarget(AName);
end;

procedure TSlimProxyCoreFixture.DisconnectTarget(const AName: String);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.DisconnectTarget(AName);
end;

initialization

RegisterSlimFixture(TSlimProxyCoreFixture);

end.
