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

  /// <summary>
  ///   The contract of Ping Target: "a harmless round trip [...] and leaves
  ///   nothing behind". These tests drive a plain TSlimExecutor - what a SUT
  ///   answers with - and send it SlimProxyPingStatement, i.e. the very
  ///   instruction the proxy puts on the wire, not a copy of it. The proxy itself
  ///   is deliberately NOT involved: the question is what the forwarded
  ///   instruction leaves behind in the context of the target.
  /// </summary>
  [TestFixture]
  TestSlimProxyPingContract = class(TestExecBase)
  private
    function  ExecuteSingle(AExecutor: TSlimExecutor; const AId: String; AStmt: TSlimList): String;
    function  MakeStmt(const AId, AInstance, AClass: String): TSlimList;
    procedure Ping(AExecutor: TSlimExecutor);
    procedure RunOnTarget(const ARun: TProc<TSlimExecutor>);
  public // Controls - fixture name resolution in the target
    [Test]
    procedure BareFixtureNameResolvesWithoutAnyImport;
    [Test]
    procedure QualifiedFixtureNameAlwaysResolves;
  public // The contract of the probe
    [Test]
    procedure PingIsAnsweredByANoInstanceResult;
    [Test]
    procedure PingMustNotRegisterANamespaceInTheTarget;
    [Test]
    procedure PingMustNotAccumulateNamespaces;
    [Test]
    procedure PingMustNotBreakBareFixtureNames;
  public // The import itself must not pile up either
    [Test]
    procedure RepeatedImportOfTheSameNamespaceIsRegisteredOnce;
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

{ TestSlimProxyPingContract }

procedure TestSlimProxyPingContract.RunOnTarget(const ARun: TProc<TSlimExecutor>);
begin
  // ONE executor for the whole test: TSlimExecutor.Destroy calls
  // TSlimStatementContext.Clear, and these tests are about exactly what SURVIVES
  // in that context between two forwarded batches.
  var Executor: TSlimExecutor := TSlimExecutor.Create(FContext);
  try
    ARun(Executor);
  finally
    Executor.Free;
  end;
end;

function TestSlimProxyPingContract.ExecuteSingle(AExecutor: TSlimExecutor; const AId: String;
  AStmt: TSlimList): String;
var
  LResult: TSlimList;
begin
  var Response: TSlimList := FGarbage.Collect(AExecutor.Execute(FGarbage.Collect(SlimList([AStmt]))));
  Assert.AreEqual(1, Response.Count, 'one statement must yield exactly one result');
  Assert.IsTrue(TryGetSlimListById(Response, AId, LResult), 'no result for ' + AId);
  Result := LResult[1].ToString;
end;

function TestSlimProxyPingContract.MakeStmt(const AId, AInstance, AClass: String): TSlimList;
begin
  Result := SlimList([AId, 'make', AInstance, AClass]);
end;

/// <summary>
///   Sends the probe of Ping Target. ExecuteSingle already asserts that exactly
///   one result came back under the id of the probe, which is the round trip.
///   The SHAPE of the answer is deliberately NOT asserted here - that belongs to
///   PingIsAnsweredByANoInstanceResult, so that a change of the probe fails the
///   tests below on their own subject and not on a shadowing assertion.
/// </summary>
procedure TestSlimProxyPingContract.Ping(AExecutor: TSlimExecutor);
begin
  ExecuteSingle(AExecutor, SlimProxyPingId, SlimProxyPingStatement);
end;

/// <summary>
///   Pins the shape of the probe: a 'call' on an instance nobody creates, so the
///   target answers NO_INSTANCE. Not a defect but the point - it walks the whole
///   statement pipeline of the target and writes nothing. Should this ever fail
///   because the instance DOES exist, the reserved name in SlimProxyPingInstance
///   has to change.
/// </summary>
procedure TestSlimProxyPingContract.PingIsAnsweredByANoInstanceResult;
begin
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      Assert.Contains(ExecuteSingle(AExecutor, SlimProxyPingId, SlimProxyPingStatement),
        'NO_INSTANCE', 'the probe must be answered, and answered without writing anything');
    end);
end;

procedure TestSlimProxyPingContract.BareFixtureNameResolvesWithoutAnyImport;
begin
  // Control. 'Division' is registered as eg.Division, and without any import the
  // resolver matches a fixture by its simple name. This is what a ping must not
  // take away.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      Assert.AreEqual('OK', ExecuteSingle(AExecutor, 'id_1', MakeStmt('id_1', 'inst_1', 'Division')));
    end);
end;

procedure TestSlimProxyPingContract.QualifiedFixtureNameAlwaysResolves;
begin
  // Control: a fully qualified name is matched before the import branch is
  // reached, so it resolves regardless of what is imported.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      Ping(AExecutor);
      Assert.AreEqual('OK', ExecuteSingle(AExecutor, 'id_1', MakeStmt('id_1', 'inst_1', 'eg.Division')));
    end);
end;

procedure TestSlimProxyPingContract.PingMustNotRegisterANamespaceInTheTarget;
begin
  // The probe used to be an 'import', and TSlimStmtImport registers its path in
  // the context of the target unconditionally - so it could never be the
  // harmless round trip Ping Target claims it is.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      Assert.AreEqual(0, FContext.ImportedNamespaces.Count, 'no import before the ping');
      Ping(AExecutor);
      Assert.AreEqual(0, FContext.ImportedNamespaces.Count,
        'CONTRACT: a ping must leave the context of the target untouched');
    end);
end;

procedure TestSlimProxyPingContract.PingMustNotAccumulateNamespaces;
begin
  // A suite pings on every page. Whatever the probe does, it must not pile
  // anything up over the lifetime of the connection.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      for var Loop: Integer := 1 to 3 do
        Ping(AExecutor);
      Assert.AreEqual(0, FContext.ImportedNamespaces.Count,
        Format('CONTRACT: three pings must not pile up namespaces, found %d',
          [FContext.ImportedNamespaces.Count]));
    end);
end;

procedure TestSlimProxyPingContract.PingMustNotBreakBareFixtureNames;
begin
  // THE regression guard. As soon as ANY namespace is imported,
  // TSlimFixtureResolver switches its "match by simple name" branch off and only
  // matches a simple name WITHIN an imported namespace. A probe that imports
  // therefore silently takes unqualified fixture names away from the target -
  // for the whole lifetime of the connection, with the failure surfacing on some
  // later page as NO_CLASS.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      Assert.AreEqual('OK', ExecuteSingle(AExecutor, 'id_1', MakeStmt('id_1', 'inst_1', 'Division')),
        'control: the bare name resolves before the ping');

      Ping(AExecutor);

      Assert.AreEqual('OK', ExecuteSingle(AExecutor, 'id_2', MakeStmt('id_2', 'inst_2', 'Division')),
        'CONTRACT: a ping must leave fixture name resolution in the target untouched');
    end);
end;

procedure TestSlimProxyPingContract.RepeatedImportOfTheSameNamespaceIsRegisteredOnce;
begin
  // Independent of the probe: a real 'import' that arrives more than once must
  // not grow the list either.
  RunOnTarget(
    procedure(AExecutor: TSlimExecutor)
    begin
      for var Loop: Integer := 1 to 3 do
        Assert.AreEqual('OK', ExecuteSingle(AExecutor, 'id_imp', SlimList(['id_imp', 'import', 'ns1'])));
      Assert.AreEqual(1, FContext.ImportedNamespaces.Count, 'the same namespace is registered once');
      Assert.AreEqual('ns1', FContext.ImportedNamespaces[0]);
    end);
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxy);
TDUnitX.RegisterTestFixture(TestSlimProxyPingContract);

end.
