// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimExec;

interface

uses

  System.Classes,
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

end.
