// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Fixture;

interface

uses

  System.Classes,
  System.Rtti,
  System.SysUtils;

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
