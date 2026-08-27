// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Everything that goes wrong with a GUI Slim host, driven against a real host
///   process: the port watch, start up dialogs, abort windows, the death of the
///   host, a call that never gets answered, and the watchdog.
///
///   The host is the SlimVerify simulation target, which makes all of that
///   testable without any foreign application and without scripts - seconds
///   instead of minutes. If SlimVerify has not been built, every test in here
///   reports itself as passed with a note instead of failing on somebody else's
///   build state.
///
///   These tests start real processes, wait for real ports and real windows, so
///   they cost SECONDS, not milliseconds. They are therefore in the
///   'Integration' category and are NOT part of the fast unit test run:
///
///     Test\_Test.Slim.BuildAndRun.bat      fast, excludes this unit
///     Test\_Test.Slim.BuildAndRunAll.bat   builds SlimVerify and runs everything
///
///   They stay code tests rather than FitNesse pages on purpose: most of them
///   assert a RAISED exception, one asserts ABORT_SLIM_SUITE - which by design
///   stops a whole FitNesse run - and one drives TSlimProxyWatchdog directly with
///   tuned thresholds. Expressing those as wiki pages would mean adding
///   "try and hand the error back" twins of half the verbs purely for testability.
/// </summary>
unit Test.SlimProxy.GuiHost;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Common,
  Slim.Exec,
  Slim.List,
  Slim.Proxy,
  Slim.Proxy.Config,
  Slim.Proxy.Host.Fixture,
  Slim.Proxy.Watchdog,
  Slim.Proxy.WinTools,

  Test.SlimExec,
  Test.SlimProxy.Helpers;

type

  [TestFixture]
  [Category('Integration')]
  TestSlimProxyGuiHost = class
  private
    FContext    : TSlimStatementContext;
    FExecutor   : TSlimProxyExecutor;
    FHost       : TSlimProxyHostFixture;
    FStartedPids: TArray<Cardinal>;
    function  Exe: String;
    procedure RequireSimulationTarget;
    function  StartHost(const AArgs: String; APort, ATimeoutSeconds: Integer): Cardinal;
    function  StartRaw(const AArgs: String): Cardinal;
    procedure KillStartedHosts;
    function  ExpectedFailure(const AProc: TProc): String;
    procedure ConnectExecutorTo(APort: Integer; AReadTimeoutMs: Integer);
    function  ForwardStmt(const AId, AInstruction, AInstance, AMember: String;
      const AArgs: TArray<String> = nil): String;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
  public // Host control
    [Test]
    procedure GoodCase_ThePortBelongsToOurOwnHost;
    [Test]
    procedure StartupDialogBlocksSlimWithoutTheConfiguredButtonClass;
    [Test]
    procedure StartupDialogIsDismissedWithTheConfiguredButtonClass;
    [Test]
    procedure AbortWindowIsRecognizedInsteadOfWaitingItOut;
    [Test]
    procedure HostDeathIsReportedWithItsExitCode;
    [Test]
    procedure AForeignProcessHoldingThePortIsRefused;
  public // Read timeout and watchdog against a running host
    [Test]
    procedure BlockingCallEndsWithinTheReadTimeout;
    [Test]
    procedure WatchdogDismissesAnErrorDialogAndFlagsTheResultUnreliable;
    [Test]
    procedure WatchdogReportsAQuestionButNeverDismissesIt;
    [Test]
    procedure WatchdogTreatsAConfiguredFatalWordingAsAbortSuite;
    [Test]
    procedure WatchdogTellsAnIdleProcessFromAComputingOne;
  end;

implementation

const
  /// <summary>Class of the simulated abort window, passed in with --AbortWindow.</summary>
  AbortWindowClass = 'SlimVerifyAbortWindow';

  /// <summary>
  ///   Class of the button in the simulated start up dialog. Matches neither the
  ///   default class list nor the substring heuristic, so it really proves the
  ///   configurability.
  /// </summary>
  CustomButtonClass = 'SlimVerifyPushControl';

  /// <summary>
  ///   Self close timeout handed to the simulated dialogs, as the string a Slim
  ///   argument is. It is only a safety net: every dialog these tests care about
  ///   has to disappear because somebody acted on it, long before this elapses.
  /// </summary>
  DialogSelfCloseMs = '12000';

{ TestSlimProxyGuiHost }

procedure TestSlimProxyGuiHost.Setup;
begin
  SlimProxyAbortWindows := DefaultAbortWindowPatterns;
  SlimProxyButtonClassContains := DefaultButtonClassContains;
  SlimProxyButtonClasses := DefaultButtonWindowClasses;
  SlimProxyConnectTimeout := 5000;
  SlimProxyDismissButtons := DefaultDismissButtonCaptions;
  SlimProxyErrorPatterns := DefaultErrorPatterns;
  SlimProxyExemptWindows := DefaultExemptWindowPatterns;
  SlimProxyFatalPatterns := DefaultFatalPatterns;
  SlimProxyPostStartDismissMs := 1000;
  SlimProxyReadTimeout := DefaultReadTimeoutMs;
  SlimProxyWatchdogEnabled := False;

  FStartedPids := [];
  FHost := TSlimProxyHostFixture.Create;
  FContext := TSlimStatementContext.Create;
  FContext.InitAllMembers;
  FExecutor := TSlimProxyExecutor.Create(FContext);
end;

procedure TestSlimProxyGuiHost.TearDown;
begin
  FExecutor.Free;
  FContext.Free;
  KillStartedHosts;
  FHost.Free;
  SlimProxyPostStartDismissMs := DefaultPostStartDismissMs;
  SlimProxyWatchdogEnabled := False;
end;

function TestSlimProxyGuiHost.Exe: String;
begin
  Result := TestSlimVerifyExePath;
end;

/// <summary>Skips the test with a note if the simulation target is missing.</summary>
procedure TestSlimProxyGuiHost.RequireSimulationTarget;
begin
  if Exe = '' then
    Assert.Pass('SlimVerify has not been built - skipped. Run Test\_Test.Slim.BuildAndRunAll.bat.');
end;

function TestSlimProxyGuiHost.StartHost(const AArgs: String; APort, ATimeoutSeconds: Integer): Cardinal;
begin
  Result := Cardinal(FHost.StartHostAndWaitForSlim(Exe, AArgs, APort, ATimeoutSeconds));
  FStartedPids := FStartedPids + [Result];
end;

/// <summary>Starts the simulation target without waiting for anything.</summary>
function TestSlimProxyGuiHost.StartRaw(const AArgs: String): Cardinal;
var
  LCmd: String;
  LPi : TProcessInformation;
  LSi : TStartupInfo;
begin
  ZeroMemory(@LSi, SizeOf(LSi));
  LSi.cb := SizeOf(LSi);
  ZeroMemory(@LPi, SizeOf(LPi));
  LCmd := '"' + Exe + '" ' + AArgs;
  if not CreateProcess(nil, PChar(LCmd), nil, nil, False, 0, nil,
       PChar(ExcludeTrailingPathDelimiter(ExtractFilePath(Exe))), LSi, LPi) then
    RaiseLastOSError;
  CloseHandle(LPi.hThread);
  CloseHandle(LPi.hProcess);
  Result := LPi.dwProcessId;
  FStartedPids := FStartedPids + [Result];
end;

procedure TestSlimProxyGuiHost.KillStartedHosts;
begin
  // The last host of a failed start up must not stay behind and occupy a port for
  // the next test.
  for var LPid in FStartedPids do
    FHost.KillHost(Integer(LPid));
  if FHost.LastHostProcessId > 0 then
    FHost.KillHost(FHost.LastHostProcessId);
  FStartedPids := [];
end;

function TestSlimProxyGuiHost.ExpectedFailure(const AProc: TProc): String;
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

procedure TestSlimProxyGuiHost.ConnectExecutorTo(APort: Integer; AReadTimeoutMs: Integer);
begin
  FExecutor.ReadTimeout := AReadTimeoutMs;
  FExecutor.AddTargetDeferred('Sim', '127.0.0.1', APort);
  FExecutor.SwitchToTarget('Sim');
end;

function TestSlimProxyGuiHost.ForwardStmt(const AId, AInstruction, AInstance, AMember: String;
  const AArgs: TArray<String>): String;
var
  LParts   : TArray<String>;
  LResponse: TSlimList;
  LResult  : TSlimList;
  LStmts   : TSlimList;
begin
  LParts := [AId, AInstruction, AInstance];
  if AMember <> '' then
    LParts := LParts + [AMember];
  LParts := LParts + AArgs;

  LStmts := SlimList([SlimList(LParts)]);
  try
    LResponse := FExecutor.Execute(LStmts);
    try
      Assert.AreEqual(1, LResponse.Count);
      Assert.IsTrue(TryGetSlimListById(LResponse, AId, LResult));
      Result := LResult[1].ToString;
    finally
      LResponse.Free;
    end;
  finally
    LStmts.Free;
  end;
end;

procedure TestSlimProxyGuiHost.GoodCase_ThePortBelongsToOurOwnHost;
var
  LPid : Cardinal;
  LPort: Integer;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  // --StartupDelay makes the port come up late: that is what the port watch is
  // for. Returning early would mean measuring a host that is not there yet.
  LPid := StartHost(Format('--SlimPort=%d --StartupDelay=2500', [LPort]), LPort, 30);

  Assert.IsTrue(LPid > 0, 'the process id of the host is the result');
  Assert.AreEqual(LPid, SlimProxyGetListenerPid(LPort),
    'the listening socket has to be owned by OUR host');
  Assert.Contains(FHost.LastStartupLog, 'slim port', 'the startup log documents the wait');
  Assert.IsTrue(FHost.IsHostRunning(Integer(LPid)));

  // Orderly shutdown, no TerminateProcess.
  Assert.IsTrue(FHost.CloseHost(Integer(LPid), 15), 'the host has to close in an orderly way');
  Assert.IsFalse(FHost.IsHostRunning(Integer(LPid)), 'and it really has to be gone');
end;

procedure TestSlimProxyGuiHost.StartupDialogBlocksSlimWithoutTheConfiguredButtonClass;
var
  LMessage: String;
  LPort   : Integer;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  // The button of the start up dialog sits on its own window class. A search that
  // only knows the usual classes does not reach it, the host stays behind its
  // modal dialog and Slim never comes up. This test nails down exactly that -
  // and therefore why the class list has to be configurable.
  LMessage := ExpectedFailure(
    procedure
    begin
      FHost.StartHostAndWaitForSlim(Exe,
        Format('--SlimPort=%d --StartupDialog=60000', [LPort]), LPort, 6);
    end);

  Assert.Contains(LMessage, 'Startup window of 6s elapsed', 'the wait window has to end by itself');
  // The dump names the dialog that is standing in the way - and it lists no
  // button at all, because the proxy does not recognize that class as one. That
  // is exactly the missing information a start up without a port leaves behind.
  Assert.Contains(LMessage, 'cls=SlimVerifyDialog', 'the message has to carry the window dump');
end;

procedure TestSlimProxyGuiHost.StartupDialogIsDismissedWithTheConfiguredButtonClass;
var
  LPid : Cardinal;
  LPort: Integer;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  FHost.SetButtonClasses(DefaultButtonWindowClasses + ';' + CustomButtonClass);
  LPid := StartHost(Format('--SlimPort=%d --StartupDialog=60000', [LPort]), LPort, 25);

  Assert.AreEqual(LPid, SlimProxyGetListenerPid(LPort), 'the port has to belong to our host');
  Assert.Contains(FHost.LastStartupLog, 'auto-dismiss', 'the log has to show the dismiss');
  Assert.IsTrue(FHost.CloseHost(Integer(LPid), 15));
end;

procedure TestSlimProxyGuiHost.AbortWindowIsRecognizedInsteadOfWaitingItOut;
var
  LElapsed: Cardinal;
  LMessage: String;
  LPort   : Integer;
  LStart  : Cardinal;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  FHost.SetAbortWindows(AbortWindowClass);
  LStart := GetTickCount;
  LMessage := ExpectedFailure(
    procedure
    begin
      FHost.StartHostAndWaitForSlim(Exe,
        Format('--SlimPort=%d --AbortWindow=%s', [LPort, AbortWindowClass]), LPort, 40);
    end);
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LMessage, 'ABORT WINDOW', 'the abort window has to be named');
  Assert.Contains(LMessage, AbortWindowClass, 'together with what matched');
  Assert.IsTrue(LElapsed < 20000,
    Format('the abort must not wait out the whole window, it took %dms', [LElapsed]));
end;

procedure TestSlimProxyGuiHost.HostDeathIsReportedWithItsExitCode;
var
  LMessage: String;
  LPort   : Integer;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  // The host dies before its Slim server is up. Without this detection the wait
  // window would simply run out and nobody would learn why.
  LMessage := ExpectedFailure(
    procedure
    begin
      FHost.StartHostAndWaitForSlim(Exe,
        Format('--SlimPort=%d --StartupDelay=60000 --DieAfter=1500 --DieExitCode=9', [LPort]),
        LPort, 40);
    end);

  Assert.Contains(LMessage, 'Host died', 'the death of the host has to be named');
  Assert.Contains(LMessage, 'exit code 9', 'together with its exit code');
end;

procedure TestSlimProxyGuiHost.AForeignProcessHoldingThePortIsRefused;
var
  LForeignPid: Cardinal;
  LMessage   : String;
  LPort      : Integer;
  LStart     : Cardinal;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;

  LForeignPid := StartRaw(Format('--SlimPort=%d --HoldPort=%d', [LPort + 1, LPort]));
  LStart := GetTickCount;
  while (SlimProxyGetListenerPid(LPort) <> LForeignPid) and (GetTickCount - LStart < 15000) do
    TThread.Sleep(100);
  Assert.AreEqual(LForeignPid, SlimProxyGetListenerPid(LPort),
    'the simulation target really holds the port');

  // A run against a foreign process is not a wrong result but NO result - and it
  // looks green.
  LMessage := ExpectedFailure(
    procedure
    begin
      FHost.StartHostAndWaitForSlim(Exe, Format('--SlimPort=%d', [LPort]), LPort, 10);
    end);

  Assert.Contains(LMessage, 'already in use', 'the preflight has to refuse');
  Assert.Contains(LMessage, IntToStr(LForeignPid), 'and it has to name the foreign PID');
end;

procedure TestSlimProxyGuiHost.BlockingCallEndsWithinTheReadTimeout;
var
  LElapsed: Cardinal;
  LPid    : Cardinal;
  LPort   : Integer;
  LResult : String;
  LStart  : Cardinal;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;
  LPid := StartHost(Format('--SlimPort=%d --BlockMax=6000', [LPort]), LPort, 25);

  ConnectExecutorTo(LPort, 2000);
  Assert.AreEqual('OK', ForwardStmt('id_make', 'make', 'blocker', 'BlockForever'));

  LStart := GetTickCount;
  LResult := ForwardStmt('id_block', 'call', 'blocker', 'Block');
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LResult, 'did not answer',
    'a host whose Slim thread never answers must not hang the run');
  Assert.IsTrue(LElapsed < 8000, Format('the call ended after %dms', [LElapsed]));
  Assert.IsTrue(FHost.IsHostRunning(Integer(LPid)), 'the host itself is still alive');
end;

procedure TestSlimProxyGuiHost.WatchdogDismissesAnErrorDialogAndFlagsTheResultUnreliable;
var
  LElapsed: Cardinal;
  LPort   : Integer;
  LResult : String;
  LStart  : Cardinal;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;
  StartHost(Format('--SlimPort=%d', [LPort]), LPort, 25);

  FHost.EnableWatchdog;
  ConnectExecutorTo(LPort, 20000);
  Assert.AreEqual('OK', ForwardStmt('id_make', 'make', 'dialog', 'ShowErrorDialog'));

  // The error dialog is occupying the message loop of the target. The watchdog
  // captures it and dismisses it, so the page goes red instead of hanging - and
  // the result is marked unreliable, because a confirming button can let the call
  // run through and the page end up undeservedly green.
  LStart := GetTickCount;
  LResult := ForwardStmt('id_error', 'call', 'dialog', 'ShowFor', [DialogSelfCloseMs]);
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LResult, TSlimConsts.ExceptionResponse, 'the call must not simply pass');
  Assert.Contains(LResult, 'UNRELIABLE', 'the result has to say that it cannot be trusted');
  Assert.Contains(LResult, 'ERROR DISMISSED', 'and it has to carry the finding');
  Assert.Contains(FExecutor.LastWatchdogReport, 'ERROR DISMISSED');
  // The dialog has to be gone because it was CLICKED, not because it closed
  // itself: without this the finding would be reported while the call still sat
  // out the whole self close timeout.
  Assert.IsTrue(LElapsed < Cardinal(StrToInt(DialogSelfCloseMs) div 2),
    Format('the dismissed dialog released the call after %dms', [LElapsed]));
end;

procedure TestSlimProxyGuiHost.WatchdogReportsAQuestionButNeverDismissesIt;
var
  LPort  : Integer;
  LResult: String;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;
  StartHost(Format('--SlimPort=%d', [LPort]), LPort, 25);

  FHost.EnableWatchdog;
  ConnectExecutorTo(LPort, 4000);
  Assert.AreEqual('OK', ForwardStmt('id_make', 'make', 'dialog', 'ShowQuestion'));

  // A yes/no is a decision of the application, not something to click away. So
  // the call runs into the read timeout - but the finding travels with the
  // message, which is what turns a hang into a diagnosable red page.
  LResult := ForwardStmt('id_question', 'call', 'dialog', 'AskFor', [DialogSelfCloseMs]);

  Assert.Contains(LResult, 'did not answer', 'the blocked call ends in the read timeout');
  Assert.Contains(LResult, 'Watchdog findings', 'and the findings travel with the message');
  Assert.Contains(LResult, 'NOT dismissed', 'the question was reported, not clicked away');
  Assert.DoesNotContain(FExecutor.LastWatchdogReport, 'ERROR DISMISSED');
end;

procedure TestSlimProxyGuiHost.WatchdogTreatsAConfiguredFatalWordingAsAbortSuite;
var
  LElapsed: Cardinal;
  LPort   : Integer;
  LResult : String;
  LStart  : Cardinal;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;
  StartHost(Format('--SlimPort=%d', [LPort]), LPort, 25);

  // Nothing here knows the application: the wording that means "the process state
  // is not trustworthy any more" is pure configuration.
  FHost.SetFatalPatterns('while processing the request');
  FHost.EnableWatchdog;
  ConnectExecutorTo(LPort, 20000);
  Assert.AreEqual('OK', ForwardStmt('id_make', 'make', 'dialog', 'ShowErrorDialog'));

  LStart := GetTickCount;
  LResult := ForwardStmt('id_fatal', 'call', 'dialog', 'ShowFor', [DialogSelfCloseMs]);
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LResult, 'ABORT_SLIM_SUITE', 'a fatal finding has to stop the run');
  Assert.Contains(FExecutor.LastWatchdogReport, 'FATAL');
  // A fatal report is captured AND dismissed, so the pending call is released
  // rather than left sitting out the self close timeout.
  Assert.IsTrue(LElapsed < Cardinal(StrToInt(DialogSelfCloseMs) div 2),
    Format('the fatal dialog released the call after %dms', [LElapsed]));
end;

procedure TestSlimProxyGuiHost.WatchdogTellsAnIdleProcessFromAComputingOne;
var
  LPid     : Cardinal;
  LPort    : Integer;
  LWatchdog: TSlimProxyWatchdog;
begin
  RequireSimulationTarget;
  LPort := TestFindFreePort;
  LPid := StartHost(Format('--SlimPort=%d', [LPort]), LPort, 25);

  // That a window pumps no messages says nothing - a long calculation on the main
  // thread looks exactly the same. Only the CPU delta separates them. The host is
  // idle here, so a stall has to be reported.
  LWatchdog := TSlimProxyWatchdog.Create(LPid, TSlimProxyWindowConfig.CreateFromGlobals);
  try
    LWatchdog.PollIntervalMs := 250;
    LWatchdog.StallReportAfterMs := 1500;
    LWatchdog.StartWatching;
    TThread.Sleep(3500);
    LWatchdog.StopAndWait;

    Assert.Contains(LWatchdog.Report, 'STALL', 'an idle process has to be reported as blocked');
    Assert.IsFalse(LWatchdog.HasFatal, 'a stall is a finding, not a reason to abort the run');
    Assert.IsFalse(LWatchdog.HasDismissedError, 'and nothing was clicked');
  finally
    LWatchdog.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxyGuiHost);

end.
