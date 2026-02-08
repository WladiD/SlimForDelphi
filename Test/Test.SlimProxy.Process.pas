// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Test.SlimProxy.Process;

interface

uses
  System.Classes,
  System.SysUtils,
  DUnitX.TestFramework,
  Slim.Proxy.Process.Fixture;

type

  [TestFixture]
  TestSlimProxyProcess = class
  private
    FFixture: TSlimProxyProcessFixture;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestOutputMatches;
    [Test]
    procedure TestOutputMatchCount;
  end;

implementation

{ TestSlimProxyProcess }

procedure TestSlimProxyProcess.Setup;
begin
  FFixture := TSlimProxyProcessFixture.Create;
end;

procedure TestSlimProxyProcess.TearDown;
begin
  FFixture.Free;
end;

procedure TestSlimProxyProcess.TestOutputMatchCount;
begin
  FFixture.Run('cmd.exe /c echo line1& echo line2& echo line3');
  Assert.AreEqual(3, FFixture.OutputMatchCount('line'), 'Should find 3 matches for "line"');
  Assert.AreEqual(1, FFixture.OutputMatchCount('line2'), 'Should find 1 match for "line2"');
  Assert.AreEqual(0, FFixture.OutputMatchCount('lineX'), 'Should find 0 matches for "lineX"');
  Assert.AreEqual(3, FFixture.OutputMatchCount('^line'), 'Should find 3 matches for start of line in multiline mode');
end;

procedure TestSlimProxyProcess.TestOutputMatches;
begin
  // We need to simulate some output since we don't want to run real processes in every unit test if possible,
  // but TSlimProxyProcessFixture doesn't have a way to set FLastOutput directly except by running.
  // However, for testing OutputMatches we can use a little trick or just run a simple command.
  
  // Use a simple command to get output
  FFixture.Run('cmd.exe /c echo Hello World');
  
  Assert.IsTrue(FFixture.OutputMatches('Hello'), 'Should match "Hello"');
  Assert.IsTrue(FFixture.OutputMatches('hello'), 'Should match "hello" (case insensitive)');
  Assert.IsTrue(FFixture.OutputMatches('W.rld'), 'Should match regex "W.rld"');
  Assert.IsFalse(FFixture.OutputMatches('Goodbye'), 'Should not match "Goodbye"');
  
  // Test multiline
  FFixture.Run('cmd.exe /c echo Line1& echo Line2');
  Assert.IsTrue(FFixture.OutputMatches('^Line2'), 'Should match start of line in multiline mode');
end;

initialization
  TDUnitX.RegisterTestFixture(TestSlimProxyProcess);

end.
