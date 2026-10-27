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

  System.IOUtils,
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
    [Test]
    procedure ACancelledCollectionReadsNoWindow;
    [Test]
    procedure FastMMReportsAreFatalInEveryTranslation;
  public // Memory dumps
    [Test]
    procedure TheDumpFolderFollowsTheSwitchAndTheLogFolder;
    [Test]
    procedure AMemoryDumpOfARunningProcessIsWritten;
    [Test]
    procedure AMemoryDumpOfAMissingProcessNamesTheReason;
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

procedure TestSlimProxyWinTools.ACancelledCollectionReadsNoWindow;
var
  LConfig: TSlimProxyWindowConfig;
  LWnd   : HWND;
begin
  // The runner has no visible window (see above), so the test makes one: a bare
  // popup of this process. The probes reach it directly, it belongs to the
  // calling thread.
  LWnd := CreateWindowEx(0, 'STATIC', 'SlimProxy probe target', WS_POPUP or WS_VISIBLE,
    0, 0, 10, 10, 0, 0, HInstance, nil);
  Assert.IsTrue(LWnd <> 0, 'the probe target has to exist');
  try
    LConfig := TSlimProxyWindowConfig.CreateDefaults;
    Assert.AreEqual(1, Length(SlimProxyCollectWindows(GetCurrentProcessId, LConfig)),
      'without a stop the window is read');
    // The watchdog stops the pass the moment the call is over; a stop that is
    // already set must not read a single window - the response waits for it.
    Assert.AreEqual(0, Length(SlimProxyCollectWindows(GetCurrentProcessId, LConfig,
      function: Boolean
      begin
        Result := True;
      end)), 'a stop before the first probe reads nothing');
  finally
    DestroyWindow(LWnd);
  end;
end;

procedure TestSlimProxyWinTools.FastMMReportsAreFatalInEveryTranslation;
var
  LConfig: TSlimProxyWindowConfig;
  LHit   : String;
begin
  LConfig := TSlimProxyWindowConfig.CreateDefaults;
  // The titles are translated, the texts all name FastMM. Without "fastmm" in the
  // defaults only the one untranslated message ("... memory manager sharing
  // settings") was fatal; every other report was dismissed as a plain error and
  // the run went on with a corrupted heap.
  Assert.AreEqual(Ord(wkFatal), Ord(LConfig.ClassifyWindow('#32770', 'App.exe: Memory Error Detected',
    'FastMM has detected an attempt to call a virtual method on a freed object.', LHit)));
  Assert.AreEqual(Ord(wkFatal), Ord(LConfig.ClassifyWindow('#32770', 'App.exe: Speicherfehler entdeckt',
    'FastMM hat einen Versuch entdeckt, eine virtuelle Methode eines freigegebenen Objektes aufzurufen.',
    LHit)));
  Assert.AreEqual('fastmm', LHit, 'the FastMM wording is what made it fatal');
end;

procedure TestSlimProxyWinTools.TheDumpFolderFollowsTheSwitchAndTheLogFolder;
begin
  try
    SlimProxyLogDir := 'Logs';
    SlimProxyFatalDump := True;
    // Relative to the working directory like the log files, but absolute, so the
    // finding names a path one can open.
    Assert.AreEqual(ExpandFileName('Logs'), SlimProxyFatalDumpDir);
    SlimProxyFatalDump := False;
    Assert.AreEqual('', SlimProxyFatalDumpDir, 'switched off means no folder, and no folder means no dump');
  finally
    SlimProxyFatalDump := DefaultFatalDump;
    SlimProxyLogDir := DefaultLogDir;
  end;
end;

procedure TestSlimProxyWinTools.AMemoryDumpOfARunningProcessIsWritten;
var
  LError: String;
  LFile : String;
begin
  LFile := TPath.Combine(TPath.GetTempPath, Format('SlimProxyDumpTest_%d.dmp', [GetCurrentProcessId]));
  try
    // The own process is the one process that is guaranteed to run. The small
    // dump keeps the test fast; the full one only differs in its flags.
    Assert.IsTrue(SlimProxyWriteMemoryDump(GetCurrentProcessId, LFile, False, LError), LError);
    Assert.AreEqual('', LError);
    Assert.IsTrue(TFile.Exists(LFile), 'the dump file has to exist');
    Assert.IsTrue(TFile.GetSize(LFile) > 0, 'and must not be empty');
  finally
    System.SysUtils.DeleteFile(LFile);
  end;
end;

procedure TestSlimProxyWinTools.AMemoryDumpOfAMissingProcessNamesTheReason;
var
  LError: String;
  LFile : String;
begin
  LFile := TPath.Combine(TPath.GetTempPath, Format('SlimProxyDumpTest_missing_%d.dmp', [GetCurrentProcessId]));
  // Far above any process id Windows hands out, and a multiple of four: the low
  // bits of a process id are ignored, an odd value could open a real process.
  Assert.IsFalse(SlimProxyWriteMemoryDump($7FFFFFF0, LFile, True, LError), 'there is no such process');
  Assert.Contains(LError, 'cannot be opened', 'the reason has to be named');
  Assert.IsFalse(TFile.Exists(LFile), 'and no file may be left behind');
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxyWinTools);

end.
