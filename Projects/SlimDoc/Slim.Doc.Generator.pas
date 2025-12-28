// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Generator;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,

  Slim.Doc.Model,
  Slim.Doc.Utils,
  Slim.Doc.UsageAnalyzer;

type

  TSlimDocGenerator = class
  private
    function  FormatXmlComment(const AXml: String): String;
    procedure SortFixtures(AFixtures: TList<TSlimDocFixture>);
    procedure SortMembers(AList: TList<TSlimDocMember>);
  public
    function Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const AOutputFilePath: String): String;
  end;

implementation

{ TSlimDocGenerator }

procedure TSlimDocGenerator.SortFixtures(AFixtures: TList<TSlimDocFixture>);
begin
  AFixtures.Sort(TComparer<TSlimDocFixture>.Construct(
    function(const L, R: TSlimDocFixture): Integer
    begin
      Result := CompareText(L.Namespace, R.Namespace);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));
end;

procedure TSlimDocGenerator.SortMembers(AList: TList<TSlimDocMember>);
begin
  AList.Sort(TComparer<TSlimDocMember>.Construct(
    function(const L, R: TSlimDocMember): Integer
    begin
      Result := CompareText(L.Name, R.Name);
    end));
end;

function TSlimDocGenerator.FormatXmlComment(const AXml: String): String;
begin
  if AXml = '' then
    Exit('');
  
  Result := AXml;
  // Summary
  Result := TRegEx.Replace(Result, '<summary>\s*(.*?)</summary>', '<div class="xml-summary">$1</div>', [roSingleLine, roIgnoreCase]);
  
  // Params
  Result := TRegEx.Replace(Result, '<param name="(.*?)">\s*', '<div class="xml-param"><span class="xml-param-name">$1</span>: ', [roIgnoreCase]);
  Result := Result.Replace('</param>', '</div>', [rfReplaceAll, rfIgnoreCase]);

  // Returns
  Result := Result.Replace('<returns>', '<div class="xml-returns"><span class="xml-param-name">Returns:</span> ', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('</returns>', '</div>', [rfReplaceAll, rfIgnoreCase]);
end;

function TSlimDocGenerator.Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const AOutputFilePath: String): String;
var
  Fixture   : TSlimDocFixture;
  HasUsage  : Boolean;
  LinkName  : String;
  Method    : TSlimDocMethod;
  Prop      : TSlimDocProperty;
  RowClass  : String;
  SB        : TStringBuilder;
  ToggleCell: String;
  U         : String;
  UsageList : TStringList;
  UsageRowId: String;
  UsageStr  : String;
begin
  SortFixtures(AFixtures);
  SB := TStringBuilder.Create;
  try
    SB.Append('''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Slim Fixture Documentation</title>
        <style>
          body { font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background-color: #f9f9f9; padding-top: 110px; }
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
          .search-container { position: fixed; top: 0; left: 0; right: 0; background-color: white; padding: 10px 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); z-index: 1000; display: flex; flex-direction: column; }
          .search-row { display: flex; align-items: center; margin-bottom: 8px; }
          #searchInput { flex-grow: 1; padding: 10px; font-size: 16px; border: 1px solid #ccc; border-radius: 4px; outline: none; }
          #searchInput:focus { border-color: #0078d7; }
          .search-label { margin-right: 15px; font-weight: bold; color: #555; }
          .filter-options { display: flex; font-size: 0.9em; color: #555; gap: 15px; }
          .filter-options label { cursor: pointer; display: flex; align-items: center; }
          .filter-options input { margin-right: 5px; }
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

          /* Description Styles */
          .description-content { color: #555; }
          .fixture-description { padding: 10px; margin-bottom: 20px; background-color: #f9f9f9; border-left: 4px solid #ddd; }
          .member-description { padding: 5px 10px 5px 30px; }
          
          /* XML Doc Styles */
          .xml-summary { margin-bottom: 8px; display: block; white-space: pre-wrap; }
          .xml-param { margin-left: 10px; display: block; }
          .xml-param-name { font-weight: bold; font-family: Consolas, monospace; color: #333; }
          .xml-returns { margin-left: 10px; margin-top: 8px; display: block; }
        </style>
        <script>
          function toggleInherited(checkbox, fixtureId) {
            var container = document.getElementById(fixtureId);
            var rows = container.querySelectorAll(".inherited-member");
            for (var i = 0; i < rows.length; i++) {
              if (rows[i].classList.contains("usage-row")) {
                 rows[i].style.display = "none"; 
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
              btn.innerHTML = "&#9660;";
            } else {
              row.style.display = "none";
              btn.innerHTML = "&#9658;";
            }
          }

          function updateSearchOption() {
            var useFixture = document.getElementById("chkFixture").checked;
            var useNamespace = document.getElementById("chkNamespace").checked;
            var useMember = document.getElementById("chkMember").checked;
            var useComment = document.getElementById("chkComment").checked;
            var useUsage = document.getElementById("chkUsage").checked;
            
            var parts = [];
            if (useFixture) parts.push("fixtures");
            if (useNamespace) parts.push("namespaces");
            if (useMember) parts.push("methods/properties");
            if (useComment) parts.push("comments");
            if (useUsage) parts.push("usage");
            
            var text = "Search";
            if (parts.length > 0) {
               text += " for " + parts.join(", ");
            }
            text += "...";
            
            document.getElementById("searchInput").placeholder = text;
            filterFixtures();
          }

          function filterFixtures() {
            var input = document.getElementById("searchInput");
            var filter = input.value.toUpperCase();
            
            var useFixture = document.getElementById("chkFixture").checked;
            var useNamespace = document.getElementById("chkNamespace").checked;
            var useMember = document.getElementById("chkMember").checked;
            var useComment = document.getElementById("chkComment").checked;
            var useUsage = document.getElementById("chkUsage").checked;

            var fixtures = document.getElementsByClassName("fixture");
            var tocLinks = document.querySelectorAll(".toc li");

            for (var i = 0; i < fixtures.length; i++) {
              var fixture = fixtures[i];
              var header = fixture.querySelector(".fixture-header");
              
              // Fixture & Namespace
              var headerText = "";
              if (useFixture) headerText += (header.querySelector("span:first-child").firstChild.textContent || ""); // Name
              if (useNamespace) headerText += (header.querySelector(".namespace").textContent || "");

              // Also check class name if useFixture
              if (useFixture) {
                 var classElem = fixture.querySelector(".class-name");
                 if (classElem) headerText += classElem.textContent;
              }
              // Also check class comment if useComment
              if (useComment) {
                 var classDesc = fixture.querySelector(".description-content"); // only the one direct under fixture div? No structure is flat inside fixture div mostly.
                 // Actually class description is inside .fixture div, before methods table.
                 // Let's iterate all description-contents in fixture, but distinguish method ones?
                 // The method ones are inside hidden rows. The class one is visible (or direct child).
                 // Implementation detail: Class desc is div.description-content direct child of div.fixture (after header and table).
                 // Method desc is inside div.description-content inside td inside tr (hidden row).
                 var directDesc = fixture.querySelectorAll(":scope > .description-content");
                 for (var d = 0; d < directDesc.length; d++) {
                    headerText += directDesc[d].textContent;
                 }
              }

              var headerMatches = headerText.toUpperCase().indexOf(filter) > -1;

              var rows = fixture.querySelectorAll("tbody tr");
              var hasVisibleRow = false;

              for (var j = 0; j < rows.length; j++) {
                var row = rows[j];
                if (row.classList.contains("usage-row")) continue;

                var usageRow = row.nextElementSibling;
                var hasUsageRow = usageRow && usageRow.classList.contains("usage-row");

                var rowMatches = false;
                var usageMatches = false;

                // Member Name
                if (useMember) {
                   var rowText = row.textContent || row.innerText;
                   if (rowText.toUpperCase().indexOf(filter) > -1) rowMatches = true;
                }

                // Comment & Usage
                if (hasUsageRow) {
                   // Description
                   if (useComment) {
                      var descDiv = usageRow.querySelector(".description-content");
                      if (descDiv && descDiv.textContent.toUpperCase().indexOf(filter) > -1) usageMatches = true;
                   }
                   // Usage
                   if (useUsage) {
                      var usageDiv = usageRow.querySelector(".usage-content");
                      if (usageDiv && usageDiv.textContent.toUpperCase().indexOf(filter) > -1) usageMatches = true;
                   }
                }

                if (filter === "") {
                   row.classList.remove("hidden-by-search");
                   if (hasUsageRow) {
                      usageRow.classList.remove("hidden-by-search");
                      usageRow.style.display = "none";
                      var btn = row.querySelector(".toggle-btn");
                      if (btn) btn.innerHTML = "&#9658;";
                   }
                   hasVisibleRow = true;
                   continue;
                }

                if (headerMatches || rowMatches || usageMatches) {
                  row.classList.remove("hidden-by-search");
                  hasVisibleRow = true;

                  if (hasUsageRow) {
                     usageRow.classList.remove("hidden-by-search");
                     
                     if (usageMatches) {
                       usageRow.style.display = "table-row";
                       var btn = row.querySelector(".toggle-btn");
                       if (btn) btn.innerHTML = "&#9660;";
                     } else {
                       usageRow.style.display = "none";
                       var btn = row.querySelector(".toggle-btn");
                       if (btn) btn.innerHTML = "&#9658;";
                     }
                  }
                } else {
                  row.classList.add("hidden-by-search");
                  if (hasUsageRow) {
                     usageRow.classList.add("hidden-by-search");
                     usageRow.style.display = "none";
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
          window.onload = updateSearchOption;
        </script>
      </head>
      <body>
        <div class="search-container">
          <div class="search-row">
            <span class="search-label">Slim Docs</span>
            <input type="text" id="searchInput" onkeyup="filterFixtures()" placeholder="Search for fixtures, namespaces, methods or properties...">
          </div>
          <div class="filter-options">
            <label><input type="checkbox" id="chkFixture" checked onchange="updateSearchOption()"> Fixture Names</label>
            <label><input type="checkbox" id="chkNamespace" checked onchange="updateSearchOption()"> Namespaces</label>
            <label><input type="checkbox" id="chkMember" checked onchange="updateSearchOption()"> Methods/Properties</label>
            <label><input type="checkbox" id="chkComment" checked onchange="updateSearchOption()"> Comments</label>
            <label><input type="checkbox" id="chkUsage" checked onchange="updateSearchOption()"> Usage</label>
          </div>
        </div>
        <h1>Registered Slim Fixtures</h1>
      ''');

    // TOC
    SB.AppendLine('<div class="toc"><h2>Table of Contents</h2><ul>');
    for Fixture in AFixtures do
      SB.AppendFormat('<li><a href="#%s">%s</a> <span style="color:#888">(%s)</span></li>',
        [Fixture.Id, Fixture.Name, Fixture.Namespace]);
    SB.AppendLine('</ul></div>');

    // Fixtures
    for Fixture in AFixtures do
    begin
      SortMembers(TList<TSlimDocMember>(Fixture.Methods));
      SortMembers(TList<TSlimDocMember>(Fixture.Properties));
      SB.AppendFormat('<div class="fixture" id="%s">', [Fixture.Id]);
      SB.Append('<div class="fixture-header">');
      SB.AppendFormat('<span>%s <span class="namespace">%s</span></span>', [Fixture.Name, Fixture.Namespace]);

      var HasInherited := False;
      for Method in Fixture.Methods do
        if Method.IsInherited then
        begin
          HasInherited := True;
          Break;
        end;
      if not HasInherited then
        for Prop in Fixture.Properties do
          if Prop.IsInherited then
          begin
            HasInherited := True;
            Break;
          end;

      if HasInherited then
        SB.AppendFormat('<label class="inherited-toggle"><input type="checkbox" onclick="toggleInherited(this, ''%s'')"> Show inherited members</label>', [Fixture.Id]);

      SB.Append('</div>');

      var ClassDecl := Fixture.DelphiClass;
      if (Fixture.InheritanceChain.Count > 0) then
      begin
        ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[0];
        for var I := 1 to Fixture.InheritanceChain.Count - 1 do
          ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[I];
      end;

      SB.Append('<table style="width: auto; border: none; margin-bottom: 15px; background-color: transparent; box-shadow: none;">');
      SB.AppendFormat('''
        <tr>
          <td style="border: none; padding: 2px 10px 2px 0; font-weight: bold;">Unit:</td>
          <td style="border: none; padding: 2px 0;">%s</td>
        </tr>
        ''', [Fixture.UnitName]);
      SB.AppendFormat('''
        <tr>
          <td style="border: none; padding: 2px 10px 2px 0; font-weight: bold;">Delphi Class:</td>
          <td style="border: none; padding: 2px 0;"><span class="class-name">%s</span></td>
        </tr>
        ''', [ClassDecl]);
      SB.Append('</table>');

      if Fixture.Description <> '' then
        SB.AppendFormat('<div class="description-content fixture-description">%s</div>', [FormatXmlComment(Fixture.Description)]);

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

      for Method in Fixture.Methods do
      begin
        var LookupKey := Format('%s.%s', [Fixture.Name, Method.Name]).ToLower;
        HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(LookupKey, UsageList);
        var HasDescription := Method.Description <> '';
        UsageRowId := Format('usage-%s-%s', [Fixture.Id, Method.Name]).Replace('.', '-');
        
        ToggleCell := '';
        if HasUsage or HasDescription then
          ToggleCell := Format('<span class="toggle-btn" onclick="toggleUsage(this, ''%s'')">&#9658;</span>', [UsageRowId]);

        RowClass := '';
        if Method.IsInherited then RowClass := 'inherited-member';
        if RowClass <> '' then RowClass := ' class="' + RowClass + '"';

        var SyncStyle := '';
        if SameText(Method.SyncMode, 'smUnsynchronized') then
          SyncStyle := ' style="color:#888"';

        SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td%s>%s</td><td style="color:#888">%s</td></tr>',
          [RowClass, ToggleCell, Method.Name, Method.GetParamsString, Method.ReturnType, SyncStyle, Method.SyncMode, Method.Origin]);

        if HasUsage or HasDescription then
        begin
          if Method.IsInherited then RowClass := ' class="inherited-member usage-row"'
          else RowClass := ' class="usage-row"';
          
          SB.AppendFormat('<tr%s id="%s" style="display:none;"><td colspan="6">', [RowClass, UsageRowId]);
          
          if HasDescription then
            SB.AppendFormat('<div class="description-content member-description">%s</div>', [FormatXmlComment(Method.Description)]);

          if HasUsage then
          begin
            UsageStr := '<div class="usage-links">';
            for U in UsageList do
            begin
               var Fragment := 'text=' + Method.Name;
               var Spaced := CamelCaseToSpaced(Method.Name);
               if Spaced <> Method.Name then
               begin
                 Fragment := Fragment + '&text=' + Spaced.Replace(' ', '%20');
                 // Range match for interleaved calls: WriteVarValue -> text=Write,Value
                 if Spaced.Contains(' ') then
                 begin
                   var Parts := Spaced.Split([' ']);
                   if Length(Parts) >= 2 then
                     Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
                 end;
               end;

               if (Method.Name.Length > 3) and Method.Name.StartsWith('Set', True) then
               begin
                 var PropName := Method.Name.Substring(3);
                 Fragment := Fragment + '&text=' + PropName;
                 
                 var SpacedProp := CamelCaseToSpaced(PropName);
                 if SpacedProp <> PropName then
                 begin
                   Fragment := Fragment + '&text=' + SpacedProp.Replace(' ', '%20');
                   if SpacedProp.Contains(' ') then
                   begin
                     var Parts := SpacedProp.Split([' ']);
                     if Length(Parts) >= 2 then
                       Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
                   end;
                 end;
               end;
               
               UsageStr := UsageStr + Format('<a href="../%s#:~:%s" target="_blank">%s</a>', [U, Fragment, U]);
            end;
            UsageStr := UsageStr + '</div>';
            SB.AppendFormat('<div class="usage-content"><strong>Used in:</strong> %s</div>', [UsageStr]);
          end;
          
          SB.Append('</td></tr>');
        end;
      end;
      SB.AppendLine('</tbody></table>');

      // Properties
      if Fixture.Properties.Count > 0 then
      begin
        SB.Append('''
            <h3>Properties</h3>
            <table>
              <thead>
                <tr>
                  <th style="width: 20px;"></th>
                  <th>Name</th>
                  <th>Type</th>
                  <th>Access</th>
                  <th>Sync Mode</th>
                  <th>Origin</th>
                </tr>
              </thead>
              <tbody>
          ''');

        for Prop in Fixture.Properties do
        begin
          var LookupKey := Format('%s.%s', [Fixture.Name, Prop.Name]).ToLower;
          HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(LookupKey, UsageList);
          var HasDescription := Prop.Description <> '';
          UsageRowId := Format('usage-%s-%s', [Fixture.Id, Prop.Name]).Replace('.', '-');
          
          ToggleCell := '';
          if HasUsage or HasDescription then
            ToggleCell := Format('<span class="toggle-btn" onclick="toggleUsage(this, ''%s'')">&#9658;</span>', [UsageRowId]);

          RowClass := '';
          if Prop.IsInherited then RowClass := 'inherited-member';
          if RowClass <> '' then RowClass := ' class="' + RowClass + '"';

          var SyncStyle := '';
          if SameText(Prop.SyncMode, 'smUnsynchronized') then
            SyncStyle := ' style="color:#888"';

          SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td%s>%s</td><td style="color:#888">%s</td></tr>',
            [RowClass, ToggleCell, Prop.Name, Prop.PropertyType, Prop.Access, SyncStyle, Prop.SyncMode, Prop.Origin]);
            
          if HasUsage or HasDescription then
          begin
             if Prop.IsInherited then RowClass := ' class="inherited-member usage-row"'
             else RowClass := ' class="usage-row"';
             SB.AppendFormat('<tr%s id="%s" style="display:none;"><td colspan="6">', [RowClass, UsageRowId]);

             if HasDescription then
               SB.AppendFormat('<div class="description-content member-description">%s</div>', [FormatXmlComment(Prop.Description)]);

             if HasUsage then
             begin
               UsageStr := '<div class="usage-links">';
               for U in UsageList do
               begin
                  var Fragment := 'text=' + Prop.Name;
                  var Spaced := CamelCaseToSpaced(Prop.Name);
                  if Spaced <> Prop.Name then
                    Fragment := Fragment + '&text=' + Spaced.Replace(' ', '%20');
                  
                  UsageStr := UsageStr + Format('<a href="../%s#:~:%s" target="_blank">%s</a>', [U, Fragment, U]);
               end;
               UsageStr := UsageStr + '</div>';
               SB.AppendFormat('<div class="usage-content"><strong>Used in:</strong> %s</div>', [UsageStr]);
             end;

             SB.Append('</td></tr>');
          end;
        end;
        SB.AppendLine('</tbody></table>');
      end;

      SB.AppendLine('</div>');
    end;

    SB.AppendLine('</body></html>');
    TFile.WriteAllText(AOutputFilePath, SB.ToString, TEncoding.UTF8);
    LinkName := ExtractFileName(AOutputFilePath);
    Result := Format('<a href="files/%s" target="_blank">Open Documentation</a>', [LinkName]);
  finally
    SB.Free;
  end;
end;

end.
