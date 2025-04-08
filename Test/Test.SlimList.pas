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
  TestSlimListUnserializer = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TwoMinuteExample;
  end;

implementation

procedure TestSlimListUnserializer.Setup;
begin
end;

procedure TestSlimListUnserializer.TearDown;
begin
end;

procedure TestSlimListUnserializer.TwoMinuteExample;
var
  SlimList: TSlimList;
  Unserializer: TSlimListUnserializer;
  Content: String;
begin
  Content := TFile.ReadAllText('Data\TwoMinuteExample.txt');
  Unserializer := TSlimListUnserializer.Create(Content);
  try
    SlimList := Unserializer.Unserialize;
    Assert.IsNotNull(SlimList);
    Assert.AreEqual(34,SlimList.Count);
    Assert.IsTrue(SlimList.Entries[0] is TSlimListEntry);

    var Entry1: TSlimListEntry := SlimList.Entries[0] as TSlimListEntry;
    Assert.AreEqual(4, Entry1.List.Count);
    Assert.AreEqual('decisionTable_0_0', (Entry1.List.Entries[0] as TSlimStringEntry).ToString);
    Assert.AreEqual('make', (Entry1.List.Entries[1] as TSlimStringEntry).ToString);
    Assert.AreEqual('decisionTable_0', (Entry1.List.Entries[2] as TSlimStringEntry).ToString);
    Assert.AreEqual('eg.Division', (Entry1.List.Entries[3] as TSlimStringEntry).ToString);

    var Entry2: TSlimListEntry := SlimList.Entries[1] as TSlimListEntry;
    Assert.AreEqual(5, Entry2.List.Count);
    var SubEntry2: TSlimListEntry:=Entry2.List.Entries[4] as TSlimListEntry;
    Assert.AreEqual(7, SubEntry2.List.Count);
  finally
    Unserializer.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimListUnserializer);

end.
