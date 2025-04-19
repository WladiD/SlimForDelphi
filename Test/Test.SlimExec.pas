// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimExec;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Exec,
  Slim.Fixture,
  Slim.List;

type

  [TestFixture]
  TestSlimExecutor = class
  protected
    function CreateStmts(const AContent: String): TSlimList;
    function CreateStmtsFromFile(const AFileName: String): TSlimList;
  public
    [Test]
    procedure TwoMinuteExample;
  end;

  [TestFixture]
  TestSlimStmtCall = class
  private
    FContext: TSlimStatementContext;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LibInstanceTest;
  end;

implementation

{ TestSlimExecutor }

function TestSlimExecutor.CreateStmts(const AContent: String): TSlimList;
begin
  Result := SlimListUnserialize(AContent);
end;

function TestSlimExecutor.CreateStmtsFromFile(const AFileName: String): TSlimList;
begin
  Result := CreateStmts(TFile.ReadAllText(AFileName));
end;

procedure TestSlimExecutor.TwoMinuteExample;
var
  Executor   : TSlimExecutor;
  Stmts      : TSlimList;
  Response   : TSlimList;
  ResponseStr: String;
begin
  Response := nil;
  Stmts := nil;
  Executor := TSlimExecutor.Create;
  try
    Stmts := CreateStmtsFromFile('Data\TwoMinuteExample.txt');
    Response := Executor.Execute(Stmts);
    Assert.AreEqual(Stmts.Count, Response.Count);

    ResponseStr := SlimListSerialize(Response);
    Assert.IsNotEmpty(ResponseStr)
  finally
    Response.Free;
    Stmts.Free;
    Executor.Free;
  end;
end;

{ TestSlimStmtCall }

procedure TestSlimStmtCall.LibInstanceTest;
begin
  var MakeStmt: TSlimStmtMake := TSlimStmtMake.Create(
    SlimList(['id', 'make', 'library_instance', 'Division']), FContext);
  try
    MakeStmt.Execute.Free;
    Assert.AreEqual(0, FContext.Instances.Count);
    Assert.AreEqual(1, FContext.LibInstances.Count);
  finally
    MakeStmt.Free;
  end;

  var CallResp1: TSlimList := nil;
  var CallStmt1: TSlimStmtCall := TSlimStmtCall.Create(
    SlimList(['call_id_1', 'call', 'invalid_instance', 'setNumerator', '30']), FContext);
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
    SlimList(['call_id_2', 'call', 'invalid_instance', 'setDenominator', '10']), FContext);
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
    SlimList(['call_id_3', 'call', 'invalid_instance', 'quotient']), FContext);
  try
    CallResp3 := CallStmt3.Execute;
    Assert.AreEqual('call_id_3', CallResp3[0].ToString);
    Assert.AreEqual('3.0', CallResp3[1].ToString);
  finally
    CallStmt3.Free;
    CallResp3.Free;
  end;
end;

procedure TestSlimStmtCall.Setup;
begin
  FContext := Default(TSlimStatementContext);
  FContext.Resolver := TSlimFixtureResolver.Create;
  FContext.Instances := TSlimFixtureDictionary.Create([doOwnsValues]);
  FContext.LibInstances := TSlimFixtureList.Create(True);
end;

procedure TestSlimStmtCall.TearDown;
begin
  FreeAndNil(FContext.Resolver);
  FreeAndNil(FContext.Instances);
  FreeAndNil(FContext.LibInstances);
end;

end.
