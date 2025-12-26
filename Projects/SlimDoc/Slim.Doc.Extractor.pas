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

  Slim.Doc.Model,
  Slim.Fixture;

type

  TSlimDocExtractor = class
  private
    function IsStandardNoise(const AMethodName: String): Boolean;
    function GetSyncModeStr(AMember: TRttiMember; AInstance: TSlimFixture): String;
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
    SameText(AMethodName, 'BeforeDestruction') or
    SameText(AMethodName, 'AfterConstruction') or
    SameText(AMethodName, 'Free') or
    SameText(AMethodName, 'DisposeOf') or
    SameText(AMethodName, 'Dispatch') or
    SameText(AMethodName, 'DefaultHandler') or
    SameText(AMethodName, 'NewInstance') or
    SameText(AMethodName, 'FreeInstance') or
    SameText(AMethodName, 'InheritsFrom') or
    SameText(AMethodName, 'ClassType') or
    SameText(AMethodName, 'ClassName') or
    SameText(AMethodName, 'ClassInfo') or
    SameText(AMethodName, 'ClassParent') or
    SameText(AMethodName, 'FieldAddress') or
    SameText(AMethodName, 'MethodAddress') or
    SameText(AMethodName, 'MethodName') or
    SameText(AMethodName, 'InstanceSize') or
    SameText(AMethodName, 'GetInterface') or
    SameText(AMethodName, 'GetInterfaceEntry') or
    SameText(AMethodName, 'GetInterfaceTable') or
    SameText(AMethodName, 'SafeCallException') or
    SameText(AMethodName, 'ToString') or
    SameText(AMethodName, 'GetHashCode') or
    SameText(AMethodName, 'Equals') or
    SameText(AMethodName, 'CleanupInstance') or
    SameText(AMethodName, 'InitInstance') or
    SameText(AMethodName, 'ClassNameIs') or
    SameText(AMethodName, 'QualifiedClassName') or
    SameText(AMethodName, 'UnitName') or
    SameText(AMethodName, 'UnitScope') or
    // TSlimFixture methods
    SameText(AMethodName, 'HasDelayedInfo') or
    SameText(AMethodName, 'InitDelayedEvent') or
    SameText(AMethodName, 'SyncMode') or
    SameText(AMethodName, 'SystemUnderTest') or
    SameText(AMethodName, 'TriggerDelayedEvent') or
    SameText(AMethodName, 'WaitForDelayedEvent') or
    SameText(AMethodName, 'DelayedOwner');
end;

function TSlimDocExtractor.GetSyncModeStr(AMember: TRttiMember; AInstance: TSlimFixture): String;
var
  LAttr: TCustomAttribute;
  Mode : TSyncMode;
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

  if (Result = '') and Assigned(AInstance) then
  begin
    Mode := AInstance.SyncMode(AMember);
    Result := GetEnumName(TypeInfo(TSyncMode), Ord(Mode));
  end;
end;

function TSlimDocExtractor.ExtractAll: TObjectList<TSlimFixtureDoc>;
var
  C: TClass;
  Fixtures: TClassList;
begin
  Result := TObjectList<TSlimFixtureDoc>.Create(True);
  Fixtures := TSlimFixtureResolverAccess.GetFixtures;
  for C in Fixtures do
  begin
    if C.InheritsFrom(TSlimFixture) then
      Result.Add(ExtractClass(C));
  end;
end;

function TSlimDocExtractor.ExtractClass(AClass: TClass): TSlimFixtureDoc;
var
  Attr          : TCustomAttribute;
  Ctx           : TRttiContext;
  DocMethod     : TSlimMethodDoc;
  DocProp       : TSlimPropertyDoc;
  FixtureInstance: TSlimFixture;
  Method        : TRttiMethod;
  Param         : TRttiParameter;
  ParentClassRef: TClass;
  Prop          : TRttiProperty;
  RType         : TRttiType;
begin
  Result := TSlimFixtureDoc.Create;
  Ctx := TRttiContext.Create;
  FixtureInstance := nil;
  try
    if AClass.InheritsFrom(TSlimFixture) then
    begin
      try
        FixtureInstance := TSlimFixtureClass(AClass).Create;
      except
        // Ignore constructor errors during doc generation
        FixtureInstance := nil;
      end;
    end;

    RType := Ctx.GetType(AClass);
    Result.DelphiClass := RType.Name;

    ParentClassRef := AClass.ClassParent;
    while Assigned(ParentClassRef) do
    begin
      Result.InheritanceChain.Add(ParentClassRef.ClassName);
      ParentClassRef := ParentClassRef.ClassParent;
    end;

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
      
      DocMethod.SyncMode := GetSyncModeStr(Method, FixtureInstance);
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
      DocProp.SyncMode := GetSyncModeStr(Prop, FixtureInstance);

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
    FixtureInstance.Free;
    Ctx.Free;
  end;
end;

end.
