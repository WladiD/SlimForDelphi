// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Fixtures;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,

  Slim.Doc.Extractor,
  Slim.Doc.Generator,
  Slim.Doc.Model,
  Slim.Doc.UsageAnalyzer,
  Slim.Fixture;

type

  /// <summary>
  /// Generates HTML documentation for Slim Fixtures, including usage analysis and XML comments extraction.
  /// </summary>
  [SlimFixture('Generator', 'SlimDoc')]
  TSlimDocGeneratorFixture = class(TSlimFixture)
  private
    FExcludePaths  : TStringList;
    FGeneratedLink : String;
    FIncludePaths  : TStringList;
    FMainTemplatePath: String;
    FUsageMap      : TUsageMap;
    function CreateExtractor: TSlimDocExtractor;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
    function  AnalyzeUsage(const AFitNesseRoot: String): String;
    procedure ExcludeSourceCodePath(const APath: String);
    function  GenerateDocumentation(const AFilePath: String): String;
    procedure IncludeSourceCodePath(const APath: String);
    /// <summary>Returns the link to the generated documentation file after execution.</summary>
    property GeneratedLink: String read FGeneratedLink;
    /// <summary>The path to the Mustache template file used for the HTML generation.</summary>
    property MainTemplate: String write FMainTemplatePath;
  end;

implementation

{ TSlimDocGeneratorFixture }

procedure TSlimDocGeneratorFixture.AfterConstruction;
begin
  inherited;
  FExcludePaths := TStringList.Create;
  FExcludePaths.Sorted := True;
  FIncludePaths := TStringList.Create;
  FIncludePaths.Sorted := True;
  FIncludePaths.Duplicates := dupIgnore;
end;

destructor TSlimDocGeneratorFixture.Destroy;
begin
  FUsageMap.Free;
  FIncludePaths.Free;
  FExcludePaths.Free;
  inherited;
end;

/// <summary>
/// Scans the FitNesse root directory for method and property usages across all wiki pages.
/// </summary>
/// <param name="AFitNesseRoot">The absolute path to the FitNesseRoot folder.</param>
/// <returns>A summary string containing the number of analyzed methods.</returns>
function TSlimDocGeneratorFixture.AnalyzeUsage(const AFitNesseRoot: String): String;
var
  Analyzer : TSlimUsageAnalyzer;
  Extractor: TSlimDocExtractor;
  Fixtures : TObjectList<TSlimDocFixture>;
begin
  FreeAndNil(FUsageMap);
  Fixtures := nil;
  Extractor := nil;
  Analyzer := TSlimUsageAnalyzer.Create;
  try
    Extractor := CreateExtractor;
    Fixtures := Extractor.ExtractAll;
    FUsageMap := Analyzer.Analyze(AFitNesseRoot, Fixtures);
    Result := Format('Analyzed files in %s. Found usage for %d unique methods.', [AFitNesseRoot, FUsageMap.Count]);
  finally
    Fixtures.Free;
    Extractor.Free;
    Analyzer.Free;
  end;
end;

function TSlimDocGeneratorFixture.CreateExtractor: TSlimDocExtractor;
var
  Path: String;
begin
  Result := TSlimDocExtractor.Create;
  for Path in FIncludePaths do
    Result.AddIncludePath(Path);
  for Path in FExcludePaths do
    Result.AddExcludePath(Path);
end;

/// <summary>
/// Adds a path to the exclusion list for source code scanning.
/// </summary>
/// <param name="APath">The path to exclude.</param>
procedure TSlimDocGeneratorFixture.ExcludeSourceCodePath(const APath: String);
begin
  FExcludePaths.Add(APath);
end;

/// <summary>
/// Adds a root path to search for source files to extract XML comments.
/// Can be called multiple times to include multiple directories.
/// </summary>
/// <param name="APath">The absolute path to a source code root directory.</param>
procedure TSlimDocGeneratorFixture.IncludeSourceCodePath(const APath: String);
begin
  FIncludePaths.Add(APath);
end;

/// <summary>
/// Generates the HTML documentation file containing all registered Slim fixtures, their members, and usage statistics.
/// </summary>
/// <param name="AFilePath">The absolute path where the HTML file should be saved.</param>
/// <returns>An HTML anchor tag linking to the generated file.</returns>
function TSlimDocGeneratorFixture.GenerateDocumentation(const AFilePath: String): String;
var
  Extractor: TSlimDocExtractor;
  Fixtures : TObjectList<TSlimDocFixture>;
  Generator: TSlimDocGenerator;
  Template : String;
begin
  if FMainTemplatePath = '' then
    raise Exception.Create('MainTemplate property must be set before generating documentation.');
  if not FileExists(FMainTemplatePath) then
    raise Exception.CreateFmt('Template file not found: %s', [FMainTemplatePath]);

  Template := TFile.ReadAllText(FMainTemplatePath, TEncoding.UTF8);
  Fixtures := nil;
  Extractor := nil;
  Generator := TSlimDocGenerator.Create;
  try
    Extractor := CreateExtractor;
    Fixtures := Extractor.ExtractAll;
    FGeneratedLink := Generator.Generate(Fixtures, FUsageMap, Template, AFilePath);
    Result := FGeneratedLink;
  finally
    Fixtures.Free;
    Extractor.Free;
    Generator.Free;
  end;
end;

initialization

RegisterSlimFixture(TSlimDocGeneratorFixture);

end.
