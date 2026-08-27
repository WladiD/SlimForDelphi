// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Test helpers for the proxy tests: an in process Slim target that can be
///   made to misbehave on purpose, free port lookup, and the path of the
///   SlimVerify simulation target.
/// </summary>
unit Test.SlimProxy.Helpers;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.SysUtils,

  IdContext,
  IdCustomTCPServer,
  IdGlobal,
  IdIOHandler,
  IdTCPServer,

  Slim.List;

type

  TFakeTargetMode = (
    /// <summary>Speaks the handshake, reads the command and answers correctly.</summary>
    ftmAnswer,
    /// <summary>
    ///   Speaks the handshake, reads the command and NEVER answers - the case
    ///   that hangs a whole run without a read timeout.
    /// </summary>
    ftmStall,
    /// <summary>Accepts the connection and sends a greeting that is not Slim.</summary>
    ftmBadGreeting);

  /// <summary>
  ///   A Slim target inside the test process. Deterministic and fast: testing the
  ///   read timeout needs no foreign application and no build step.
  /// </summary>
  TFakeSlimTarget = class
  private
    FAnswerDelayMs: Integer;
    FMode         : TFakeTargetMode;
    FPort         : Integer;
    FReceived     : Integer;
    FServer       : TIdTCPServer;
    FStallMs      : Integer;
    FStopping     : Boolean;
    procedure WaitInterruptible(AMilliseconds: Integer);
    procedure ServerConnect(AContext: TIdContext);
    procedure ServerException(AContext: TIdContext; AException: Exception);
    procedure ServerExecute(AContext: TIdContext);
    function  ReadRequest(AIo: TIdIOHandler): String;
  public
    constructor Create(AMode: TFakeTargetMode);
    destructor Destroy; override;
    /// <summary>Delay before the answer is written, in ms. Only for ftmAnswer.</summary>
    property AnswerDelayMs: Integer read FAnswerDelayMs write FAnswerDelayMs;
    property Mode: TFakeTargetMode read FMode write FMode;
    property Port: Integer read FPort;
    /// <summary>Number of commands that were read.</summary>
    property Received: Integer read FReceived;
    /// <summary>Upper bound for the stall, in ms. Keeps the tests from wedging.</summary>
    property StallMs: Integer read FStallMs write FStallMs;
  end;

  /// <summary>
  ///   A plain listening socket that accepts a connection and drops it again.
  ///   Used to occupy a port on purpose - the owner of the socket is then this
  ///   very process, which is what the ownership check has to report.
  /// </summary>
  TTestListener = class
  private
    FServer: TIdTCPServer;
    procedure ServerExecute(AContext: TIdContext);
  public
    constructor Create(APort: Integer);
    destructor Destroy; override;
    function Port: Integer;
  end;

function TestFindFreePort: Integer;

function TestSlimVerifyExePath: String;

implementation

const
  FirstCandidatePort = 19100;
  StallDefaultMs     = 30000;

{ TFakeSlimTarget }

constructor TFakeSlimTarget.Create(AMode: TFakeTargetMode);
begin
  inherited Create;
  FMode := AMode;
  FStallMs := StallDefaultMs;
  FServer := TIdTCPServer.Create(nil);
  FServer.OnConnect := ServerConnect;
  FServer.OnExecute := ServerExecute;
  FServer.OnException := ServerException;

  for var LPort: Integer := FirstCandidatePort to FirstCandidatePort + 200 do
    try
      FServer.DefaultPort := LPort;
      FServer.Active := True;
      FPort := LPort;
      Break;
    except
      FServer.Active := False;
    end;

  if FPort = 0 then
    raise Exception.Create('No free port found for the fake Slim target.');
end;

destructor TFakeSlimTarget.Destroy;
begin
  // Set the flag BEFORE deactivating: Indy waits for its context threads while
  // shutting down, and a thread that is still sleeping in a stall would hold the
  // whole test run for as long as the stall lasts.
  FStopping := True;
  FServer.Active := False;
  FServer.Free;
  inherited;
end;

/// <summary>Waits, but gives up as soon as the target is being torn down.</summary>
procedure TFakeSlimTarget.WaitInterruptible(AMilliseconds: Integer);
var
  LStart: Cardinal;
begin
  LStart := GetTickCount;
  while (GetTickCount - LStart < Cardinal(AMilliseconds)) and not FStopping do
    Sleep(25);
end;

procedure TFakeSlimTarget.ServerConnect(AContext: TIdContext);
begin
  if FMode = ftmBadGreeting then
    AContext.Connection.IOHandler.WriteLn('Hello, I am not a Slim server')
  else
    AContext.Connection.IOHandler.WriteLn('Slim -- V0.5');
end;

procedure TFakeSlimTarget.ServerException(AContext: TIdContext; AException: Exception);
begin
  // A client that walks away is the normal end of a test - nothing to report.
end;

function TFakeSlimTarget.ReadRequest(AIo: TIdIOHandler): String;
var
  LLength: Integer;
begin
  var LLengthStr: String := AIo.ReadString(6);
  if not TryStrToInt(LLengthStr, LLength) then
    raise Exception.CreateFmt('Invalid length "%s"', [LLengthStr]);
  AIo.ReadString(1); // colon
  Result := AIo.ReadString(LLength, IndyTextEncoding_UTF8);
end;

procedure TFakeSlimTarget.ServerExecute(AContext: TIdContext);
var
  LIo      : TIdIOHandler;
  LRequest : TSlimList;
  LResponse: TSlimList;
begin
  LIo := AContext.Connection.IOHandler;
  var LRequestStr: String := ReadRequest(LIo);
  TInterlocked.Increment(FReceived);

  if FMode = ftmStall then
  begin
    // Read the command and never answer. Bounded so a test cannot wedge the
    // whole run, and cut short as soon as the target is being torn down.
    WaitInterruptible(FStallMs);
    Exit;
  end;

  if FAnswerDelayMs > 0 then
    WaitInterruptible(FAnswerDelayMs);

  LRequest := SlimListUnserialize(LRequestStr);
  try
    var LId: String := 'unknown_id';
    if (LRequest.Count > 0) and (LRequest[0] is TSlimList) and (TSlimList(LRequest[0]).Count > 0) then
      LId := TSlimList(LRequest[0])[0].ToString;

    LResponse := SlimList([SlimList([LId, 'OK'])]);
    try
      var LBody: TIdBytes := ToBytes(SlimListSerialize(LResponse), IndyTextEncoding_UTF8);
      LIo.Write(Format('%.6d:', [Length(LBody)]));
      LIo.Write(LBody);
    finally
      LResponse.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

{ Helpers }

{ TTestListener }

constructor TTestListener.Create(APort: Integer);
begin
  inherited Create;
  FServer := TIdTCPServer.Create(nil);
  // Indy refuses to become active without an OnExecute handler.
  FServer.OnExecute := ServerExecute;
  FServer.DefaultPort := APort;
  FServer.Active := True;
end;

destructor TTestListener.Destroy;
begin
  FServer.Active := False;
  FServer.Free;
  inherited;
end;

function TTestListener.Port: Integer;
begin
  Result := FServer.DefaultPort;
end;

procedure TTestListener.ServerExecute(AContext: TIdContext);
begin
  AContext.Connection.Disconnect;
end;

/// <summary>
///   A port nobody is listening on. Determined by actually binding it, so the
///   answer is not a guess.
/// </summary>
function TestFindFreePort: Integer;
var
  LListener: TTestListener;
begin
  for var LPort: Integer := FirstCandidatePort + 300 to FirstCandidatePort + 500 do
  begin
    LListener := nil;
    try
      try
        LListener := TTestListener.Create(LPort);
      except
        Continue;
      end;
      Exit(LPort);
    finally
      LListener.Free;
    end;
  end;
  raise Exception.Create('No free port found.');
end;

/// <summary>
///   Path of the built SlimVerify simulation target, or an empty string if it has
///   not been built. Tests that need it report themselves as passed with a note
///   instead of failing on somebody else's build state.
/// </summary>
function TestSlimVerifyExePath: String;
var
  LBase: String;
begin
  // The test executable lives in Test\<Platform>\<Config>, the simulation target
  // in Test\SlimVerify\<Platform>\<Config>.
  LBase := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\SlimVerify'));
  for var LPlatform in TArray<String>.Create({$IFDEF WIN64} 'Win64', 'Win32' {$ELSE} 'Win32', 'Win64' {$ENDIF}) do
    for var LConfig in TArray<String>.Create('Debug', 'Release') do
    begin
      Result := TPath.Combine(TPath.Combine(TPath.Combine(LBase, LPlatform), LConfig), 'SlimVerify.exe');
      if TFile.Exists(Result) then
        Exit;
    end;
  Result := '';
end;

end.
