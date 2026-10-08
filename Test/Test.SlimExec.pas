// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
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
    function RunDelayedCallInExecutorThread(const AMethodName: String; ADone: TEvent; const AAfterFree: TProc): IFuture<String>;
    function ServeDelayedCall(ADone: TEvent; const ABetweenPasses: TProc): Boolean;
    procedure WaitForDone(AEvent: TEvent);
  protected
    function CreateStmtsFromFile(const AFileName: String): TSlimList;
  public
    [Test]
    procedure AssignSymbol;
    [TestCase('Manual', 'RunDelayedManual,Void,False')]
    [TestCase('Method', 'RunDelayed,Void,False')]
    [TestCase('Exception', 'ThrowDelayed,Exception,True')]
    procedure FixtureWithDelayedExecution(const AMethodName, AExpectedResult: String; AExpectException: Boolean);
    /// <summary>
    ///   Delayed call whose method keeps running in a message loop (like a modal dialog): the
    ///   delayed event is triggered while the method still runs, the executor finishes and frees
    ///   the fixture, and only then the method returns. The fixture must outlive its own call.
    /// </summary>
    [Test]
    procedure DelayedCallMustNotOutliveItsFixture;
    /// <summary>
    ///   Delayed call whose method destroys the owner of the delayed trigger: the trigger never
    ///   fires, and the executor thread must not wait forever for it.
    /// </summary>
    [Test]
    procedure DelayedWaitMustNotHangWhenTriggerOwnerDies;
    /// <summary>
    ///   The owner of a scheduled delayed call dies before the call runs: the executor thread
    ///   must get an exception response instead of waiting forever.
    /// </summary>
    [Test]
    procedure DelayedWaitMustNotHangWhenOwnerDiesBeforeCall;
    [Test]
    procedure FixtureWithProperties;
    [Test]
    procedure FixtureWithPropertiesSyncModes;
    [Test]
    procedure IgnoreAllTestsPersistBug;
    [Test]
    procedure ImportTable;
    [Test]
    procedure ScriptTableActor;
    [Test]
    procedure StopTestExceptionTest;
    [Test]
    procedure SutOnLibInstance;
    /// <summary>
    ///   Stress test for the smSynchronized path: several executor threads hammer the main thread
    ///   with synchronized calls, while the main thread pumps CheckSynchronize re-entrantly (as a
    ///   modal message loop inside a fixture method would do). Every response must carry the value
    ///   computed in the main thread, and no synchronize entry may be left behind.
    /// </summary>
    [TestCase('Default', '4,500')]
    procedure SynchronizedCallsUnderReentrantPump(AWorkerCount, ACallsPerWorker: Integer);
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
    FLock   : TCriticalSection;
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
    /// <summary>Instance pointer of the fixture destroyed last - for use-after-free detection</summary>
    class var LastDestroyed: Pointer;
    /// <summary>Fixture instance created last - lets a test unblock a hanging delayed wait</summary>
    class var LastInstance: TSlimDelayedFixture;
    /// <summary>Set by a test to let HoldLikeModalDialog return</summary>
    class var ReleaseDialog: Boolean;
    /// <summary>Counts delayed calls that returned after their fixture was destroyed</summary>
    class var ReturnedAfterDestroy: Integer;
    /// <summary>Destroys the DelayedOwner of the last instance once a delayed call is scheduled on it</summary>
    class procedure FreeOwnerIfCallScheduled;
    constructor Create;
    destructor Destroy; override;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure FreeOwnerDuringCall;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure HoldLikeModalDialog;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure ThrowDelayed;
    [SlimMemberSyncMode(smSynchronizedAndDelayedManual)]
    procedure RunDelayedManual;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure RunDelayed;
  end;

  [SlimFixture('SyncStress')]
  TSlimSyncStressFixture = class(TSlimFixture)
  public
    class var ExecutedCount: Integer;
    class var NestedPumpEnabled: Boolean;
    function Echo(const AValue: String): String;
    function SyncMode(AMember: TRttiMember): TSyncMode; override;
  end;

  TSyncStressWorker = class
  private
    FCallCount  : Integer;
    FDone       : TCountdownEvent;
    FFailure    : String;
    FIndex      : Integer;
    procedure Run;
  public
    constructor Create(AIndex, ACallCount: Integer; ADone: TCountdownEvent);
    function Start: ITask;
    property Failure: String read FFailure;
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

procedure TestSlimExecutor.SynchronizedCallsUnderReentrantPump(AWorkerCount, ACallsPerWorker: Integer);
var
  Done      : TCountdownEvent;
  NoiseCount: Integer;
  NoiseStop : Boolean;
  NoiseTask : ITask;
  Tasks     : TArray<ITask>;
  Workers   : TObjectList<TSyncStressWorker>;
begin
  TSlimSyncStressFixture.ExecutedCount := 0;
  TSlimSyncStressFixture.NestedPumpEnabled := True;
  NoiseCount := 0;
  NoiseStop := False;
  Done := TCountdownEvent.Create(AWorkerCount);
  Workers := TObjectList<TSyncStressWorker>.Create(True);
  try
    SetLength(Tasks, AWorkerCount);
    for var Loop: Integer := 0 to AWorkerCount - 1 do
    begin
      Workers.Add(TSyncStressWorker.Create(Loop, ACallsPerWorker, Done));
      Tasks[Loop] := Workers.Last.Start;
    end;

    // Background noise: queued (heap based) synchronize entries compete with the blocking ones
    NoiseTask := TTask.Run(
      procedure
      begin
        while not NoiseStop do
        begin
          TThread.Queue(nil,
            procedure
            begin
              Inc(NoiseCount);
            end);
          TThread.Yield;
        end;
      end);

    // The main thread acts like a GUI message loop: it serves synchronize requests and messages
    while Done.WaitFor(0) = wrTimeout do
    begin
      CheckSynchronize(1);
      PumpMessages;
    end;
    TTask.WaitForAll(Tasks);
    NoiseStop := True;
    NoiseTask.Wait;
    CheckSynchronize; // drains the last queued noise entries

    for var Worker: TSyncStressWorker in Workers do
      Assert.IsEmpty(Worker.Failure, Worker.Failure);
    Assert.AreEqual(AWorkerCount * ACallsPerWorker, TSlimSyncStressFixture.ExecutedCount, 'Executed count');
    Assert.IsTrue(NoiseCount > 0, 'Noise entries were executed');
    // No synchronize entry may survive its caller
    Assert.IsFalse(CheckSynchronize, 'A stale synchronize entry was executed after all workers finished');
  finally
    TSlimSyncStressFixture.NestedPumpEnabled := False;
    Workers.Free;
    Done.Free;
  end;
end;

function TestSlimExecutor.RunDelayedCallInExecutorThread(const AMethodName: String; ADone: TEvent; const AAfterFree: TProc): IFuture<String>;
begin
  Result := TTask.Future<String>(
    function: String
    var
      CallResponse: TSlimList;
      Context     : TSlimStatementContext;
      Executor    : TSlimExecutor;
      Reply       : TSlimList;
      Stmts       : TSlimList;
    begin
      Result := '';
      Context := nil;
      Executor := nil;
      try
        try
          Context := TSlimStatementContext.Create;
          Context.InitAllMembers;
          Executor := TSlimExecutor.Create(Context);
          Stmts := SlimList([
            SlimList(['id_1', 'make', 'instance_1', 'DelayedFixture']),
            SlimList(['id_2', 'call', 'instance_1', AMethodName])]);
          try
            Reply := Executor.Execute(Stmts);
            try
              if TryGetSlimListById(Reply, 'id_2', CallResponse) then
                Result := CallResponse[1].ToString
              else
                Result := 'no response: ' + SlimListSerialize(Reply);
            finally
              Reply.Free;
            end;
          finally
            Stmts.Free;
          end;
        finally
          try
            // Like TSlimServer at the end of a connection: the executor thread frees the fixtures
            Executor.Free;
            Context.Free;
          finally
            if Assigned(AAfterFree) then
              AAfterFree;
            ADone.SetEvent;
          end;
        end;
      except
        on E: Exception do
          Result := E.ClassName + ': ' + E.Message;
      end;
    end);
end;

procedure TestSlimExecutor.DelayedCallMustNotOutliveItsFixture;
begin
  TSlimDelayedFixture.ReleaseDialog := False;
  TSlimDelayedFixture.ReturnedAfterDestroy := 0;
  TSlimDelayedFixture.LastDestroyed := nil;
  var Done: TEvent := TEvent.Create(nil, True, False, '');
  try
    var Response: IFuture<String> := RunDelayedCallInExecutorThread('HoldLikeModalDialog', Done,
      procedure
      begin
        // The "dialog" closes only after the executor has freed the fixture
        TSlimDelayedFixture.ReleaseDialog := True;
      end);

    WaitForDone(Done);

    Assert.AreEqual(TSlimConsts.VoidResponse, Response.Value);
    Assert.IsNotNull(TSlimDelayedFixture.LastDestroyed, 'The executor should have freed the fixture');
    Assert.AreEqual(0, TSlimDelayedFixture.ReturnedAfterDestroy, 'The delayed call returned on an already destroyed fixture');
  finally
    TSlimDelayedFixture.ReleaseDialog := True;
    Done.Free;
  end;
end;

/// <summary>
///   Serves the main thread part of a delayed call for a bounded time. Returns True, if the executor
///   thread did not finish within that time, i.e. it hangs in WaitForDelayedEvent.
/// </summary>
function TestSlimExecutor.ServeDelayedCall(ADone: TEvent; const ABetweenPasses: TProc): Boolean;
const
  GracePeriodMs = 1500;
var
  PassError: Exception;
begin
  PassError := nil;
  try
    var Started: UInt64 := GetTickCount64;
    while (ADone.WaitFor(0) = wrTimeout) and (GetTickCount64 - Started < GracePeriodMs) do
    begin
      CheckSynchronize(1);
      if Assigned(ABetweenPasses) and not Assigned(PassError) then
      begin
        try
          ABetweenPasses;
        except
          PassError := Exception(AcquireExceptionObject);
        end;
      end;
      PumpMessages;
    end;
    Result := ADone.WaitFor(0) = wrTimeout;
    // Unblock the executor thread by hand, so the test leaves no thread behind in WaitForDelayedEvent
    if Result and Assigned(TSlimDelayedFixture.LastInstance) then
      TSlimDelayedFixture.LastInstance.TriggerDelayedEvent;
    WaitForDone(ADone);
    if Assigned(PassError) then
    begin
      var RaiseError: Exception := PassError;
      PassError := nil;
      raise RaiseError;
    end;
  finally
    PassError.Free;
  end;
end;

procedure TestSlimExecutor.DelayedWaitMustNotHangWhenTriggerOwnerDies;
begin
  TSlimDelayedFixture.LastInstance := nil;
  var Done: TEvent := TEvent.Create(nil, True, False, '');
  try
    var Response: IFuture<String> := RunDelayedCallInExecutorThread('FreeOwnerDuringCall', Done, nil);
    var HangDetected: Boolean := ServeDelayedCall(Done, nil);

    Assert.IsFalse(HangDetected, 'The executor thread waited forever for a delayed trigger that died with its owner');
    Assert.AreEqual(TSlimConsts.VoidResponse, Response.Value);
  finally
    Done.Free;
  end;
end;

procedure TestSlimExecutor.DelayedWaitMustNotHangWhenOwnerDiesBeforeCall;
begin
  TSlimDelayedFixture.LastInstance := nil;
  var Done: TEvent := TEvent.Create(nil, True, False, '');
  try
    var Response: IFuture<String> := RunDelayedCallInExecutorThread('RunDelayed', Done, nil);
    var HangDetected: Boolean := ServeDelayedCall(Done,
      procedure
      begin
        // Right after the call was scheduled, before the message loop gets to run it
        TSlimDelayedFixture.FreeOwnerIfCallScheduled;
      end);

    Assert.IsFalse(HangDetected, 'The executor thread waited forever for a delayed call that died with its owner');
    Assert.Contains(Response.Value, TSlimConsts.ExceptionResponse);
    Assert.Contains(Response.Value, 'destroyed before the call could run');
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
  LastInstance := Self;
end;

destructor TSlimDelayedFixture.Destroy;
begin
  LastDestroyed := Self;
  if LastInstance = Self then
    LastInstance := nil;
  FDummyOwner.Free;
  inherited;
end;

procedure TSlimDelayedFixture.FreeOwnerDuringCall;
begin
  // Like a method that closes the form serving as DelayedOwner: the pending trigger dies with it
  FreeAndNil(FDummyOwner);
  DelayedOwner := nil;
end;

class procedure TSlimDelayedFixture.FreeOwnerIfCallScheduled;
begin
  // The delayed event exists from the moment the call was scheduled in the main thread
  var Instance: TSlimDelayedFixture := LastInstance;
  if Assigned(Instance) and Assigned(Instance.FDelayedEvent) and Assigned(Instance.FDummyOwner) then
  begin
    // Detach first: destroying the owner wakes the executor thread, which may free the fixture
    // while the owner is still being destroyed
    var Owner: TComponent := Instance.FDummyOwner;
    Instance.FDummyOwner := nil;
    Instance.DelayedOwner := nil;
    Owner.Free;
  end;
end;

procedure TSlimDelayedFixture.HoldLikeModalDialog;
var
  Msg: TMsg;
begin
  // Keeps the main thread in a message loop, like ShowModal would, until the test releases it
  while not ReleaseDialog do
  begin
    CheckSynchronize(1);
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;
  // No field access here on purpose: Self may already be freed, which is exactly what is measured
  if Pointer(Self) = LastDestroyed then
    AtomicIncrement(ReturnedAfterDestroy);
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

{ TSlimSyncStressFixture }

function TSlimSyncStressFixture.Echo(const AValue: String): String;
begin
  if TThread.CurrentThread.ThreadID <> MainThreadID then
    raise Exception.Create('Echo must be executed in the main thread');
  AtomicIncrement(ExecutedCount);
  // A fixture method that runs a modal dialog pumps messages, and with them the pending
  // synchronize entries of other threads. Do the same here, so CheckSynchronize nests.
  if NestedPumpEnabled then
    CheckSynchronize;
  Result := AValue + '!';
end;

function TSlimSyncStressFixture.SyncMode(AMember: TRttiMember): TSyncMode;
begin
  Result := smSynchronized;
end;

{ TSyncStressWorker }

constructor TSyncStressWorker.Create(AIndex, ACallCount: Integer; ADone: TCountdownEvent);
begin
  inherited Create;
  FIndex := AIndex;
  FCallCount := ACallCount;
  FDone := ADone;
end;

function TSyncStressWorker.Start: ITask;
begin
  Result := TTask.Run(Run);
end;

procedure TSyncStressWorker.Run;
var
  CallResponse: TSlimList;
  Context     : TSlimStatementContext;
  Executor    : TSlimExecutor;
  Junk        : TArray<TBytes>;
  Response    : TSlimList;
  Stmts       : TSlimList;
  Value       : String;
begin
  Context := nil;
  Executor := nil;
  try
    try
      Context := TSlimStatementContext.Create;
      Context.InitAllMembers;
      Executor := TSlimExecutor.Create(Context);

      Stmts := SlimList([SlimList(['id_make', 'make', 'inst', 'SyncStress'])]);
      try
        Response := Executor.Execute(Stmts);
        try
          if not (TryGetSlimListById(Response, 'id_make', CallResponse) and (CallResponse[1].ToString = 'OK')) then
            raise Exception.Create('make failed: ' + SlimListSerialize(Response));
        finally
          Response.Free;
        end;
      finally
        Stmts.Free;
      end;

      SetLength(Junk, 64);
      for var Loop: Integer := 1 to FCallCount do
      begin
        Value := Format('w%d-%d', [FIndex, Loop]);
        Stmts := SlimList([SlimList(['id_call', 'call', 'inst', 'Echo', Value])]);
        try
          Response := Executor.Execute(Stmts);
          try
            if not TryGetSlimListById(Response, 'id_call', CallResponse) then
              raise Exception.Create('no response for ' + Value + ': ' + SlimListSerialize(Response));
            if CallResponse[1].ToString <> Value + '!' then
              raise Exception.CreateFmt('wrong response for %s: "%s"', [Value, CallResponse[1].ToString]);
          finally
            Response.Free;
          end;
        finally
          Stmts.Free;
        end;
        // Churn the heap, so freed memory of the previous round trip is reused quickly
        SetLength(Junk[Loop mod Length(Junk)], 16 + Random(240));
      end;
    except
      on E: Exception do
        FFailure := Format('Worker %d: %s: %s', [FIndex, E.ClassName, E.Message]);
    end;
  finally
    Executor.Free;
    Context.Free;
    FDone.Signal;
  end;
end;

initialization

RegisterSlimFixture(TSlimSyncStressFixture);
RegisterSlimFixture(TMySutFixture);
RegisterSlimFixture(TMyImportedFixture);
RegisterSlimFixture(TSlimReflectObjectFixture);
RegisterSlimFixture(TSlimDelayedFixture);

TDUnitX.RegisterTestFixture(TestContext);
TDUnitX.RegisterTestFixture(TestSlimExecutor);
TDUnitX.RegisterTestFixture(TestSlimStatement);

end.
