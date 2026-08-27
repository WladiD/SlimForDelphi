// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Read timeout and target state after a failure.
///
///   Every test in here runs against the in process fake target from
///   Test.SlimProxy.Helpers, so it needs no foreign application, no build step
///   and no script, and it runs in seconds.
/// </summary>
unit Test.SlimProxy.Timeout;

interface

uses

  Winapi.Windows,

  System.SysUtils,

  DUnitX.TestFramework,

  Slim.Common,
  Slim.Exec,
  Slim.Fixture,
  Slim.List,
  Slim.Proxy,
  Slim.Proxy.Config,

  Test.SlimExec,
  Test.SlimProxy.Helpers;

type

  [TestFixture]
  TestSlimProxyTimeout = class
  private
    FContext : TSlimStatementContext;
    FExecutor: TSlimProxyExecutor;
    FTarget  : TFakeSlimTarget;
    function  ForwardCall(const AId: String): String;
    procedure UseTarget(AMode: TFakeTargetMode);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StallingTargetEndsWithinTheTimeLimit;
    [Test]
    procedure TheFirstCauseSurvivesOnEveryFollowingCall;
    [Test]
    procedure ReconnectTakesABrokenTargetBackIntoService;
    [Test]
    procedure ReadTimeoutForNextCallLetsALongCallThrough;
    [Test]
    procedure UnlimitedReadTimeoutIsStillTheDefault;
    [Test]
    procedure InvalidGreetingIsNamedInTheResult;
    [Test]
    procedure AFailedConnectIsNotRetriedForEveryFollowingCall;
    [Test]
    procedure PingTargetReportsTheCauseInsteadOfRaisingIt;
  end;

implementation

const
  TestReadTimeoutMs = 400;

{ TestSlimProxyTimeout }

procedure TestSlimProxyTimeout.Setup;
begin
  // Reset the globals: other fixtures may have changed them, and the test order
  // is not guaranteed.
  SlimProxyConnectTimeout := DefaultConnectTimeoutMs;
  SlimProxyReadTimeout := DefaultReadTimeoutMs;
  SlimProxyWatchdogEnabled := False;

  FContext := TSlimStatementContext.Create;
  FContext.InitAllMembers;
  FExecutor := TSlimProxyExecutor.Create(FContext);
  FExecutor.ConnectTimeout := 2000;
end;

procedure TestSlimProxyTimeout.TearDown;
begin
  FExecutor.Free;
  FContext.Free;
  FTarget.Free;
  FTarget := nil;
end;

procedure TestSlimProxyTimeout.UseTarget(AMode: TFakeTargetMode);
begin
  FTarget := TFakeSlimTarget.Create(AMode);
  FTarget.StallMs := 4000;
  FExecutor.AddTargetDeferred('Fake', '127.0.0.1', FTarget.Port);
  FExecutor.SwitchToTarget('Fake');
end;

/// <summary>Forwards one call and returns the result text of that statement.</summary>
function TestSlimProxyTimeout.ForwardCall(const AId: String): String;
var
  LResponse: TSlimList;
  LResult  : TSlimList;
  LStmts   : TSlimList;
begin
  LStmts := SlimList([SlimList([AId, 'call', 'remote_instance', 'AnyMethod'])]);
  try
    LResponse := FExecutor.Execute(LStmts);
    try
      Assert.AreEqual(1, LResponse.Count, 'exactly one result expected');
      Assert.IsTrue(TryGetSlimListById(LResponse, AId, LResult), 'result must carry the id of the call');
      Result := LResult[1].ToString;
    finally
      LResponse.Free;
    end;
  finally
    LStmts.Free;
  end;
end;

procedure TestSlimProxyTimeout.StallingTargetEndsWithinTheTimeLimit;
var
  LElapsed: Cardinal;
  LResult : String;
  LStart  : Cardinal;
begin
  // The target speaks the handshake, reads the command and never answers. Without
  // a read timeout the proxy blocks along with it - and FitNesse has no read
  // timeout of its own, so the proxy is the only place where this is fixable.
  UseTarget(ftmStall);
  FExecutor.ReadTimeout := TestReadTimeoutMs;

  LStart := GetTickCount;
  LResult := ForwardCall('id_stall');
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LResult, TSlimConsts.ExceptionResponse, 'the call must fail, not hang');
  Assert.Contains(LResult, 'did not answer', 'the message has to name the cause');
  Assert.IsTrue(LElapsed < 3 * TestReadTimeoutMs,
    Format('the call must end by itself, it took %dms', [LElapsed]));
  Assert.AreEqual(1, FTarget.Received, 'the target really did read the command');
end;

procedure TestSlimProxyTimeout.TheFirstCauseSurvivesOnEveryFollowingCall;
var
  LFirst : String;
  LSecond: String;
begin
  UseTarget(ftmStall);
  FExecutor.ReadTimeout := TestReadTimeoutMs;

  LFirst := ForwardCall('id_first');
  Assert.Contains(LFirst, 'EIdReadTimeout', 'the first failure names the read timeout');

  // After a read failure the byte stream is in an unknown state, so the target is
  // marked broken. Reusing it would read the answer of the PREVIOUS request and
  // deliver silently wrong results - the most dangerous case of all, because it
  // looks green.
  LSecond := ForwardCall('id_second');
  Assert.Contains(LSecond, TSlimConsts.ExceptionResponse, 'a broken target must not be reused');
  Assert.Contains(LSecond, 'is broken since', 'the follow up message says the target is broken');
  Assert.Contains(LSecond, 'EIdReadTimeout', 'and it still names the FIRST cause');
end;

procedure TestSlimProxyTimeout.ReconnectTakesABrokenTargetBackIntoService;
var
  LResult: String;
begin
  UseTarget(ftmStall);
  FExecutor.ReadTimeout := TestReadTimeoutMs;

  Assert.Contains(ForwardCall('id_break'), 'did not answer');

  // The host behaves again - e.g. after a restart.
  FTarget.Mode := ftmAnswer;
  FExecutor.ReconnectTarget('Fake');

  LResult := ForwardCall('id_after_reconnect');
  Assert.AreEqual('OK', LResult, 'after Reconnect Target the target answers again');
end;

procedure TestSlimProxyTimeout.ReadTimeoutForNextCallLetsALongCallThrough;
var
  LResult: String;
begin
  // A long but legitimate calculation must not be cut off by the limit that
  // exists to catch a blocked host.
  UseTarget(ftmAnswer);
  // Three times the base limit, so which limit applied is never a matter of
  // milliseconds.
  FTarget.AnswerDelayMs := 600;
  FExecutor.ReadTimeout := 200;

  FExecutor.SetReadTimeoutForNextCall(8000);
  LResult := ForwardCall('id_slow_but_allowed');
  Assert.AreEqual('OK', LResult, 'the raised limit has to hold for this one call');

  // ...and only for this one call: afterwards the normal limit applies again.
  LResult := ForwardCall('id_slow_and_cut_off');
  Assert.Contains(LResult, 'did not answer', 'the raise must not stay in effect');
end;

procedure TestSlimProxyTimeout.UnlimitedReadTimeoutIsStillTheDefault;
begin
  // Backwards compatibility: an existing setup must not change behaviour just
  // because the proxy learned about time limits.
  Assert.AreEqual(0, DefaultReadTimeoutMs, 'the default read timeout stays unlimited');
  UseTarget(ftmAnswer);
  Assert.AreEqual(0, FExecutor.ReadTimeout, 'a fresh executor inherits the unlimited default');
  Assert.AreEqual('OK', ForwardCall('id_default'));
end;

procedure TestSlimProxyTimeout.InvalidGreetingIsNamedInTheResult;
var
  LResult: String;
begin
  UseTarget(ftmBadGreeting);
  FExecutor.ReadTimeout := TestReadTimeoutMs;
  LResult := ForwardCall('id_greeting');
  Assert.Contains(LResult, 'Invalid greeting', 'a target that is not a Slim server has to be named as such');
end;

procedure TestSlimProxyTimeout.AFailedConnectIsNotRetriedForEveryFollowingCall;
var
  LElapsed: Cardinal;
  LFirst  : String;
  LPort   : Integer;
  LSecond : String;
  LStart  : Cardinal;
begin
  // This is what a host that died in the middle of a suite looks like. Spending
  // the whole connect window again on every following instruction would drag the
  // rest of the suite out for hours while every page fails anyway.
  LPort := TestFindFreePort;
  FExecutor.ConnectTimeout := 400;
  FExecutor.AddTargetDeferred('Gone', '127.0.0.1', LPort);
  FExecutor.SwitchToTarget('Gone');

  LFirst := ForwardCall('id_first');
  Assert.Contains(LFirst, 'could not be connected', 'the first attempt waits and then gives up');

  LStart := GetTickCount;
  LSecond := ForwardCall('id_second');
  LElapsed := GetTickCount - LStart;

  Assert.Contains(LSecond, 'is broken since', 'and every following call fails at once');
  Assert.IsTrue(LElapsed < 500, Format('the follow up call took %dms', [LElapsed]));
end;

procedure TestSlimProxyTimeout.PingTargetReportsTheCauseInsteadOfRaisingIt;
begin
  UseTarget(ftmAnswer);
  Assert.AreEqual('OK', FExecutor.PingTarget('Fake'), 'a living target answers OK');

  FTarget.Mode := ftmStall;
  FExecutor.ReadTimeout := TestReadTimeoutMs;
  Assert.Contains(ForwardCall('id_break'), 'did not answer');

  // The ping hands the cause back instead of raising it. That is what lets a test
  // page ASSERT the state of a broken target instead of just going red - and it
  // answers "is my target still there, and if not, why".
  Assert.Contains(FExecutor.PingTarget('Fake'), 'is broken since');
  Assert.Contains(FExecutor.PingTarget('Fake'), 'EIdReadTimeout', 'including the first cause');
end;

initialization

TDUnitX.RegisterTestFixture(TestSlimProxyTimeout);

end.
