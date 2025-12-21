// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimDoc.UsageAnalyzer;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Doc.Model,
  Slim.Doc.UsageAnalyzer;

type

  [TestFixture]
  TTestSlimUsageAnalyzer = class
  private
    FAnalyzer: TSlimUsageAnalyzer;
    FFixtures: TObjectList<TSlimFixtureDoc>;
    FTempDir : String;
    procedure CreateWikiFile(const AFileName, AContent: String);
  public
    [Setup]
    procedure Setup;
    [Teardown]
    procedure Teardown;
    [Test]
    procedure TestAnalysis;
    [Test]
    procedure TestCamelCaseSplitting;
    [Test]
    procedure TestIgnoreRerunFiles;
    [Test]
    procedure TestSetterUsageWithoutSetPrefix;
  end;

implementation

{ TTestSlimUsageAnalyzer }

procedure TTestSlimUsageAnalyzer.Setup;
var
  Fixture: TSlimFixtureDoc;
  Method : TSlimMethodDoc;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'SlimUsageTest_' + TGUID.NewGuid.ToString);
  // Ensure no trailing delimiter
  if FTempDir.EndsWith(PathDelim) then
    FTempDir := FTempDir.Substring(0, FTempDir.Length - 1);

  TDirectory.CreateDirectory(FTempDir);

  FAnalyzer := TSlimUsageAnalyzer.Create;
  FFixtures := TObjectList<TSlimFixtureDoc>.Create;

  // Create a dummy fixture model for testing
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'MyFixture';

  Method := TSlimMethodDoc.Create;
  Method.Name := 'DoSomething';
  Fixture.Methods.Add(Method);

  Method := TSlimMethodDoc.Create;
  Method.Name := 'CalculateValue';
  Fixture.Methods.Add(Method);

  Method := TSlimMethodDoc.Create;
  Method.Name := 'SetSelId';
  Fixture.Methods.Add(Method);

  FFixtures.Add(Fixture);
end;

procedure TTestSlimUsageAnalyzer.Teardown;
begin
  FFixtures.Free;
  FAnalyzer.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestSlimUsageAnalyzer.CreateWikiFile(const AFileName, AContent: String);
var
  Path: String;
begin
  Path := TPath.Combine(FTempDir, AFileName);
  TDirectory.CreateDirectory(ExtractFileDir(Path));
  TFile.WriteAllText(Path, AContent, TEncoding.UTF8);
end;

procedure TTestSlimUsageAnalyzer.TestAnalysis;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  CreateWikiFile('PageOne.wiki', '| script | MyFixture |'#13#10'| do something |');
  CreateWikiFile('SubDir\PageTwo.wiki', '| script |'#13#10'| check | calculate value | 5 |');
  CreateWikiFile('PageThree.wiki', 'No relevant methods here.');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('dosomething'));
    List := UsageMap['dosomething'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('PageOne', List[0]);

    Assert.IsTrue(UsageMap.ContainsKey('calculatevalue'));
    List := UsageMap['calculatevalue'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('SubDir.PageTwo', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestCamelCaseSplitting;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // "CalculateValue" should be found as "CalculateValue" AND "calculate value"
  CreateWikiFile('Camel.wiki', '| check | CalculateValue |');
  CreateWikiFile('Spaced.wiki', '| check | calculate value |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('calculatevalue'), 'Should find usage for calculatevalue');
    List := UsageMap['calculatevalue'];
    Assert.AreEqual(2, List.Count, 'Should find 2 usages'); // Should find both
    // Check if both files are present (list is sorted)
    Assert.IsTrue(List.IndexOf('Camel') >= 0);
    Assert.IsTrue(List.IndexOf('Spaced') >= 0);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestIgnoreRerunFiles;
var
  UsageMap: TUsageMap;
begin
  CreateWikiFile('RerunLastFailures.wiki', '| do something |');
  CreateWikiFile('RerunLastFailures_Suite.wiki', '| do something |');
  
  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsFalse(UsageMap.ContainsKey('dosomething'), 'Should ignore RerunLastFailures files');
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestSetterUsageWithoutSetPrefix;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // "SetSelId" should be found when used as "Sel Id" or "sel id"
  CreateWikiFile('DecisionTable.wiki', '| sel id |'#13#10'| 1 |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('setselid'), 'Should find usage for setselid');
    List := UsageMap['setselid'];
    Assert.AreEqual(1, List.Count, 'Should find 1 usage');
    Assert.AreEqual('DecisionTable', List[0]);
  finally
    UsageMap.Free;
  end;
end;

end.
