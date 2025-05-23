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
  TestSlimExecutor = class(TestExecBase)
  private
    procedure Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
  protected
    function CreateStmtsFromFile(const AFileName: String): TSlimList;
  public
    [Test]
    procedure StopTestExceptionTest;
    [Test]
    procedure TwoMinuteExample;
    [Test]
    procedure SutOnLibInstance;
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

implementation


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
    begin
      Assert.AreEqual(3, AResponse.Count);
      Assert.AreEqual('id_3', (AResponse[2] as TSlimList)[0].ToString);
      Assert.Contains((AResponse[2] as TSlimList)[1].ToString, 'ABORT_SLIM_TEST');
    end);
end;

procedure TestSlimExecutor.SutOnLibInstance;
begin
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
      Assert.AreEqual(1, FContext.LibInstances.Count);
      Assert.AreEqual(1, FContext.Instances.Count);
      Assert.IsTrue(FContext.Symbols.ContainsKey('AnyObject'));
      Assert.AreEqual('What a wonderful world, hello!', TSlimList(AResponse[4])[1].ToString);
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
    MakeStmt.Execute.Free;
    Assert.AreEqual(0, FContext.Instances.Count);
    Assert.AreEqual(1, FContext.LibInstances.Count);
  finally
    MakeStmt.Free;
  end;

  var CallResp1: TSlimList := nil;
  var CallStmt1: TSlimStmtCall := TSlimStmtCall.Create(
    FGarbage.Collect(SlimList(['call_id_1', 'call', 'invalid_instance', 'setNumerator', '30'])), FContext);
  try
    CallResp1 := CallStmt1.Execute;
    Assert.AreEqual('call_id_1', CallResp1[0].ToString);
    Assert.AreEqual('/__VOID__/', CallResp1[1].ToString);
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
    Assert.AreEqual('/__VOID__/', CallResp2[1].ToString);
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
