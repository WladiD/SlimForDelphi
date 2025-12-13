// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
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
    destructor Destroy; override;
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
    property LogContent: TStringList read FLogContent;
  end;

  TTestableSlimServer = class(TSlimServer)
  public
    function ExecutePublic(AExecutor: TSlimExecutor; const ARequest: String): TSlimList;
  end;

  [TestFixture]
  TestSlimLogger = class
  private
    FContext: TSlimStatementContext;
    FServer: TTestableSlimServer;
    FExecutor: TSlimExecutor;
    FMockLogger: TMockSlimLogger;
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
  // Store a simplified representation or just a marker
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
  // Initialize members to avoid access violations if Executor uses them
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
  if Assigned(FExecutor) then
    FExecutor.Free;
  
  if Assigned(FContext) then
    FContext.Free;

  FServer.Free;
  FMockLogger := nil; 
end;

procedure TestSlimLogger.TestLoggingHook;
var
  Request: String;
  ResultList: TSlimList;
  ExpectedInstr1, ExpectedInstr2: String;
begin
  FServer.Logger := FMockLogger;

  // Create a request with 2 instructions
  var Instr1 := SlimList(['id1', 'call', 'instance', 'method1']);
  var Instr2 := SlimList(['id2', 'call', 'instance', 'method2']);
  
  // Calculate expected strings BEFORE adding to list (ownership transfer) or freeing list
  ExpectedInstr1 := 'INSTR:' + SlimListSerialize(Instr1);
  ExpectedInstr2 := 'INSTR:' + SlimListSerialize(Instr2);

  var List := SlimList([Instr1, Instr2]);
  
  Request := SlimListSerialize(List);
  List.Free; // This frees Instr1 and Instr2

  try
    try
      ResultList := FServer.ExecutePublic(FExecutor, Request);
      ResultList.Free;
    except
      // Ignore execution errors
    end;

    // Assert
    // Expect: ENTER -> INSTR 1 -> INSTR 2 -> EXIT
    Assert.AreEqual(4, FMockLogger.LogContent.Count, 'Should have 4 log entries');
    Assert.AreEqual('ENTER:2', FMockLogger.LogContent[0]);
    
    Assert.AreEqual(ExpectedInstr1, FMockLogger.LogContent[1]);
    Assert.AreEqual(ExpectedInstr2, FMockLogger.LogContent[2]);
    
    Assert.AreEqual('EXIT', FMockLogger.LogContent[3]);
    
  finally
    // Cleanup
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TestSlimLogger);

end.
