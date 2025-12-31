// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimLogger;

interface

uses

  System.Classes,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Exec,
  Slim.List,
  Slim.Logger,
  Slim.Server;

type

  TMockSlimLogger = class(TInterfacedObject, ISlimLogger)
  private
    FLogContent: TStringList;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
    property  LogContent: TStringList read FLogContent;
  end;

  TTestableSlimServer = class(TSlimServer)
  public
    function ExecutePublic(AExecutor: TSlimExecutor; const ARequest: String): TSlimList;
  end;

  [TestFixture]
  TestSlimLogger = class
  private
    FContext   : TSlimStatementContext;
    FExecutor  : TSlimExecutor;
    FMockLogger: TMockSlimLogger;
    FServer    : TTestableSlimServer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestLoggingHook;
  end;

implementation

{ TMockSlimLogger }

constructor TMockSlimLogger.Create;
begin
  FLogContent := TStringList.Create;
end;

destructor TMockSlimLogger.Destroy;
begin
  FLogContent.Free;
  inherited;
end;

procedure TMockSlimLogger.EnterList(const AList: TSlimList);
begin
  FLogContent.Add('ENTER:' + IntToStr(AList.Count));
end;

procedure TMockSlimLogger.ExitList(const AList: TSlimList);
begin
  FLogContent.Add('EXIT');
end;

procedure TMockSlimLogger.LogInstruction(const AInstruction: TSlimList);
begin
  FLogContent.Add('INSTR:' + SlimListSerialize(AInstruction));
end;

{ TTestableSlimServer }

function TTestableSlimServer.ExecutePublic(AExecutor: TSlimExecutor; const ARequest: String): TSlimList;
begin
  Result := inherited Execute(AExecutor, ARequest);
end;

{ TestSlimLogger }

procedure TestSlimLogger.Setup;
begin
  FServer := TTestableSlimServer.Create(nil);
  FMockLogger := TMockSlimLogger.Create;
  FContext := TSlimStatementContext.Create;
  FContext.InitMembers([
    TSlimStatementContext.TContextMember.cmInstances,
    TSlimStatementContext.TContextMember.cmLibInstances,
    TSlimStatementContext.TContextMember.cmResolver,
    TSlimStatementContext.TContextMember.cmSymbols,
    TSlimStatementContext.TContextMember.cmImportedNamespaces]);
  FExecutor := TSlimExecutor.Create(FContext);
end;

procedure TestSlimLogger.TearDown;
begin
  FExecutor.Free;
  FContext.Free;
  FServer.Free;
  FMockLogger := nil; 
end;

procedure TestSlimLogger.TestLoggingHook;
var
  ExpectedInstr1: String;
  ExpectedInstr2: String;
  List          : TSlimList;
  Request       : String;
begin
  FServer.Logger := FMockLogger;

  // Create a request with 2 valid instructions using MySutFixture (defined in Test.SlimExec)
  var Instr1: TSlimList := SlimList(['id1', 'make', 'inst1', 'MySutFixture']);
  var Instr2: TSlimList := SlimList(['id2', 'call', 'inst1', 'AnswerOfLife']);

  // Calculate expected strings BEFORE adding to list (ownership transfer) or freeing list
  ExpectedInstr1 := 'INSTR:' + SlimListSerialize(Instr1);
  ExpectedInstr2 := 'INSTR:' + SlimListSerialize(Instr2);

  List := SlimList([Instr1, Instr2]);
  try
    Request := SlimListSerialize(List);
  finally
    List.Free;
  end;

  List := FServer.ExecutePublic(FExecutor, Request);
  try
    Assert.AreEqual(2, List.Count, 'Should return results for 2 instructions');
    Assert.AreEqual('OK', TSlimList(List[0])[1].ToString, 'Make should return OK');
    Assert.AreEqual('~42', TSlimList(List[1])[1].ToString, 'AnswerOfLife should return ~42');
  finally
    List.Free;
  end;

  Assert.AreEqual(4, FMockLogger.LogContent.Count, 'Should have 4 log entries');
  Assert.AreEqual('ENTER:2', FMockLogger.LogContent[0]);
  Assert.AreEqual(ExpectedInstr1, FMockLogger.LogContent[1]);
  Assert.AreEqual(ExpectedInstr2, FMockLogger.LogContent[2]);
  Assert.AreEqual('EXIT', FMockLogger.LogContent[3]);
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimLogger);

end.

