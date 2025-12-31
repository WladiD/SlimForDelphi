// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
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
  System.Threading,

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
    function SyncMode(AMember: TRttiMember): TSyncMode; override;
    property Numerator: Double read FNumerator write FNumerator;
    property Denominator: Double read FDenominator write FDenominator;
    [SlimMemberSyncMode(smSynchronized)]
    property Quotient: Double read GetQuotient;
  end;

  // Fixtures for advanced resolver tests
  [SlimFixture('AmbigFixture', 'ns1')]
  TAmbigFixture1 = class(TSlimFixture);

  [SlimFixture('AmbigFixture', 'ns2')]
  TAmbigFixture2 = class(TSlimFixture);

  [SlimFixture('GlobalFixture')]
  TGlobalFixture = class(TSlimFixture);

  [SlimFixture('GlobalFixture', 'ns1')]
  TGlobalNsFixture = class(TSlimFixture);

  [SlimFixture('DelayedOwner', 'test')]
  TSlimDelayedOwnerFixture = class(TSlimFixture)
  public
    [SlimMemberSyncMode(smSynchronizedAndDelayedManual)]
    procedure ManualMethod;
    procedure AutoMethod;
  end;

  [TestFixture]
  TestSlimFixtureResolver = class
  public
    [Test]
    procedure AmbiguousWithImport;
    [Test]
    procedure AmbiguousWithoutImport;
    [Test]
    procedure CaseInsensitivity;
    [Test]
    procedure GlobalAndImported;
    [Test]
    procedure NotFound;
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

  [TestFixture]
  TestSlimFixture = class
  public
    [Test]
    procedure DelayedEvents;
    [Test]
    procedure DelayedEventsWithException;
    [Test]
    procedure MemberSyncMode;
    [Test]
    procedure DelayedOwnerAndAttribute;
  end;

implementation

type
  TSlimFixtureAccess = class(TSlimFixture);

{ TestSlimFixtureResolver }

procedure TestSlimFixtureResolver.TryGetSlimFixture;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := TSlimFixtureResolver.Create;
  try
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionFixture', nil, LClassType));
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);
    LClassType := nil;

    Assert.IsTrue(Resolver.TryGetSlimFixture('Division', nil, LClassType));
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);
    Assert.AreEqual('Test.SlimFixture', LClassType.DeclaringUnitName);

    Assert.IsTrue(Resolver.TryGetSlimFixture('eg.Division', nil, LClassType));
  finally
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.AmbiguousWithoutImport;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := TSlimFixtureResolver.Create;
  try
    // Without an import, the first registered fixture with the simple name wins.
    // In this case, TAmbigFixture1 is registered first.
    Assert.IsTrue(Resolver.TryGetSlimFixture('AmbigFixture', nil, LClassType), 'Should find the first registered ambiguous fixture.');
    Assert.AreEqual(TAmbigFixture1, LClassType.MetaclassType, 'Should resolve to the first registered fixture.');
  finally
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.AmbiguousWithImport;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := nil;
  var Imports: TStringList := TStringList.Create;
  try
    Resolver := TSlimFixtureResolver.Create;
    // With an import, it should resolve to the specific fixture from the namespace.
    Imports.Add('ns2');
    Assert.IsTrue(Resolver.TryGetSlimFixture('AmbigFixture', Imports, LClassType), 'Should find fixture in imported namespace ns2.');
    Assert.AreEqual(TAmbigFixture2, LClassType.MetaclassType, 'Should resolve to the fixture from namespace ns2.');

    Imports.Clear;
    Imports.Add('ns1');
    Assert.IsTrue(Resolver.TryGetSlimFixture('AmbigFixture', Imports, LClassType), 'Should find fixture in imported namespace ns1.');
    Assert.AreEqual(TAmbigFixture1, LClassType.MetaclassType, 'Should resolve to the fixture from namespace ns1.');
  finally
    Imports.Free;
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.GlobalAndImported;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := nil;
  var Imports: TStringList := TStringList.Create;
  try
    Resolver := TSlimFixtureResolver.Create;
    // With import "ns1", it should find the namespaced fixture
    Imports.Add('ns1');
    Assert.IsTrue(Resolver.TryGetSlimFixture('GlobalFixture', Imports, LClassType), 'Should find namespaced fixture when imported.');
    Assert.AreEqual(TGlobalNsFixture, LClassType.MetaclassType, 'Should resolve to TGlobalNsFixture.');

    // Without an import, the first registered one wins. TGlobalFixture is registered before TGlobalNsFixture.
    Imports.Clear;
    Assert.IsTrue(Resolver.TryGetSlimFixture('GlobalFixture', nil, LClassType), 'Should find global fixture when not imported.');
    Assert.AreEqual(TGlobalFixture, LClassType.MetaclassType, 'Should resolve to TGlobalFixture.');
  finally
    Imports.Free;
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.CaseInsensitivity;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := nil;
  var Imports: TStringList := TStringList.Create;
  try
    Resolver := TSlimFixtureResolver.Create;
    // Test case insensitivity for different lookup types
    Assert.IsTrue(Resolver.TryGetSlimFixture('tslimdivisionfixture', nil, LClassType), 'Class name should be case-insensitive.');
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);

    Assert.IsTrue(Resolver.TryGetSlimFixture('EG.DIVISION', nil, LClassType), 'FQN should be case-insensitive.');
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);

    Assert.IsTrue(Resolver.TryGetSlimFixture('division', nil, LClassType), 'Simple name should be case-insensitive.');
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);

    Imports.Add('eG');
    Assert.IsTrue(Resolver.TryGetSlimFixture('Division', Imports, LClassType), 'Imported lookup should be case-insensitive.');
    Assert.AreEqual(TSlimDivisionFixture, LClassType.MetaclassType);
  finally
    Imports.Free;
    Resolver.Free;
  end;
end;

procedure TestSlimFixtureResolver.NotFound;
var
  LClassType: TRttiInstanceType;
begin
  var Resolver: TSlimFixtureResolver := nil;
  var Imports: TStringList := TStringList.Create;
  try
    Resolver := TSlimFixtureResolver.Create;
    // 1. Simple non-existent fixture
    Assert.IsFalse(Resolver.TryGetSlimFixture('NonExistentFixture', nil, LClassType), 'Should not find a non-existent fixture.');
    Assert.IsNull(LClassType, 'LClassType should be nil for non-existent fixture.');

    // 2. Non-existent fixture with import
    Imports.Add('ns1');
    Assert.IsFalse(Resolver.TryGetSlimFixture('NonExistentFixture', Imports, LClassType), 'Should not find a non-existent fixture in an imported namespace.');
    Assert.IsNull(LClassType, 'LClassType should be nil for non-existent fixture with import.');

    // 3. Fixture with simple name from a different, un-imported namespace
    // TAmbigFixture is in ns1 and ns2. If we import nsX, it shouldn't be found.
    Imports.Clear;
    Imports.Add('nsX'); // A namespace that has no 'AmbigFixture'
    Assert.IsFalse(Resolver.TryGetSlimFixture('AmbigFixture', Imports, LClassType), 'Should not find AmbigFixture by simple name if its namespace is not imported.');
    Assert.IsNull(LClassType);
  finally
    Imports.Free;
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
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionFixture', nil, LClassType));
    Stmts := SlimList(['CallId', '4.5']);

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'setNumerator', Stmts, 1, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('SetNumerator', SlimMethod.Name);
    Assert.AreEqual(1, Integer(Length(InvokeArgs)));

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'setDenominator', Stmts, 1, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('SetDenominator', SlimMethod.Name);
    Assert.AreEqual(1, Integer(Length(InvokeArgs)));

    Assert.IsTrue(Resolver.TryGetSlimMethod(LClassType, 'quotient', Stmts, 0, SlimMethod, InvokeArgs));
    Assert.IsNotNull(SlimMethod);
    Assert.AreEqual('Quotient', SlimMethod.Name);
    Assert.AreEqual(0, Integer(Length(InvokeArgs)));
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
  Stmts := nil;
  Resolver := TSlimFixtureResolver.Create;
  try
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionWithPropsFixture', nil, LClassType));
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
    Assert.AreEqual(TSlimConsts.VoidResponse, InvokeArg.ToString);

    Stmts.Free;
    Stmts := SlimList(['CallId', '0.5']);

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'Denominator', Stmts, 1, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Denominator', SlimProperty.Name);
    Assert.AreEqual(Double(0.5), Double(InvokeArg.AsExtended));

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'SetDenominator', Stmts, 1, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Denominator', SlimProperty.Name);
    Assert.AreEqual(Double(0.5), Double(InvokeArg.AsExtended));

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'Quotient', nil, 0, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Quotient', SlimProperty.Name);
    Assert.AreEqual(TSlimConsts.VoidResponse, InvokeArg.ToString);

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'GetQuotient', nil, 0, SlimProperty, InvokeArg));
    Assert.IsNotNull(SlimProperty);
    Assert.AreEqual('Quotient', SlimProperty.Name);
    Assert.AreEqual(TSlimConsts.VoidResponse, InvokeArg.ToString);

    Assert.IsFalse(Resolver.TryGetSlimProperty(LClassType, 'SetQuotient', Stmts, 1, SlimProperty, InvokeArg));

    // Empty name property
    Assert.IsFalse(Resolver.TryGetSlimProperty(LClassType, '', Stmts, 1, SlimProperty, InvokeArg));

    // Getter should not be found when any params exists
    Assert.IsFalse(Resolver.TryGetSlimProperty(LClassType, 'getNumerator', Stmts, 1, SlimProperty, InvokeArg));

    // Setter with more than 1 Parameter shoud not be found
    Stmts.Free;
    Stmts := SlimList(['CallId', '0.5', '1.5']);
    Assert.IsFalse(Resolver.TryGetSlimProperty(LClassType, 'SetDenominator', Stmts, 1, SlimProperty, InvokeArg));
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

function TSlimDivisionWithPropsFixture.SyncMode(AMember: TRttiMember): TSyncMode;
begin
  if SameText(AMember.Name, 'Numerator') or SameText(AMember.Name, 'Denominator') then
    Result := smSynchronized
  else
    Result := smUnsynchronized;
end;

{ TSlimDelayedOwnerFixture }

procedure TSlimDelayedOwnerFixture.AutoMethod;
begin
end;

procedure TSlimDelayedOwnerFixture.ManualMethod;
begin
end;

{ TestScriptTableActorStack }

procedure TestScriptTableActorStack.Setup;
begin
  FInstances := TSlimFixtureDictionary.Create([doOwnsValues]);
  FActors := TScriptTableActorStack.Create(FInstances);
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
    end, ESlim);
end;

procedure TestScriptTableActorStack.MultipleFixtures;
begin
  var FirstFixture: TSlimDivisionFixture := TSlimDivisionFixture.Create;
  FirstFixture.SetNumerator(77);
  FirstFixture.SetDenominator(7);
  FInstances.Add(TSlimConsts.ScriptTableActor, FirstFixture);
  Assert.AreEqual(1, Integer(FInstances.Count));

  Assert.AreEqual(Double(11), TSlimDivisionFixture(FActors.GetFixture).Quotient);

  var SecondFixture: TSlimDivisionFixture := TSlimDivisionFixture.Create;
  try
    SecondFixture.SetNumerator(60);
    SecondFixture.SetDenominator(6);

    Assert.WillRaise(
      procedure
      begin
        FInstances.Add(TSlimConsts.ScriptTableActor, SecondFixture);
      end, EListError);
  finally
    SecondFixture.Free;
  end;

  SecondFixture := TSlimDivisionFixture.Create; // Create a new instance
  SecondFixture.SetNumerator(60);
  SecondFixture.SetDenominator(6);

  FInstances.AddOrSetValue(TSlimConsts.ScriptTableActor, SecondFixture);
  Assert.AreEqual(1, Integer(FInstances.Count)); // FirstFixture was destroyed at previous AddOrSetValue

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
  var Fixture: TSlimDivisionFixture := TSlimDivisionFixture.Create;
  Fixture.SetNumerator(10);
  Fixture.SetDenominator(2);

  FInstances.Add(TSlimConsts.ScriptTableActor, Fixture);
  Assert.AreEqual(1, Integer(FInstances.Count));
  FActors.PushFixture;
  Assert.AreEqual(0, Integer(FInstances.Count));

  FActors.PopFixture;
  Assert.AreEqual(1, Integer(FInstances.Count));

  Assert.IsTrue(Fixture = FActors.GetFixture);
  Assert.AreEqual(Double(5), TSlimDivisionFixture(FActors.GetFixture).Quotient);
end;

{ TestSlimFixture }

procedure TestSlimFixture.DelayedEvents;
begin
  var Fixture: TSlimFixture := TSlimFixture.Create;
  try
    Fixture.InitDelayedEvent;

    TTask.Run(
      procedure
      begin
        Fixture.TriggerDelayedEvent;
      end);

    Fixture.WaitForDelayedEvent;
    Assert.Pass;
  finally
    Fixture.Free;
  end;
end;

procedure TestSlimFixture.DelayedEventsWithException;
begin
  var Fixture: TSlimFixture := TSlimFixture.Create;
  try
    Fixture.InitDelayedEvent;

    TTask.Run(
      procedure
      begin
        try
          raise Exception.Create('Delayed Crash');
        except
          on E: Exception do
          begin
             TSlimFixtureAccess(Fixture).SetDelayedException(Exception(AcquireExceptionObject));
             Fixture.TriggerDelayedEvent;
          end;
        end;
      end);

    Fixture.WaitForDelayedEvent;

    Assert.WillRaise(
      procedure
      begin
        TSlimFixtureAccess(Fixture).CheckAndRaiseDelayedException;
      end, Exception, 'Delayed Crash');
  finally
    Fixture.Free;
  end;
end;

procedure TestSlimFixture.MemberSyncMode;
var
  InvokeArg   : TValue;
  LClassType  : TRttiInstanceType;
  SlimProperty: TRttiProperty;
begin
  var Resolver: TSlimFixtureResolver := nil;
  var Fixture: TSlimFixture := TSlimDivisionWithPropsFixture.Create;
  try
    Resolver := TSlimFixtureResolver.Create;
    Assert.IsTrue(Resolver.TryGetSlimFixture('TSlimDivisionWithPropsFixture', nil, LClassType));
    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'GetQuotient', nil, 0, SlimProperty, InvokeArg));
    Assert.IsTrue(Fixture.SyncMode(SlimProperty) = smUnsynchronized); // Note: The attribute of Quotient is not evaluated at this level

    Assert.IsTrue(Resolver.TryGetSlimProperty(LClassType, 'Numerator', nil, 0, SlimProperty, InvokeArg));
    Assert.IsTrue(Fixture.SyncMode(SlimProperty) = smSynchronized);
  finally
    Fixture.Free;
    Resolver.Free;
  end;
end;

procedure TestSlimFixture.DelayedOwnerAndAttribute;
var
  Comp        : TComponent;
  Ctx         : TRttiContext;
  Fixture     : TSlimDelayedOwnerFixture;
  Info        : TDelayedInfo;
  MethodAuto  : TRttiMethod;
  MethodManual: TRttiMethod;
  SyncAttr    : TCustomAttribute;
  Typ         : TRttiType;
begin
  Fixture := TSlimDelayedOwnerFixture.Create;
  Comp := TComponent.Create(nil);
  try
    // 1. Without Owner -> False
    Typ := Ctx.GetType(TSlimDelayedOwnerFixture);
    MethodManual := Typ.GetMethod('ManualMethod');
    MethodAuto := Typ.GetMethod('AutoMethod');

    Assert.IsFalse(Fixture.HasDelayedInfo(MethodManual, Info));

    // 2. With Owner
    Fixture.DelayedOwner := Comp;

    // Manual Method
    Assert.IsTrue(Fixture.HasDelayedInfo(MethodManual, Info));
    Assert.AreEqual(Comp, Info.Owner);
    Assert.IsTrue(Info.ManualDelayedEvent, 'ManualDelayedEvent should be true due to smSynchronizedAndDelayedManual');

    // Auto Method
    Assert.IsTrue(Fixture.HasDelayedInfo(MethodAuto, Info));
    Assert.AreEqual(Comp, Info.Owner);
    Assert.IsFalse(Info.ManualDelayedEvent, 'ManualDelayedEvent should be false by default');
    
    // Check if the attribute is accessible via standard RTTI logic
    SyncAttr := MethodManual.GetAttribute(SlimMemberSyncModeAttribute);
    Assert.IsNotNull(SyncAttr, 'SlimMemberSyncModeAttribute should be present');
    Assert.IsTrue(SlimMemberSyncModeAttribute(SyncAttr).SyncMode = smSynchronizedAndDelayedManual);
  finally
    Comp.Free;
    Fixture.Free;
  end;
end;

initialization

RegisterSlimFixture(TSlimDivisionFixture);
RegisterSlimFixture(TSlimDivisionWithPropsFixture);
// The registration order matters for ambiguity tests
RegisterSlimFixture(TAmbigFixture1);
RegisterSlimFixture(TAmbigFixture2);
RegisterSlimFixture(TGlobalFixture);
RegisterSlimFixture(TGlobalNsFixture);
RegisterSlimFixture(TSlimDelayedOwnerFixture);

TDUnitX.RegisterTestFixture(TestSlimFixtureResolver);
TDUnitX.RegisterTestFixture(TestScriptTableActorStack);
TDUnitX.RegisterTestFixture(TestSlimFixture);

end.
