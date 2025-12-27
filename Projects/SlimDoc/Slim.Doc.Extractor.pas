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
  System.IOUtils,
  System.RegularExpressions,
  System.Rtti,
  System.SysUtils,
  System.Types,
  System.TypInfo,

  Slim.Doc.Model,
  Slim.Fixture;

type

  TSlimDocExtractor = class
  private
    FRootSourcePath: String;
    function IsStandardNoise(const AMethodName: String): Boolean;
    function GetSyncModeStr(AMember: TRttiMember; AInstance: TSlimFixture): String;
    procedure InjectXmlDocs(ADoc: TSlimFixtureDoc; const AUnitName: String);
  public
    function ExtractAll: TObjectList<TSlimFixtureDoc>;
    function ExtractClass(AClass: TClass): TSlimFixtureDoc;
    property RootSourcePath: String read FRootSourcePath write FRootSourcePath;
  end;

  TSlimXmlDocExtractor = class
  private
    function NormalizeComment(const ALines: TStringList): String;
  public
    // Returns a dictionary where Key = "ClassName.MethodName" (or just "MethodName")
    // and Value = XML Content string
    function ExtractXmlDocs(const ASourceFile: String): TDictionary<String, String>;
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

    if (FRootSourcePath <> '') and (Result.UnitName <> '') then
      InjectXmlDocs(Result, Result.UnitName);

  finally
    FixtureInstance.Free;
    Ctx.Free;
  end;
end;

procedure TSlimDocExtractor.InjectXmlDocs(ADoc: TSlimFixtureDoc; const AUnitName: String);
var
  Files: TStringDynArray;
  SourceFile: String;
  XmlExtractor: TSlimXmlDocExtractor;
  Docs: TDictionary<String, String>;
  FullMemberName: String;
begin
  // Find file
  Files := TDirectory.GetFiles(FRootSourcePath, AUnitName + '.pas', TSearchOption.soAllDirectories);
  if Length(Files) = 0 then Exit;
  SourceFile := Files[0]; // Take first match

  XmlExtractor := TSlimXmlDocExtractor.Create;
  try
    Docs := XmlExtractor.ExtractXmlDocs(SourceFile);
    try
      // Enrich Class Description
      if Docs.ContainsKey(ADoc.DelphiClass) then
        ADoc.Description := Docs[ADoc.DelphiClass];

      // Enrich Methods
      for var M in ADoc.Methods do
      begin
        // Try 'ClassName.MethodName'
        FullMemberName := Format('%s.%s', [ADoc.DelphiClass, M.Name]);
        if Docs.ContainsKey(FullMemberName) then
          M.Description := Docs[FullMemberName]
        else if Docs.ContainsKey(M.Name) then
          M.Description := Docs[M.Name];
      end;
      
      // Enrich Properties
      for var P in ADoc.Properties do
      begin
        FullMemberName := Format('%s.%s', [ADoc.DelphiClass, P.Name]);
        if Docs.ContainsKey(FullMemberName) then
          P.Description := Docs[FullMemberName]
        else if Docs.ContainsKey(P.Name) then
          P.Description := Docs[P.Name];
      end;
    finally
      Docs.Free;
    end;
  finally
    XmlExtractor.Free;
  end;
end;


{ TSlimXmlDocExtractor }

function TSlimXmlDocExtractor.NormalizeComment(const ALines: TStringList): String;
var
  S: String;
begin
  Result := '';
  for S in ALines do
  begin
    var Line := S.Trim;
    if Line.StartsWith('///') then
      Line := Line.Substring(3).Trim;
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + Line;
  end;
end;

function TSlimXmlDocExtractor.ExtractXmlDocs(const ASourceFile: String): TDictionary<String, String>;
var
  ClassRegex  : TRegEx;
  CommentBlock: TStringList;
  I           : Integer;
  InComment   : Boolean;
  Line        : String;
  Lines       : TArray<string>;
  Match       : TMatch;
  MemberName  : String;
  MethodRegex : TRegEx;
begin
  Result := TDictionary<String, String>.Create;

  if not TFile.Exists(ASourceFile) then
    Exit;

  Lines := TFile.ReadAllLines(ASourceFile);
  CommentBlock := TStringList.Create;
  try
    InComment := False;
    // Regex to capture "procedure ClassName.MethodName"
    MethodRegex := TRegEx.Create('^(?:class\s+)?(procedure|function|constructor|destructor|property)\s+([\w\.]+)', [TRegExOption.roIgnoreCase]);
    // Regex to capture "TMyClass = class"
    ClassRegex := TRegEx.Create('^(\w+)\s*=\s*class', [TRegExOption.roIgnoreCase]);

    for I := 0 to High(Lines) do
    begin
      Line := Lines[I].Trim;

      if Line.StartsWith('///') then
      begin
        InComment := True;
        CommentBlock.Add(Line);
      end
      else if InComment then
      begin
        // Ignore attributes (lines starting with [)
        if Line.StartsWith('[') then
          Continue;

        // End of comment block, check if next line is a declaration
        if Line <> '' then
        begin
          Match := MethodRegex.Match(Line);
          if Match.Success then
          begin
           MemberName := Match.Groups[2].Value; // Method/Prop name
           if not Result.ContainsKey(MemberName) then
             Result.Add(MemberName, NormalizeComment(CommentBlock));
          end
          else
          begin
           Match := ClassRegex.Match(Line);
           if Match.Success then
           begin
             MemberName := Match.Groups[1].Value; // Class name
             if not Result.ContainsKey(MemberName) then
               Result.Add(MemberName, NormalizeComment(CommentBlock));
           end;
          end;
        end;

        // Reset
        CommentBlock.Clear;
        InComment := False;
      end;
    end;
  finally
    CommentBlock.Free;
  end;
end;

end.
