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
  Slim.Fixture,
  Slim.Doc.Model,
  Slim.Doc.Extractor,
  Slim.Doc.UsageAnalyzer,
  Slim.Doc.Generator;

type

  [SlimFixture('Documentation', 'common')]
  TSlimDocumentationFixture = class(TSlimFixture)
  private
    FUsageMap: TUsageMap;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
    function GenerateDocumentation(const AFilePath: String): String;
    function AnalyzeUsage(const AFitNesseRoot: String): String;
  end;

implementation

{ TSlimDocumentationFixture }

procedure TSlimDocumentationFixture.AfterConstruction;
begin
  inherited;
end;

destructor TSlimDocumentationFixture.Destroy;
begin
  FUsageMap.Free;
  inherited;
end;

function TSlimDocumentationFixture.AnalyzeUsage(const AFitNesseRoot: String): String;
var
  Extractor: TSlimDocExtractor;
  Analyzer: TSlimUsageAnalyzer;
  Fixtures: TObjectList<TSlimFixtureDoc>;
begin
  FUsageMap.Free;
  FUsageMap := nil;

  Extractor := TSlimDocExtractor.Create;
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

function TSlimDocumentationFixture.GenerateDocumentation(const AFilePath: String): String;
var
  Extractor: TSlimDocExtractor;
  Generator: TSlimDocGenerator;
  Fixtures: TObjectList<TSlimFixtureDoc>;
begin
  Extractor := TSlimDocExtractor.Create;
  Generator := TSlimDocGenerator.Create;
  try
    Fixtures := Extractor.ExtractAll;
    try
      Result := Generator.Generate(Fixtures, FUsageMap, AFilePath);
    finally
      Fixtures.Free;
    end;
  finally
    Extractor.Free;
    Generator.Free;
  end;
end;

initialization
  RegisterSlimFixture(TSlimDocumentationFixture);

end.