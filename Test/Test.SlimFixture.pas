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
