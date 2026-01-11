// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Extractor;

interface

uses

  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.NetEncoding,
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
    FExcludePaths: TStringList;
    FIncludePaths: TStringList;
    FUnitMap     : TDictionary<String, String>;
    procedure EnsureUnitMap;
    function  GetSyncModeStr(AMember: TRttiMember; AInstance: TSlimFixture): String;
    procedure InjectXmlDocs(ADoc: TSlimDocFixture; const AUnitName: String);
    function  IsStandardNoise(const AMethodName: String): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddExcludePath(const APath: String);
    procedure AddIncludePath(const APath: String);
    function  ExtractAll: TObjectList<TSlimDocFixture>;
    function  ExtractClass(AClass: TClass): TSlimDocFixture;
  end;

  TSlimXmlDocExtractor = class
  private
    function NormalizeComment(ALines: TStringList): String;
  public
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

constructor TSlimDocExtractor.Create;
begin
  inherited;
  FExcludePaths := TStringList.Create;
  FExcludePaths.Sorted := True;
  FIncludePaths := TStringList.Create;
  FIncludePaths.Sorted := True;
  FIncludePaths.Duplicates := dupIgnore;
  FUnitMap := TDictionary<String, String>.Create(System.Generics.Defaults.TStringComparer.Ordinal);
end;

destructor TSlimDocExtractor.Destroy;
begin
  FUnitMap.Free;
  FIncludePaths.Free;
  FExcludePaths.Free;
  inherited;
end;

procedure TSlimDocExtractor.AddExcludePath(const APath: String);
begin
  FExcludePaths.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(APath)));
end;

procedure TSlimDocExtractor.AddIncludePath(const APath: String);
begin
  FIncludePaths.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(APath)));
end;

procedure TSlimDocExtractor.EnsureUnitMap;
var
  FileName: String;
  Files   : TStringDynArray;
  Skip    : Boolean;
begin
  if (FUnitMap.Count > 0) or
     FIncludePaths.IsEmpty then
    Exit;

  for var Path: String in FIncludePaths do
  begin
    if not TDirectory.Exists(Path) then
      Continue;

    Files := TDirectory.GetFiles(Path, '*.pas', TSearchOption.soAllDirectories);
    for var FilePath: String in Files do
    begin
      Skip := False;
      for var ExcludePath: String in FExcludePaths do
      begin
        if FilePath.StartsWith(ExcludePath, True) then
        begin
          Skip := True;
          Break;
        end;
      end;

      if not Skip then
      begin
        FileName := TPath.GetFileNameWithoutExtension(FilePath);
        // Assuming filename matches unit name
        if not FUnitMap.ContainsKey(FileName) then
          FUnitMap.Add(FileName, FilePath);
      end;
    end;
  end;
end;

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
begin
  for var LAttr: TCustomAttribute in AMember.GetAttributes do
  begin
    if LAttr is SlimMemberSyncModeAttribute then
      Exit(GetEnumName(TypeInfo(TSyncMode), Ord(SlimMemberSyncModeAttribute(LAttr).SyncMode)));
  end;
  if Assigned(AInstance) then
  begin
    var Mode : TSyncMode := AInstance.SyncMode(AMember);
    Result := GetEnumName(TypeInfo(TSyncMode), Ord(Mode));
  end;
end;

function TSlimDocExtractor.ExtractAll: TObjectList<TSlimDocFixture>;
begin
  Result := TObjectList<TSlimDocFixture>.Create(True);
  for var C: TClass in TSlimFixtureResolverAccess.GetFixtures do
  begin
    if C.InheritsFrom(TSlimFixture) then
      Result.Add(ExtractClass(C));
  end;
end;

function TSlimDocExtractor.ExtractClass(AClass: TClass): TSlimDocFixture;
var
  Ctx            : TRttiContext;
  DocMethod      : TSlimDocMethod;
  DocProp        : TSlimDocProperty;
  FixtureInstance: TSlimFixture;
  ParentClassRef : TClass;
  RType          : TRttiType;
begin
  Result := TSlimDocFixture.Create;
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

    for var Attr: TCustomAttribute in RType.GetAttributes do
      if Attr is SlimFixtureAttribute then
      begin
        Result.Name := SlimFixtureAttribute(Attr).Name;
        if SlimFixtureAttribute(Attr).Namespace <> '' then
          Result.Namespace := SlimFixtureAttribute(Attr).Namespace;
        Break;
      end;

    for var Method: TRttiMethod in RType.GetMethods do
    begin
      if (Method.Visibility < mvPublic) or
         (Method.IsDestructor ) or
         (Method.IsConstructor and (Length(Method.GetParameters) = 0)) or
         IsStandardNoise(Method.Name) then
        Continue;

      DocMethod := TSlimDocMethod.Create;
      DocMethod.Name := Method.Name;
      DocMethod.IsInherited := Method.Parent <> RType;
      DocMethod.Origin := Method.Parent.Name;
      if not DocMethod.IsInherited then
        DocMethod.Origin := 'Self';

      DocMethod.SyncMode := GetSyncModeStr(Method, FixtureInstance);
      if Assigned(Method.ReturnType) then
        DocMethod.ReturnType := Method.ReturnType.Name
      else
        DocMethod.ReturnType := 'void';

      DocMethod.DeclaringClass := Method.Parent.Name;
      var MemberUnitName := Method.Parent.AsInstance.MetaclassType.UnitName;
      EnsureUnitMap;
      if FUnitMap.ContainsKey(MemberUnitName) then
        DocMethod.UnitPath := FUnitMap[MemberUnitName];

      for var Param: TRttiParameter in Method.GetParameters do
        DocMethod.Parameters.Add(TSlimDocParameter.Create(Param.Name, Param.ParamType.Name));

      if Method.IsConstructor then
        Result.Constructors.Add(DocMethod)
      else
        Result.Methods.Add(DocMethod);
    end;

    for var Prop: TRttiProperty in RType.GetProperties do
    begin
      if (Prop.Visibility < mvPublic) or
         IsStandardNoise(Prop.Name) then
        Continue;

      DocProp := TSlimDocProperty.Create;
      DocProp.Name := Prop.Name;
      DocProp.PropertyType := Prop.PropertyType.Name;
      DocProp.IsInherited := Prop.Parent <> RType;
      DocProp.Origin := Prop.Parent.Name;
      if not DocProp.IsInherited then
        DocProp.Origin := 'Self';
      DocProp.SyncMode := GetSyncModeStr(Prop, FixtureInstance);

      DocProp.DeclaringClass := Prop.Parent.Name;
      var MemberUnitName := Prop.Parent.AsInstance.MetaclassType.UnitName;
      EnsureUnitMap;
      if FUnitMap.ContainsKey(MemberUnitName) then
        DocProp.UnitPath := FUnitMap[MemberUnitName];

      var LIsReadable: Boolean:=Prop.IsReadable;
      var LIsWritable: Boolean:=Prop.IsWritable;
      if LIsReadable and LIsWritable then
        DocProp.Access := 'Read/Write'
      else if LIsReadable then
        DocProp.Access := 'Read'
      else if LIsWritable then
        DocProp.Access := 'Write';
      Result.Properties.Add(DocProp);
    end;

    if Result.UnitName <> '' then
    begin
      EnsureUnitMap;
      if FUnitMap.ContainsKey(Result.UnitName) then
      begin
        Result.UnitPath := FUnitMap[Result.UnitName];
        Result.OpenUnitLink := Format('dpt://openunit/?file=%s', [TNetEncoding.URL.Encode(Result.UnitPath)]);
      end;

      InjectXmlDocs(Result, Result.UnitName);
    end;
  finally
    FixtureInstance.Free;
    Ctx.Free;
  end;
end;

procedure TSlimDocExtractor.InjectXmlDocs(ADoc: TSlimDocFixture; const AUnitName: String);
var
  Description   : String;
  Docs          : TDictionary<String, String>;
  FullMemberName: String;
  SourceFile    : String;
  XmlExtractor  : TSlimXmlDocExtractor;
begin
  EnsureUnitMap;

  if not FUnitMap.TryGetValue(AUnitName, SourceFile) then
    Exit;

  Docs := nil;
  XmlExtractor := TSlimXmlDocExtractor.Create;
  try
    Docs := XmlExtractor.ExtractXmlDocs(SourceFile);
    if Docs.TryGetValue(ADoc.DelphiClass, Description) then
      ADoc.Description := Description;

    for var M: TSlimDocMethod in ADoc.Methods do
    begin
      if M.IsInherited then
        Continue;

      FullMemberName := Format('%s.%s', [ADoc.DelphiClass, M.Name]);
      if Docs.TryGetValue(FullMemberName, Description) or
         Docs.TryGetValue(M.Name, Description) then
        M.Description := Description;
    end;

    for var C: TSlimDocMethod in ADoc.Constructors do
    begin
      if C.IsInherited then
        Continue;

      FullMemberName := Format('%s.%s', [ADoc.DelphiClass, C.Name]);
      if Docs.TryGetValue(FullMemberName, Description) or
         Docs.TryGetValue(C.Name, Description) then
        C.Description := Description;
    end;

    for var P: TSlimDocProperty in ADoc.Properties do
    begin
      if P.IsInherited then
        Continue;

      FullMemberName := Format('%s.%s', [ADoc.DelphiClass, P.Name]);
      if Docs.TryGetValue(FullMemberName, Description) or
         Docs.TryGetValue(P.Name, Description) then
        P.Description := Description;
    end;
  finally
    Docs.Free;
    XmlExtractor.Free;
  end;
end;

{ TSlimXmlDocExtractor }

function TSlimXmlDocExtractor.NormalizeComment(ALines: TStringList): String;
begin
  Result := '';
  for var S: String in ALines do
  begin
    var Line: String := S.Trim;
    if Line.StartsWith('///') then
      Line := Line.Substring(3).Trim;
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + Line;
  end;
end;

/// <summary>
///   Returns a dictionary where Key = "ClassName.MethodName" (or just "MethodName")
///   and Value = XML Content string
/// </summary>
function TSlimXmlDocExtractor.ExtractXmlDocs(const ASourceFile: String): TDictionary<String, String>;
var
  ClassRegex  : TRegEx;
  CommentBlock: TStringList;
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

    for var Loop: Integer := 0 to High(Lines) do
    begin
      Line := Lines[Loop].Trim;
      if (Line = '') or
         Line.StartsWith('[') then // Ignore attributes (lines starting with [)
        Continue;

      if Line.StartsWith('///') then
      begin
        InComment := True;
        CommentBlock.Add(Line);
      end
      else if InComment then
      begin
        // End of comment block, check if next line is a declaration
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

