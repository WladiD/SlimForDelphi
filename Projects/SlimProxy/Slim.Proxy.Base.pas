unit Slim.Proxy.Base;

interface

uses

  Slim.Fixture,
  Slim.Proxy.Interfaces;

type

  TSlimProxyBaseFixture = class(TSlimFixture)
  protected
    FExecutor: ISlimProxyExecutor;
  public
    property Executor: ISlimProxyExecutor read FExecutor write FExecutor;
  end;

implementation

end.
