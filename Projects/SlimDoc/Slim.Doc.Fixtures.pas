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

  [SlimFixture('Generator', 'SlimDoc')]
  TSlimDocGeneratorFixture = class(TSlimFixture)
  private
    FGeneratedLink: String;
    FUsageMap     : TUsageMap;
  public
    destructor Destroy; override;
    function GenerateDocumentation(const AFilePath: String): String;
    function AnalyzeUsage(const AFitNesseRoot: String): String;
    property GeneratedLink: String read FGeneratedLink;
  end;

implementation

{ TSlimDocGeneratorFixture }

destructor TSlimDocGeneratorFixture.Destroy;
begin
  FUsageMap.Free;
  inherited;
end;

function TSlimDocGeneratorFixture.AnalyzeUsage(const AFitNesseRoot: String): String;
var
  Analyzer : TSlimUsageAnalyzer;
  Extractor: TSlimDocExtractor;
  Fixtures : TObjectList<TSlimFixtureDoc>;
begin
  FreeAndNil(FUsageMap);
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

function TSlimDocGeneratorFixture.GenerateDocumentation(const AFilePath: String): String;
var
  Extractor: TSlimDocExtractor;
  Fixtures : TObjectList<TSlimFixtureDoc>;
  Generator: TSlimDocGenerator;
begin
  Extractor := TSlimDocExtractor.Create;
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
