// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Fixtures;

interface

uses

  System.Classes,
  System.Contnrs,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.Rtti,
  System.StrUtils,
  System.SysUtils,
  System.Types,
  System.TypInfo,

  Slim.Fixture;

type

  [SlimFixture('Documentation', 'common')]
  TSlimDocumentationFixture = class(TSlimFixture)
  private
    FUsageMap: TObjectDictionary<String, TStringList>;
    function IsStandardNoise(const AMethodName: String): Boolean;
    function GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
    function GenerateDocumentation(const AFilePath: String): String;
    function AnalyzeUsage(const AFitNesseRoot: String): String;
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

procedure TSlimDocumentationFixture.AfterConstruction;
begin
  inherited;
  FUsageMap := TObjectDictionary<String, TStringList>.Create([doOwnsValues]);
end;

destructor TSlimDocumentationFixture.Destroy;
begin
  FUsageMap.Free;
  inherited;
end;

function TSlimDocumentationFixture.GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
var
  RelPath: String;
begin
  // Remove Root
  if AFilePath.StartsWith(AFitNesseRoot, True) then
    RelPath := AFilePath.Substring(AFitNesseRoot.Length)
  else
    RelPath := AFilePath;

  if RelPath.StartsWith(PathDelim) then
    RelPath := RelPath.Substring(1);

  // Remove extension
  RelPath := TPath.ChangeExtension(RelPath, '');

  // Handle content.txt
  if SameText(ExtractFileName(RelPath), 'content') then
     RelPath := ExtractFileDir(RelPath);

  // Replace separators
  Result := RelPath.Replace(PathDelim, '.');
end;

function TSlimDocumentationFixture.AnalyzeUsage(const AFitNesseRoot: String): String;
var
  SearchPatterns: TDictionary<String, TArray<String>>;
  FileName: String;
  Files: TStringDynArray;

  function CamelCaseToSpaced(const S: String): String;
  var
    SB: TStringBuilder;
    I: Integer;
  begin
    if S.IsEmpty then Exit('');
    SB := TStringBuilder.Create;
    try
      for I := 1 to S.Length do
      begin
        if (I > 1) and CharInSet(S[I], ['A'..'Z']) then
          SB.Append(' ');
        SB.Append(S[I]);
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  end;

  procedure CollectMethods;
  var
    C: TClass;
    Ctx: TRttiContext;
    Fixtures: TClassList;
    Method: TRttiMethod;
    Methods: TArray<TRttiMethod>;
    Patterns: TArray<String>;
    RType: TRttiType;
    Spaced: String;
  begin
    Fixtures := TSlimFixtureResolverAccess.GetFixtures;
    Ctx := TRttiContext.Create;
    try
      for C in Fixtures do
      begin
        if not C.InheritsFrom(TSlimFixture) then Continue;
        RType := Ctx.GetType(C);
        Methods := RType.GetMethods;
        for Method in Methods do
        begin
           if (Method.Visibility < mvPublic) or Method.IsConstructor or Method.IsDestructor then Continue;
           if IsStandardNoise(Method.Name) then Continue;

           if not SearchPatterns.ContainsKey(Method.Name) then
           begin
             SetLength(Patterns, 1);
             Patterns[0] := Method.Name;
             Spaced := CamelCaseToSpaced(Method.Name);
             if not SameText(Spaced, Method.Name) then
             begin
               SetLength(Patterns, 2);
               Patterns[1] := Spaced;
             end;
             SearchPatterns.Add(Method.Name, Patterns);
           end;
        end;
      end;
    finally
      Ctx.Free;
    end;
  end;

  procedure ProcessFile(const AFilePath: String);
  var
    FileContent: String;
    MethodName: String;
    Pat: String;
    UsageList: TStringList;
    WikiPageName: String;
  begin
    if ExtractFileName(AFilePath).StartsWith('RerunLastFailures', True) then
      Exit;

    try
      FileContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    except
      on E: EInOutError do
        Exit;
    end;

    WikiPageName := GetWikiPageName(AFitNesseRoot, AFilePath);

    for var Pair in SearchPatterns do
    begin
      MethodName := Pair.Key;
      for Pat in Pair.Value do
      begin
        if ContainsText(FileContent, Pat) then
        begin
          if not FUsageMap.TryGetValue(MethodName.ToLower, UsageList) then
          begin
            UsageList := TStringList.Create;
            UsageList.Sorted := True;
            UsageList.Duplicates := dupIgnore;
            FUsageMap.Add(MethodName.ToLower, UsageList);
          end;
          UsageList.Add(WikiPageName);
          Break; // Stop checking patterns for this method in this file
        end;
      end;
    end;
  end;

begin
  FUsageMap.Clear;
  SearchPatterns := TDictionary<String, TArray<String>>.Create;
  try
    CollectMethods;

    // Scan .wiki files
    Files := TDirectory.GetFiles(AFitNesseRoot, '*.wiki', TSearchOption.soAllDirectories);
    for FileName in Files do
      ProcessFile(FileName);

    // Scan content.txt files
    Files := TDirectory.GetFiles(AFitNesseRoot, 'content.txt', TSearchOption.soAllDirectories);
    for FileName in Files do
      ProcessFile(FileName);

    Result := Format('Analyzed %d files. Found usage for %d unique methods.', [Length(Files), FUsageMap.Count]);
  finally
    SearchPatterns.Free;
  end;
end;

function TSlimDocumentationFixture.IsStandardNoise(const AMethodName: String): Boolean;
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
    (AMethodName = 'Equals');
end;

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
  HasUsage        : Boolean;
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
  ToggleCell      : String;
  UsageList       : TStringList;
  UsageRowId      : String;
  UsageStr        : String;
  U               : String;

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
    // Header, CSS, JS, and Search Bar using Delphi Multi-Line String
    SB.Append(
      '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Slim Fixture Documentation</title>
        <style>
          body { font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background-color: #f9f9f9; padding-top: 80px; }
          h1 { color: #333; border-bottom: 2px solid #ddd; padding-bottom: 10px; }
          h2 { color: #0078d7; margin-top: 30px; }
          table { border-collapse: collapse; width: 100%; margin-bottom: 20px; background-color: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
          th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
          th { background-color: #f2f2f2; color: #333; }
          tr:nth-child(even) { background-color: #fcfcfc; }
          .fixture { background-color: white; border: 1px solid #ccc; padding: 20px; margin-bottom: 30px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
          .fixture-header { background-color: #e6f2ff; padding: 10px; font-weight: bold; font-size: 1.4em; border-radius: 5px; margin-bottom: 15px; border-left: 5px solid #0078d7; display: flex; justify-content: space-between; align-items: center; }
          .namespace { color: #555; font-size: 0.7em; font-weight: normal; margin-left: 10px; }
          .class-name { font-family: Consolas, monospace; color: #d63384; }
          .toc { background-color: white; padding: 20px; border: 1px solid #ddd; border-radius: 5px; margin-bottom: 30px; }

          /* Search Bar Styles */
          .search-container { position: fixed; top: 0; left: 0; right: 0; background-color: white; padding: 15px 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); z-index: 1000; display: flex; align-items: center; }
          #searchInput { flex-grow: 1; padding: 10px; font-size: 16px; border: 1px solid #ccc; border-radius: 4px; outline: none; }
          #searchInput:focus { border-color: #0078d7; }
          .search-label { margin-right: 15px; font-weight: bold; color: #555; }
          .hidden-by-search { display: none !important; }

          /* Styles for inherited members */
          .inherited-member { display: none; color: #777; font-style: italic; background-color: #f8f8f8 !important; }
          .inherited-toggle { font-size: 0.6em; font-weight: normal; margin-left: 20px; cursor: pointer; user-select: none; }

          /* Usage Row Styles */
          .usage-row { background-color: #f0f0f0; }
          .usage-content { padding: 5px 10px 5px 30px; font-size: 0.9em; color: #444; }
          .usage-content strong { color: #222; }
          .toggle-btn { cursor: pointer; color: #0078d7; font-weight: bold; user-select: none; display: inline-block; width: 16px; text-align: center; }
          .usage-links a { display: inline-block; margin-right: 5px; margin-bottom: 3px; padding: 1px 5px; background-color: #fff; border-radius: 3px; font-size: 0.9em; color: #333; text-decoration: none; border: 1px solid #ccc; }
          .usage-links a:hover { background-color: #e6f2ff; border-color: #0078d7; }
        </style>
        <script>
          function toggleInherited(checkbox, fixtureId) {
            var container = document.getElementById(fixtureId);
            var rows = container.querySelectorAll(".inherited-member");
            for (var i = 0; i < rows.length; i++) {
              if (rows[i].classList.contains("usage-row")) {
                 // Keep usage row hidden unless manually toggled?
                 // Or just let it be controlled by its parent row?
                 // Actually inherited-member class is on the main row.
                 // The usage row should probably also have inherited-member if parent does?
                 // For simplicity, we hide them. If user expands usage, it will show.
                 rows[i].style.display = "none"; 
                 // Reset the toggle button on parent if we hide? 
                 // Maybe too complex for now.
              } else {
                 rows[i].style.display = checkbox.checked ? "table-row" : "none";
              }
            }
          }

          function toggleUsage(btn, rowId) {
            var row = document.getElementById(rowId);
            if (!row) return;
            if (row.style.display === "none") {
              row.style.display = "table-row";
              btn.innerHTML = "&#9660;"; // Down arrow
            } else {
              row.style.display = "none";
              btn.innerHTML = "&#9658;"; // Right arrow
            }
          }

          function filterFixtures() {
            var input = document.getElementById("searchInput");
            var filter = input.value.toUpperCase();
            var fixtures = document.getElementsByClassName("fixture");
            var tocLinks = document.querySelectorAll(".toc li");

            for (var i = 0; i < fixtures.length; i++) {
              var fixture = fixtures[i];
              var header = fixture.querySelector(".fixture-header");
              var headerText = header.textContent || header.innerText;
              var headerMatches = headerText.toUpperCase().indexOf(filter) > -1;

              var rows = fixture.querySelectorAll("tbody tr");
              var hasVisibleRow = false;

              for (var j = 0; j < rows.length; j++) {
                var row = rows[j];
                // Skip usage rows in search logic to avoid double counting or mess
                if (row.classList.contains("usage-row")) continue;

                var rowText = row.textContent || row.innerText;
                if (rowText.toUpperCase().indexOf(filter) > -1 || headerMatches) {
                  row.classList.remove("hidden-by-search");
                  hasVisibleRow = true;
                  var usageRow = row.nextElementSibling;
                  if (usageRow && usageRow.classList.contains("usage-row")) {
                     usageRow.classList.remove("hidden-by-search");
                  }
                } else {
                  row.classList.add("hidden-by-search");
                  // Also hide the usage row if parent is hidden
                  var usageRow = row.nextElementSibling;
                  if (usageRow && usageRow.classList.contains("usage-row")) {
                     usageRow.classList.add("hidden-by-search");
                  }
                }
              }

              if (hasVisibleRow || headerMatches) {
                fixture.style.display = "";
              } else {
                fixture.style.display = "none";
              }
            }

            for (var k = 0; k < tocLinks.length; k++) {
              var link = tocLinks[k];
              if (link.textContent.toUpperCase().indexOf(filter) > -1) {
                link.style.display = "";
              } else {
                link.style.display = "none";
              }
            }
          }
        </script>
      </head>
      <body>
        <div class="search-container">
          <span class="search-label">Slim Docs</span>
          <input type="text" id="searchInput" onkeyup="filterFixtures()" placeholder="Search for fixtures, namespaces, methods or properties...">
        </div>
        <h1>Registered Slim Fixtures</h1>
      ''');

    Fixtures := TSlimFixtureResolverAccess.GetFixtures;
    for C in Fixtures do
      if C.InheritsFrom(TSlimFixture) then
        FixtureList.Add(TSlimFixtureClass(C));

    // Sort by Namespace then Name
    FixtureList.Sort(TComparer<TSlimFixtureClass>.Construct(
      function(const Left, Right: TSlimFixtureClass): Integer
      var
        Attr : TCustomAttribute;
        LAttr: SlimFixtureAttribute;
        LName: String;
        LNs  : String;
        LType: TRttiType;
        RAttr: SlimFixtureAttribute;
        RName: String;
        RNs  : String;
        RType: TRttiType;
      begin
        LType := Ctx.GetType(Left);
        RType := Ctx.GetType(Right);
        LNs := '';
        RNs := '';
        LName := LType.Name;
        RName := RType.Name;

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
      SB.Append('''
        <h3>Methods</h3>
        <table>
          <thead>
            <tr>
              <th style="width: 20px;"></th>
              <th>Name</th>
              <th>Parameters</th>
              <th>Return Type</th>
              <th>Sync Mode</th>
              <th>Origin</th>
            </tr>
          </thead>
          <tbody>
      ''');

      Methods := RType.GetMethods;
      TArray.Sort<TRttiMethod>(Methods, TComparer<TRttiMethod>.Construct(
        function(const L, R: TRttiMethod): Integer
        begin
          Result := CompareText(L.Name, R.Name);
        end
      ));

      for Method in Methods do
      begin
        if Method.Visibility < mvPublic then
          Continue;
        if Method.IsConstructor or Method.IsDestructor then
          Continue;

        // Filter standard noise
        if IsStandardNoise(Method.Name) then
          Continue;

        // Determine if inherited
        IsInherited := Method.Parent <> RType;

        RowClass := '';
        InheritedLabel := 'Self';

        if IsInherited then
        begin
          RowClass := 'inherited-member';
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

        // Usage Info
        HasUsage := FUsageMap.TryGetValue(Method.Name.ToLower, UsageList) and (UsageList.Count > 0);
        
        UsageRowId := Format('usage-%s-%s', [FixtureId, Method.Name]);
        // Sanitize ID
        UsageRowId := UsageRowId.Replace('.', '-');

        ToggleCell := '';
        if HasUsage then
          ToggleCell := Format('<span class="toggle-btn" onclick="toggleUsage(this, ''%s'')">&#9658;</span>', [UsageRowId]);

        if RowClass <> '' then RowClass := ' class="' + RowClass + '"';

        SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td style="color:#888">%s</td></tr>',
          [RowClass, ToggleCell, Method.Name, Params, RetType, GetSyncModeStr(Method), InheritedLabel]);

        // Secondary Row for Usage
        if HasUsage then
        begin
          UsageStr := '<div class="usage-links">';
          for U in UsageList do
          begin
             UsageStr := UsageStr + Format('<a href="../%s" target="_blank">%s</a>', [U, U]);
          end;
          UsageStr := UsageStr + '</div>';

          // Reuse RowClass if it was inherited, so it toggles visibility correctly
          if IsInherited then
             RowClass := ' class="inherited-member usage-row"'
          else
             RowClass := ' class="usage-row"';
          
          // Default style is hidden
          SB.AppendFormat('<tr%s id="%s" style="display:none;"><td colspan="6"><div class="usage-content"><strong>Used in:</strong> %s</div></td></tr>',
            [RowClass, UsageRowId, UsageStr]);
        end;
      end;
      SB.AppendLine('</tbody></table>');

      // Properties
      SB.Append('''
        <h3>Properties</h3>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Type</th>
              <th>Access</th>
              <th>Origin</th>
            </tr>
          </thead>
          <tbody>
      ''');

      Properties := RType.GetProperties;
      TArray.Sort<TRttiProperty>(Properties, TComparer<TRttiProperty>.Construct(
        function(const L, R: TRttiProperty): Integer
        begin
          Result := CompareText(L.Name, R.Name);
        end
      ));

      for Prop in Properties do
      begin
        if Prop.Visibility < mvPublic then
          Continue;

        IsInherited := Prop.Parent <> RType;

        RowClass := '';
        InheritedLabel := 'Self';

        if IsInherited then
        begin
          RowClass := ' class="inherited-member"';
          InheritedLabel := Prop.Parent.Name;
        end;

        Access := '';
        if Prop.IsReadable then
          Access := 'Read';
        if Prop.IsWritable then
        begin
          if Access <> '' then
            Access := Access + '/Write'
          else
            Access := 'Write';
        end;

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
