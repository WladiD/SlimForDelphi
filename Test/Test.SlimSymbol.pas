// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimSymbol;

interface

uses

  System.Classes,
  System.Rtti,

  DUnitX.TestFramework,

  Slim.Symbol;

type

  [TestFixture]
  TestSlimSymbolDictionary = class
  public
    [Test]
    procedure TestSamples;
  end;

implementation

{ TestSlimSymbolDictionary }

procedure TestSlimSymbolDictionary.TestSamples;
var
  VarStore: TSlimSymbolDictionary;
begin
  VarStore := TSlimSymbolDictionary.Create;
  try
    VarStore.Add('FirstId', '123');
    VarStore.Add('SecondId', '234');
    VarStore.Add('ThirdId', '345');

    Assert.AreEqual('my ids: 123, 234, 345', VarStore.EvalSymbols('my ids: $FirstId, $SecondId, $ThirdId'));
  finally
    VarStore.Free;
  end;
end;

end.
