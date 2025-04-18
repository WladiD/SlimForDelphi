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

  [SlimFixture('Division')]
  TSlimDivisionFixture = class(TSlimFixture)
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
  finally
    Resolver.Free;
  end;
end;

end.
