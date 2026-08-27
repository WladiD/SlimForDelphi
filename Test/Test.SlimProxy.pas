// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
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
  Slim.Proxy.Config,
  Slim.Proxy.Core.Fixture,
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
  public // Routing local/remote
    [Test]
    procedure MixedSequenceRoutesEachTableCorrectly;
    [Test]
    procedure UnknownInstanceGoesToTheTarget;
    [Test]
    procedure ForwardedMakeDropsTheLocalShadow;
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
  // 2. Calling a method on the fixture (like ConnectToTarget) executes without
  //    an "Executor not assigned" exception. If the executor wasn't injected,
  //    TSlimProxyCoreFixture.ConnectToTarget would raise that exception.
  //    We are NOT connecting to a real target here, just adding a definition.

  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy.Core']),
      SlimList(['id_2', 'call', 'proxy_instance', 'ConnectToTarget', 'Target1', '127.0.0.1', '54321'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(2, AResponse.Count);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
      // ConnectToTarget should fail quickly and return an exception because
      // nothing is listening on that port.
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

procedure TestSlimProxy.MixedSequenceRoutesEachTableCorrectly;
begin
  // FitNesse uses the instance name 'scriptTableActor' for EVERY script table.
  // After a SlimProxy.Core table the local instance used to stay behind, and the
  // next call on that name ran against the proxy instead of the target and ended
  // in NO_METHOD_IN_CLASS. There is no target here, so a forwarded instruction
  // ends in "No active target" - which is exactly the proof that it was routed
  // remotely and not answered locally.
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', TSlimConsts.ScriptTableActor, 'SlimProxy.Core']),
      SlimList(['id_2', 'call', TSlimConsts.ScriptTableActor, 'ActiveTarget']),
      SlimList(['id_3', 'make', TSlimConsts.ScriptTableActor, 'MySutFixture']),
      SlimList(['id_4', 'call', TSlimConsts.ScriptTableActor, 'AnswerOfLife'])
    ])),
    procedure(AResponse: TSlimList)
    var
      LResult: TSlimList;
    begin
      Assert.AreEqual(4, AResponse.Count);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', LResult));
      Assert.AreEqual('OK', LResult[1].ToString, 'make SlimProxy.Core must run locally');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', LResult));
      Assert.DoesNotContain(LResult[1].ToString, TSlimConsts.ExceptionResponse,
        'call on the local proxy fixture must run locally');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', LResult));
      Assert.Contains(LResult[1].ToString, 'No active target',
        'make of a target fixture must be forwarded, even on the same instance name');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_4', LResult));
      Assert.Contains(LResult[1].ToString, 'No active target',
        'the call after a forwarded make must be forwarded too');
      Assert.DoesNotContain(LResult[1].ToString, 'NO_METHOD_IN_CLASS',
        'the local instance of the previous table must not answer any more');
    end);
end;

procedure TestSlimProxy.UnknownInstanceGoesToTheTarget;
begin
  // CheckLocalFixtureInstance used to leave the local/remote decision UNCHANGED
  // for an unknown instance name, i.e. on the value of the previous instruction.
  // An unknown instance name always belongs to the target.
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'proxy_instance', 'SlimProxy.Core']),
      SlimList(['id_2', 'call', 'never_created_instance', 'DoSomething'])
    ])),
    procedure(AResponse: TSlimList)
    var
      LResult: TSlimList;
    begin
      Assert.AreEqual(2, AResponse.Count);
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', LResult));
      Assert.Contains(LResult[1].ToString, 'No active target',
        'an unknown instance name must be routed to the target');
    end);
end;

procedure TestSlimProxy.ForwardedMakeDropsTheLocalShadow;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', TSlimConsts.ScriptTableActor, 'SlimProxy.Core']),
      SlimList(['id_2', 'make', TSlimConsts.ScriptTableActor, 'MySutFixture'])
    ])),
    procedure(AResponse: TSlimList)
    begin
      Assert.IsFalse(FContext.Instances.ContainsKey(TSlimConsts.ScriptTableActor),
        'a forwarded make must drop the local instance of the same name');
    end);
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxy);

end.
