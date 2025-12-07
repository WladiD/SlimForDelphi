// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
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
  Slim.Proxy.Interfaces;

type

  [SlimFixture('SlimProxy')]
  TSlimProxyFixture = class(TSlimFixture)
  private
    FExecutor: ISlimProxyExecutor;
  public
    procedure ConnectToTarget(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    procedure StartProcess(const APath, AArgs: String);
    procedure SwitchToTarget(const AName: String);
    property  Executor: ISlimProxyExecutor write FExecutor;
  end;

implementation

{ TSlimProxyFixture }

procedure TSlimProxyFixture.StartProcess(const APath, AArgs: String);
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

procedure TSlimProxyFixture.ConnectToTarget(const AName, AHost: String; APort: Integer);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.AddTarget(AName, AHost, APort);
end;

procedure TSlimProxyFixture.SwitchToTarget(const AName: String);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.SwitchToTarget(AName);
end;

procedure TSlimProxyFixture.DisconnectTarget(const AName: String);
begin
  if not Assigned(FExecutor) then
    raise ESlim.Create('Executor not assigned');
  FExecutor.DisconnectTarget(AName);
end;

initialization

  RegisterSlimFixture(TSlimProxyFixture);

end.
