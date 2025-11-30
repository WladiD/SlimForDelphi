unit Slim.Proxy.Fixtures;

interface

uses
  System.SysUtils,
  Slim.Fixture;

type
  ISlimProxyExecutor = interface
    ['{B4B384E2-2B8A-4A7B-9D3A-28B0D3B0E8D1}']
    procedure AddTarget(const AName, AHost: string; APort: Integer);
    procedure SwitchToTarget(const AName: string);
    procedure DisconnectTarget(const AName: string);
  end;

  [SlimFixture('SlimProxy')]
  TSlimProxyFixture = class(TSlimFixture)
  private
    FExecutor: ISlimProxyExecutor;
  public
    destructor Destroy; override;
    procedure StartProcess(const APath, AArgs: String);
    procedure ConnectToTarget(const AName, AHost: String; APort: Integer);
    procedure SwitchToTarget(const AName: String);
    procedure DisconnectTarget(const AName: String);
    property  Executor: ISlimProxyExecutor write FExecutor;
  end;

implementation

uses
  Winapi.Windows,
  Slim.Proxy,
  Slim.Common;

{ TSlimProxyFixture }

destructor TSlimProxyFixture.Destroy;
begin
  inherited;
end;

procedure TSlimProxyFixture.StartProcess(const APath, AArgs: String);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
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
  if not Assigned(FExecutor) then raise ESlim.Create('Executor not assigned');
  FExecutor.AddTarget(AName, AHost, APort);
end;

procedure TSlimProxyFixture.SwitchToTarget(const AName: String);
begin
  if not Assigned(FExecutor) then raise ESlim.Create('Executor not assigned');
  FExecutor.SwitchToTarget(AName);
end;

procedure TSlimProxyFixture.DisconnectTarget(const AName: String);
begin
  if not Assigned(FExecutor) then raise ESlim.Create('Executor not assigned');
  FExecutor.DisconnectTarget(AName);
end;

initialization
  RegisterSlimFixture(TSlimProxyFixture);

end.
