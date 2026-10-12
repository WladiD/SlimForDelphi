// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
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
    [Test]
    procedure TestComponentSymbolIsClearedWhenTheComponentDies;
    [Test]
    procedure TestSymbolObjectAsChecksTheClass;
    [Test]
    procedure TestPlainObjectSymbolIsNotTracked;
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

// A page keeps a form reference in a symbol; the form dies with its modal click handler. From
// then on the symbol must resolve to nil instead of the dead pointer.
procedure TestSlimSymbolDictionary.TestComponentSymbolIsClearedWhenTheComponentDies;
var
  Component: TComponent;
  VarStore : TSlimSymbolDictionary;
begin
  VarStore := TSlimSymbolDictionary.Create;
  try
    Component := TComponent.Create(nil);
    VarStore.SetSymbol('Form', Component);
    VarStore.SetSymbol('SameForm', Component);
    Assert.AreSame(Component, VarStore.SymbolObject('$Form'));
    Assert.AreSame(Component, VarStore.SymbolObjectAs('$SameForm', TComponent));

    Component.Free;

    Assert.IsNull(VarStore.SymbolObject('$Form'));
    Assert.IsNull(VarStore.SymbolObjectAs('$SameForm', TComponent));
    Assert.IsTrue(VarStore.ContainsKey('Form'), 'The symbol itself stays known');
  finally
    VarStore.Free;
  end;
end;

procedure TestSlimSymbolDictionary.TestSymbolObjectAsChecksTheClass;
var
  Component: TComponent;
  VarStore : TSlimSymbolDictionary;
begin
  VarStore := TSlimSymbolDictionary.Create;
  try
    Component := TComponent.Create(nil);
    try
      VarStore.SetSymbol('Form', Component);
      VarStore.SetSymbol('Text', 'no object');
      Assert.AreSame(Component, VarStore.SymbolObjectAs('$Form', TComponent));
      Assert.AreSame(Component, VarStore.SymbolObjectAs('$Form', nil));
      Assert.IsNull(VarStore.SymbolObjectAs('$Form', TStringList));
      Assert.IsNull(VarStore.SymbolObjectAs('$Text', TObject));
      Assert.IsNull(VarStore.SymbolObjectAs('$Unknown', TObject));
    finally
      Component.Free;
    end;
  finally
    VarStore.Free;
  end;
end;

procedure TestSlimSymbolDictionary.TestPlainObjectSymbolIsNotTracked;
var
  Obj     : TObject;
  ObjPtr  : Pointer;
  VarStore: TSlimSymbolDictionary;
begin
  VarStore := TSlimSymbolDictionary.Create;
  try
    Obj := TObject.Create;
    ObjPtr := Pointer(Obj);
    VarStore.SetSymbol('Obj', Obj);
    Assert.AreSame(Obj, VarStore.SymbolObjectAs('$Obj', TObject));

    Obj.Free;

    // Nobody tells the dictionary about a plain object, so the symbol keeps the stale pointer.
    // SymbolObject only reads the stored value and never touches the object behind it.
    Assert.IsTrue(ObjPtr = Pointer(VarStore.SymbolObject('$Obj')), 'The stale pointer is still held');
    VarStore.Clear;
    Assert.AreEqual(0, Integer(VarStore.Count));
  finally
    VarStore.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimSymbolDictionary);

end.
