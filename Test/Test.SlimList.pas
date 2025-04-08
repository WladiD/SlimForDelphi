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
  finally
    Unserializer.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimListUnserializer);

end.
