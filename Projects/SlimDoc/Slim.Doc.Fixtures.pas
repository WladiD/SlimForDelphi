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
    FGeneratedLink : String;
    FRootSourcePath: String;
    FUsageMap      : TUsageMap;
  public
    destructor Destroy; override;
    function GenerateDocumentation(const AFilePath: String): String;
    function AnalyzeUsage(const AFitNesseRoot: String): String;
    function IncludeXmlComments(const ARootSourcePath: String): Boolean;
    /// <summary>
    /// Returns the link to the generated documentation file after execution.
    /// </summary>
    property GeneratedLink: String read FGeneratedLink;
  end;

implementation

{ TSlimDocGeneratorFixture }

destructor TSlimDocGeneratorFixture.Destroy;
begin
  FUsageMap.Free;
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
  Fixtures : TObjectList<TSlimFixtureDoc>;
begin
  FreeAndNil(FUsageMap);
  Extractor := TSlimDocExtractor.Create;
  if FRootSourcePath <> '' then
    Extractor.RootSourcePath := FRootSourcePath;

  Analyzer := TSlimUsageAnalyzer.Create;
  try
    Fixtures := Extractor.ExtractAll;
    try
      FUsageMap := Analyzer.Analyze(AFitNesseRoot, Fixtures);
      Result := Format('Analyzed files in %s. Found usage for %d unique methods.', [AFitNesseRoot, FUsageMap.Count]);
    finally
      Fixtures.Free;
    end;
  finally
    Extractor.Free;
    Analyzer.Free;
  end;
end;

/// <summary>
/// Configures the root path to search for source files to extract XML comments.
/// </summary>
/// <param name="ARootSourcePath">The absolute path to the source code root directory.</param>
/// <returns>True if the path was accepted.</returns>
function TSlimDocGeneratorFixture.IncludeXmlComments(const ARootSourcePath: String): Boolean;
begin
  FRootSourcePath := ARootSourcePath;
  Result := True;
end;

/// <summary>
/// Generates the HTML documentation file containing all registered Slim fixtures, their members, and usage statistics.
/// </summary>
/// <param name="AFilePath">The absolute path where the HTML file should be saved.</param>
/// <returns>An HTML anchor tag linking to the generated file.</returns>
function TSlimDocGeneratorFixture.GenerateDocumentation(const AFilePath: String): String;
var
  Extractor: TSlimDocExtractor;
  Fixtures : TObjectList<TSlimFixtureDoc>;
  Generator: TSlimDocGenerator;
begin
  Extractor := TSlimDocExtractor.Create;
  if FRootSourcePath <> '' then
    Extractor.RootSourcePath := FRootSourcePath;

  Generator := TSlimDocGenerator.Create;
  try
    Fixtures := Extractor.ExtractAll;
    try
      FGeneratedLink := Generator.Generate(Fixtures, FUsageMap, AFilePath);
      Result := FGeneratedLink;
    finally
      Fixtures.Free;
    end;
  finally
    Extractor.Free;
    Generator.Free;
  end;
end;

initialization

RegisterSlimFixture(TSlimDocGeneratorFixture);

end.
