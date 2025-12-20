// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Common.SlimDocumentationFixture;

interface

uses

  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,

  Slim.Fixture;

type

  [SlimFixture('Documentation', 'common')]
  TSlimDocumentationFixture = class(TSlimFixture)
  public
    function GenerateDocumentation(const AFilePath: String): String;
  end;

implementation

type

  TSlimFixtureResolverAccess = class(TSlimFixtureResolver)
  public
    class function GetFixtures: TClassList;
  end;

{ TSlimFixtureResolverAccess }

class function TSlimFixtureResolverAccess.GetFixtures: TClassList;
begin
  Result := FFixtures;
end;

{ TSlimDocumentationFixture }

function TSlimDocumentationFixture.GenerateDocumentation(const AFilePath: String): String;
var
  Access          : String;
  Attr            : TCustomAttribute;
  C               : TClass;
  Ctx             : TRttiContext;
  FixtureClass    : TSlimFixtureClass;
  FixtureId       : String;
  FixtureList     : TList<TSlimFixtureClass>;
  FixtureName     : String;
  FixtureNamespace: String;
  Fixtures        : TClassList;
  InheritedLabel  : String;
  IsInherited     : Boolean;
  LinkName        : String;
  Method          : TRttiMethod;
  Methods         : TArray<TRttiMethod>;
  Params          : String;
  Prop            : TRttiProperty;
  Properties      : TArray<TRttiProperty>;
  RetType         : String;
  RowClass        : String;
  RType           : TRttiType;
  SB              : TStringBuilder;

  function GetSyncModeStr(AMember: TRttiMember): String;
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

begin
  SB := TStringBuilder.Create;
  Ctx := TRttiContext.Create;
  FixtureList := TList<TSlimFixtureClass>.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html><head><meta charset="utf-8"><title>Slim Fixture Documentation</title>');

    // CSS
    SB.AppendLine('<style>');
    SB.AppendLine('body { font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background-color: #f9f9f9; }');
    SB.AppendLine('h1 { color: #333; border-bottom: 2px solid #ddd; padding-bottom: 10px; }');
    SB.AppendLine('h2 { color: #0078d7; margin-top: 30px; }');
    SB.AppendLine('table { border-collapse: collapse; width: 100%; margin-bottom: 20px; background-color: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }');
    SB.AppendLine('th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }');
    SB.AppendLine('th { background-color: #f2f2f2; color: #333; }');
    SB.AppendLine('tr:nth-child(even) { background-color: #fcfcfc; }');
    SB.AppendLine('.fixture { background-color: white; border: 1px solid #ccc; padding: 20px; margin-bottom: 30px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }');
    SB.AppendLine('.fixture-header { background-color: #e6f2ff; padding: 10px; font-weight: bold; font-size: 1.4em; border-radius: 5px; margin-bottom: 15px; border-left: 5px solid #0078d7; display: flex; justify-content: space-between; align-items: center; }');
    SB.AppendLine('.namespace { color: #555; font-size: 0.7em; font-weight: normal; margin-left: 10px; }');
    SB.AppendLine('.class-name { font-family: Consolas, monospace; color: #d63384; }');
    SB.AppendLine('.toc { background-color: white; padding: 20px; border: 1px solid #ddd; border-radius: 5px; margin-bottom: 30px; }');

    // Styles for inherited members
    SB.AppendLine('.inherited-member { display: none; color: #777; font-style: italic; background-color: #f8f8f8 !important; }');
    SB.AppendLine('.inherited-toggle { font-size: 0.6em; font-weight: normal; margin-left: 20px; cursor: pointer; user-select: none; }');
    SB.AppendLine('</style>');

    // JavaScript
    SB.AppendLine('<script>');
    SB.AppendLine('function toggleInherited(checkbox, fixtureId) {');
    SB.AppendLine('  var container = document.getElementById(fixtureId);');
    SB.AppendLine('  var rows = container.querySelectorAll(".inherited-member");');
    SB.AppendLine('  for (var i = 0; i < rows.length; i++) {');
    SB.AppendLine('    rows[i].style.display = checkbox.checked ? "table-row" : "none";');
    SB.AppendLine('  }');
    SB.AppendLine('}');
    SB.AppendLine('</script>');

    SB.AppendLine('</head><body>');

    SB.AppendLine('<h1>Registered Slim Fixtures</h1>');

    Fixtures := TSlimFixtureResolverAccess.GetFixtures;
    for C in Fixtures do
      if C.InheritsFrom(TSlimFixture) then
        FixtureList.Add(TSlimFixtureClass(C));

    // Sort by Namespace then Name
    FixtureList.Sort(TComparer<TSlimFixtureClass>.Construct(
      function(const Left, Right: TSlimFixtureClass): Integer
      var
        LType, RType: TRttiType;
        LName, RName, LNs, RNs: String;
        LAttr, RAttr: SlimFixtureAttribute;
        Attr: TCustomAttribute;
      begin
        LType := Ctx.GetType(Left);
        RType := Ctx.GetType(Right);

        LName := LType.Name; LNs := '';
        RName := RType.Name; RNs := '';

        for Attr in LType.GetAttributes do
          if Attr is SlimFixtureAttribute then
          begin
            LAttr := SlimFixtureAttribute(Attr);
            LName := LAttr.Name;
            LNs := LAttr.Namespace;
            Break;
          end;

        for Attr in RType.GetAttributes do
          if Attr is SlimFixtureAttribute then
          begin
            RAttr := SlimFixtureAttribute(Attr);
            RName := RAttr.Name;
            RNs := RAttr.Namespace;
            Break;
          end;

        Result := CompareText(LNs, RNs);
        if Result = 0 then
          Result := CompareText(LName, RName);
      end));

    // Table of Contents
    SB.AppendLine('<div class="toc"><h2>Table of Contents</h2><ul>');
    for FixtureClass in FixtureList do
    begin
      RType := Ctx.GetType(FixtureClass);
      FixtureName := RType.Name;
      FixtureNamespace := 'global';

      for Attr in RType.GetAttributes do
        if Attr is SlimFixtureAttribute then
        begin
           FixtureName := SlimFixtureAttribute(Attr).Name;
           if SlimFixtureAttribute(Attr).Namespace <> '' then
              FixtureNamespace := SlimFixtureAttribute(Attr).Namespace;
           Break;
        end;
      SB.AppendFormat('<li><a href="#%s.%s">%s</a> <span style="color:#888">(%s)</span></li>',
        [FixtureNamespace, FixtureName, FixtureName, FixtureNamespace]);
    end;
    SB.AppendLine('</ul></div>');

    // Fixtures
    for FixtureClass in FixtureList do
    begin
      RType := Ctx.GetType(FixtureClass);
      FixtureName := RType.Name;
      FixtureNamespace := 'global';

      for Attr in RType.GetAttributes do
        if Attr is SlimFixtureAttribute then
        begin
           FixtureName := SlimFixtureAttribute(Attr).Name;
           if SlimFixtureAttribute(Attr).Namespace <> '' then
              FixtureNamespace := SlimFixtureAttribute(Attr).Namespace;
           Break;
        end;

      FixtureId := Format('%s.%s', [FixtureNamespace, FixtureName]);

      SB.AppendFormat('<div class="fixture" id="%s">', [FixtureId]);

      // Header with Checkbox
      SB.Append('<div class="fixture-header">');
      SB.AppendFormat('<span>%s <span class="namespace">%s</span></span>', [FixtureName, FixtureNamespace]);
      SB.AppendFormat('<label class="inherited-toggle"><input type="checkbox" onclick="toggleInherited(this, ''%s'')"> Show inherited members</label>', [FixtureId]);
      SB.Append('</div>');

      SB.AppendFormat('<p><strong>Delphi Class:</strong> <span class="class-name">%s</span></p>', [RType.Name]);
      SB.AppendFormat('<p><strong>Unit:</strong> %s</p>', [FixtureClass.UnitName]);

      // Methods
      SB.AppendLine('<h3>Methods</h3>');
      SB.AppendLine('<table><thead><tr><th>Name</th><th>Parameters</th><th>Return Type</th><th>Sync Mode</th><th>Origin</th></tr></thead><tbody>');

      Methods := RType.GetMethods;
      TArray.Sort<TRttiMethod>(Methods, TComparer<TRttiMethod>.Construct(
        function(const L, R: TRttiMethod): Integer
        begin
          Result := CompareText(L.Name, R.Name);
        end
      ));

      for Method in Methods do
      begin
        if Method.Visibility < mvPublic then Continue;
        if Method.IsConstructor or Method.IsDestructor then Continue;

        // Filter standard noise
        if (Method.Name = 'BeforeDestruction') or (Method.Name = 'AfterConstruction') or
           (Method.Name = 'Free') or (Method.Name = 'DisposeOf') or 
           (Method.Name = 'Dispatch') or (Method.Name = 'DefaultHandler') or
           (Method.Name = 'NewInstance') or (Method.Name = 'FreeInstance') or
           (Method.Name = 'InheritsFrom') or (Method.Name = 'ClassType') or
           (Method.Name = 'ClassName') or (Method.Name = 'ClassInfo') or
           (Method.Name = 'ClassParent') or (Method.Name = 'FieldAddress') or
           (Method.Name = 'MethodAddress') or (Method.Name = 'MethodName') or
           (Method.Name = 'InstanceSize') or (Method.Name = 'GetInterface') or
           (Method.Name = 'GetInterfaceEntry') or (Method.Name = 'GetInterfaceTable') or
           (Method.Name = 'SafeCallException') or (Method.Name = 'ToString') or
           (Method.Name = 'GetHashCode') or (Method.Name = 'Equals') then Continue;

        // Determine if inherited
        // Note: Comparing RTTI objects directly usually works for checking definition context.
        IsInherited := Method.Parent <> RType;

        RowClass := '';
        InheritedLabel := 'Self';

        if IsInherited then
        begin
          RowClass := ' class="inherited-member"';
          InheritedLabel := Method.Parent.Name;
        end;

        Params := '';
        for var P in Method.GetParameters do
        begin
          if Params <> '' then Params := Params + ', ';
          Params := Params + P.Name + ': ' + P.ParamType.Name;
        end;

        RetType := 'void';
        if Assigned(Method.ReturnType) then RetType := Method.ReturnType.Name;

        SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td style="color:#888">%s</td></tr>',
          [RowClass, Method.Name, Params, RetType, GetSyncModeStr(Method), InheritedLabel]);
      end;
      SB.AppendLine('</tbody></table>');

      // Properties
      SB.AppendLine('<h3>Properties</h3>');
      SB.AppendLine('<table><thead><tr><th>Name</th><th>Type</th><th>Access</th><th>Origin</th></tr></thead><tbody>');

      Properties := RType.GetProperties;
      TArray.Sort<TRttiProperty>(Properties, TComparer<TRttiProperty>.Construct(
        function(const L, R: TRttiProperty): Integer
        begin
          Result := CompareText(L.Name, R.Name);
        end
      ));

      for Prop in Properties do
      begin
        if Prop.Visibility < mvPublic then Continue;

        IsInherited := Prop.Parent <> RType;

        RowClass := '';
        InheritedLabel := 'Self';

        if IsInherited then
        begin
          RowClass := ' class="inherited-member"';
          InheritedLabel := Prop.Parent.Name;
        end;

        Access := '';
        if Prop.IsReadable then Access := 'Read';
        if Prop.IsWritable then
          if Access <> '' then Access := Access + '/Write' else Access := 'Write';

        SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td style="color:#888">%s</td></tr>',
          [RowClass, Prop.Name, Prop.PropertyType.Name, Access, InheritedLabel]);
      end;
      SB.AppendLine('</tbody></table>');

      SB.AppendLine('</div>');
    end;

    SB.AppendLine('</body></html>');

    TFile.WriteAllText(AFilePath, SB.ToString, TEncoding.UTF8);

    LinkName := ExtractFileName(AFilePath);
    Result := Format('<a href="files/%s" target="_blank">Open Documentation</a>', [LinkName]);

  finally
    FixtureList.Free;
    Ctx.Free;
    SB.Free;
  end;
end;

initialization
  RegisterSlimFixture(TSlimDocumentationFixture);

end.