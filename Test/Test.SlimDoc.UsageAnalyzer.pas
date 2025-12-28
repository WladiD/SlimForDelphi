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
    FFixtures: TObjectList<TSlimDocFixture>;
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
    procedure TestMyFormReproduction;
    [Test]
    procedure TestScenarioUsage;
    [Test]
    procedure TestPropertyUsage;
  end;

implementation

{ TTestSlimUsageAnalyzer }

procedure TTestSlimUsageAnalyzer.Setup;
var
  Fixture: TSlimDocFixture;
  Method : TSlimDocMethod;
begin
  FTempDir := IncludeTrailingPathDelimiter(
    TPath.Combine(TPath.GetTempPath, 'SlimUsageTest_' + TGUID.NewGuid.ToString));

  TDirectory.CreateDirectory(FTempDir);

  FAnalyzer := TSlimUsageAnalyzer.Create;
  FFixtures := TObjectList<TSlimDocFixture>.Create;

  // Create a dummy fixture model for testing
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'MyFixture';

  Method := TSlimDocMethod.Create;
  Method.Name := 'DoSomething';
  Fixture.Methods.Add(Method);

  Method := TSlimDocMethod.Create;
  Method.Name := 'CalculateValue';
  Fixture.Methods.Add(Method);

  Method := TSlimDocMethod.Create;
  Method.Name := 'SetSelId';
  Fixture.Methods.Add(Method);

  // Method with multiple arguments for interleaved testing
  Method := TSlimDocMethod.Create;
  Method.Name := 'ClickToolbarButtonOnFormWithIcon';
  Fixture.Methods.Add(Method);

  var Prop := TSlimDocProperty.Create;
  Prop.Name := 'SomeProp';
  Fixture.Properties.Add(Prop);


  // Library Fixture
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'LibraryFixture';
  Method := TSlimDocMethod.Create;
  Method.Name := 'ExecuteAction';
  Fixture.Methods.Add(Method);

  // Flow Control Fixture (simulating the issue)
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'FlowControl';
  Method := TSlimDocMethod.Create;
  Method.Name := 'IgnoreAllTestsIfDefined';
  Fixture.Methods.Add(Method);

  // Script Fixture (empty, relies on Library)
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'ScriptFixture';

  // Specific Fixture from user case
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'MyForm';
  Method := TSlimDocMethod.Create;
  Method.Name := 'ClickToolbarButtonOnFormWithIcon';
  Fixture.Methods.Add(Method);
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
  CreateWikiFile('Camel.wiki', '''
    | script | MyFixture |
    | check | CalculateValue
    ''');
  CreateWikiFile('Spaced.wiki', '''
    | script | MyFixture |
    | check  | calculate value |
    ''');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.calculatevalue'), 'Should find usage for calculatevalue');
    List := UsageMap['myfixture.calculatevalue'];
    Assert.AreEqual(2, List.Count, 'Should find 2 usages');
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
  CreateWikiFile('RerunLastFailures.wiki', '''
    | script | MyFixture |
    | do something |
    ''');
  CreateWikiFile('RerunLastFailures_Suite.wiki', '''
    | script | MyFixture |
    | do something |
    ''');

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
  CreateWikiFile('DecisionTable.wiki', '''
    | MyFixture |
    | sel id    |
    | 1         |
    ''');

  // Also check escaped variant (typically used for CamelCase to avoid WikiWords)
  CreateWikiFile('EscapedDecisionTable.wiki', '''
    | MyFixture |
    | !-SelId-! |
    | 1         |
    ''');

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
  FixtureA: TSlimDocFixture;
  FixtureB: TSlimDocFixture;
  List    : TStringList;
  Method  : TSlimDocMethod;
  UsageMap: TUsageMap;
begin
  // Setup FixtureA with SetName
  FixtureA := TSlimDocFixture.Create;
  FixtureA.Name := 'FixtureA';
  Method := TSlimDocMethod.Create;
  Method.Name := 'SetName';
  FixtureA.Methods.Add(Method);
  FFixtures.Add(FixtureA);

  // Setup FixtureB with SetName
  FixtureB := TSlimDocFixture.Create;
  FixtureB.Name := 'FixtureB';
  Method := TSlimDocMethod.Create;
  Method.Name := 'SetName';
  FixtureB.Methods.Add(Method);
  FFixtures.Add(FixtureB);

  // PageA uses FixtureA
  CreateWikiFile('PageA.wiki', '''
    | FixtureA |
    | name     |
    | Alice    |
    ''');

  // PageB uses FixtureB
  CreateWikiFile('PageB.wiki', '''
    | script   | FixtureB |
    | set name | Bob      |
    ''');

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
  Fixture : TSlimDocFixture;
  List    : TStringList;
  Method  : TSlimDocMethod;
  UsageMap: TUsageMap;
begin
  // Setup Fixture with Namespace
  Fixture := TSlimDocFixture.Create;
  Fixture.Name := 'Generator';
  Fixture.Namespace := 'SlimDoc'; // Full name: SlimDoc.Generator

  Method := TSlimDocMethod.Create;
  Method.Name := 'AnalyzeUsage';
  Fixture.Methods.Add(Method);
  FFixtures.Add(Fixture);

  // Wiki uses fully qualified and escaped name
  CreateWikiFile('Doc.wiki', '''
    | script        | !-SlimDoc.Generator-! |
    | analyze usage | arg                   |
    ''');

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
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // Setup already contains 'MyFixture' with 'DoSomething'
  // Wiki uses escaped simple name !-MyFixture-!
  CreateWikiFile('SimpleEscaped.wiki', '''
    | script | !-MyFixture-! |
    | do something           |
    ''');

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
  CreateWikiFile('LibraryUsage.wiki', '''
    | Library        |
    | LibraryFixture |

    | script         | ScriptFixture |
    | execute action | arg           |
    ''');

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
  CreateWikiFile('SetUp.wiki', '''
    | Library |
    | LibraryFixture |
    ''');

  // Test page uses "ScriptFixture" but calls "ExecuteAction" from Library
  CreateWikiFile('TestPage.wiki', '''
    | script         | ScriptFixture |
    | execute action | arg           |
    ''');

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
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // Included page defines library
  CreateWikiFile('IncludedPage.wiki', '''
    | library        |
    | LibraryFixture |
    ''');

  // Test page includes the other page and uses the library method
  CreateWikiFile('TestPage.wiki', '''
    !include -setup <IncludedPage
    | script         | ScriptFixture |
    | execute action | arg           |
    ''');

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
  CreateWikiFile('InvalidInclude.wiki', '''
    !include -setup <[>Vars]
    | script | MyFixture |
    | do something       |
    ''');

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
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // Create a structure: Root/ATDD/MySuite/Setup.wiki
  var AtddDir: String := TPath.Combine(FTempDir, 'ATDD');
  var SuiteDir: String := TPath.Combine(AtddDir, 'MySuite');
  TDirectory.CreateDirectory(SuiteDir);

  TFile.WriteAllText(TPath.Combine(SuiteDir, 'Setup.wiki'), '''
    | library        |
    | LibraryFixture |
    ''', TEncoding.UTF8);

  // Test page includes using <MySuite.Setup (skipping ATDD)
  CreateWikiFile('TestPage.wiki', '''
    !include -setup <MySuite.Setup
    | script         | ScriptFixture |
    | execute action | arg           |
    ''');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
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
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // SuiteSetUp defines "Flow Control" as library
  CreateWikiFile('SuiteSetUp.wiki', '''
    | Library      |
    | Flow Control |
    ''');

  // Page uses ScriptFixture but calls IgnoreAllTestsIfDefined
  CreateWikiFile('TestPage.wiki', '''
    | script                      | ScriptFixture |
    | ignore all tests if defined | arg           |
    ''');

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
  Fixture : TSlimDocFixture;
  UsageMap: TUsageMap;
begin
  // Setup a fixture named "Script" (like Base.UI.Script)
  Fixture := TSlimDocFixture.Create;
  Fixture.Name := 'Script';
  FFixtures.Add(Fixture);

  // SuiteSetUp defines "FlowControl" as library
  CreateWikiFile('SuiteSetUp.wiki', '''
    | Library     |
    | FlowControl |
    ''');

  // Page uses "script" table with fixture "Script"
  CreateWikiFile('TestPage.wiki', '''
    | script                      | Script |
    | ignore all tests if defined | arg    |
    ''');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('flowcontrol.ignorealltestsifdefined'), 'Should find library usage even if fixture is named Script');
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestInterleavedMethodUsage;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // Wiki page with interleaved method call
  CreateWikiFile('Interleaved.wiki', '''
    | script                       | MyFixture                      |
    | Click Toolbar Button On Form | $ReserveForm | With Icon | ADD |
    ''');

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

procedure TTestSlimUsageAnalyzer.TestMyFormReproduction;
var
  UsageMap: TUsageMap;
  List    : TStringList;
begin
  CreateWikiFile('MyFormPositions.wiki', '''
    |script                      |My Form         |$MyForm          |
    |Click Toolbar Button On Form|$MyForm         |With Icon    |ADD|
    ''');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myform.clicktoolbarbuttononformwithicon'),
      'Should find usage for ClickToolbarButtonOnFormWithIcon in reproduction case');
    List := UsageMap['myform.clicktoolbarbuttononformwithicon'];
    Assert.AreEqual(1, List.Count);
    Assert.AreEqual('MyFormPositions', List[0]);
  finally
    UsageMap.Free;
  end;
end;

procedure TTestSlimUsageAnalyzer.TestScenarioUsage;
var
  Fixture : TSlimDocFixture;
  List    : TStringList;
  Method  : TSlimDocMethod;
  UsageMap: TUsageMap;
begin
  // Fixture setup
  Fixture := TSlimDocFixture.Create;
  FFixtures.Add(Fixture);
  Fixture.Name := 'ScenarioFixture';
  Method := TSlimDocMethod.Create;
  Method.Name := 'ScenarioMethod';
  Fixture.Methods.Add(Method);

  // Wiki file with scenario
  // Even without explicit fixture usage, methods in scenarios should be detected
  // (potentially matching against all fixtures or libraries)
  CreateWikiFile('ScenarioUsage.wiki', '''
    | scenario        | MyScenario | arg |
    | scenario method | arg              |
    ''');

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

procedure TTestSlimUsageAnalyzer.TestPropertyUsage;
var
  List    : TStringList;
  UsageMap: TUsageMap;
begin
  // Property usage via 'check' (getter)
  CreateWikiFile('PropGetter.wiki', '''
    | script | MyFixture         |
    | check  | some prop | value |
    ''');

  // Property usage via 'set' (setter without set-prefix, common in decision tables)
  // Or in script tables: | some prop | value | (setter call)
  CreateWikiFile('PropSetter.wiki', '''
    | script    | MyFixture |
    | some prop | value     |
    ''');

  UsageMap := FAnalyzer.Analyze(FTempDir, FFixtures);
  try
    Assert.IsTrue(UsageMap.ContainsKey('myfixture.someprop'), 'Should find usage for property SomeProp');
    List := UsageMap['myfixture.someprop'];
    Assert.AreEqual(2, List.Count, 'Should find 2 usages');
    Assert.IsTrue(List.IndexOf('PropGetter') >= 0);
    Assert.IsTrue(List.IndexOf('PropSetter') >= 0);
  finally
    UsageMap.Free;
  end;
end;

end.
