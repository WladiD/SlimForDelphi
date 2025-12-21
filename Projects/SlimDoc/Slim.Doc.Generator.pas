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
  System.SysUtils,

  Slim.Doc.Model,
  Slim.Doc.UsageAnalyzer;

type

  TSlimDocGenerator = class
  private
    procedure SortFixtures(AFixtures: TList<TSlimFixtureDoc>);
    procedure SortMemberList(AList: TList<TSlimMemberDoc>);
  public
    function Generate(AFixtures: TList<TSlimFixtureDoc>; AUsageMap: TUsageMap; const AOutputFilePath: String): String;
  end;

implementation

{ TSlimDocGenerator }

procedure TSlimDocGenerator.SortFixtures(AFixtures: TList<TSlimFixtureDoc>);
begin
  AFixtures.Sort(TComparer<TSlimFixtureDoc>.Construct(
    function(const L, R: TSlimFixtureDoc): Integer
    begin
      Result := CompareText(L.Namespace, R.Namespace);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));
end;

procedure TSlimDocGenerator.SortMemberList(AList: TList<TSlimMemberDoc>);
begin
  AList.Sort(TComparer<TSlimMemberDoc>.Construct(
    function(const L, R: TSlimMemberDoc): Integer
    begin
      Result := CompareText(L.Name, R.Name);
    end));
end;

function TSlimDocGenerator.Generate(AFixtures: TList<TSlimFixtureDoc>; AUsageMap: TUsageMap; const AOutputFilePath: String): String;
var
  Fixture   : TSlimFixtureDoc;
  HasUsage  : Boolean;
  LinkName  : String;
  Method    : TSlimMethodDoc;
  Prop      : TSlimPropertyDoc;
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

    // TOC
    SB.AppendLine('<div class="toc"><h2>Table of Contents</h2><ul>');
    for Fixture in AFixtures do
      SB.AppendFormat('<li><a href="#%s">%s</a> <span style="color:#888">(%s)</span></li>',
        [Fixture.Id, Fixture.Name, Fixture.Namespace]);
    SB.AppendLine('</ul></div>');

    // Fixtures
    for Fixture in AFixtures do
    begin
      SortMemberList(TList<TSlimMemberDoc>(Fixture.Methods));
      SortMemberList(TList<TSlimMemberDoc>(Fixture.Properties));
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
      SB.AppendFormat('<tr><td style="border: none; padding: 2px 10px 2px 0; font-weight: bold;">Delphi Class:</td><td style="border: none; padding: 2px 0;"><span class="class-name">%s</span></td></tr>', [ClassDecl]);
      SB.AppendFormat('<tr><td style="border: none; padding: 2px 10px 2px 0; font-weight: bold;">Unit:</td><td style="border: none; padding: 2px 0;">%s</td></tr>', [Fixture.UnitName]);
      SB.Append('</table>');

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
        HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(Method.Name.ToLower, UsageList);
        UsageRowId := Format('usage-%s-%s', [Fixture.Id, Method.Name]).Replace('.', '-');
        
        ToggleCell := '';
        if HasUsage then
          ToggleCell := Format('<span class="toggle-btn" onclick="toggleUsage(this, ''%s'')">&#9658;</span>', [UsageRowId]);

        RowClass := '';
        if Method.IsInherited then RowClass := 'inherited-member';
        if RowClass <> '' then RowClass := ' class="' + RowClass + '"';

        SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td style="color:#888">%s</td></tr>',
          [RowClass, ToggleCell, Method.Name, Method.GetParamsString, Method.ReturnType, Method.SyncMode, Method.Origin]);

        if HasUsage then
        begin
          UsageStr := '<div class="usage-links">';
          for U in UsageList do
             UsageStr := UsageStr + Format('<a href="../%s" target="_blank">%s</a>', [U, U]);
          UsageStr := UsageStr + '</div>';

          if Method.IsInherited then RowClass := ' class="inherited-member usage-row"'
          else RowClass := ' class="usage-row"';
          
          SB.AppendFormat('<tr%s id="%s" style="display:none;"><td colspan="6"><div class="usage-content"><strong>Used in:</strong> %s</div></td></tr>',
            [RowClass, UsageRowId, UsageStr]);
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
                <th>Name</th>
                <th>Type</th>
                <th>Access</th>
                <th>Origin</th>
              </tr>
            </thead>
            <tbody>
        ''');

        for Prop in Fixture.Properties do
        begin
          RowClass := '';
          if Prop.IsInherited then RowClass := 'inherited-member';
          if RowClass <> '' then RowClass := ' class="' + RowClass + '"';

          SB.AppendFormat('<tr%s><td>%s</td><td>%s</td><td>%s</td><td style="color:#888">%s</td></tr>',
            [RowClass, Prop.Name, Prop.PropertyType, Prop.Access, Prop.Origin]);
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
