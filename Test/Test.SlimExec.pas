// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimExec;

interface

uses

  Winapi.Messages,
  Winapi.Windows,

  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.IOUtils,
  System.Rtti,
  System.SyncObjs,
  System.SysUtils,
  System.Threading,

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
    procedure PumpMessages;
    procedure WaitForDone(AEvent: TEvent);
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
    [Test]
    procedure FixtureWithProperties;
    [Test]
    procedure FixtureWithPropertiesSyncModes;
    [TestCase('Manual', 'RunDelayedManual,Void,False')]
    [TestCase('Method', 'RunDelayed,Void,False')]
    [TestCase('Exception', 'ThrowDelayed,Exception,True')]
    procedure FixtureWithDelayedExecution(const AMethodName, AExpectedResult: String; AExpectException: Boolean);
    [Test]
    procedure ImportTable;
    [Test]
    procedure IgnoreAllTestsPersistBug;
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
    FLock: TCriticalSection;
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

  [SlimFixture('DelayedFixture')]
  TSlimDelayedFixture = class(TSlimFixture)
  private
    FDummyOwner: TComponent;
  public
    constructor Create;
    destructor Destroy; override;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure ThrowDelayed;
    [SlimMemberSyncMode(smSynchronizedAndDelayedManual)]
    procedure RunDelayedManual;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure RunDelayed;
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
    procedure RaiseIgnoreAllTestsException;
    function SystemUnderTest: TObject; override;
  end;

  [SlimFixture('MyImportedFixture', 'MyNamespace')]
  TMyImportedFixture = class(TSlimFixture)
  public
    function HelloWorld: String;
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
    Assert.AreEqual(1, Integer(Context.LibInstances.Count));
    Assert.AreEqual(TScriptTableActorStack, Context.LibInstances[0].ClassType);
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

    Assert.AreEqual(1, Integer(Context.LibInstances.Count));
    Assert.AreEqual(TScriptTableActorStack, Context.LibInstances[0].ClassType);
    Assert.IsTrue(TScriptTableActorStack(Context.LibInstances[0]).Instances = Context.Instances);
  finally
    Context.Free;
  end;
end;

{ TestSlimExecutor }

function TestSlimExecutor.CreateStmtsFromFile(const AFileName: String): TSlimList;
begin
  Result := SlimListUnserialize(TFile.ReadAllText(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\Data\TwoMinuteExample.txt')));
end;

procedure TestSlimExecutor.Execute(AStmts: TSlimList; ACheckResponseProc: TProc<TSlimList>);
var
  Executor: TSlimExecutor;
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

procedure TestSlimExecutor.PumpMessages;
var
  Msg: TMsg;
begin
  while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
end;

procedure TestSlimExecutor.WaitForDone(AEvent: TEvent);
begin
  while AEvent.WaitFor(1) = wrTimeout do
  begin
    CheckSynchronize;
    PumpMessages;
  end;
end;

procedure TestSlimExecutor.FixtureWithProperties;
begin
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'make', 'instance_1', 'DivisionWithProps']),
      SlimList(['id_2', 'call', 'instance_1', 'Numerator', '15']),
      SlimList(['id_3', 'call', 'instance_1', 'Denominator', '5']),
      SlimList(['id_4', 'call', 'instance_1', 'Quotient'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.AreEqual(4, Integer(AResponse.Count));

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse));
      Assert.AreEqual('OK', CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
      Assert.AreEqual(TSlimConsts.VoidResponse, CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', CallResponse));
      Assert.AreEqual(TSlimConsts.VoidResponse, CallResponse[1].ToString);

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_4', CallResponse));
      Assert.AreEqual('3.0', CallResponse[1].ToString);
    end);
end;

procedure TestSlimExecutor.FixtureWithPropertiesSyncModes;
begin
  var Done: TEvent := TEvent.Create(nil, True, False, '');
  try
    var Task: IFuture<String> := TTask.Future<String>(
      function: String
      var
        LQuotient: String;
      begin
        try
          Execute(
            FGarbage.Collect(SlimList([
              SlimList(['id_1', 'make', 'instance_1', 'DivisionWithProps']),
              SlimList(['id_2', 'call', 'instance_1', 'Numerator', '20']),
              SlimList(['id_3', 'call', 'instance_1', 'Denominator', '4']),
              SlimList(['id_4', 'call', 'instance_1', 'Quotient'])
            ])),
            procedure(AResponse: TSlimList)
            var
              CallResponse: TSlimList;
            begin
              Assert.AreEqual(4, Integer(AResponse.Count));
              Assert.IsTrue(TryGetSlimListById(AResponse, 'id_4', CallResponse));
              LQuotient := CallResponse[1].ToString;
            end);
          Result := LQuotient;
        finally
          Done.SetEvent;
        end;
      end);

    WaitForDone(Done);

    Assert.AreEqual('5.0', Task.Value);
  finally
    Done.Free;
  end;
end;

procedure TestSlimExecutor.FixtureWithDelayedExecution(const AMethodName, AExpectedResult: String; AExpectException: Boolean);
begin
  var Done: TEvent := TEvent.Create(nil, True, False, '');
  try
    var Task: IFuture<String> := TTask.Future<String>(
      function: String
      var
        LResponse: String;
      begin
        try
          Execute(
            FGarbage.Collect(SlimList([
              SlimList(['id_1', 'make', 'instance_1', 'DelayedFixture']),
              SlimList(['id_2', 'call', 'instance_1', AMethodName])
            ])),
            procedure(AResponse: TSlimList)
            var
              CallResponse: TSlimList;
            begin
              Assert.AreEqual(2, Integer(AResponse.Count));
              Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse));
              LResponse := CallResponse[1].ToString;
            end);
          Result := LResponse;
        finally
          Done.SetEvent;
        end;
      end);

    WaitForDone(Done);

    if AExpectException then
    begin
      Assert.Contains(Task.Value, TSlimConsts.ExceptionResponse);
      if AExpectedResult <> 'Exception' then
         Assert.Contains(Task.Value, 'This is a delayed crash!');
    end
    else
      Assert.AreEqual(TSlimConsts.VoidResponse, Task.Value);
  finally
    Done.Free;
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
      Assert.AreEqual(8, Integer(AResponse.Count));

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

      Assert.AreEqual(1, Integer(FContext.Instances.Count));
      Assert.AreEqual(1, Integer(FContext.LibInstances.Count));
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
      Assert.AreEqual(3, Integer(AResponse.Count));
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', CallResponse));
      Assert.Contains(CallResponse[1].ToString, TSlimConsts.ExceptionResponse);
      Assert.Contains(CallResponse[1].ToString, 'ABORT_SLIM_TEST');
      Assert.IsFalse(TryGetSlimListById(AResponse, 'id_4', CallResponse));
    end);
end;

procedure TestSlimExecutor.SutOnLibInstance;
begin
  Assert.AreEqual(1, Integer(FContext.LibInstances.Count));

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
      Assert.AreEqual(5, Integer(AResponse.Count));
      Assert.AreEqual(2, Integer(FContext.LibInstances.Count));
      Assert.AreEqual(1, Integer(FContext.Instances.Count));
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
      Assert.AreEqual(3, Integer(AResponse.Count));
      Assert.AreEqual(2, Integer(FContext.Symbols.Count));
      Assert.AreEqual('Value of first var was changed', FContext.Symbols['MyFirstVar'].ToString);
      Assert.AreEqual('Value of second var', FContext.Symbols['MySecondVar'].ToString);
    end);
end;

procedure TestSlimExecutor.TwoMinuteExample;
begin
  var Stmts: TSlimList := FGarbage.Collect(CreateStmtsFromFile('Test\Data\TwoMinuteExample.txt'));
  Execute(Stmts,
    procedure(AResponse: TSlimList)
    begin
      Assert.AreEqual(Stmts.Count, Integer(AResponse.Count));
      var ResponseStr: String := SlimListSerialize(AResponse);
      Assert.IsNotEmpty(ResponseStr)
    end);
end;

procedure TestSlimExecutor.IgnoreAllTestsPersistBug;
begin
  var Stmts1: TSlimList := FGarbage.Collect(
    SlimList([
      SlimList(['id_1', 'make', 'instance_1', 'MySutFixture']),
      SlimList(['id_2', 'call', 'instance_1', 'RaiseIgnoreAllTestsException'])
    ]));

  var Stmts2: TSlimList := FGarbage.Collect(
    SlimList([
      SlimList(['id_3', 'call', 'instance_1', 'AnswerOfLife']),
      SlimList(['id_4', 'call', 'instance_1', 'AnswerOfLife'])
    ]));

  var Executor: TSlimExecutor := TSlimExecutor.Create(FContext);
  try
    var Response1: TSlimList := Executor.Execute(Stmts1);
    try
      Assert.AreEqual(2, Integer(Response1.Count));
      Assert.Contains(TSlimList(Response1[1])[1].ToString, 'IGNORE_ALL_TESTS');
    finally
      Response1.Free;
    end;

    var Response2: TSlimList := Executor.Execute(Stmts2);
    try
      Assert.AreEqual(2, Integer(Response2.Count), 'Second request should execute both statements');
      if Response2.Count > 0 then
        Assert.AreEqual('~42', TSlimList(Response2[0])[1].ToString);
    finally
      Response2.Free;
    end;
  finally
    Executor.Free;
  end;
end;

procedure TestSlimExecutor.ImportTable;
begin
  // 1. Test with wrong namespace -> should fail
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'import', 'WrongNamespace']),
      SlimList(['id_2', 'make', 'instance_1', 'MyImportedFixture'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse), 'Import statement should have a response.');
      Assert.AreEqual('OK', CallResponse[1].ToString, 'Import statement should return OK.');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse), 'Make statement should have a response.');
      Assert.Contains(CallResponse[1].ToString, TSlimConsts.ExceptionResponse, 'Make with wrong namespace should fail.');
      Assert.Contains(CallResponse[1].ToString, 'NO_CLASS', 'Make with wrong namespace should fail with NO_CLASS.');
    end);

  // 2. Test with correct namespace -> should succeed
  Execute(
    FGarbage.Collect(SlimList([
      SlimList(['id_1', 'import', 'MyNamespace']),
      SlimList(['id_2', 'make', 'instance_1', 'MyImportedFixture']),
      SlimList(['id_3', 'call', 'instance_1', 'HelloWorld'])
    ])),
    procedure(AResponse: TSlimList)
    var
      CallResponse: TSlimList;
    begin
      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_1', CallResponse), 'Import statement should have a response.');
      Assert.AreEqual('OK', CallResponse[1].ToString, 'Import statement should return OK.');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_2', CallResponse), 'Make statement should have a response.');
      Assert.AreEqual('OK', CallResponse[1].ToString, 'Make statement for imported fixture should succeed.');

      Assert.IsTrue(TryGetSlimListById(AResponse, 'id_3', CallResponse), 'Call statement should have a response.');
      Assert.AreEqual('Hello from imported fixture!', CallResponse[1].ToString, 'Method call on imported fixture should succeed.');
    end);
end;

{ TestSlimStatement }

procedure TestSlimStatement.LibInstance;
begin
  var MakeStmt: TSlimStmtMake := TSlimStmtMake.Create(
    FGarbage.Collect(SlimList(['id', 'make', 'library_instance', 'Division'])), FContext);
  try
    Assert.AreEqual(1, Integer(FContext.LibInstances.Count));
    MakeStmt.Execute.Free;
    Assert.AreEqual(0, Integer(FContext.Instances.Count));
    Assert.AreEqual(2, Integer(FContext.LibInstances.Count));
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
    Assert.AreEqual(1, Integer(FContext.Instances.Count));
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
  FLock := TCriticalSection.Create;
end;

destructor TGarbage.Destroy;
begin
  FGarbage.Free;
  FLock.Free;
  inherited;
end;

function TGarbage.Collect(AList: TSlimList): TSlimList;
begin
  FLock.Enter;
  try
    FGarbage.Add(AList);
  finally
    FLock.Leave;
  end;
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

procedure TMySutFixture.RaiseIgnoreAllTestsException;
begin
  IgnoreAllTests;
end;

function TMySutFixture.SystemUnderTest: TObject;
begin
  if not Assigned(FMySut) then
    FMySut := TMySystemUnderTest.Create;
  Result := FMySut;
end;

{ TMyImportedFixture }

function TMyImportedFixture.HelloWorld: String;
begin
  Result := 'Hello from imported fixture!';
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

{ TSlimDelayedFixture }

constructor TSlimDelayedFixture.Create;
begin
  inherited;
  FDummyOwner := TComponent.Create(nil);
  DelayedOwner := FDummyOwner;
end;

destructor TSlimDelayedFixture.Destroy;
begin
  FDummyOwner.Free;
  inherited;
end;

procedure TSlimDelayedFixture.ThrowDelayed;
begin
  raise Exception.Create('This is a delayed crash!');
end;

procedure TSlimDelayedFixture.RunDelayedManual;
begin
  TriggerDelayedEvent;
end;

procedure TSlimDelayedFixture.RunDelayed;
begin
end;

initialization

RegisterSlimFixture(TMySutFixture);
RegisterSlimFixture(TMyImportedFixture);
RegisterSlimFixture(TSlimReflectObjectFixture);
RegisterSlimFixture(TSlimDelayedFixture);

TDUnitX.RegisterTestFixture(TestContext);
TDUnitX.RegisterTestFixture(TestSlimExecutor);
TDUnitX.RegisterTestFixture(TestSlimStatement);

end.
