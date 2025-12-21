// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Extractor;

interface

uses
  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Slim.Fixture,
  Slim.Doc.Model;

type

  TSlimDocExtractor = class
  private
    function IsStandardNoise(const AMethodName: String): Boolean;
    function GetSyncModeStr(AMember: TRttiMember): String;
  public
    function ExtractAll: TObjectList<TSlimFixtureDoc>;
    function ExtractClass(AClass: TClass): TSlimFixtureDoc;
  end;

implementation

type
  TSlimFixtureResolverAccess = class(TSlimFixtureResolver)
  public
    class function GetFixtures: TClassList;
  end;

class function TSlimFixtureResolverAccess.GetFixtures: TClassList;
begin
  Result := FFixtures;
end;

{ TSlimDocExtractor }

function TSlimDocExtractor.IsStandardNoise(const AMethodName: String): Boolean;
begin
  Result :=
    (AMethodName = 'BeforeDestruction') or
    (AMethodName = 'AfterConstruction') or
    (AMethodName = 'Free') or
    (AMethodName = 'DisposeOf') or
    (AMethodName = 'Dispatch') or
    (AMethodName = 'DefaultHandler') or
    (AMethodName = 'NewInstance') or
    (AMethodName = 'FreeInstance') or
    (AMethodName = 'InheritsFrom') or
    (AMethodName = 'ClassType') or
    (AMethodName = 'ClassName') or
    (AMethodName = 'ClassInfo') or
    (AMethodName = 'ClassParent') or
    (AMethodName = 'FieldAddress') or
    (AMethodName = 'MethodAddress') or
    (AMethodName = 'MethodName') or
    (AMethodName = 'InstanceSize') or
    (AMethodName = 'GetInterface') or
    (AMethodName = 'GetInterfaceEntry') or
    (AMethodName = 'GetInterfaceTable') or
    (AMethodName = 'SafeCallException') or
    (AMethodName = 'ToString') or
    (AMethodName = 'GetHashCode') or
    (AMethodName = 'Equals') or
    // More TObject methods
    (AMethodName = 'CleanupInstance') or
    (AMethodName = 'InitInstance') or
    (AMethodName = 'ClassNameIs') or
    (AMethodName = 'QualifiedClassName') or
    (AMethodName = 'UnitName') or
    (AMethodName = 'UnitScope') or
    // TSlimFixture methods
    (AMethodName = 'HasDelayedInfo') or
    (AMethodName = 'InitDelayedEvent') or
    (AMethodName = 'SyncMode') or
    (AMethodName = 'SystemUnderTest') or
    (AMethodName = 'TriggerDelayedEvent') or
    (AMethodName = 'WaitForDelayedEvent') or
    (AMethodName = 'DelayedOwner');
end;

function TSlimDocExtractor.GetSyncModeStr(AMember: TRttiMember): String;
var
  LAttr: TCustomAttribute;
begin
  Result := '';
  for LAttr in AMember.GetAttributes do
  begin
    if LAttr is SlimMemberSyncModeAttribute then
    begin
      Result := GetEnumName(TypeInfo(TSyncMode), Ord(SlimMemberSyncModeAttribute(LAttr).SyncMode));
      Exit;
    end;
  end;
end;

function TSlimDocExtractor.ExtractAll: TObjectList<TSlimFixtureDoc>;
var
  C: TClass;
  Fixtures: TClassList;
begin
  Result := TObjectList<TSlimFixtureDoc>.Create(True);
  try
    Fixtures := TSlimFixtureResolverAccess.GetFixtures;
    for C in Fixtures do
    begin
      if C.InheritsFrom(TSlimFixture) then
        Result.Add(ExtractClass(C));
    end;
  finally
    // Sorting could be done here or in the Generator
  end;
end;

function TSlimDocExtractor.ExtractClass(AClass: TClass): TSlimFixtureDoc;
var
  Ctx: TRttiContext;
  RType: TRttiType;
  Attr: TCustomAttribute;
  Method: TRttiMethod;
  Prop: TRttiProperty;
  Param: TRttiParameter;
  DocMethod: TSlimMethodDoc;
  DocProp: TSlimPropertyDoc;
begin
  Result := TSlimFixtureDoc.Create;
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(AClass);
    Result.DelphiClass := RType.Name;
    Result.UnitName := AClass.UnitName;
    Result.Name := RType.Name;
    Result.Namespace := 'global';

    for Attr in RType.GetAttributes do
      if Attr is SlimFixtureAttribute then
      begin
        Result.Name := SlimFixtureAttribute(Attr).Name;
        if SlimFixtureAttribute(Attr).Namespace <> '' then
          Result.Namespace := SlimFixtureAttribute(Attr).Namespace;
        Break;
      end;

    // Methods
    for Method in RType.GetMethods do
    begin
      if Method.Visibility < mvPublic then Continue;
      if Method.IsDestructor then Continue;
      if Method.IsConstructor and (Length(Method.GetParameters) = 0) then Continue;
      if IsStandardNoise(Method.Name) then Continue;

      DocMethod := TSlimMethodDoc.Create;
      DocMethod.Name := Method.Name;
      DocMethod.IsInherited := Method.Parent <> RType;
      DocMethod.Origin := Method.Parent.Name;
      if not DocMethod.IsInherited then DocMethod.Origin := 'Self';
      
      DocMethod.SyncMode := GetSyncModeStr(Method);
      if Assigned(Method.ReturnType) then
        DocMethod.ReturnType := Method.ReturnType.Name
      else
        DocMethod.ReturnType := 'void';

      for Param in Method.GetParameters do
        DocMethod.Parameters.Add(TSlimParameterDoc.Create(Param.Name, Param.ParamType.Name));

      Result.Methods.Add(DocMethod);
    end;

    // Properties
    for Prop in RType.GetProperties do
    begin
      if Prop.Visibility < mvPublic then Continue;
      if IsStandardNoise(Prop.Name) then Continue;

      DocProp := TSlimPropertyDoc.Create;
      DocProp.Name := Prop.Name;
      DocProp.PropertyType := Prop.PropertyType.Name;
      DocProp.IsInherited := Prop.Parent <> RType;
      DocProp.Origin := Prop.Parent.Name;
      if not DocProp.IsInherited then DocProp.Origin := 'Self';

      DocProp.Access := '';
      if Prop.IsReadable then DocProp.Access := 'Read';
      if Prop.IsWritable then
      begin
        if DocProp.Access <> '' then DocProp.Access := DocProp.Access + '/Write'
        else DocProp.Access := 'Write';
      end;

      Result.Properties.Add(DocProp);
    end;

  finally
    Ctx.Free;
  end;
end;

end.
