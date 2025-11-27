unit Test.SlimProxy;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Slim.Common,
  Slim.List,
  Slim.Exec,
  Slim.Proxy,
  Slim.Proxy.Fixtures,
  Test.SlimExec;

type
  [TestFixture]
  TestSlimProxy = class(TestExecBase)
  private
    procedure Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
  public
    [Test]
    procedure MakeSlimProxy;
    [Test]
    procedure ProxyMethodsCallExecutor;
    [Test]
    procedure IsProxyCommand_Import;
  end;

implementation

uses
  System.Rtti;

{ TestSlimProxy }

procedure TestSlimProxy.Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
var
  Executor: TSlimProxyExecutor;
  ExecutorHolder: IInterface;
begin
  Executor := TSlimProxyExecutor.Create(FContext);
  ExecutorHolder := Executor; // Hold reference to manage lifetime
  var Response: TSlimList := nil;
  try
    Response := Executor.Execute(AStmts);
    if Assigned(ACheckResponseProc) then
      ACheckResponseProc(Response);
  finally
    Response.Free;
    // Executor will be freed when ExecutorHolder and other references (in fixtures) go out of scope
  end;
end;

procedure TestSlimProxy.MakeSlimProxy;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(1, AResponse.Count);
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);

      // Verify instance exists in context
      Assert.IsTrue(FContext.Instances.ContainsKey('proxy_instance'));
      Assert.IsTrue(FContext.Instances['proxy_instance'] is TSlimProxyFixture);
    end);
end;

procedure TestSlimProxy.ProxyMethodsCallExecutor;
begin
  // This test verifies that:
  // 1. 'make' injects the executor into the fixture.
  // 2. Calling a method on the fixture (like AddTarget) executes without "Executor not assigned" exception.
  //    If the executor wasn't injected, TSlimProxyFixture.AddTarget would raise an exception.
  //    We are NOT connecting to a real target here, just adding a definition.

  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy']),
      SlimList(['id_2', 'call', 'proxy_instance', 'ConnectToTarget', 'Target1', 'localhost', '8080'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(2, AResponse.Count);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
      // If successful, it returns VoidResponse (usually empty string or specific void marker?
      // Slim.Exec returns '/__VOID__/' usually, or just 'OK' for make?)
      // Checking Slim.Proxy.Fixtures logic:
      // procedure TSlimProxyFixture.ConnectToTarget... calls FExecutor.AddTarget...
      // AddTarget returns nothing (void).
      Assert.AreEqual(TSlimConsts.VoidResponse, CallResponse[1].ToString);
    end);
end;

procedure TestSlimProxy.IsProxyCommand_Import;
begin
  // Test that 'import' is handled by ProxyExecutor (it should return True in IsProxyCommand)
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'import', 'Slim.Proxy.Fixtures'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(1, AResponse.Count);
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);
    end);
end;

initialization
  TDUnitX.RegisterTestFixture(TestSlimProxy);

end.
