// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimFixture;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Common,
  Slim.Fixture,
  Slim.List;

type

  [SlimFixture('Division', 'eg')]
  TSlimDivisionFixture = class(TSlimDecisionTableFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
  public
    procedure SetNumerator(ANumerator: Double);
    procedure SetDenominator(ADenominator: Double);
    function Quotient: Double;
  end;

  [SlimFixture('DivisionWithProps', 'eg')]
  TSlimDivisionWithPropsFixture = class(TSlimDecisionTableFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
    function GetQuotient: Double;
  public
    property Numerator: Double read FNumerator write FNumerator;
    property Denominator: Double read FDenominator write FDenominator;
    property Quotient: Double read GetQuotient;
  end;

  [TestFixture]
  TestSlimFixtureResolver = class
  public
    [Test]
    procedure TryGetSlimFixture;
    [Test]
    procedure TryGetSlimMethod;
    [Test]
    procedure TryGetSlimProperty;
  end;

  [TestFixture]
  TestScriptTableActorStack = class
  private
    FActors   : TScriptTableActorStack;
    FInstances: TSlimFixtureDictionary;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SimpleCreate;
    [Test]
    procedure NoCurrentFixture;
    [Test]
    procedure FirstFixture;
    [Test]
    procedure MultipleFixtures;
  end;

implementation

{ TestSlimFixtureResolver }

procedure TestSlimFixtureResolver.TryGetSlimFixture;
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

procedure TestSlimFixtureResolver.TryGetSlimMethod;
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

procedure TestSlimFixtureResolver.TryGetSlimProperty;
var
  Resolver    : TSlimFixtureResolver;
  LClassType  : TRttiInstanceType;
  Stmts       : TSlimList;
  SlimProperty: TRttiProperty;
  InvokeArg   : TValue;
begin
// TODO: Ein Test benötigt, wenn es mehr als 1 Parameter gibt,
//       denn ohne Parameter ist der Getter und mit einem Parameter der Setter gemeint,
//       andernfalls eine Exception werfen.
// TODO: Eine Property sollte sowohl über SetAnyName, GetAnyName als auch über AnyName auffindbar sein.
// TODO: Es sollte eine Exception geworfen werden, wenn ein leerer Name übergeben wird

  Stmts := nil;
  Resolver := TSlimFixtureResolver.Create;
  try
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionWithPropsFixture', LClassType));
    Stmts := SlimList(['CallId', '4.5']);

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'Numerator', Stmts, 1, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Numerator', SlimProperty.Name);
    Assert.AreEqual(Double(4.5), Double(InvokeArg.AsExtended));

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'setNumerator', Stmts, 1, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Numerator', SlimProperty.Name);
    Assert.AreEqual(Double(4.5), Double(InvokeArg.AsExtended));

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'getNumerator', Stmts, 0, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Numerator', SlimProperty.Name);
    Assert.IsTrue(InvokeArg.IsEmpty);

    Assert.IsFalse(Resolver.TryGetSlimProperty(LClassType, 'getNumerator', Stmts, 1, SlimProperty, InvokeArg));

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

{ TSlimDivisionWithPropsFixture }

function TSlimDivisionWithPropsFixture.GetQuotient: Double;
begin
  Result := FNumerator / FDenominator;
end;

{ TestScriptTableActorStack }

procedure TestScriptTableActorStack.Setup;
begin
  FInstances:=TSlimFixtureDictionary.Create([doOwnsValues]);
  FActors:=TScriptTableActorStack.Create(FInstances);
end;

procedure TestScriptTableActorStack.TearDown;
begin
  FInstances.Free;
  FActors.Free;
end;

procedure TestScriptTableActorStack.SimpleCreate;
begin
  Assert.IsNotNull(FActors);
  FreeAndNil(FActors);
  // Unassigned Instances param should raise an exception
  Assert.WillRaise(
    procedure
    begin
      FActors := TScriptTableActorStack.Create(nil);
    end);
end;

procedure TestScriptTableActorStack.MultipleFixtures;
begin
  var FirstFixture: TSlimDivisionFixture:=TSlimDivisionFixture.Create;
  FirstFixture.SetNumerator(77);
  FirstFixture.SetDenominator(7);
  FInstances.Add(TSlimConsts.ScriptTableActor, FirstFixture);
  Assert.AreEqual(1, FInstances.Count);

  Assert.AreEqual(Double(11), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  var SecondFixture: TSlimDivisionFixture:=TSlimDivisionFixture.Create;
  SecondFixture.SetNumerator(60);
  SecondFixture.SetDenominator(6);

  Assert.WillRaise(
    procedure
    begin
      FInstances.Add(TSlimConsts.ScriptTableActor, SecondFixture);
    end);

  FInstances.AddOrSetValue(TSlimConsts.ScriptTableActor, SecondFixture);
  Assert.AreEqual(1, FInstances.Count); // FirstFixture was destroyed at previous AddOrSetValue

  Assert.IsTrue(FActors.GetFixture = SecondFixture);
  Assert.AreEqual(Double(10), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  FirstFixture := TSlimDivisionFixture.Create;
  FirstFixture.SetNumerator(81);
  FirstFixture.SetDenominator(9);

  FActors.PushFixture;

  FInstances.AddOrSetValue(TSlimConsts.ScriptTableActor, FirstFixture);

  Assert.IsTrue(FActors.GetFixture = FirstFixture);
  Assert.AreEqual(Double(9), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  var ThirdFixture: TSlimDivisionFixture := TSlimDivisionFixture.Create;
  ThirdFixture.SetNumerator(21);
  ThirdFixture.SetDenominator(7);

  FActors.PushFixture;

  FInstances.AddOrSetValue(TSlimConsts.ScriptTableActor, ThirdFixture);

  Assert.IsTrue(FActors.GetFixture = ThirdFixture);
  Assert.AreEqual(Double(3), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  FActors.PopFixture;

  Assert.IsTrue(FActors.GetFixture = FirstFixture);
  Assert.AreEqual(Double(9), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  FActors.PopFixture;

  Assert.IsTrue(FActors.GetFixture = SecondFixture);
  Assert.AreEqual(Double(10), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  Assert.WillRaise(
    procedure
    begin
      FActors.PopFixture;
    end, ESlim);
end;

procedure TestScriptTableActorStack.NoCurrentFixture;
begin
  Assert.WillRaise(
    procedure
    begin
      FActors.GetFixture;
    end, ESlim);
  Assert.WillRaise(
    procedure
    begin
      FActors.PushFixture;
    end, ESlim);
  Assert.WillRaise(
    procedure
    begin
      FActors.PopFixture;
    end, ESlim);
end;

procedure TestScriptTableActorStack.FirstFixture;
begin
  var Fixture: TSlimDivisionFixture:=TSlimDivisionFixture.Create;
  Fixture.SetNumerator(10);
  Fixture.SetDenominator(2);

  FInstances.Add(TSlimConsts.ScriptTableActor,Fixture);
  Assert.AreEqual(1, FInstances.Count);
  FActors.PushFixture;
  Assert.AreEqual(0, FInstances.Count);

  FActors.PopFixture;
  Assert.AreEqual(1, FInstances.Count);

  Assert.IsTrue(Fixture = FActors.GetFixture);
  Assert.AreEqual(Double(5), TSlimDivisionFixture(FActors.GetFixture).Quotient);
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimFixtureResolver);
TDUnitX.RegisterTestFixture(TestScriptTableActorStack);

end.
