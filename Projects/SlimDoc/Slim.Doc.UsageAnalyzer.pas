// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.UsageAnalyzer;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.Types,

  Slim.Doc.Model;

type

  TUsageMap = TObjectDictionary<String, TStringList>;

  // Maps Fixture -> (MethodKey -> Patterns)
  TPatternMap = TObjectDictionary<TSlimFixtureDoc, TDictionary<String, TArray<String>>>;

  TSlimUsageAnalyzer = class
  private
    function  CamelCaseToSpaced(const S: String): String;
    procedure DetectActiveFixture(const ACells: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; var AActiveFixture: TSlimFixtureDoc; var AIsDT, AIsScript: Boolean);
    function  ExtractTableCells(const ALine: String): TArray<String>;
    function  FindFixture(const AName: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TSlimFixtureDoc;
    function  GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
    function  IsIgnoredFile(const AFilePath: String): Boolean;
    procedure ProcessFile(const AFitNesseRoot, AFilePath: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; APatternMap: TPatternMap; AUsageMap: TUsageMap);
    procedure ScanRowForUsage(const ALine, AWikiPageName: String; AActiveFixture: TSlimFixtureDoc; APatternMap: TPatternMap; AUsageMap: TUsageMap);
  public
    function Analyze(const AFitNesseRoot: String; AFixtures: TList<TSlimFixtureDoc>): TUsageMap;
  end;

implementation

{ TSlimUsageAnalyzer }

function TSlimUsageAnalyzer.CamelCaseToSpaced(const S: String): String;
begin
  Result := '';
  if S.IsEmpty
    then Exit;
  
  var SB := TStringBuilder.Create;
  try
    for var I := 1 to S.Length do
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

function TSlimUsageAnalyzer.IsIgnoredFile(const AFilePath: String): Boolean;
begin
  Result := ExtractFileName(AFilePath).StartsWith('RerunLastFailures', True);
end;

function TSlimUsageAnalyzer.GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
var
  RelPath: String;
  Root   : String;
begin
  Root := IncludeTrailingPathDelimiter(AFitNesseRoot);

  if AFilePath.StartsWith(Root, True) then
    RelPath := AFilePath.Substring(Root.Length)
  else
    RelPath := AFilePath;

  if RelPath.StartsWith(PathDelim) then
    RelPath := RelPath.Substring(Length(PathDelim));

  if SameText(ExtractFileName(RelPath), 'content.txt') then
     RelPath := ExtractFileDir(RelPath);

  var Ext := ExtractFileExt(RelPath);
  if Ext <> '' then
    RelPath := RelPath.Substring(0, RelPath.Length - Ext.Length);

  Result := RelPath.Replace(PathDelim, '.');
end;

function TSlimUsageAnalyzer.FindFixture(const AName: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TSlimFixtureDoc;
var
  CleanName: String;
begin
  if AName.IsEmpty then
    Exit(nil);
  CleanName := AName.Replace(' ', '').ToLower;
  if not AFixtureMap.TryGetValue(CleanName, Result) then
    Result := nil;
end;

function TSlimUsageAnalyzer.ExtractTableCells(const ALine: String): TArray<String>;
var
  C       : Integer;
  EndIdx  : Integer;
  RawCells: TArray<String>;
  StartIdx: Integer;
begin
  RawCells := ALine.Trim.Split(['|']);
  StartIdx := 0;
  if (Length(RawCells) > 0) and (RawCells[0] = '') then
    StartIdx := 1;
  EndIdx := High(RawCells);
  if (EndIdx >= StartIdx) and (RawCells[EndIdx] = '') then
    Dec(EndIdx);

  SetLength(Result, 0);
  for C := StartIdx to EndIdx do
  begin
    var CellVal := RawCells[C].Trim;
    if CellVal.StartsWith('!-') and CellVal.EndsWith('-!') then
       CellVal := CellVal.Substring(2, CellVal.Length - 4);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := CellVal;
  end;
end;

procedure TSlimUsageAnalyzer.DetectActiveFixture(const ACells: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; var AActiveFixture: TSlimFixtureDoc; var AIsDT, AIsScript: Boolean);
begin
  AActiveFixture := nil;
  AIsDT := False;
  AIsScript := False;
  if Length(ACells) = 0 then
    Exit;

  // Case 1: | FixtureName | ... (Decision Table)
  AActiveFixture := FindFixture(ACells[0], AFixtureMap);
  AIsDT:=Assigned(AActiveFixture);
  if AIsDT then
    Exit;

  if Length(ACells) > 1 then
  begin
    // Case 2: | script | FixtureName | ...
    // Case 3: | dt | FixtureName | ...
    var TableType := ACells[0].ToLower;
    if (TableType = 'script') or (TableType = 'dt') or (TableType = 'ddt') or (TableType = 'table') or (TableType = 'query') then
    begin
      AActiveFixture := FindFixture(ACells[1], AFixtureMap);
      if Assigned(AActiveFixture) then
      begin
        if TableType = 'script' then
          AIsScript := True
        else
          AIsDT := True;
      end;
    end;
  end;
end;

procedure TSlimUsageAnalyzer.ScanRowForUsage(const ALine, AWikiPageName: String; AActiveFixture: TSlimFixtureDoc; APatternMap: TPatternMap; AUsageMap: TUsageMap);
var
  CurrentPatterns: TDictionary<String, TArray<String>>;
  MethodKey      : String;
  MethodPatterns : TArray<String>;
  Pat            : String;
  UsageKey       : String;
  UsageList      : TStringList;
begin
  if not APatternMap.TryGetValue(AActiveFixture, CurrentPatterns) then
    Exit;

  for var Pair in CurrentPatterns do
  begin
    MethodKey := Pair.Key;
    MethodPatterns := Pair.Value;

    var Found := False;
    for Pat in MethodPatterns do
    begin
      if ContainsText(ALine, Pat) then
      begin
        Found := True;
        Break;
      end;
    end;

    if Found then
    begin
      UsageKey := Format('%s.%s', [AActiveFixture.Name, MethodKey]).ToLower;
      if not AUsageMap.TryGetValue(UsageKey, UsageList) then
      begin
        UsageList := TStringList.Create;
        UsageList.Sorted := True;
        UsageList.Duplicates := dupIgnore;
        AUsageMap.Add(UsageKey, UsageList);
      end;
      UsageList.Add(AWikiPageName);
    end;
  end;
end;

procedure TSlimUsageAnalyzer.ProcessFile(const AFitNesseRoot, AFilePath: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; APatternMap: TPatternMap; AUsageMap: TUsageMap);
var
  ActiveFixture: TSlimFixtureDoc;
  Cells        : TArray<String>;
  InTable      : Boolean;
  IsDT         : Boolean;
  IsScript     : Boolean;
  Line         : String;
  Lines        : TArray<String>;
  TableRow     : Integer;
  WikiPageName : String;
begin
  if IsIgnoredFile(AFilePath)
    then Exit;

  WikiPageName := GetWikiPageName(AFitNesseRoot, AFilePath);
  Lines := TFile.ReadAllLines(AFilePath, TEncoding.UTF8);

  InTable := False;
  ActiveFixture := nil;
  TableRow := 0;
  IsDT := False;
  IsScript := False;

  for Line in Lines do
  begin
    var TrimmedLine := Line.Trim;
    if TrimmedLine.StartsWith('|') then
    begin
      if not InTable then
      begin
        InTable := True;
        TableRow := 0;
        Cells := ExtractTableCells(TrimmedLine);
        DetectActiveFixture(Cells, AFixtureMap, ActiveFixture, IsDT, IsScript);
      end
      else
      begin
        Inc(TableRow);
        if Assigned(ActiveFixture) then
        begin
          if IsScript or (IsDT and (TableRow = 1)) then
            ScanRowForUsage(TrimmedLine, WikiPageName, ActiveFixture, APatternMap, AUsageMap);
        end;
      end;
    end
    else
    begin
      InTable := False;
      ActiveFixture := nil;
    end;
  end;
end;

function TSlimUsageAnalyzer.Analyze(const AFitNesseRoot: String; AFixtures: TList<TSlimFixtureDoc>): TUsageMap;
var
  FileName  : String;
  Files     : TArray<String>;
  Fixture   : TSlimFixtureDoc;
  FixtureMap: TDictionary<String, TSlimFixtureDoc>;
  Method    : TSlimMethodDoc;
  PatternMap: TPatternMap;
  Patterns  : TArray<String>;
  Spaced    : String;
begin
  Result := TObjectDictionary<String, TStringList>.Create([doOwnsValues]);
  FixtureMap := TDictionary<String, TSlimFixtureDoc>.Create;
  PatternMap := TObjectDictionary<TSlimFixtureDoc, TDictionary<String, TArray<String>>>.Create([doOwnsValues]);
  try
    // Build Maps
    for Fixture in AFixtures do
    begin
      FixtureMap.AddOrSetValue(Fixture.Name.ToLower, Fixture);
      if Fixture.Namespace <> '' then
      begin
        var FullName := Fixture.Namespace + '.' + Fixture.Name;
        FixtureMap.AddOrSetValue(FullName.ToLower, Fixture);
      end;

      if Fixture.DelphiClass <> '' then
         FixtureMap.AddOrSetValue(Fixture.DelphiClass.ToLower, Fixture);

      var MMap := TDictionary<String, TArray<String>>.Create;
      PatternMap.Add(Fixture, MMap);

      for Method in Fixture.Methods do
      begin
        SetLength(Patterns, 1);
        Patterns[0] := Method.Name;
        Spaced := CamelCaseToSpaced(Method.Name);
        if not SameText(Spaced, Method.Name) then
        begin
          SetLength(Patterns, Length(Patterns) + 1);
          Patterns[High(Patterns)] := Spaced;
        end;

        if (Method.Name.Length > 3) and Method.Name.StartsWith('Set', True) then
        begin
          var PropName := Method.Name.Substring(3);
          var BaseIdx := Length(Patterns);
          SetLength(Patterns, BaseIdx + 1);
          Patterns[BaseIdx] := PropName;

          Spaced := CamelCaseToSpaced(PropName);
          if not SameText(Spaced, PropName) then
          begin
            SetLength(Patterns, Length(Patterns) + 1);
            Patterns[High(Patterns)] := Spaced;
          end;
        end;

        MMap.AddOrSetValue(Method.Name, Patterns);
      end;
    end;

    if TDirectory.Exists(AFitNesseRoot) then
    begin
      Files := TDirectory.GetFiles(AFitNesseRoot, '*.wiki', TSearchOption.soAllDirectories);
      for FileName in Files do
        ProcessFile(AFitNesseRoot, FileName, FixtureMap, PatternMap, Result);

      Files := TDirectory.GetFiles(AFitNesseRoot, 'content.txt', TSearchOption.soAllDirectories);
      for FileName in Files do
        ProcessFile(AFitNesseRoot, FileName, FixtureMap, PatternMap, Result);
    end;
  finally
    FixtureMap.Free;
    PatternMap.Free;
  end;
end;

end.
