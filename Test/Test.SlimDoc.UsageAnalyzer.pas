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
    [Test]
    procedure TestAmbiguousMethodUsage;
    [Test]
    procedure TestNamespacedFixtureUsage;
    [Test]
    procedure TestEscapedFixtureName;
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
  // Need explicit fixture for analyzer to detect context
  CreateWikiFile('SubDir\PageTwo.wiki', '| script | MyFixture |'#13#10'| check | calculate value | 5 |');
  CreateWikiFile('PageThree.wiki', 'No relevant methods here.');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.dosomething'));
    List := UsageMap['myfixture.dosomething'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('PageOne', List[0]);

    Assert.IsTrue(UsageMap.ContainsKey('myfixture.calculatevalue'));
    List := UsageMap['myfixture.calculatevalue'];
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
  CreateWikiFile('Camel.wiki', '| script | MyFixture |'#13#10'| check | CalculateValue |');
  CreateWikiFile('Spaced.wiki', '| script | MyFixture |'#13#10'| check | calculate value |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.calculatevalue'), 'Should find usage for calculatevalue');
    List := UsageMap['myfixture.calculatevalue'];
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
  CreateWikiFile('RerunLastFailures.wiki', '| script | MyFixture |'#13#10'| do something |');
  CreateWikiFile('RerunLastFailures_Suite.wiki', '| script | MyFixture |'#13#10'| do something |');
  
  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsFalse(UsageMap.ContainsKey('myfixture.dosomething'), 'Should ignore RerunLastFailures files');
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestSetterUsageWithoutSetPrefix;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // "SetSelId" should be found when used as "Sel Id" or "sel id" in a Decision Table
  // Header row 1: Fixture Name. Header row 2: Column names (setters)
  CreateWikiFile('DecisionTable.wiki', '| MyFixture |'#13#10'| sel id |'#13#10'| 1 |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.setselid'), 'Should find usage for setselid');
    List := UsageMap['myfixture.setselid'];
    Assert.AreEqual(1, List.Count, 'Should find 1 usage');
    Assert.AreEqual('DecisionTable', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestAmbiguousMethodUsage;
var
  FixtureA, FixtureB: TSlimFixtureDoc;
  Method    : TSlimMethodDoc;
  UsageMap  : TUsageMap;
  List      : TStringList;
begin
  // Setup FixtureA with SetName
  FixtureA := TSlimFixtureDoc.Create;
  FixtureA.Name := 'FixtureA';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'SetName';
  FixtureA.Methods.Add(Method);
  FFixtures.Add(FixtureA);

  // Setup FixtureB with SetName
  FixtureB := TSlimFixtureDoc.Create;
  FixtureB.Name := 'FixtureB';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'SetName';
  FixtureB.Methods.Add(Method);
  FFixtures.Add(FixtureB);

  // PageA uses FixtureA
  CreateWikiFile('PageA.wiki', '| FixtureA |'#13#10'| name |'#13#10'| Alice |');
  
  // PageB uses FixtureB
  CreateWikiFile('PageB.wiki', '| script | FixtureB |'#13#10'| set name | Bob |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    // FixtureA.SetName should ONLY be used in PageA
    Assert.IsTrue(UsageMap.ContainsKey('fixturea.setname'), 'Should find usage for FixtureA.SetName');
    List := UsageMap['fixturea.setname'];
    Assert.AreEqual(1, List.Count, 'FixtureA.SetName should have 1 usage');
    Assert.AreEqual('PageA', List[0]);

    // FixtureB.SetName should ONLY be used in PageB
    Assert.IsTrue(UsageMap.ContainsKey('fixtureb.setname'), 'Should find usage for FixtureB.SetName');
    List := UsageMap['fixtureb.setname'];
    Assert.AreEqual(1, List.Count, 'FixtureB.SetName should have 1 usage');
    Assert.AreEqual('PageB', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestNamespacedFixtureUsage;
var
  Fixture : TSlimFixtureDoc;
  Method  : TSlimMethodDoc;
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Setup Fixture with Namespace
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'Generator';
  Fixture.Namespace := 'SlimDoc'; // Full name: SlimDoc.Generator

  Method := TSlimMethodDoc.Create;
  Method.Name := 'AnalyzeUsage';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Wiki uses fully qualified name
  CreateWikiFile('Doc.wiki', '| script | SlimDoc.Generator |'#13#10'| analyze usage | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('generator.analyzeusage'), 'Should find usage for Generator.AnalyzeUsage');
    List := UsageMap['generator.analyzeusage'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('Doc', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestEscapedFixtureName;
var
  Fixture : TSlimFixtureDoc;
  Method  : TSlimMethodDoc;
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'Generator';
  Fixture.Namespace := 'SlimDoc';

  Method := TSlimMethodDoc.Create;
  Method.Name := 'AnalyzeUsage';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Wiki uses escaped name !-SlimDoc.Generator-!
  CreateWikiFile('Doc.wiki', '| script | !-SlimDoc.Generator-! |'#13#10'| analyze usage | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('generator.analyzeusage'), 'Should find usage for Generator.AnalyzeUsage with escaped fixture name');
    List := UsageMap['generator.analyzeusage'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('Doc', List[0]);
  finally
    UsageMap.Free;
  end;
end;

end.