// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimFixture;

interface

uses

  System.Classes,
  System.IOUtils,
  System.Rtti,

  DUnitX.TestFramework,

  Slim.Exec,
  Slim.Fixture,
  Slim.List;

type

  [SlimFixture('Division')]
  TSlimDivisionFixture = class(TSlimFixture)
  end;

  [TestFixture]
  TestSlimFixtureResolver = class
  public
    [Test]
    procedure TryGetSlimFixtureTest;
  end;

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

{ TestSlimFixtureResolver }

procedure TestSlimFixtureResolver.TryGetSlimFixtureTest;
var
  Resolver  : TSlimFixtureResolver;
  LClassType: TRttiInstanceType;
begin
  Resolver := TSlimFixtureResolver.Create;
  try
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionFixture', LClassType));
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);
    LClassType := nil;

    Assert.IsTrue(Resolver.TryGetSlimFixture('Division', LClassType));
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);
    Assert.AreEqual('Test.SlimFixture', LClassType.DeclaringUnitName);
  finally
    Resolver.Free;
  end;
end;

{ TestSlimExecutor }

function TestSlimExecutor.CreateStmts(const AContent: String): TSlimList;
var
  Unserializer: TSlimListUnserializer;
begin
  Result := nil;
  Unserializer := TSlimListUnserializer.Create(AContent);
  try
    Result := Unserializer.Unserialize;
  finally
    Unserializer.Free;
  end;
end;

function TestSlimExecutor.CreateStmtsFromFile(const AFileName: String): TSlimList;
begin
  Result := CreateStmts(TFile.ReadAllText(AFileName));
end;

procedure TestSlimExecutor.TwoMinuteExample;
var
  Executor: TSlimExecutor;
  Stmts   : TSlimList;
begin
  Stmts := nil;
  Executor := TSlimExecutor.Create;
  try
    Stmts := CreateStmtsFromFile('Data\TwoMinuteExample.txt');
    Executor.Execute(Stmts);
  finally
    Stmts.Free;
    Executor.Free;
  end;
end;

end.
