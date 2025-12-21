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
    function MethodTwo(A: String): Boolean;
    [SlimMemberSyncMode(smSynchronized)]
    procedure SyncMethod;
    property MyProp: Integer read FProp write FProp;
  end;

  [TestFixture]
  TTestSlimDocExtractor = class
  public
    [Test]
    procedure TestExtraction;
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

procedure TTestSlimDocExtractor.TestExtraction;
var
  Doc      : TSlimFixtureDoc;
  Extractor: TSlimDocExtractor;
  Method   : TSlimMethodDoc;
  Prop     : TSlimPropertyDoc;

  function GetDocMethod(const AName: String): TSlimMethodDoc;
  begin
    for var M in Doc.Methods do
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
      for var M in Doc.Methods do
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

end.
