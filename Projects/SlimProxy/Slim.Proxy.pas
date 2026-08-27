// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,

  IdGlobal,
  IdTCPClient,

  Slim.Common,
  Slim.Exec,
  Slim.Fixture,
  Slim.List,
  Slim.Logger,
  Slim.Proxy.Config,
  Slim.Proxy.Interfaces,
  Slim.Proxy.Watchdog,
  Slim.Proxy.WinTools;

type

  TSlimProxyTarget = class
  private
    FBroken        : Boolean;
    FBrokenReason  : String;
    FClient        : TIdTCPClient;
    FConnectTimeout: Integer;
    FHost          : String;
    FLogger        : ISlimLogger;
    FName          : String;
    FPort          : Integer;
    FProcessId     : Cardinal;
    FReadTimeout   : Integer;
    procedure ApplyReadTimeout(AReadTimeout: Integer);
    function  GetConnected: Boolean;
    procedure LogEvent(const AMessage: String);
  public
    constructor Create(const AName, AHost: String; APort: Integer);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function  Describe: String;
    function  IsLocal: Boolean;
    procedure MarkBroken(const AReason: String);
    function  ResolveProcessId: Cardinal;
    procedure Reconnect;
    function  SendCommand(const ACommand: String; AReadTimeout: Integer): String;
    property  Broken: Boolean read FBroken;
    property  BrokenReason: String read FBrokenReason;
    property  Connected: Boolean read GetConnected;
    property  ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
    property  Host: String read FHost;
    property  Logger: ISlimLogger read FLogger write FLogger;
    property  Name: String read FName;
    property  Port: Integer read FPort;
    /// <summary>
    ///   Process id of the host, for the watchdog. 0 = unknown, the watchdog
    ///   then stays out.
    /// </summary>
    property  ProcessId: Cardinal read FProcessId write FProcessId;
    /// <summary>
    ///   Time limit for reading the answer in ms. 0 = unlimited. Without a limit
    ///   a modal dialog in the target host blocks the proxy along with it,
    ///   because the Slim thread of the target stops answering.
    /// </summary>
    property  ReadTimeout: Integer read FReadTimeout write FReadTimeout;
  end;

  TSlimProxyExecutor = class(TSlimExecutor, ISlimProxyExecutor)
  private
    FActiveTarget      : TSlimProxyTarget;
    FConnectTimeout    : Integer;
    FLastWatchdogReport: String;
    FReadTimeout       : Integer;
    FReadTimeoutOnce   : Integer;
    FTargets           : TObjectDictionary<String, TSlimProxyTarget>;
    procedure CheckLocalFixtureInstance(const AInstanceName: String; var AIsLocal: Boolean);
    procedure DropLocalInstanceShadow(const AInstanceName: String);
    function  ForwardCommand(ARawStmt: TSlimList; const AId: String): TSlimList;
    procedure LogError(const ASource, AMessage: String);
    procedure LogEvent(const ACategory, AMessage: String);
    function  TakeReadTimeout: Integer;
    function  TryForwardToTarget(ARawStmt: TSlimList; out AResult: TSlimList): Boolean;
  public
    constructor Create(AContext: TSlimStatementContext); override;
    destructor Destroy; override;
    function Execute(ARawStmts: TSlimList): TSlimList; override;
  public // ISlimProxyExecutor
    procedure AddTarget(const AName, AHost: String; APort: Integer);
    procedure AddTargetDeferred(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    procedure ReconnectTarget(const AName: String);
    procedure SwitchToTarget(const AName: String);
    function  ActiveTargetName: String;
    function  PingTarget(const AName: String): String;
    function  LastWatchdogReport: String;
    function  TargetStatus: String;
    procedure SetTargetProcessId(const AName: String; APid: Cardinal);
    function  GetTargetProcessId(const AName: String): Cardinal;
    function  GetConnectTimeout: Integer;
    procedure SetConnectTimeout(AValue: Integer);
    function  GetReadTimeout: Integer;
    procedure SetReadTimeout(AValue: Integer);
    procedure SetReadTimeoutForNextCall(AValue: Integer);
    property ConnectTimeout: Integer read GetConnectTimeout write SetConnectTimeout;
    property ReadTimeout: Integer read GetReadTimeout write SetReadTimeout;
  end;

function SlimProxyExceptionResponse(const AMessage: String): String;

implementation

uses
  Slim.Proxy.Base;

/// <summary>
///   Composes a Slim exception response and does not prefix a message that is
///   already a composed standard exception (e.g. ABORT_SLIM_SUITE).
/// </summary>
function SlimProxyExceptionResponse(const AMessage: String): String;
begin
  if AMessage.StartsWith(TSlimConsts.ExceptionResponse) then
    Result := AMessage
  else
    Result := TSlimConsts.ExceptionResponse + ':' + AMessage;
end;

{ TSlimProxyTarget }

constructor TSlimProxyTarget.Create(const AName, AHost: String; APort: Integer);
begin
  inherited Create;
  FName := AName;
  FHost := AHost;
  FPort := APort;
  FClient := TIdTCPClient.Create(nil);
  FConnectTimeout := SlimProxyConnectTimeout;
  FReadTimeout := SlimProxyReadTimeout;
end;

destructor TSlimProxyTarget.Destroy;
begin
  Disconnect;
  FClient.Free;
  inherited;
end;

function TSlimProxyTarget.GetConnected: Boolean;
begin
  Result := FClient.Connected;
end;

procedure TSlimProxyTarget.LogEvent(const AMessage: String);
begin
  if Assigned(FLogger) then
    FLogger.LogEvent('target', AMessage);
end;

function TSlimProxyTarget.Describe: String;
begin
  Result := Format('%s (%s:%d)', [FName, FHost, FPort]);
end;

function TSlimProxyTarget.IsLocal: Boolean;
begin
  Result := (FHost = '') or SameText(FHost, 'localhost') or (FHost = '127.0.0.1') or
            (FHost = '::1') or SameText(FHost, GetEnvironmentVariable('COMPUTERNAME'));
end;

/// <summary>
///   Determines the process id of the host from the owner of the listening
///   socket. Only meaningful for a target on this machine.
/// </summary>
function TSlimProxyTarget.ResolveProcessId: Cardinal;
begin
  if (FProcessId = 0) and IsLocal then
    FProcessId := SlimProxyGetListenerPid(FPort);
  Result := FProcessId;
end;

/// <summary>
///   Marks the target as unusable and keeps the FIRST cause. Without that,
///   every following page would only carry "is marked broken" and the actual
///   finding - connection gone, time limit exceeded - would not be readable
///   in any result any more.
/// </summary>
procedure TSlimProxyTarget.MarkBroken(const AReason: String);
begin
  if not FBroken then
  begin
    FBroken := True;
    FBrokenReason := AReason;
    LogEvent(Format('%s marked broken: %s', [Describe, AReason]));
  end;
end;

procedure TSlimProxyTarget.ApplyReadTimeout(AReadTimeout: Integer);
begin
  if AReadTimeout > 0 then
    FClient.ReadTimeout := AReadTimeout
  else
    FClient.ReadTimeout := IdTimeoutInfinite;
  if Assigned(FClient.IOHandler) then
    FClient.IOHandler.ReadTimeout := FClient.ReadTimeout;
end;

procedure TSlimProxyTarget.Connect;
var
  LGreeting: String;
  LStart   : Cardinal;
begin
  if FBroken then
    raise ESlim.CreateFmt('Target %s is broken since: %s', [Describe, FBrokenReason]);

  if FClient.Connected then
    Exit;

  FClient.Host := FHost;
  FClient.Port := FPort;
  FClient.ConnectTimeout := FConnectTimeout;
  ApplyReadTimeout(FReadTimeout);

  LStart := GetTickCount;
  while True do
  begin
    try
      FClient.Connect;
      Break;
    except
      on E: Exception do
      begin
        if (GetTickCount - LStart) >= Cardinal(FConnectTimeout) then
        begin
          // Give up for good instead of spending the whole wait window again on
          // every following instruction: after the host died that would drag a
          // suite out for hours while every page fails anyway. The first cause is
          // kept, and "Reconnect Target" is the way back after a host restart.
          MarkBroken(Format('%s: %s', [E.ClassName, E.Message]));
          raise ESlim.CreateFmt('Target %s could not be connected: %s', [Describe, FBrokenReason]);
        end;
        TThread.Sleep(10);
      end;
    end;
  end;

  // The greeting needs the time limit as well - a host that accepts the
  // connection but never introduces itself would otherwise block right here.
  ApplyReadTimeout(FReadTimeout);

  // Consume and validate the greeting message from the server (e.g. "Slim -- V0.5")
  try
    LGreeting := FClient.IOHandler.ReadLn;
  except
    on E: Exception do
    begin
      MarkBroken(Format('%s while reading the greeting: %s', [E.ClassName, E.Message]));
      Disconnect;
      raise ESlim.CreateFmt('Target %s did not send a greeting: %s', [Describe, FBrokenReason]);
    end;
  end;

  if not LGreeting.StartsWith('Slim --') then
  begin
    Disconnect;
    MarkBroken(Format('invalid greeting "%s"', [LGreeting]));
    raise ESlim.CreateFmt('Invalid greeting from target %s: "%s"', [Describe, LGreeting]);
  end;

  ResolveProcessId;
  LogEvent(Format('%s connected, host process id %d', [Describe, FProcessId]));
end;

procedure TSlimProxyTarget.Disconnect;
begin
  if FClient.Connected then
    FClient.Disconnect;
end;

/// <summary>Takes a broken target back into service.</summary>
procedure TSlimProxyTarget.Reconnect;
begin
  try
    Disconnect;
  except
    // A failure while tearing down must not stand in the way of a fresh start.
  end;
  FBroken := False;
  FBrokenReason := '';
  FProcessId := 0;
  LogEvent(Format('%s taken back into service', [Describe]));
  Connect;
end;

/// <summary>
///   Sends a command and reads the answer. AReadTimeout overrides the
///   target's own limit for this one call; 0 means unlimited.
/// </summary>
function TSlimProxyTarget.SendCommand(const ACommand: String; AReadTimeout: Integer): String;
var
  LLengthStr     : String;
  LRequestBytes  : TBytes;
  LResponseLength: Integer;
begin
  Connect;
  ApplyReadTimeout(AReadTimeout);

  // Every failure from here on leaves the byte stream in an UNKNOWN state (half
  // an answer sitting in the buffer). The connection is therefore dropped and
  // the target is marked broken - another request on it would otherwise read the
  // answer of the PREVIOUS one and deliver silently wrong results. That is the
  // most dangerous case of all, because it looks green.
  try
    LRequestBytes := TEncoding.UTF8.GetBytes(ACommand);
    LLengthStr := Format('%.6d:', [Length(LRequestBytes)]);
    FClient.IOHandler.Write(LLengthStr);
    FClient.IOHandler.Write(TIdBytes(LRequestBytes));

    LLengthStr := FClient.IOHandler.ReadString(6);
    if not TryStrToInt(LLengthStr, LResponseLength) then
      raise ESlim.CreateFmt('Invalid response length: "%s"', [LLengthStr]);

    // Read colon
    FClient.IOHandler.ReadString(1);

    Result := FClient.IOHandler.ReadString(LResponseLength, IndyTextEncoding_UTF8);
  except
    on E: Exception do
    begin
      MarkBroken(Format('%s: %s', [E.ClassName, E.Message]));
      try
        Disconnect;
      except
        // A failure while tearing down must not hide the actual cause.
      end;
      if IsConsole then
      begin
        Writeln(Format('*** TARGET %s DID NOT ANSWER: %s', [Describe, FBrokenReason]));
        Flush(Output);
      end;
      raise ESlim.CreateFmt('Target %s did not answer: %s', [Describe, FBrokenReason]);
    end;
  end;
end;

{ TSlimProxyExecutor }

constructor TSlimProxyExecutor.Create(AContext: TSlimStatementContext);
begin
  inherited Create(AContext);
  ManageInstances := True; // Proxy needs to manage instances too
  FTargets := TObjectDictionary<String, TSlimProxyTarget>.Create([doOwnsValues]);
  if FManageInstances then
    FContext.SetInstances(TSlimFixtureDictionary.Create([doOwnsValues]), True);
  FConnectTimeout := SlimProxyConnectTimeout;
  FReadTimeout := SlimProxyReadTimeout;
  FReadTimeoutOnce := -1;

  // Targets from the command line, created for EVERY incoming Slim connection so
  // that an existing test suite does not have to see the proxy at all. They are
  // NOT connected here - the target host may still be starting up; the connection
  // is established with the first forwarded command and a failure becomes a
  // regular Slim result there.
  for var LStartup in SlimProxyStartupTargets do
  begin
    AddTargetDeferred(LStartup.Name, LStartup.Host, LStartup.Port);
    if not Assigned(FActiveTarget) then
      FTargets.TryGetValue(LStartup.Name, FActiveTarget);
  end;
end;

destructor TSlimProxyExecutor.Destroy;
var
  LFixture: TSlimFixture;
begin
  // Ensure instances are freed before the executor is destroyed.
  if FManageInstances and Assigned(FContext) and Assigned(FContext.Instances) then
  begin
    for LFixture in FContext.Instances.Values do
      if LFixture is TSlimProxyBaseFixture then
        TSlimProxyBaseFixture(LFixture).Executor := nil;
    FContext.Instances.Clear;
  end;

  FActiveTarget := nil;
  FTargets.Free;
  inherited;
end;

procedure TSlimProxyExecutor.LogError(const ASource, AMessage: String);
begin
  if Assigned(FLogger) then
    FLogger.LogError(ASource, AMessage);
  if IsConsole then
  begin
    Writeln(Format('*** %s: %s', [ASource, AMessage]));
    Flush(Output);
  end;
end;

procedure TSlimProxyExecutor.LogEvent(const ACategory, AMessage: String);
begin
  if Assigned(FLogger) then
    FLogger.LogEvent(ACategory, AMessage);
end;

procedure TSlimProxyExecutor.AddTarget(const AName, AHost: String; APort: Integer);
var
  LTarget: TSlimProxyTarget;
begin
  AddTargetDeferred(AName, AHost, APort);
  if FTargets.TryGetValue(AName, LTarget) then
    LTarget.Connect;
end;

procedure TSlimProxyExecutor.AddTargetDeferred(const AName, AHost: String; APort: Integer);
var
  LTarget: TSlimProxyTarget;
begin
  if FTargets.ContainsKey(AName) then
    raise ESlim.CreateFmt('Target with name "%s" already exists.', [AName]);

  LTarget := TSlimProxyTarget.Create(AName, AHost, APort);
  LTarget.ConnectTimeout := FConnectTimeout;
  LTarget.ReadTimeout := FReadTimeout;
  LTarget.Logger := FLogger;
  FTargets.Add(AName, LTarget);
  LogEvent('target', Format('registered %s', [LTarget.Describe]));
  // No implicit activation here: which target is active stays the decision of
  // the test script (Switch To Target) resp. of the command line, where the
  // FIRST --Target becomes active.
end;

procedure TSlimProxyExecutor.SwitchToTarget(const AName: String);
begin
  if not FTargets.TryGetValue(AName, FActiveTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
  LogEvent('target', Format('switched to %s', [FActiveTarget.Describe]));
end;

procedure TSlimProxyExecutor.DisconnectTarget(const AName: String);
var
  LTarget: TSlimProxyTarget;
begin
  if FTargets.TryGetValue(AName, LTarget) then
  begin
    LogEvent('target', Format('disconnected %s', [LTarget.Describe]));
    if FActiveTarget = LTarget then
      FActiveTarget := nil;
    FTargets.Remove(AName);
  end;
end;

procedure TSlimProxyExecutor.ReconnectTarget(const AName: String);
var
  LTarget: TSlimProxyTarget;
begin
  if not FTargets.TryGetValue(AName, LTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
  LTarget.Logger := FLogger;
  LTarget.Reconnect;
end;

function TSlimProxyExecutor.ActiveTargetName: String;
begin
  if Assigned(FActiveTarget) then
    Result := FActiveTarget.Name
  else
    Result := '';
end;

function TSlimProxyExecutor.PingTarget(const AName: String): String;
var
  LStmts : TSlimList;
  LTarget: TSlimProxyTarget;
begin
  if not FTargets.TryGetValue(AName, LTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
  LTarget.Logger := FLogger;

  try
    // A REAL round trip: an 'import' is answered by every Slim server and changes
    // nothing. Anything less would not notice a host that died, because a socket
    // only fails on the next actual IO. The one-shot read timeout is deliberately
    // left alone - a ping must not consume it.
    LStmts := SlimList([SlimList(['slim_proxy_ping', 'import', 'SlimProxyPing'])]);
    try
      LTarget.SendCommand(SlimListSerialize(LStmts), FReadTimeout);
      Result := 'OK';
    finally
      LStmts.Free;
    end;
  except
    on E: Exception do
    begin
      Result := E.Message;
      LogEvent('target', Format('ping of %s failed: %s', [LTarget.Describe, Result]));
    end;
  end;
end;

function TSlimProxyExecutor.LastWatchdogReport: String;
begin
  Result := FLastWatchdogReport;
end;

function TSlimProxyExecutor.TargetStatus: String;
begin
  Result := '';
  for var LTarget in FTargets.Values do
  begin
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + LTarget.Describe;
    if LTarget = FActiveTarget then
      Result := Result + ' [active]';
    if LTarget.ProcessId <> 0 then
      Result := Result + Format(' pid=%d', [LTarget.ProcessId]);
    if LTarget.Broken then
      Result := Result + ' BROKEN since: ' + LTarget.BrokenReason;
  end;
  if Result = '' then
    Result := '(no target)';
end;

procedure TSlimProxyExecutor.SetTargetProcessId(const AName: String; APid: Cardinal);
var
  LTarget: TSlimProxyTarget;
begin
  if not FTargets.TryGetValue(AName, LTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
  LTarget.ProcessId := APid;
end;

function TSlimProxyExecutor.GetTargetProcessId(const AName: String): Cardinal;
var
  LTarget: TSlimProxyTarget;
begin
  if not FTargets.TryGetValue(AName, LTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
  Result := LTarget.ResolveProcessId;
end;

function TSlimProxyExecutor.GetConnectTimeout: Integer;
begin
  Result := FConnectTimeout;
end;

procedure TSlimProxyExecutor.SetConnectTimeout(AValue: Integer);
begin
  FConnectTimeout := AValue;
  for var LTarget in FTargets.Values do
    LTarget.ConnectTimeout := AValue;
end;

function TSlimProxyExecutor.GetReadTimeout: Integer;
begin
  Result := FReadTimeout;
end;

procedure TSlimProxyExecutor.SetReadTimeout(AValue: Integer);
begin
  FReadTimeout := AValue;
  for var LTarget in FTargets.Values do
    LTarget.ReadTimeout := AValue;
end;

procedure TSlimProxyExecutor.SetReadTimeoutForNextCall(AValue: Integer);
begin
  FReadTimeoutOnce := AValue;
end;

function TSlimProxyExecutor.TakeReadTimeout: Integer;
begin
  if FReadTimeoutOnce >= 0 then
  begin
    Result := FReadTimeoutOnce;
    FReadTimeoutOnce := -1;
    LogEvent('timeout', Format('read timeout raised to %dms for this call', [Result]));
  end
  else
    Result := FReadTimeout;
end;

function TSlimProxyExecutor.ForwardCommand(ARawStmt: TSlimList; const AId: String): TSlimList;
var
  LResponseList: TSlimList;
  LResponseStr : String;
  LWatchdog    : TSlimProxyWatchdog;
begin
  Result := nil;
  LResponseList := nil;
  LWatchdog := nil;
  FLastWatchdogReport := '';
  FActiveTarget.Logger := FLogger;

  var LForwardList: TSlimList := TSlimList.Create;
  try
    LForwardList.Add(ARawStmt); // Wrap in list as expected by Slim Server
    try
      // The watchdog runs exactly as long as this call is pending - that is the
      // knowledge no external driver script has.
      if SlimProxyWatchdogEnabled then
      begin
        var LPid: Cardinal := FActiveTarget.ResolveProcessId;
        if LPid <> 0 then
        begin
          LWatchdog := TSlimProxyWatchdog.Create(LPid, TSlimProxyWindowConfig.CreateFromGlobals);
          LWatchdog.StartWatching;
        end;
      end;

      try
        LResponseStr := FActiveTarget.SendCommand(SlimListSerialize(LForwardList), TakeReadTimeout);
      finally
        if Assigned(LWatchdog) then
        begin
          LWatchdog.StopAndWait;
          FLastWatchdogReport := LWatchdog.Report;
          if FLastWatchdogReport <> '' then
            LogEvent('watchdog', FLastWatchdogReport);
        end;
      end;

      LResponseList := SlimListUnserialize(LResponseStr);

      // Expecting list of results: [[id, result]]
      if (LResponseList.Count > 0) and (LResponseList[0] is TSlimList) then
        Result := TSlimList(LResponseList.Extract(LResponseList[0]))
      else
        raise ESlim.Create('Invalid response format from target');

      // A dismissed error dialog makes the result UNRELIABLE: a confirming
      // button can let the call run through and the page end up undeservedly
      // green. That has to be recorded in the result, not only in the log.
      if Assigned(LWatchdog) and LWatchdog.HasDismissedError then
      begin
        Result.Free;
        Result := SlimList([AId, SlimProxyExceptionResponse(Format(
          'Watchdog dismissed an error dialog in target %s while this call was pending - ' +
          'the result of this call is UNRELIABLE.' + sLineBreak + '%s',
          [FActiveTarget.Describe, FLastWatchdogReport]))]);
      end;
    except
      on E: Exception do
      begin
        LogError('forward', E.Message);
        var LMessage: String := E.Message;
        if FLastWatchdogReport <> '' then
          LMessage := LMessage + sLineBreak + 'Watchdog findings:' + sLineBreak + FLastWatchdogReport;
        Result.Free;
        Result := SlimList([AId, SlimProxyExceptionResponse(LMessage)]);
      end;
    end;

    // A fatal report means: stop the run. The process state is not trustworthy
    // any more, every further result would be garbage.
    if Assigned(LWatchdog) and LWatchdog.HasFatal then
    begin
      FActiveTarget.MarkBroken('fatal watchdog finding');
      FStopExecute := True;
      // ESlimStopSuite is only used to compose the standard ABORT_SLIM_SUITE
      // message - it is not raised, so it has to be freed here.
      var LAbort: ESlimStopSuite := ESlimStopSuite.Create(Format(
        'Fatal finding in target %s - the process state is not trustworthy any more.' + sLineBreak + '%s',
        [FActiveTarget.Describe, FLastWatchdogReport]));
      try
        Result.Free;
        Result := SlimList([AId, SlimProxyExceptionResponse(LAbort.Message)]);
      finally
        LAbort.Free;
      end;
    end;
  finally
    LWatchdog.Free;
    // ARawStmt belongs to the caller (ARawStmts list in Execute).
    // LForwardList.Add took ownership. We must extract it back to prevent
    // LForwardList.Free from destroying ARawStmt.
    LForwardList.Extract(ARawStmt);
    LForwardList.Free;
    LResponseList.Free;
  end;
end;

function TSlimProxyExecutor.TryForwardToTarget(ARawStmt: TSlimList; out AResult: TSlimList): Boolean;
begin
  AResult := nil;
  if not Assigned(FActiveTarget) then
    Exit(False);

  AResult := ForwardCommand(ARawStmt, ARawStmt[0].ToString);
  Result := True;
end;

function TSlimProxyExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  LClass       : TRttiInstanceType;
  LFixture     : TSlimFixture;
  LInstr       : String;
  LInstruction : TSlimInstruction;
  LIsLocal     : Boolean;
  LRawStmt     : TSlimList;
  LRawStmtEntry: TSlimEntry;
  LStmtResult  : TSlimList;
begin
  Result := TSlimList.Create;
  try
    if Assigned(FLogger) then
      FLogger.EnterList(ARawStmts);

    try
      FStopExecute := False;
      LIsLocal := False;

      for var Loop: Integer := 0 to ARawStmts.Count - 1 do
      begin
        LStmtResult := nil;
        LRawStmtEntry := ARawStmts[Loop];
        if not (LRawStmtEntry is TSlimList) then
          Continue;

        LRawStmt := LRawStmtEntry as TSlimList;

        if Assigned(FLogger) then
          FLogger.LogInstruction(LRawStmt);

        if LRawStmt.Count > 1 then
          LInstr := LRawStmt[1].ToString
        else
          Continue;

        LInstruction := StringToSlimInstruction(LInstr);

        // --- Decision Logic: Local or Remote? ---

        if (LInstruction = siMake) and (LRawStmt.Count > 3) then
        begin
          var LClassName: String := LRawStmt[3].ToString.Trim;
          LIsLocal :=
            LClassName.StartsWith('SlimProxy.', True) and                    // We expect fully qualified names like "SlimProxy.ClassName" as imports are ignored locally
            FContext.Resolver.TryGetSlimFixture(LClassName, nil, LClass) and // Try to resolve locally without imports
            LClass.MetaclassType.InheritsFrom(TSlimProxyBaseFixture);        // Check if it inherits from our base class (security/consistency check)
        end
        else if (LInstruction = siCall) and (LRawStmt.Count > 2) then
          CheckLocalFixtureInstance(LRawStmt[2].ToString, LIsLocal)
        else if (LInstruction = siCallAndAssign) and (LRawStmt.Count > 3) then
          CheckLocalFixtureInstance(LRawStmt[3].ToString, LIsLocal);

        if LIsLocal then // --- 1. Local Execution ---
        begin
          LStmtResult := inherited ExecuteStmt(LRawStmt, FContext);

          // Inject Executor if it's a make command on a Proxy Fixture
          if (LInstruction = siMake) and Assigned(LStmtResult) and (LStmtResult.Count > 1) and
             (LStmtResult[1].ToString = 'OK') then
          begin
            var LInstName: String := LRawStmt[2].ToString;
            if FContext.Instances.TryGetValue(LInstName, LFixture) and (LFixture is TSlimProxyBaseFixture) then
              (LFixture as TSlimProxyBaseFixture).Executor := Self as ISlimProxyExecutor;
          end;
        end
        else // --- 2. Remote Execution (Forwarding) ---
        begin
          // A 'make' on the same instance name - FitNesse uses 'scriptTableActor'
          // for EVERY script table - would otherwise leave a LOCAL instance from
          // a previous SlimProxy.Core table standing. The next 'call' on that name
          // would then run against the proxy instead of the target and end in
          // NO_METHOD_IN_CLASS.
          if (LInstruction = siMake) and (LRawStmt.Count > 2) then
            DropLocalInstanceShadow(LRawStmt[2].ToString);

          var LRemoteResult: TSlimList;
          if TryForwardToTarget(LRawStmt, LRemoteResult) then
          begin
            // If not local, the remote result is THE result
            LStmtResult.Free;
            LStmtResult := LRemoteResult;
          end
          else
          begin
            // Error: No active target and not handled locally
            // But for import/assign we can ignore/return OK if no target is there.
            LStmtResult.Free;
            if (LInstruction = siImport) or (LInstruction = siAssign) then
              LStmtResult := SlimList([LRawStmt[0].ToString, 'OK'])
            else
              LStmtResult := SlimList([LRawStmt[0].ToString, SlimProxyExceptionResponse(
                'No active target selected and not a local proxy command.')]);
          end;
        end;

        if Assigned(LStmtResult) then
        begin
          if Assigned(FLogger) then
            FLogger.LogResult(LStmtResult);
          Result.Add(LStmtResult);
        end;

        if FStopExecute then
          Break;
      end;
    finally
      if Assigned(FLogger) then
        FLogger.ExitList(ARawStmts);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TSlimProxyExecutor.CheckLocalFixtureInstance(const AInstanceName: String; var AIsLocal: Boolean);
var
  LFixture: TSlimFixture;
begin
  // No 'else if not SameText(..., ''scriptTableActor'')' any more: that left
  // AIsLocal UNCHANGED for an unknown name, i.e. on the value of the PREVIOUS
  // instruction. An unknown instance name always belongs to the target.
  if FContext.Instances.TryGetValue(AInstanceName, LFixture) then
    AIsLocal := LFixture is TSlimProxyBaseFixture
  else
    AIsLocal := False;
end;

procedure TSlimProxyExecutor.DropLocalInstanceShadow(const AInstanceName: String);
var
  LFixture: TSlimFixture;
begin
  if not (Assigned(FContext) and Assigned(FContext.Instances)) then
    Exit;
  if not FContext.Instances.TryGetValue(AInstanceName, LFixture) then
    Exit;
  if LFixture is TSlimProxyBaseFixture then
    TSlimProxyBaseFixture(LFixture).Executor := nil;
  FContext.Instances.Remove(AInstanceName);
end;

end.
