// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimDoc.Extractor;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Doc.Extractor,
  Slim.Doc.Model,
  Slim.Fixture;

type

  [SlimFixture('TestFixture', 'test')]
  TSampleFixture = class(TSlimFixture)
  private
    FProp: Integer;
  public
    constructor Create(AParam: Integer);
    procedure MethodOne;
    function  MethodTwo(A: String): Boolean;
    [SlimMemberSyncMode(smSynchronized)]
    procedure SyncMethod;
    property  MyProp: Integer read FProp write FProp;
  end;

  TSimpleBaseFixture = class(TSlimFixture)
  end;

  TSimpleChildFixture = class(TSimpleBaseFixture)
  end;

  [TestFixture]
  TTestSlimDocExtractor = class
  public
    [Test]
    procedure TestExtraction;
    [Test]
    procedure TestInheritanceChain;
  end;

  [TestFixture]
  TTestSlimXmlDocExtractor = class
  public
    [Test]
    procedure TestExtractXmlDocs;
  end;

implementation

{ TSampleFixture }

constructor TSampleFixture.Create(AParam: Integer);
begin
end;

procedure TSampleFixture.MethodOne;
begin
end;

function TSampleFixture.MethodTwo(A: String): Boolean;
begin
  Result := True;
end;

procedure TSampleFixture.SyncMethod;
begin
end;

{ TTestSlimDocExtractor }

procedure TTestSlimDocExtractor.TestInheritanceChain;
var
  Doc      : TSlimDocFixture;
  Extractor: TSlimDocExtractor;
begin
  Doc := nil;
  Extractor := TSlimDocExtractor.Create;
  try
    Doc := Extractor.ExtractClass(TSimpleChildFixture);
    Assert.AreEqual('TSimpleChildFixture', Doc.DelphiClass);
    
    // Chain: TSimpleBaseFixture -> TSlimFixture -> TObject
    Assert.IsTrue(Doc.InheritanceChain.Count >= 3, 'Inheritance chain should have at least 3 items');
    Assert.AreEqual('TSimpleBaseFixture', Doc.InheritanceChain[0]);
    Assert.AreEqual('TSlimFixture', Doc.InheritanceChain[1]);
    Assert.AreEqual('TObject', Doc.InheritanceChain[Doc.InheritanceChain.Count - 1]);
  finally
    Doc.Free;
    Extractor.Free;
  end;
end;

procedure TTestSlimDocExtractor.TestExtraction;
var
  Doc      : TSlimDocFixture;
  Extractor: TSlimDocExtractor;
  Method   : TSlimDocMethod;
  Prop     : TSlimDocProperty;

  function GetDocMethod(const AName: String): TSlimDocMethod;
  begin
    for var M: TSlimDocMethod in Doc.Methods do
      if SameText(M.Name, AName) then
        Exit(M);
    Result := nil;
  end;

begin
  Doc := nil;
  Extractor := TSlimDocExtractor.Create;
  try
    Doc := Extractor.ExtractClass(TSampleFixture);
    Assert.AreEqual('TestFixture', Doc.Name);
    Assert.AreEqual('test', Doc.Namespace);
    Assert.AreEqual('TSampleFixture', Doc.DelphiClass);

    // Check Methods (Should have Create, MethodOne, MethodTwo, SyncMethod)
    if Doc.Methods.Count <> 4 then
    begin
      var Msg := 'Extracted methods: ';
      for var M: TSlimDocMethod in Doc.Methods do
        Msg := Msg + M.Name + ', ';
      Assert.AreEqual(4, Doc.Methods.Count, Msg);
    end;

    // Look for specific method
    Method := GetDocMethod('MethodTwo');
    Assert.IsNotNull(Method);
    Assert.AreEqual(1, Method.Parameters.Count);
    Assert.AreEqual('A', Method.Parameters[0].Name);
    Assert.AreEqual('Boolean', Method.ReturnType);

    // Check SyncMode
    Method := GetDocMethod('SyncMethod');
    Assert.IsNotNull(Method);
    Assert.AreEqual('smSynchronized', Method.SyncMode);

    // Check constructor
    Method := GetDocMethod('Create');
    Assert.IsNotNull(Method);
    Assert.AreEqual(1, Method.Parameters.Count);

    // Check Property
    Assert.AreEqual(1, Doc.Properties.Count);
    Prop := Doc.Properties[0];
    Assert.AreEqual('MyProp', Prop.Name);
    Assert.AreEqual('Integer', Prop.PropertyType);
    Assert.AreEqual('Read/Write', Prop.Access);
  finally
    Doc.Free;
    Extractor.Free;
  end;
end;

{ TSlimXmlDocExtractor }

procedure TTestSlimXmlDocExtractor.TestExtractXmlDocs;
var
  Description: String;
  Docs       : TDictionary<String, String>;
  Extractor  : TSlimXmlDocExtractor;
  Path       : String;
begin
  Docs := nil;
  Extractor := TSlimXmlDocExtractor.Create;
  try
    // Adjust path to find the source file relative to the test runner executable
    // Expected: Test/Win32/Debug/Test.Slim.exe
    Path := '..\..\..\Projects\SlimDoc\Slim.Doc.Fixtures.pas';
    if not TFile.Exists(Path) then
      Path := '..\Projects\SlimDoc\Slim.Doc.Fixtures.pas'; // Fallback if running from root

    Assert.IsTrue(TFile.Exists(Path), 'Source file not found at: ' + Path);
    Docs := Extractor.ExtractXmlDocs(Path);

    Assert.IsTrue(Docs.TryGetValue('TSlimDocGeneratorFixture', Description), 'Should contain Class TSlimDocGeneratorFixture');
    Assert.IsTrue(Description.Contains('Generates HTML documentation for Slim Fixtures'), 'Class Doc content mismatch');

    Assert.IsTrue(Docs.TryGetValue('TSlimDocGeneratorFixture.GenerateDocumentation', Description), 'Should contain GenerateDocumentation');
    Assert.IsTrue(Description.Contains('Generates the HTML documentation file'), 'Doc content mismatch');

    Assert.IsTrue(Docs.TryGetValue('TSlimDocGeneratorFixture.AnalyzeUsage', Description), 'Should contain AnalyzeUsage');
    Assert.IsTrue(Description.Contains('Scans the FitNesse root directory'), 'Doc content mismatch');

    Assert.IsTrue(Docs.TryGetValue('TSlimDocGeneratorFixture.IncludeXmlComments', Description), 'Should contain IncludeXmlComments');
    Assert.IsTrue(Description.Contains('Configures the root path to search for source files'), 'Doc content mismatch');

    Assert.IsTrue(Docs.TryGetValue('GeneratedLink', Description), 'Should contain GeneratedLink');
    Assert.IsTrue(Description.Contains('Returns the link to the generated documentation'), 'Doc content mismatch');
  finally
    Docs.Free;
    Extractor.Free;
  end;
end;

end.
