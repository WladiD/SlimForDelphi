﻿// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Fixture;

interface

uses

  System.Classes,
  System.Rtti,
  System.SysUtils,

  Slim.List;

type

  /// <summary>
  /// Classes with this attribute are automatically considered by the TSlimExecutor
  /// </summary>
  SlimFixtureAttribute = class(TCustomAttribute)
  private
    FName: String;
  public
    constructor Create; overload;
    constructor Create(const AName: String); overload;
    property Name: String read FName;
  end;

  SlimMethodAttribute = class(TCustomAttribute);

  /// <summary>
  /// Base class for all fixtures
  /// </summary>
  TSlimFixture = class
  /// <summary>
  /// The following public [SlimMethod]s are called in this order:
  /// 1. Table
  /// 2. Next the beginTable method is called.
  ///    Use this for initializations if you want to.
  /// Then for each row in the table:
  ///   2.1. First the Reset method is called, just in case you want to prepare or clean up.
  ///   2.2. Then all the inputs are loaded by calling the appropriate Set-Methods
  ///        (must be implemented in the derived class).
  ///   2.3. Then the Execute method of the fixture is called.
  ///   2.4  Finally all the output functions are called
  /// 3. Finally the EndTable method is called.
  ///    Use this for closedown and cleanup if you want to.
  /// </summary>
  public
    [SlimMethod]
    procedure Table(AList: TSlimList); virtual;
    [SlimMethod]
    procedure BeginTable; virtual;
    [SlimMethod]
    procedure Reset; virtual;
    [SlimMethod]
    procedure Execute; virtual;
    [SlimMethod]
    procedure EndTable; virtual;
  end;

  TSlimFixtureResolver = class
  private
    FContext: TRttiContext;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
  end;

implementation

{ SlimFixtureAttribute }

constructor SlimFixtureAttribute.Create;
begin
  inherited Create;
end;

constructor SlimFixtureAttribute.Create(const AName: String);
begin
  inherited Create;
  FName := AName;
end;

{ TSlimFixture }

procedure TSlimFixture.BeginTable;
begin

end;

procedure TSlimFixture.EndTable;
begin

end;

procedure TSlimFixture.Execute;
begin

end;

procedure TSlimFixture.Reset;
begin

end;

procedure TSlimFixture.Table(AList: TSlimList);
begin

end;


{ TSlimFixtureResolver }

constructor TSlimFixtureResolver.Create;
begin
  FContext := TRttiContext.Create;
end;

destructor TSlimFixtureResolver.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TSlimFixtureResolver.TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
var
  Attribute: TCustomAttribute;
  LType    : TRttiType;
begin
  for LType in FContext.GetTypes do
  begin
    if LType.IsInstance then
    begin
      AClassType := LType.AsInstance;
      for Attribute in AClassType.GetAttributes do
      begin
        if
          (Attribute.ClassType = SlimFixtureAttribute) and
          AClassType.MetaclassType.InheritsFrom(TSlimFixture) and
          (
            SameText(SlimFixtureAttribute(Attribute).Name, AFixtureName) or
            AClassType.MetaclassType.ClassNameIs(AFixtureName)
          ) then
          Exit(true);
      end;
    end;
  end;
  Result := false;
  AClassType := nil;
end;

end.
