unit Slim.Proxy.Interfaces;

interface

var
  SlimProxyStopRequested: Boolean = False;

type

  ISlimProxyExecutor = interface
    ['{B4B384E2-2B8A-4A7B-9D3A-28B0D3B0E8D1}']
    procedure AddTarget(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    procedure SwitchToTarget(const AName: String);
  end;

implementation

end.
