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

  Slim.Fixture,
  Slim.List;

type

  [SlimFixture('Division', 'eg')]
  TSlimDivisionFixture = class(TSlimFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
  public
    procedure SetNumerator(ANumerator: Double);
    procedure SetDenominator(ADenominator: Double);
    function Quotient: Double;
  end;

  [TestFixture]
  TestSlimFixtureResolver = class
  public
    [Test]
    procedure TryGetSlimFixtureTest;
    [Test]
    procedure TryGetSlimMethodTest;
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

    Assert.IsTrue(Resolver.TryGetSlimFixture('eg.Division', LClassType));
  finally
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.TryGetSlimMethodTest;
var
  Resolver  : TSlimFixtureResolver;
  LClassType: TRttiInstanceType;
  Stmts     : TSlimList;
  SlimMethod: TRttiMethod;
  InvokeArgs: TArray<TValue>;
begin
  Stmts := nil;
  Resolver := TSlimFixtureResolver.Create;
  try
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionFixture', LClassType));
    Stmts := SlimList(['CallId', '4.5']);

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'setNumerator', Stmts, 1, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('SetNumerator', SlimMethod.Name);
    Assert.AreEqual(1, Length(InvokeArgs));

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'setDenominator', Stmts, 1, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('SetDenominator', SlimMethod.Name);
    Assert.AreEqual(1, Length(InvokeArgs));

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'quotient', Stmts, 0, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('Quotient', SlimMethod.Name);
    Assert.AreEqual(0, Length(InvokeArgs));
  finally
    Stmts.Free;
    Resolver.Free;
  end;
end;

{ TSlimDivisionFixture }

function TSlimDivisionFixture.Quotient: Double;
begin
  Result := FNumerator / FDenominator;
end;

procedure TSlimDivisionFixture.SetDenominator(ADenominator: Double);
begin
  FDenominator := ADenominator;
end;

procedure TSlimDivisionFixture.SetNumerator(ANumerator: Double);
begin
  FNumerator := ANumerator;
end;

end.
