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
    [Test]
    procedure TestLibraryTableUsage;
    [Test]
    procedure TestLibraryTableInSetupPage;
    [Test]
    procedure TestLibraryTableInIncludedPage;
    [Test]
    procedure TestIncludeWithInvalidPath;
    [Test]
    procedure TestIncludeWithImplicitPath;
    [Test]
    procedure TestLibraryTableWithSpaces;
    [Test]
    procedure TestScriptTableWithFixtureNamedScript;
    [Test]
    procedure TestInterleavedMethodUsage;
    [Test]
    procedure TestOnlyReservePositionsReproduction;
    [Test]
    procedure TestScenarioUsage;
  end;

implementation

{ TTestSlimUsageAnalyzer }

procedure TTestSlimUsageAnalyzer.Setup;
var
  Fixture: TSlimFixtureDoc;
  Method : TSlimMethodDoc;
begin
  FTempDir := IncludeTrailingPathDelimiter(
    TPath.Combine(TPath.GetTempPath, 'SlimUsageTest_' + TGUID.NewGuid.ToString));

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

  // Method with multiple arguments for interleaved testing
  // Name: ClickToolbarButtonOnFormWithIcon
  Method := TSlimMethodDoc.Create;
  Method.Name := 'ClickToolbarButtonOnFormWithIcon';
  Fixture.Methods.Add(Method);

  FFixtures.Add(Fixture);

  // Library Fixture
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'LibraryFixture';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'ExecuteAction';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Flow Control Fixture (simulating the issue)
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'FlowControl';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'IgnoreAllTestsIfDefined';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Script Fixture (empty, relies on Library)
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'ScriptFixture';
  FFixtures.Add(Fixture);

  // Specific Fixture from user case
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'NpkReserveForm';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'ClickToolbarButtonOnFormWithIcon';
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

  // Also check escaped variant (typically used for CamelCase to avoid WikiWords)
  CreateWikiFile('EscapedDecisionTable.wiki', '| MyFixture |'#13#10'| !-SelId-! |'#13#10'| 1 |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.setselid'), 'Should find usage for setselid');
    List := UsageMap['myfixture.setselid'];
    Assert.AreEqual(2, List.Count, 'Should find 2 usages (normal and escaped)');
    Assert.IsTrue(List.IndexOf('DecisionTable') >= 0);
    Assert.IsTrue(List.IndexOf('EscapedDecisionTable') >= 0);
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

  // Wiki uses fully qualified and escaped name
  CreateWikiFile('Doc.wiki', '| script | !-SlimDoc.Generator-! |'#13#10'| analyze usage | arg |');

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
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Setup already contains 'MyFixture' with 'DoSomething'
  // Wiki uses escaped simple name !-MyFixture-!
  CreateWikiFile('SimpleEscaped.wiki', '| script | !-MyFixture-! |'#13#10'| do something |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.dosomething'), 'Should find usage for MyFixture.DoSomething with escaped fixture name');
    List := UsageMap['myfixture.dosomething'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('SimpleEscaped', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestLibraryTableUsage;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Library table imports "LibraryFixture"
  // Script table uses "ScriptFixture"
  // Method "ExecuteAction" is in LibraryFixture, not ScriptFixture
  CreateWikiFile('LibraryUsage.wiki',
    '| Library |'#13#10 +
    '| LibraryFixture |'#13#10 +
    ''#13#10 +
    '| script | ScriptFixture |'#13#10 +
    '| execute action | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('libraryfixture.executeaction'), 'Should find usage for LibraryFixture.ExecuteAction via Library table');
    List := UsageMap['libraryfixture.executeaction'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('LibraryUsage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestLibraryTableInSetupPage;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // SetUp page imports "LibraryFixture"
  CreateWikiFile('SetUp.wiki',
    '| Library |'#13#10 +
    '| LibraryFixture |');

  // Test page uses "ScriptFixture" but calls "ExecuteAction" from Library
  CreateWikiFile('TestPage.wiki',
    '| script | ScriptFixture |'#13#10 +
    '| execute action | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('libraryfixture.executeaction'), 'Should find usage from inherited SetUp library');
    List := UsageMap['libraryfixture.executeaction'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('TestPage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestLibraryTableInIncludedPage;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Included page defines library
  CreateWikiFile('IncludedPage.wiki',
    '| library |'#13#10 +
    '| LibraryFixture |');

  // Test page includes the other page and uses the library method
  CreateWikiFile('TestPage.wiki',
    '!include -setup <IncludedPage'#13#10 +
    '| script | ScriptFixture |'#13#10 +
    '| execute action | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('libraryfixture.executeaction'), 'Should find usage from included library');
    List := UsageMap['libraryfixture.executeaction'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('TestPage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestIncludeWithInvalidPath;
var
  UsageMap: TUsageMap;
begin
  // Test page with invalid include path that causes EInOutArgumentException
  CreateWikiFile('InvalidInclude.wiki',
    '!include -setup <[>Vars]'#13#10 +
    '| script | MyFixture |'#13#10 +
    '| do something |');

  // Should not raise exception
  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.dosomething'));
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestIncludeWithImplicitPath;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Create a structure: Root/ATDD/MySuite/Setup.wiki
  var AtddDir := TPath.Combine(FTempDir, 'ATDD');
  var SuiteDir := TPath.Combine(AtddDir, 'MySuite');
  TDirectory.CreateDirectory(SuiteDir);

  TFile.WriteAllText(TPath.Combine(SuiteDir, 'Setup.wiki'),
    '| library |'#13#10 +
    '| LibraryFixture |', TEncoding.UTF8);

  // Test page includes using <MySuite.Setup (skipping ATDD)
  CreateWikiFile('TestPage.wiki',
    '!include -setup <MySuite.Setup'#13#10 +
    '| script | ScriptFixture |'#13#10 +
    '| execute action | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    // This will likely fail until we implement the fallback logic
    Assert.IsTrue(UsageMap.ContainsKey('libraryfixture.executeaction'), 'Should find usage from included library with implicit ATDD path');
    List := UsageMap['libraryfixture.executeaction'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('TestPage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestLibraryTableWithSpaces;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // SuiteSetUp defines "Flow Control" as library
  CreateWikiFile('SuiteSetUp.wiki',
    '| Library |'#13#10 +
    '| Flow Control |');

  // Page uses ScriptFixture but calls IgnoreAllTestsIfDefined
  CreateWikiFile('TestPage.wiki',
    '| script | ScriptFixture |'#13#10 +
    '| ignore all tests if defined | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('flowcontrol.ignorealltestsifdefined'), 'Should find usage for FlowControl.IgnoreAllTestsIfDefined via inherited Library');
    List := UsageMap['flowcontrol.ignorealltestsifdefined'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('TestPage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestScriptTableWithFixtureNamedScript;
var
  UsageMap: TUsageMap;
  Fixture : TSlimFixtureDoc;
begin
  // Setup a fixture named "Script" (like Base.UI.Script)
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'Script';
  FFixtures.Add(Fixture);

  // SuiteSetUp defines "FlowControl" as library
  CreateWikiFile('SuiteSetUp.wiki', '| Library |'#13#10'| FlowControl |');

  // Page uses "script" table with fixture "Script"
  CreateWikiFile('TestPage.wiki',
    '| script | Script |'#13#10 +
    '| ignore all tests if defined | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('flowcontrol.ignorealltestsifdefined'), 'Should find library usage even if fixture is named Script');
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestInterleavedMethodUsage;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Wiki page with interleaved method call
  // | Click Toolbar Button On Form | $Form | With Icon | ADD |
  CreateWikiFile('Interleaved.wiki',
    '| script | MyFixture |'#13#10 +
    '| Click Toolbar Button On Form | $ReserveForm | With Icon | DOC_ADD |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.clicktoolbarbuttononformwithicon'), 'Should find usage for interleaved method call');
    List := UsageMap['myfixture.clicktoolbarbuttononformwithicon'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('Interleaved', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestOnlyReservePositionsReproduction;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Exact reproduction of the user's wiki snippet
  CreateWikiFile('OnlyReservePositions.wiki',
    '|script                                       |Npk Reserve Form|$ReserveForm     |'#13#10 +
    '|Click Toolbar Button On Form                 |$ReserveForm    |With Icon|DOC_ADD|');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('npkreserveform.clicktoolbarbuttononformwithicon'),
      'Should find usage for ClickToolbarButtonOnFormWithIcon in reproduction case');
    List := UsageMap['npkreserveform.clicktoolbarbuttononformwithicon'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('OnlyReservePositions', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestScenarioUsage;
var
  Fixture : TSlimFixtureDoc;
  Method  : TSlimMethodDoc;
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  // Fixture setup
  Fixture := TSlimFixtureDoc.Create;
  Fixture.Name := 'ScenarioFixture';
  Method := TSlimMethodDoc.Create;
  Method.Name := 'ScenarioMethod';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Wiki file with scenario
  // Even without explicit fixture usage, methods in scenarios should be detected
  // (potentially matching against all fixtures or libraries)
  CreateWikiFile('ScenarioUsage.wiki',
    '| scenario | MyScenario | arg |'#13#10 +
    '| scenario method | arg |');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('scenariofixture.scenariomethod'), 'Should find usage in scenario');
    List := UsageMap['scenariofixture.scenariomethod'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('ScenarioUsage', List[0]);
  finally
    UsageMap.Free;
  end;
end;

end.
