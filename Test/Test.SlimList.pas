// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimList;

interface

uses

  System.Classes,
  System.IOUtils,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.List;

type

  [TestFixture]
  TestSlimListSerializer = class
  public
    [Test]
    procedure TwoMinuteExampleTest;
  end;

  [TestFixture]
  TestSlimListUnserializer = class
  public
    class procedure TwoMinuteExample(const AContent: String);
    [Test]
    procedure TwoMinuteExampleTest;
  end;

  [TestFixture]
  TestSlimFunctions = class
  public
    [Test]
    procedure SlimStringFuncTest;
    [Test]
    procedure SlimListFuncTest;
    [Test]
    procedure SlimList2FuncTest;
  end;

implementation

{ TestSlimListSerializer }

procedure TestSlimListSerializer.TwoMinuteExampleTest;
var
  SlimList    : TSlimList;
  Unserializer: TSlimListUnserializer;
  Content     : String;
begin
  SlimList := nil;
  Content := TFile.ReadAllText('Data\TwoMinuteExample.txt');
  Unserializer := TSlimListUnserializer.Create(Content);
  try
    SlimList := Unserializer.Unserialize;
    Content := SlimListSerialize(SlimList);
    TestSlimListUnserializer.TwoMinuteExample(Content); // Eat our own dog food
  finally
    SlimList.Free;
    Unserializer.Free;
  end;
end;

{ TestSlimListUnserializer }

procedure TestSlimListUnserializer.TwoMinuteExampleTest;
begin
  TwoMinuteExample(TFile.ReadAllText('Data\TwoMinuteExample.txt'));
end;

class procedure TestSlimListUnserializer.TwoMinuteExample(const AContent: String);
var
  SlimList    : TSlimList;
  Unserializer: TSlimListUnserializer;
begin
  SlimList := nil;
  Unserializer := TSlimListUnserializer.Create(AContent);
  try
    SlimList := Unserializer.Unserialize;
    Assert.IsNotNull(SlimList);
    Assert.AreEqual(34, SlimList.Count);
    Assert.IsTrue(SlimList.Entries[0] is TSlimList);

    var Entry1: TSlimList := SlimList[0] as TSlimList;
    Assert.AreEqual(4, Entry1.Count);
    Assert.AreEqual('decisionTable_0_0', (Entry1[0] as TSlimString).ToString);
    Assert.AreEqual('make', (Entry1[1] as TSlimString).ToString);
    Assert.AreEqual('decisionTable_0', (Entry1[2] as TSlimString).ToString);
    Assert.AreEqual('eg.Division', (Entry1[3] as TSlimString).ToString);

    var Entry2: TSlimList := SlimList[1] as TSlimList;
    Assert.AreEqual(5, Entry2.Count);
    Assert.AreEqual('table', (Entry2[3] as TSlimString).ToString);
    var SubEntry2: TSlimList:=Entry2[4] as TSlimList;
    Assert.AreEqual(7, SubEntry2.Count);
    Assert.AreEqual('numerator', (SubEntry2[0] as TSlimList)[0].ToString); // First Sub-List
    Assert.AreEqual('denominator', (SubEntry2[0] as TSlimList)[1].ToString);
    Assert.AreEqual('quotient?', (SubEntry2[0] as TSlimList)[2].ToString);
    Assert.AreEqual('100', (SubEntry2[6] as TSlimList)[0].ToString); // Last Sub-List
    Assert.AreEqual('4', (SubEntry2[6] as TSlimList)[1].ToString);
    Assert.AreEqual('25.0', (SubEntry2[6] as TSlimList)[2].ToString);

    var EntryLast: TSlimList := SlimList[SlimList.Count-1] as TSlimList;
    Assert.AreEqual(4, EntryLast.Count);
    Assert.AreEqual('decisionTable_0_33', (EntryLast[0] as TSlimString).ToString);
    Assert.AreEqual('call', (EntryLast[1] as TSlimString).ToString);
    Assert.AreEqual('decisionTable_0', (EntryLast[2] as TSlimString).ToString);
    Assert.AreEqual('endTable', (EntryLast[3] as TSlimString).ToString);
  finally
    SlimList.Free;
    Unserializer.Free;
  end;
end;

{ TestSlimFunctions }

procedure TestSlimFunctions.SlimListFuncTest;
var
  LSlimList: TSlimList;
begin
  LSlimList := SlimList([
    SlimString('First item'),
    SlimString('Second item'),
    SlimList([
      SlimString('First sub item'),
      SlimString('Second sub item')])
    ]);
  try
    Assert.AreEqual(3, LSlimList.Count);
    Assert.AreEqual('First item', LSlimList[0].ToString);
    Assert.AreEqual('Second item', LSlimList[1].ToString);
    Assert.AreEqual(TSlimList, LSlimList[2].ClassType);
    Assert.AreEqual(2, (LSlimList[2] as TSlimList).Count);
    Assert.AreEqual('First sub item', (LSlimList[2] as TSlimList)[0].ToString);
    Assert.AreEqual('Second sub item', (LSlimList[2] as TSlimList)[1].ToString);
  finally
    LSlimList.Free;
  end;
end;

procedure TestSlimFunctions.SlimList2FuncTest;
var
  LSlimList: TSlimList;
begin
  LSlimList := SlimList(['First item', 'Second item', 'Third item']);
  try
    Assert.AreEqual(3, LSlimList.Count);
    Assert.AreEqual('First item', LSlimList[0].ToString);
    Assert.AreEqual('Second item', LSlimList[1].ToString);
    Assert.AreEqual('Third item', LSlimList[2].ToString);
  finally
    LSlimList.Free;
  end;
end;

procedure TestSlimFunctions.SlimStringFuncTest;
var
  LSlimString: TSlimString;
begin
  LSlimString := SlimString('Hello world!');
  try
    Assert.AreEqual('Hello world!', LSlimString.ToString);
  finally
    LSlimString.Free;
  end;
end;

end.
