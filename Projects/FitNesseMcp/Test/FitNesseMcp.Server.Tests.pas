unit FitNesseMcp.Server.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  FitNesseMcp.Config,
  FitNesseMcp.Server;

type
  [TestFixture]
  TFitNesseMcpTests = class
  public
    [Test]
    procedure TestConfigLoad;
    [Test]
    procedure TestInstanceLookup;
  end;

implementation

{ TFitNesseMcpTests }

procedure TFitNesseMcpTests.TestConfigLoad;
var
  LConfig: TFitNesseConfig;
begin
  // Note: This requires the fitnesse-config.json to be in the same folder as the exe during test
  // For unit tests, we could use a mock or temp file, but for now we check if LoadFromFile returns False on non-existing file.
  Assert.IsFalse(LConfig.LoadFromFile('non-existing.json'));
end;

procedure TFitNesseMcpTests.TestInstanceLookup;
var
  LConfig: TFitNesseConfig;
  LInstance: TFitNesseInstance;
begin
  // Set up dummy config
  SetLength(LConfig.instances, 1);
  LConfig.instances[0].name := 'TestInst';
  LConfig.instances[0].port := 1234;

  Assert.IsTrue(LConfig.GetInstanceByName('TestInst', LInstance));
  Assert.AreEqual(1234, LInstance.port);
  
  Assert.IsFalse(LConfig.GetInstanceByName('Unknown', LInstance));
end;

initialization
  TDUnitX.RegisterTestFixture(TFitNesseMcpTests);

end.
