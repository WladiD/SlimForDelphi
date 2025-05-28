﻿// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimExec;

interface

uses

  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Common,
  Slim.Exec,
  Slim.Fixture,
  Slim.List,
  Slim.Symbol;

type

  TGarbage = class;

  TestExecBase = class
  protected
    FGarbage: TGarbage;
    FContext: TSlimStatementContext;
  public
    [Setup]
    procedure Setup; virtual;
    [TearDown]
    procedure TearDown; virtual;
  end;

  [TestFixture]
  TestContext = class
  public
    [Test]
    procedure EnsureScriptTableActorsFullInit;
    [Test]
    procedure EnsureScriptTableActorsPartialInit;
  end;

  [TestFixture]
  TestSlimExecutor = class(TestExecBase)
  private
    procedure Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
  protected
    function CreateStmtsFromFile(const AFileName: String): TSlimList;
  public
    [Test]
    procedure AssignSymbol;
    [Test]
    procedure ScriptTableActor;
    [Test]
    procedure StopTestExceptionTest;
    [Test]
    procedure SutOnLibInstance;
    [Test]
    procedure TwoMinuteExample;
  end;

  [TestFixture]
  TestSlimStatement = class(TestExecBase)
  public
    [Test]
    procedure LibInstance;
    [Test]
    procedure SystemUnderTest;
  end;

  TGarbage = class
  private
    FGarbage: TObjectList;
  public
    constructor Create;
    destructor Destroy; override;
    function Collect(AList: TSlimList): TSlimList;
  end;

  TMySystemUnderTest = class
  public
    function AnswerOfUniverse: String;
  end;

  TMyAnyObject = class
  public
    function HelloWorld: String;
  end;

  [SlimFixture('MySutFixture')]
  TMySutFixture = class(TSlimFixture)
  private
    FMyAnyObject: TMyAnyObject;
    FMySut: TMySystemUnderTest;
  public
    destructor Destroy; override;
    function AnswerOfLife: String;
    function AnyObject: TObject;
    procedure RaiseStopException;
    function SystemUnderTest: TObject; override;
  end;

  [SlimFixture('ReflectObject')]
  TSlimReflectObjectFixture = class(TSlimFixture)
   private
    FTarget: TObject;
   public
    procedure ReflectObject(ATarget: TObject);
    function  SystemUnderTest: TObject; override;
  end;

function TryGetSlimListById(AResponse: TSlimList; const AId: String; out ASlimList: TSlimList): Boolean;

implementation

function TryGetSlimListById(AResponse: TSlimList; const AId: String; out ASlimList: TSlimList): Boolean;
begin
  for var Loop: Integer := 0 to AResponse.Count - 1 do
  begin
    if not (AResponse[Loop] is TSlimList) then
      Continue;
    var SubList: TSlimList := TSlimList(AResponse[Loop]);
    if (SubList.Count > 0) and (SubList[0].ToString = AId) then
    begin
      ASlimList := SubList;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TestExecBase }

procedure TestExecBase.Setup;
begin
  FGarbage := TGarbage.Create;
  FContext := TSlimStatementContext.Create;
  FContext.InitAllMembers;
end;

procedure TestExecBase.TearDown;
begin
  FGarbage.Free;
  FContext.Free;
end;

{ TestContext }

procedure TestContext.EnsureScriptTableActorsFullInit;
begin
  var Context: TSlimStatementContext := TSlimStatementContext.Create;
  try
    Context.InitAllMembers;
    Assert.IsNotNull(Context.Instances);
    Assert.IsNotNull(Context.LibInstances);
    Assert.AreEqual(1, Context.LibInstances.Count);
    Assert.AreEqual(TScriptTableActorStack,Context.LibInstances[0].ClassType);
    Assert.IsTrue(TScriptTableActorStack(Context.LibInstances[0]).Instances = Context.Instances);

    Context.SetInstances(TSlimFixtureDictionary.Create([doOwnsValues]), True);

    Assert.IsTrue(TScriptTableActorStack(Context.LibInstances[0]).Instances = Context.Instances);
  finally
    Context.Free;
  end;
end;

procedure TestContext.EnsureScriptTableActorsPartialInit;
begin
  var Context: TSlimStatementContext := TSlimStatementContext.Create;
  try
    Context.InitMembers([
      TSlimStatementContext.TContextMember.cmLibInstances,
      TSlimStatementContext.TContextMember.cmResolver,
      TSlimStatementContext.TContextMember.cmSymbols]);

    Context.SetInstances(TSlimFixtureDictionary.Create([doOwnsValues]), True);

    Assert.AreEqual(1, Context.LibInstances.Count);
    Assert.AreEqual(TScriptTableActorStack,Context.LibInstances[0].ClassType);
    Assert.IsTrue(TScriptTableActorStack(Context.LibInstances[0]).Instances = Context.Instances);
  finally
    Context.Free;
  end;
end;

{ TestSlimExecutor }

function TestSlimExecutor.CreateStmtsFromFile(const AFileName: String): TSlimList;
begin
  Result := SlimListUnserialize(TFile.ReadAllText(AFileName));
end;

procedure TestSlimExecutor.Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
var
  Executor   : TSlimExecutor;
  ResponseStr: String;
begin
  Executor := nil;
  var Response: TSlimList := nil;
  try
    Executor := TSlimExecutor.Create(FContext);
    Response := Executor.Execute(AStmts);
    ACheckResponseProc(Response);
  finally
    Response.Free;
    Executor.Free;
  end;
end;

procedure TestSlimExecutor.ScriptTableActor;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'scriptTableActor', 'MySutFixture']),
      SlimList(['id_2', 'call', 'no_instance', 'getFixture']),
      SlimList(['id_3', 'call', 'no_instance', 'pushFixture']),
      SlimList(['id_4', 'make', 'scriptTableActor', 'ReflectObject']),
      SlimList(['id_5', 'call', 'no_instance', 'getFixture']),
      SlimList(['id_6', 'call', 'no_instance', 'popFixture']),
      SlimList(['id_7', 'call', 'no_instance', 'getFixture']),
      SlimList(['id_8', 'call', 'no_instance', 'popFixture']) // Here we should get an exception
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(8, AResponse.Count);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
      Assert.Contains(CallResponse[1].ToString, 'TMySutFixture');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', CallResponse));
      Assert.AreEqual(TSlimConsts.VoidResponse, CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_5', CallResponse));
      Assert.Contains(CallResponse[1].ToString, 'TSlimReflectObjectFixture');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_6', CallResponse));
      Assert.AreEqual(TSlimConsts.VoidResponse, CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_7', CallResponse));
      Assert.Contains(CallResponse[1].ToString, 'TMySutFixture');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_8', CallResponse));
      Assert.Contains(CallResponse[1].ToString, TSlimConsts.ExceptionResponse);

      Assert.AreEqual(1, FContext.Instances.Count);
      Assert.AreEqual(1, FContext.LibInstances.Count);
    end);
end;

procedure TestSlimExecutor.StopTestExceptionTest;
begin
  var Stmts: TSlimList := FGarbage.Collect(
    SlimList([
      SlimList(['id_1', 'make', 'instance_1', 'MySutFixture']),
      SlimList(['id_2', 'call', 'instance_1', 'AnswerOfLife']),
      SlimList(['id_3', 'call', 'instance_1', 'RaiseStopException']),
      SlimList(['id_4', 'call', 'instance_1', 'AnswerOfLife']) // This should not execute
    ]));
  Execute(Stmts,
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(3, AResponse.Count);
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', CallResponse));
      Assert.Contains(CallResponse[1].ToString, TSlimConsts.ExceptionResponse);
      Assert.Contains(CallResponse[1].ToString, 'ABORT_SLIM_TEST');
      Assert.IsFalse(TryGetSlimListById(AResponse, 'id_4', CallResponse));
    end);
end;

procedure TestSlimExecutor.SutOnLibInstance;
begin
  Assert.AreEqual(1, FContext.LibInstances.Count);

  // Note: The method HelloWorld is not reachable through a fixture, but of a SystemUnderObject.
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'library1', 'ReflectObject']),
      SlimList(['id_2', 'make', 'instance_1', 'MySutFixture']),
      SlimList(['id_3', 'callAndAssign', 'AnyObject', 'instance_1', 'AnyObject']),
      SlimList(['id_4', 'call', 'instance_1', 'ReflectObject', '$AnyObject']),
      SlimList(['id_5', 'call', 'instance_1', 'HelloWorld'])
    ])),
    procedure(AResponse: TSlimList)
    begin
      Assert.AreEqual(5, AResponse.Count);
      Assert.AreEqual(2, FContext.LibInstances.Count);
      Assert.AreEqual(1, FContext.Instances.Count);
      Assert.IsTrue(FContext.Symbols.ContainsKey('AnyObject'));
      Assert.AreEqual('What a wonderful world, hello!', TSlimList(AResponse[4])[1].ToString);
    end);
end;

procedure TestSlimExecutor.AssignSymbol;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'assign', 'MyFirstVar', 'Value of first var']),
      SlimList(['id_2', 'assign', 'MySecondVar', 'Value of second var']),
      SlimList(['id_3', 'assign', 'MyFirstVar', 'Value of first var was changed'])
    ])),
    procedure(AResponse: TSlimList)
    begin
      Assert.AreEqual(3, AResponse.Count);
      Assert.AreEqual(2, FContext.Symbols.Count);
      Assert.AreEqual('Value of first var was changed', FContext.Symbols['MyFirstVar'].ToString);
      Assert.AreEqual('Value of second var', FContext.Symbols['MySecondVar'].ToString);
    end);
end;

procedure TestSlimExecutor.TwoMinuteExample;
begin
  var Stmts: TSlimList := FGarbage.Collect(CreateStmtsFromFile('Data\TwoMinuteExample.txt'));
  Execute(Stmts,
    procedure(AResponse: TSlimList)
    begin
      Assert.AreEqual(Stmts.Count, AResponse.Count);
      var ResponseStr: String := SlimListSerialize(AResponse);
      Assert.IsNotEmpty(ResponseStr)
    end);
end;

{ TestSlimStatement }

procedure TestSlimStatement.LibInstance;
begin
  var MakeStmt: TSlimStmtMake := TSlimStmtMake.Create(
    FGarbage.Collect(SlimList(['id', 'make', 'library_instance', 'Division'])), FContext);
  try
    Assert.AreEqual(1, FContext.LibInstances.Count);
    MakeStmt.Execute.Free;
    Assert.AreEqual(0, FContext.Instances.Count);
    Assert.AreEqual(2, FContext.LibInstances.Count);
  finally
    MakeStmt.Free;
  end;

  var CallResp1: TSlimList := nil;
  var CallStmt1: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_1', 'call', 'invalid_instance', 'setNumerator', '30'])), FContext);
  try
    CallResp1 := CallStmt1.Execute;
    Assert.AreEqual('call_id_1', CallResp1[0].ToString);
    Assert.AreEqual(TSlimConsts.VoidResponse, CallResp1[1].ToString);
  finally
    CallStmt1.Free;
    CallResp1.Free;
  end;

  var CallResp2: TSlimList := nil;
  var CallStmt2: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_2', 'call', 'invalid_instance', 'setDenominator', '10'])), FContext);
  try
    CallResp2 := CallStmt2.Execute;
    Assert.AreEqual('call_id_2', CallResp2[0].ToString);
    Assert.AreEqual(TSlimConsts.VoidResponse, CallResp2[1].ToString);
  finally
    CallStmt2.Free;
    CallResp2.Free;
  end;

  var CallResp3: TSlimList := nil;
  var CallStmt3: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_3', 'call', 'invalid_instance', 'quotient'])), FContext);
  try
    CallResp3 := CallStmt3.Execute;
    Assert.AreEqual('call_id_3', CallResp3[0].ToString);
    Assert.AreEqual('3.0', CallResp3[1].ToString);
  finally
    CallStmt3.Free;
    CallResp3.Free;
  end;
end;

procedure TestSlimStatement.SystemUnderTest;
begin
  var MakeStmt: TSlimStmtMake := TSlimStmtMake.Create(
    FGarbage.Collect(SlimList(['id', 'make', 'valid_instance', 'MySutFixture'])), FContext);
  try
    MakeStmt.Execute.Free;
    Assert.AreEqual(1, FContext.Instances.Count);
  finally
    MakeStmt.Free;
  end;

  // The method AnswerOfUniverse is implemented on the SystemUnderTest
  var CallResp1: TSlimList := nil;
  var CallStmt1: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_1', 'call', 'valid_instance', 'AnswerOfUniverse'])), FContext);
  try
    CallResp1 := CallStmt1.Execute;
    Assert.IsNotNull(CallResp1);
    Assert.AreEqual('call_id_1', CallResp1[0].ToString);
    Assert.AreEqual('42', CallResp1[1].ToString);
  finally
    CallStmt1.Free;
    CallResp1.Free;
  end;

  var CallResp2: TSlimList := nil;
  var CallStmt2: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_2', 'call', 'valid_instance', 'AnswerOfLife'])), FContext);
  try
    CallResp2 := CallStmt2.Execute;
    Assert.IsNotNull(CallResp2);
    Assert.AreEqual('call_id_2', CallResp2[0].ToString);
    Assert.AreEqual('~42', CallResp2[1].ToString);
  finally
    CallStmt2.Free;
    CallResp2.Free;
  end;
end;

{ TGarbage }

constructor TGarbage.Create;
begin
  FGarbage := TObjectList.Create(True);
end;

destructor TGarbage.Destroy;
begin
  FGarbage.Free;
  inherited;
end;

function TGarbage.Collect(AList: TSlimList): TSlimList;
begin
  FGarbage.Add(AList);
  Result := AList;
end;

{ TMySystemUnderTest }

function TMySystemUnderTest.AnswerOfUniverse: String;
begin
  Result := '42';
end;

{ TMySutFixture }

function TMySutFixture.AnswerOfLife: String;
begin
  Result := '~42';
end;

function TMySutFixture.AnyObject: TObject;
begin
  if not Assigned(FMyAnyObject) then
    FMyAnyObject := TMyAnyObject.Create;
  Result := FMyAnyObject;
end;

destructor TMySutFixture.Destroy;
begin
  FMySut.Free;
  FMyAnyObject.Free;
  inherited;
end;

procedure TMySutFixture.RaiseStopException;
begin
  StopTest;
end;

function TMySutFixture.SystemUnderTest: TObject;
begin
  if not Assigned(FMySut) then
    FMySut := TMySystemUnderTest.Create;
  Result := FMySut;
end;

{ TMyAnyObject }

function TMyAnyObject.HelloWorld: String;
begin
  Result := 'What a wonderful world, hello!';
end;

{ TSlimReflectObjectFixture }

procedure TSlimReflectObjectFixture.ReflectObject(ATarget: TObject);
begin
  FTarget := ATarget;
end;

function TSlimReflectObjectFixture.SystemUnderTest: TObject;
begin
  Result := FTarget;
end;

end.
