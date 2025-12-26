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

  Slim.Doc.Model,
  Slim.Doc.Utils;

type

  TUsageMap = TObjectDictionary<String, TStringList>;

  // Maps Fixture -> (MethodKey -> Patterns)
  TPatternMap = TObjectDictionary<TSlimFixtureDoc, TDictionary<String, TArray<String>>>;

  TSlimUsageAnalyzer = class
  private
    procedure CollectLibrariesFromIncludes(const AFitNesseRoot, ACurrentDir: String; const ALines: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; ALibraryFixtures: TList<TSlimFixtureDoc>; AVisitedFiles: TStringList);
    function  CollectLibrariesFromLines(const ALines: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TList<TSlimFixtureDoc>;
    procedure DetectActiveFixture(const ACells: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; var AActiveFixture: TSlimFixtureDoc; var AIsDT, AIsScript, AIsScenario: Boolean);
    function  ExtractTableCells(const ALine: String): TArray<String>;
    function  FindFixture(const AName: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TSlimFixtureDoc;
    function  GetInheritedLibraries(const AFitNesseRoot, AFilePath: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TList<TSlimFixtureDoc>;
    function  GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
    function  IsIgnoredFile(const AFilePath: String): Boolean;
    procedure ProcessFile(const AFitNesseRoot, AFilePath: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; APatternMap: TPatternMap; AUsageMap: TUsageMap);
    function  ResolveIncludePath(const AFitNesseRoot, ACurrentDir, AIncludePath: String): String;
    procedure ScanRowForUsage(const ALine, AWikiPageName: String; AActiveFixture: TSlimFixtureDoc; APatternMap: TPatternMap; AUsageMap: TUsageMap);
  public
    function Analyze(const AFitNesseRoot: String; AFixtures: TList<TSlimFixtureDoc>): TUsageMap;
  end;

implementation

{ TSlimUsageAnalyzer }

function TSlimUsageAnalyzer.CollectLibrariesFromLines(const ALines: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TList<TSlimFixtureDoc>;
var
  Cells         : TArray<String>;
  InLibraryTable: Boolean;
  LibFixture    : TSlimFixtureDoc;
begin
  Result := TList<TSlimFixtureDoc>.Create;
  InLibraryTable := False;

  for var Line: String in ALines do
  begin
    var TrimmedLine: String := Line.Trim;
    if TrimmedLine.StartsWith('|') then
    begin
      Cells := ExtractTableCells(TrimmedLine);
      if Length(Cells) = 0 then
        Continue;
      if InLibraryTable then
      begin
        LibFixture := FindFixture(Cells[0], AFixtureMap);
        if Assigned(LibFixture) and (not Result.Contains(LibFixture)) then
          Result.Add(LibFixture);
      end
      else
        InLibraryTable := SameText(Cells[0], 'library');
    end
    else
      InLibraryTable := False;
  end;
end;

procedure TSlimUsageAnalyzer.CollectLibrariesFromIncludes(const AFitNesseRoot, ACurrentDir: String; const ALines: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; ALibraryFixtures: TList<TSlimFixtureDoc>; AVisitedFiles: TStringList);
begin
  for var Line: String in ALines do
  begin
    var TrimmedLine: String := Line.Trim;
    if not TrimmedLine.StartsWith('!include', True) then
      Continue;

    var Parts: TArray<String> := TrimmedLine.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if Length(Parts) < 2 then
      Continue;

    var IncludePath: String := '';
    for var I := 1 to High(Parts) do
      if not Parts[I].StartsWith('-') then
      begin
        IncludePath := Parts[I];
        Break;
      end;

    if IncludePath = '' then
      Continue;

    var FullPath: String := ResolveIncludePath(AFitNesseRoot, ACurrentDir, IncludePath);
    if (FullPath <> '') and TFile.Exists(FullPath) and (AVisitedFiles.IndexOf(FullPath) < 0) then
    begin
      AVisitedFiles.Add(FullPath);
      var IncludedLines: TArray<String> := TFile.ReadAllLines(FullPath, TEncoding.UTF8);

      // 1. Collect libraries from the included file itself
      var Libs: TList<TSlimFixtureDoc> := CollectLibrariesFromLines(IncludedLines, AFixtureMap);
      try
        for var F: TSlimFixtureDoc in Libs do
          if not ALibraryFixtures.Contains(F) then
            ALibraryFixtures.Add(F);
      finally
        Libs.Free;
      end;

      // 2. Recursively follow includes in the included file
      CollectLibrariesFromIncludes(AFitNesseRoot, ExtractFileDir(FullPath), IncludedLines, AFixtureMap, ALibraryFixtures, AVisitedFiles);
    end;
  end;
end;

function TSlimUsageAnalyzer.ResolveIncludePath(const AFitNesseRoot, ACurrentDir, AIncludePath: String): String;
var
  CleanPath: String;
  Root     : String;
begin
  Result := '';
  try
    CleanPath := AIncludePath;
    Root := IncludeTrailingPathDelimiter(AFitNesseRoot);

    if CleanPath.StartsWith('<') then
    begin
      // Relative to FitNesseRoot
      CleanPath := CleanPath.Substring(1).Replace('.', PathDelim);
      Result := Root + CleanPath;
    end
    else if CleanPath.StartsWith('.') then
    begin
      // Relative to FitNesseRoot (absolute path in FitNesse terms)
      CleanPath := CleanPath.Substring(1).Replace('.', PathDelim);
      Result := Root + CleanPath;
    end
    else if CleanPath.StartsWith('^') then
    begin
      // Subpage
      CleanPath := CleanPath.Substring(1).Replace('.', PathDelim);
      Result := TPath.Combine(ACurrentDir, CleanPath);
    end
    else
    begin
      // Sibling or relative
      CleanPath := CleanPath.Replace('.', PathDelim);
      Result := TPath.Combine(ACurrentDir, CleanPath);
    end;

    if (not Result.EndsWith('.wiki', True)) and (not Result.EndsWith('content.txt', True)) then
    begin
      if TFile.Exists(Result + '.wiki') then
        Result := Result + '.wiki'
      else if TFile.Exists(TPath.Combine(Result, 'content.txt')) then
        Result := TPath.Combine(Result, 'content.txt');
    end;

    // If file not found and path started with < (root relative), try checking common subfolders like ATDD
    if (Result <> '') and (not TFile.Exists(Result)) and AIncludePath.StartsWith('<') then
    begin
      // Re-calculate RelPath from original AIncludePath
      var RelPath := AIncludePath.Substring(1).Replace('.', PathDelim);
      var Candidates: TArray<String>;
      Candidates := ['ATDD', 'Playground'];

      for var Candidate in Candidates do
      begin
        var AltPath := TPath.Combine(Root, Candidate);
        AltPath := TPath.Combine(AltPath, RelPath);

        if TFile.Exists(AltPath + '.wiki') then
        begin
          Result := AltPath + '.wiki';
          Break;
        end
        else if TFile.Exists(TPath.Combine(AltPath, 'content.txt')) then
        begin
          Result := TPath.Combine(AltPath, 'content.txt');
          Break;
        end;
      end;
    end;
  except
    on E: Exception do
    begin
      // Ignore invalid paths (e.g. variables in path like <[>Vars])
      Result := '';
    end;
  end;
end;

function TSlimUsageAnalyzer.GetInheritedLibraries(const AFitNesseRoot, AFilePath: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TList<TSlimFixtureDoc>;
var
  CurrentDir: String;
  Libs      : TList<TSlimFixtureDoc>;
  Root      : String;

  procedure CheckFile(const AName: String);
  begin
    var Path: String := TPath.Combine(CurrentDir, AName);
    if not TFile.Exists(Path) then
      Exit;

    Libs := CollectLibrariesFromLines(TFile.ReadAllLines(Path, TEncoding.UTF8), AFixtureMap);
    try
      for var F: TSlimFixtureDoc in Libs do
        if not Result.Contains(F) then
          Result.Add(F);
    finally
      Libs.Free;
    end;
  end;

begin
  Result := TList<TSlimFixtureDoc>.Create;
  Root := ExcludeTrailingPathDelimiter(AFitNesseRoot);
  CurrentDir := ExtractFileDir(AFilePath);

  // Walk up until we are above Root
  while (Length(CurrentDir) >= Length(Root)) and (SameText(CurrentDir, Root) or CurrentDir.StartsWith(Root + PathDelim, True)) do
  begin
    CheckFile('SetUp.wiki');
    CheckFile('SuiteSetUp.wiki');
    CheckFile('SetUp');

    CurrentDir := ExtractFileDir(CurrentDir);
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

  var Ext: String := ExtractFileExt(RelPath);
  if Ext <> '' then
    RelPath := RelPath.Substring(0, RelPath.Length - Ext.Length);

  Result := RelPath.Replace(PathDelim, '.');
end;

function TSlimUsageAnalyzer.FindFixture(const AName: String; AFixtureMap: TDictionary<String, TSlimFixtureDoc>): TSlimFixtureDoc;
var
  CleanName: String;
begin
  Result := nil;
  if AName.IsEmpty then
    Exit;
  CleanName := AName.Replace(' ', '').ToLower;
  AFixtureMap.TryGetValue(CleanName, Result);
end;

function TSlimUsageAnalyzer.ExtractTableCells(const ALine: String): TArray<String>;
var
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

  var CellsCount: Integer := 0;
  if EndIdx >= StartIdx then
    CellsCount := EndIdx - StartIdx + 1;
  SetLength(Result, CellsCount);
  if CellsCount=0 then
    Exit;

  for var Loop: Integer := StartIdx to EndIdx do
  begin
    var CellVal := RawCells[Loop].Trim;
    if CellVal.StartsWith('!-') and CellVal.EndsWith('-!') then
       CellVal := CellVal.Substring(2, CellVal.Length - 4);

    Result[Loop - StartIdx] := CellVal;
  end;
end;

procedure TSlimUsageAnalyzer.DetectActiveFixture(const ACells: TArray<String>; AFixtureMap: TDictionary<String, TSlimFixtureDoc>; var AActiveFixture: TSlimFixtureDoc; var AIsDT, AIsScript, AIsScenario: Boolean);
begin
  AActiveFixture := nil;
  AIsDT := False;
  AIsScript := False;
  AIsScenario := False;

  if Length(ACells) = 0 then
    Exit;

  var FirstCell := ACells[0].ToLower;

  // Case 0: | Scenario | ...
  if FirstCell = 'scenario' then
  begin
    AIsScenario := True;
    Exit;
  end;

  // Check for table type keywords first, before checking if FirstCell is a fixture name.
  // This is important because a fixture could be named "Script" (e.g. Base.UI.Script).
  if (FirstCell = 'script') or (FirstCell = 'dt') or (FirstCell = 'ddt') or
     (FirstCell = 'table') or (FirstCell = 'query') or (FirstCell = 'ordered query') or
     (FirstCell = 'subset query') then
  begin
    if Length(ACells) > 1 then
    begin
      AActiveFixture := FindFixture(ACells[1], AFixtureMap);
      if Assigned(AActiveFixture) then
      begin
        if FirstCell = 'script' then
          AIsScript := True
        else
          AIsDT := True;
        Exit;
      end;
    end;

    // If it's just "| script |" without a fixture name, it's still a script table
    if FirstCell = 'script' then
    begin
      AIsScript := True;
      Exit;
    end;
  end;

  // Case 1: | FixtureName | ... (Decision Table)
  AActiveFixture := FindFixture(ACells[0], AFixtureMap);
  AIsDT := Assigned(AActiveFixture);
end;

procedure TSlimUsageAnalyzer.ScanRowForUsage(const ALine, AWikiPageName: String; AActiveFixture: TSlimFixtureDoc; APatternMap: TPatternMap; AUsageMap: TUsageMap);
var
  Cells          : TArray<String>;
  CurrentPatterns: TDictionary<String, TArray<String>>;
  MethodKey      : String;
  MethodPatterns : TArray<String>;
  Pat            : String;
  UsageKey       : String;
  UsageList      : TStringList;
begin
  if not APatternMap.TryGetValue(AActiveFixture, CurrentPatterns) then
    Exit;

  Cells := ExtractTableCells(ALine);
  if Length(Cells) = 0 then
    Exit;

  // Build a "compact" version of the row for matching.
  // Standard Slim logic for script tables:
  // | method | arg1 | arg2 | -> "method"
  // | method | arg1 | extra | arg2 | -> "method extra"
  // We'll build a combined string from alternate cells: 0, 2, 4...
  var Combined := '';
  var I := 0;
  while I < Length(Cells) do
  begin
    if not Combined.IsEmpty then
      Combined := Combined + ' ';
    Combined := Combined + Cells[I];
    Inc(I, 2);
  end;

  for var Pair in CurrentPatterns do
  begin
    MethodKey := Pair.Key;
    MethodPatterns := Pair.Value;

    var Found := False;
    for Pat in MethodPatterns do
    begin
      Found :=
        ContainsText(ALine, Pat) or  // 1. Check full line (legacy behavior, good for Decision Tables and simple scripts)
        ContainsText(Combined, Pat); // 2. Check combined alternate cells (Interleaved arguments in script tables)
      if Found then
        Break;
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
  ActiveFixture  : TSlimFixtureDoc;
  Cells          : TArray<String>;
  InTable        : Boolean;
  IsDT           : Boolean;
  IsLibraryTable : Boolean;
  IsScenario     : Boolean;
  IsScript       : Boolean;
  LibFixture     : TSlimFixtureDoc;
  LibraryFixtures: TList<TSlimFixtureDoc>;
  Line           : String;
  Lines          : TArray<String>;
  TableRow       : Integer;
  VisitedFiles   : TStringList;
  WikiPageName   : String;
begin
  if IsIgnoredFile(AFilePath) then
    Exit;

  WikiPageName := GetWikiPageName(AFitNesseRoot, AFilePath);
  Lines := TFile.ReadAllLines(AFilePath, TEncoding.UTF8);

  InTable := False;
  ActiveFixture := nil;
  TableRow := 0;
  IsDT := False;
  IsScript := False;
  IsScenario := False;
  IsLibraryTable := False;

  // Init libraries with inherited ones
  LibraryFixtures := GetInheritedLibraries(AFitNesseRoot, AFilePath, AFixtureMap);
  try
    // Also scan for !include in the current file to find more libraries
    VisitedFiles := TStringList.Create;
    try
      VisitedFiles.Sorted := True;
      VisitedFiles.Duplicates := dupIgnore;
      VisitedFiles.Add(AFilePath);
      CollectLibrariesFromIncludes(AFitNesseRoot, ExtractFileDir(AFilePath), Lines, AFixtureMap, LibraryFixtures, VisitedFiles);
    finally
      VisitedFiles.Free;
    end;

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

          if (Length(Cells) > 0) and SameText(Cells[0], 'library') then
          begin
            IsLibraryTable := True;
            IsDT := False;
            IsScript := False;
            IsScenario := False;
            ActiveFixture := nil;
          end
          else
          begin
            IsLibraryTable := False;
            DetectActiveFixture(Cells, AFixtureMap, ActiveFixture, IsDT, IsScript, IsScenario);
          end;
        end
        else
        begin
          Inc(TableRow);

          if IsLibraryTable then
          begin
            Cells := ExtractTableCells(TrimmedLine);
            if Length(Cells) > 0 then
            begin
              LibFixture := FindFixture(Cells[0], AFixtureMap);
              if Assigned(LibFixture) and (not LibraryFixtures.Contains(LibFixture)) then
                LibraryFixtures.Add(LibFixture);
            end;
          end
          else
          begin
            if Assigned(ActiveFixture) then
            begin
              if IsScript or (IsDT and (TableRow = 1)) then
              begin
                ScanRowForUsage(TrimmedLine, WikiPageName, ActiveFixture, APatternMap, AUsageMap);

                // Also scan libraries if it is a script table
                if IsScript then
                  for LibFixture in LibraryFixtures do
                    ScanRowForUsage(TrimmedLine, WikiPageName, LibFixture, APatternMap, AUsageMap);
              end;
            end
            else if IsScenario then
            begin
              // In scenarios, we don't know the active fixture, so we check all available fixtures.
              for LibFixture in APatternMap.Keys do
                ScanRowForUsage(TrimmedLine, WikiPageName, LibFixture, APatternMap, AUsageMap);
            end;
          end;
        end;
      end
      else
      begin
        InTable := False;
        ActiveFixture := nil;
        IsLibraryTable := False;
        IsScenario := False;
      end;
    end;
  finally
    LibraryFixtures.Free;
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
        Patterns := [Method.Name];
        Spaced := CamelCaseToSpaced(Method.Name);
        if not SameText(Spaced, Method.Name) then
          Patterns := Patterns + [Spaced];

        if (Method.Name.Length > 3) and Method.Name.StartsWith('Set', True) then
        begin
          var PropName := Method.Name.Substring(3);
          var BaseIdx := Length(Patterns);
          Patterns := Patterns + [PropName];

          Spaced := CamelCaseToSpaced(PropName);
          if not SameText(Spaced, PropName) then
            Patterns := Patterns + [Spaced];
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
