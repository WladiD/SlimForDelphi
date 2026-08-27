// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Port watch and window classification, plus the two host control cases that
///   need no GUI: an occupied port and the death of a host.
/// </summary>
unit Test.SlimProxy.WinTools;

interface

uses

  Winapi.Windows,

  System.SysUtils,

  DUnitX.TestFramework,

  IdTCPServer,

  Slim.Common,
  Slim.Proxy.Config,
  Slim.Proxy.Host.Fixture,
  Slim.Proxy.WinTools,

  Test.SlimProxy.Helpers;

type

  [TestFixture]
  TestSlimProxyWinTools = class
  private
    FHost: TSlimProxyHostFixture;
    function ExpectedFailure(const AProc: TProc): String;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
  public // Port watch
    [Test]
    procedure ListenerPidIsTheOwningProcess;
    [Test]
    procedure APortNobodyListensOnYieldsZero;
    [Test]
    procedure PreflightNamesTheForeignProcess;
    [Test]
    procedure HostDeathIsReportedWithItsExitCode;
  public // Window classification
    [Test]
    procedure FatalWordingWinsOverEverything;
    [Test]
    procedure ErrorWordingWinsOverTheExemptionList;
    [Test]
    procedure TheExemptionListOnlySuppressesPlainMessages;
    [Test]
    procedure ACustomButtonClassIsFoundBySubstringOrByList;
    [Test]
    procedure AbortWindowsMatchClassAndTitle;
    [Test]
    procedure WindowDumpNamesTheAbsenceOfWindows;
  end;

implementation

{ TestSlimProxyWinTools }

procedure TestSlimProxyWinTools.Setup;
begin
  SlimProxyAbortWindows := DefaultAbortWindowPatterns;
  SlimProxyButtonClassContains := DefaultButtonClassContains;
  SlimProxyButtonClasses := DefaultButtonWindowClasses;
  SlimProxyDismissButtons := DefaultDismissButtonCaptions;
  SlimProxyErrorPatterns := DefaultErrorPatterns;
  SlimProxyExemptWindows := DefaultExemptWindowPatterns;
  SlimProxyFatalPatterns := DefaultFatalPatterns;
  SlimProxyPostStartDismissMs := 0; // no trailing dismissing wanted in a unit test
  FHost := TSlimProxyHostFixture.Create;
end;

procedure TestSlimProxyWinTools.TearDown;
begin
  FHost.Free;
  SlimProxyPostStartDismissMs := DefaultPostStartDismissMs;
end;

/// <summary>Runs AProc and returns the message of the ESlim it must raise.</summary>
function TestSlimProxyWinTools.ExpectedFailure(const AProc: TProc): String;
begin
  Result := '';
  try
    AProc;
    Assert.Fail('an ESlim was expected here');
  except
    on E: ESlim do
      Result := E.Message;
  end;
end;

procedure TestSlimProxyWinTools.ListenerPidIsTheOwningProcess;
var
  LListener: TTestListener;
begin
  LListener := TTestListener.Create(TestFindFreePort);
  try
    // A plain "somebody listens" is no information: a foreign host on the same
    // port lets a run look green and proves nothing. The owner is what counts.
    Assert.AreEqual(GetCurrentProcessId, SlimProxyGetListenerPid(LListener.Port),
      'the listening socket must be attributed to this process');
  finally
    LListener.Free;
  end;
end;

procedure TestSlimProxyWinTools.APortNobodyListensOnYieldsZero;
begin
  Assert.AreEqual(Cardinal(0), SlimProxyGetListenerPid(TestFindFreePort));
end;

procedure TestSlimProxyWinTools.PreflightNamesTheForeignProcess;
var
  LListener: TTestListener;
  LMessage : String;
begin
  LListener := TTestListener.Create(TestFindFreePort);
  try
    LMessage := ExpectedFailure(
      procedure
      begin
        FHost.StartHostAndWaitForSlim(GetEnvironmentVariable('ComSpec'), '/c exit 0',
          LListener.Port, 5);
      end);

    Assert.Contains(LMessage, 'already in use', 'the preflight has to refuse');
    Assert.Contains(LMessage, IntToStr(GetCurrentProcessId), 'and it has to name the foreign PID');
  finally
    LListener.Free;
  end;
end;

procedure TestSlimProxyWinTools.HostDeathIsReportedWithItsExitCode;
var
  LMessage: String;
begin
  LMessage := ExpectedFailure(
    procedure
    begin
      FHost.StartHostAndWaitForSlim(GetEnvironmentVariable('ComSpec'), '/c exit 7',
        TestFindFreePort, 10);
    end);

  Assert.Contains(LMessage, 'Host died', 'the death of the host must be named');
  Assert.Contains(LMessage, 'exit code 7', 'together with its exit code');
  Assert.Contains(FHost.LastStartupLog, 'started ', 'the startup log has to survive the failure');
end;

procedure TestSlimProxyWinTools.FatalWordingWinsOverEverything;
var
  LConfig: TSlimProxyWindowConfig;
  LHit   : String;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  LConfig.ExemptWindows := 'TReportWindow';
  // Fatal beats both the error wording and the exemption list: after such a
  // report the process state is not trustworthy any more.
  Assert.AreEqual(Ord(wkFatal), Ord(LConfig.ClassifyWindow('TReportWindow', 'Error',
    'Memory Manager detected a corrupted block header', LHit)));
  Assert.AreEqual('memory corruption', SlimProxyMatchSubstring('memory corruption report',
    LConfig.FatalPatterns), 'the matched pattern is reported back');
end;

procedure TestSlimProxyWinTools.ErrorWordingWinsOverTheExemptionList;
var
  LConfig: TSlimProxyWindowConfig;
  LHit   : String;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  LConfig.ExemptWindows := 'TOrderForm';
  // The exemption list has exactly one job: leave legitimate forms alone. It must
  // not throw away a window that carries a real error wording.
  Assert.AreEqual(Ord(wkError), Ord(LConfig.ClassifyWindow('TOrderForm', 'Error while saving', '', LHit)));
  Assert.AreEqual('error', LHit);
end;

procedure TestSlimProxyWinTools.TheExemptionListOnlySuppressesPlainMessages;
var
  LConfig: TSlimProxyWindowConfig;
  LHit   : String;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  Assert.AreEqual(Ord(wkMessage), Ord(LConfig.ClassifyWindow('TOrderForm', 'Save the order?', '', LHit)),
    'a message without an error wording is reported, never dismissed');

  LConfig.ExemptWindows := 'TOrderForm';
  Assert.AreEqual(Ord(wkIgnore), Ord(LConfig.ClassifyWindow('TOrderForm', 'Save the order?', '', LHit)),
    'and it is left completely alone once it is on the exemption list');
end;

procedure TestSlimProxyWinTools.ACustomButtonClassIsFoundBySubstringOrByList;
var
  LConfig: TSlimProxyWindowConfig;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  Assert.IsTrue(LConfig.IsButtonClass('Button'), 'the native class');
  Assert.IsTrue(LConfig.IsButtonClass('TcxButton1'), 'a prefix from the class list');
  Assert.IsTrue(LConfig.IsButtonClass('CToolButton42'),
    'an unknown custom class is still caught by the substring heuristic');
  Assert.IsFalse(LConfig.IsButtonClass('SlimVerifyPushControl'),
    'a custom class that matches nothing needs configuration - that is why the list exists');

  LConfig.ButtonClasses := LConfig.ButtonClasses + ';SlimVerifyPushControl';
  Assert.IsTrue(LConfig.IsButtonClass('SlimVerifyPushControl'), 'and configuration makes it work');
end;

procedure TestSlimProxyWinTools.AbortWindowsMatchClassAndTitle;
var
  LConfig: TSlimProxyWindowConfig;
  LHit   : String;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  Assert.IsFalse(LConfig.IsAbortWindow('TSomeLoginForm', 'Please sign in', LHit),
    'nothing is an abort window until it is configured');

  LConfig.AbortWindows := 'TSomeLoginForm';
  Assert.IsTrue(LConfig.IsAbortWindow('TSomeLoginForm', 'Please sign in', LHit), 'by class');

  LConfig.AbortWindows := 'already running';
  Assert.IsTrue(LConfig.IsAbortWindow('TMessageForm', 'The application is already running', LHit),
    'or by title');
  Assert.AreEqual('already running', LHit);
end;

procedure TestSlimProxyWinTools.WindowDumpNamesTheAbsenceOfWindows;
begin
  // The test runner is a console application, so it has no visible window. The
  // dump has to say so instead of returning an empty string.
  Assert.AreEqual('(no visible window)',
    SlimProxyDumpWindows(GetCurrentProcessId, TSlimProxyWindowConfig.CreateDefaults));
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxyWinTools);

end.
