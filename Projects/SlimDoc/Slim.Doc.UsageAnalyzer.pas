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

  TSlimUsageAnalyzer = class
  private
    function  CamelCaseToSpaced(const S: String): String;
    function  GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
    procedure ProcessFile(const AFitNesseRoot, AFilePath: String; ASearchPatterns: TDictionary<String, TArray<String>>; AUsageMap: TUsageMap);
  public
    function Analyze(const AFitNesseRoot: String; AFixtures: TList<TSlimFixtureDoc>): TUsageMap;
  end;

implementation

{ TSlimUsageAnalyzer }

function TSlimUsageAnalyzer.CamelCaseToSpaced(const S: String): String;
var
  I : Integer;
  SB: TStringBuilder;
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

function TSlimUsageAnalyzer.GetWikiPageName(const AFitNesseRoot, AFilePath: String): String;
var
  RelPath: String;
begin
  // Ensure consistent handling of root path length
  if AFilePath.StartsWith(AFitNesseRoot, True) then
    RelPath := AFilePath.Substring(AFitNesseRoot.Length)
  else
    RelPath := AFilePath;

  // Remove leading separator
  if RelPath.StartsWith(PathDelim) then
    RelPath := RelPath.Substring(Length(PathDelim));

  // Handle content.txt special case (it represents the folder it is in)
  if SameText(ExtractFileName(RelPath), 'content.txt') then
     RelPath := ExtractFileDir(RelPath);

  // Remove extension (e.g. .wiki)
  // Note: TPath.ChangeExtension('file.wiki', '') returns 'file.' on some versions/platforms if not careful?
  // Actually documentation says it removes the period.
  // Let's use a safer approach for the extension.
  var Ext := ExtractFileExt(RelPath);
  if Ext <> '' then
    RelPath := RelPath.Substring(0, RelPath.Length - Ext.Length);

  // Replace directory separators with dots for Wiki path
  Result := RelPath.Replace(PathDelim, '.');
end;

procedure TSlimUsageAnalyzer.ProcessFile(const AFitNesseRoot, AFilePath: String; ASearchPatterns: TDictionary<String, TArray<String>>; AUsageMap: TUsageMap);
var
  FileContent : String;
  MethodName  : String;
  Pat         : String;
  UsageList   : TStringList;
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

  for var Pair in ASearchPatterns do
  begin
    MethodName := Pair.Key;
    for Pat in Pair.Value do
    begin
      if ContainsText(FileContent, Pat) then
      begin
        if not AUsageMap.TryGetValue(MethodName.ToLower, UsageList) then
        begin
          UsageList := TStringList.Create;
          UsageList.Sorted := True;
          UsageList.Duplicates := dupIgnore;
          AUsageMap.Add(MethodName.ToLower, UsageList);
        end;
        UsageList.Add(WikiPageName);
        Break;
      end;
    end;
  end;
end;

function TSlimUsageAnalyzer.Analyze(const AFitNesseRoot: String; AFixtures: TList<TSlimFixtureDoc>): TUsageMap;
var
  FileName      : String;
  Files         : TStringDynArray;
  Fixture       : TSlimFixtureDoc;
  Method        : TSlimMethodDoc;
  Patterns      : TArray<String>;
  SearchPatterns: TDictionary<String, TArray<String>>;
  Spaced        : String;
begin
  Result := TObjectDictionary<String, TStringList>.Create([doOwnsValues]);
  SearchPatterns := TDictionary<String, TArray<String>>.Create;
  try
    // Collect patterns from fixtures
    for Fixture in AFixtures do
    begin
      for Method in Fixture.Methods do
      begin
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

    if TDirectory.Exists(AFitNesseRoot) then
    begin
      Files := TDirectory.GetFiles(AFitNesseRoot, '*.wiki', TSearchOption.soAllDirectories);
      for FileName in Files do
        ProcessFile(AFitNesseRoot, FileName, SearchPatterns, Result);

      Files := TDirectory.GetFiles(AFitNesseRoot, 'content.txt', TSearchOption.soAllDirectories);
      for FileName in Files do
        ProcessFile(AFitNesseRoot, FileName, SearchPatterns, Result);
    end;
  finally
    SearchPatterns.Free;
  end;
end;

end.