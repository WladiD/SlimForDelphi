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

implementation

{ TestSlimListSerializer }

procedure TestSlimListSerializer.TwoMinuteExampleTest;
var
  SlimList    : TSlimList;
  Unserializer: TSlimListUnserializer;
  Serializer  : TSlimListSerializer;
  Content     : String;
begin
  SlimList := nil;
  Serializer := nil;
  Content := TFile.ReadAllText('Data\TwoMinuteExample.txt');
  Unserializer := TSlimListUnserializer.Create(Content);
  try
    SlimList := Unserializer.Unserialize;
    Serializer := TSlimListSerializer.Create(SlimList);
    Content := Serializer.Serialize;
    TestSlimListUnserializer.TwoMinuteExample(Content); // Eat our own dog food
  finally
    SlimList.Free;
    Serializer.Free;
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
  Unserializer := TSlimListUnserializer.Create(AContent);
  try
    SlimList := Unserializer.Unserialize;
    Assert.IsNotNull(SlimList);
    Assert.AreEqual(34, SlimList.Count);
    Assert.IsTrue(SlimList.Entries[0] is TSlimListEntry);

    var Entry1: TSlimListEntry := SlimList[0] as TSlimListEntry;
    Assert.AreEqual(4, Entry1.List.Count);
    Assert.AreEqual('decisionTable_0_0', (Entry1.List[0] as TSlimStringEntry).ToString);
    Assert.AreEqual('make', (Entry1.List[1] as TSlimStringEntry).ToString);
    Assert.AreEqual('decisionTable_0', (Entry1.List[2] as TSlimStringEntry).ToString);
    Assert.AreEqual('eg.Division', (Entry1.List[3] as TSlimStringEntry).ToString);

    var Entry2: TSlimListEntry := SlimList[1] as TSlimListEntry;
    Assert.AreEqual(5, Entry2.List.Count);
    Assert.AreEqual('table', (Entry2.List[3] as TSlimStringEntry).ToString);
    var SubEntry2: TSlimListEntry:=Entry2.List[4] as TSlimListEntry;
    Assert.AreEqual(7, SubEntry2.List.Count);
    Assert.AreEqual('numerator', (SubEntry2.List[0] as TSlimListEntry).List[0].ToString); // First Sub-List
    Assert.AreEqual('denominator', (SubEntry2.List[0] as TSlimListEntry).List[1].ToString);
    Assert.AreEqual('quotient?', (SubEntry2.List[0] as TSlimListEntry).List[2].ToString);
    Assert.AreEqual('100', (SubEntry2.List[6] as TSlimListEntry).List[0].ToString); // Last Sub-List
    Assert.AreEqual('4', (SubEntry2.List[6] as TSlimListEntry).List[1].ToString);
    Assert.AreEqual('25.0', (SubEntry2.List[6] as TSlimListEntry).List[2].ToString);

    var EntryLast: TSlimListEntry := SlimList[SlimList.Count-1] as TSlimListEntry;
    Assert.AreEqual(4, EntryLast.List.Count);
    Assert.AreEqual('decisionTable_0_33', (EntryLast.List[0] as TSlimStringEntry).ToString);
    Assert.AreEqual('call', (EntryLast.List[1] as TSlimStringEntry).ToString);
    Assert.AreEqual('decisionTable_0', (EntryLast.List[2] as TSlimStringEntry).ToString);
    Assert.AreEqual('endTable', (EntryLast.List[3] as TSlimStringEntry).ToString);
  finally
    SlimList.Free;
    Unserializer.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimListSerializer);
TDUnitX.RegisterTestFixture(TestSlimListUnserializer);

end.
