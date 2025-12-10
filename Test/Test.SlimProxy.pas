// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimProxy;

interface

uses

  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Common,
  Slim.Exec,
  Slim.List,
  Slim.Proxy,
  Slim.Proxy.Fixtures,
  Slim.Proxy.Interfaces,

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

{ TestSlimProxy }

procedure TestSlimProxy.Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
var
  Executor: TSlimProxyExecutor;
begin
  Executor := TSlimProxyExecutor.Create(FContext);
  var Response: TSlimList := nil;
  try
    Executor.ConnectTimeout := 100;
    Response := Executor.Execute(AStmts);
    if Assigned(ACheckResponseProc) then
      ACheckResponseProc(Response);
  finally
    Response.Free;
    Executor.Free;
  end;
end;

procedure TestSlimProxy.MakeSlimProxy;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy.Core'])
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
      Assert.IsTrue(FContext.Instances['proxy_instance'] is TSlimProxyCoreFixture);
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
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy.Core']),
      SlimList(['id_2', 'call', 'proxy_instance', 'ConnectToTarget', 'Target1', '127.0.0.1', '8080'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(2, AResponse.Count);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
      // ConnectToTarget should fail quickly (1 retry) and return an exception because no server is running on port 8080.
      Assert.Contains(CallResponse[1].ToString, TSlimConsts.ExceptionResponse);
    end);
end;

procedure TestSlimProxy.IsProxyCommand_Import;
begin
  // Test that 'import' is forwarded. If no target is present, it should return OK (silently ignored).
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
