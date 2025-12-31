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
  Slim.Proxy.Interfaces;

type

  TSlimProxyTarget = class
  private
    FClient        : TIdTCPClient;
    FConnectTimeout: Integer;
    FHost          : String;
    FName          : String;
    FPort          : Integer;
  public
    constructor Create(const AName, AHost: String; APort: Integer);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function  SendCommand(ACommand: String): String;
    property  ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
    property  Name: String read FName;
  end;

  TSlimProxyExecutor = class(TSlimExecutor, ISlimProxyExecutor)
  private
    FActiveTarget  : TSlimProxyTarget;
    FConnectTimeout: Integer;
    FTargets       : TObjectDictionary<string, TSlimProxyTarget>;
    function TryForwardToTarget(ARawStmt: TSlimList; out AResult: TSlimList): Boolean;
  public
    constructor Create(AContext: TSlimStatementContext); override;
    destructor Destroy; override;
    function Execute(ARawStmts: TSlimList): TSlimList; override;
    property ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
  public // Target Management
    procedure AddTarget(const AName, AHost: string; APort: Integer);
    procedure DisconnectTarget(const AName: string);
    procedure SwitchToTarget(const AName: string);
  end;

implementation

uses
  Slim.Proxy.Base;

{ TSlimProxyTarget }

constructor TSlimProxyTarget.Create(const AName, AHost: String; APort: Integer);
begin
  inherited Create;
  FName := AName;
  FHost := AHost;
  FPort := APort;
  FClient := TIdTCPClient.Create(nil);
  FConnectTimeout := 20000; // Default 20s
end;

destructor TSlimProxyTarget.Destroy;
begin
  Disconnect;
  FClient.Free;
  inherited;
end;

procedure TSlimProxyTarget.Connect;
var
  LGreeting: String;
  LStart   : Cardinal;
begin
  if FClient.Connected then
    Exit;

  FClient.Host := FHost;
  FClient.Port := FPort;
  FClient.ConnectTimeout := FConnectTimeout;

  LStart := GetTickCount;
  while True do
  begin
    try
      FClient.Connect;
      Break;
    except
      if (GetTickCount - LStart) >= Cardinal(FConnectTimeout) then
        raise;
      TThread.Sleep(100);
    end;
  end;

  // Consume and validate the greeting message from the server (e.g. "Slim -- V0.5")
  LGreeting := FClient.IOHandler.ReadLn;
  if not LGreeting.StartsWith('Slim --') then
  begin
    FClient.Disconnect;
    raise ESlim.CreateFmt('Invalid greeting from target %s:%d: "%s"', [FHost, FPort, LGreeting]);
  end;
end;

procedure TSlimProxyTarget.Disconnect;
begin
  if FClient.Connected then
    FClient.Disconnect;
end;

function TSlimProxyTarget.SendCommand(ACommand: String): String;
var
  LLengthStr     : String;
  LRequestBytes  : TBytes;
  LResponseLength: Integer;
begin
  Connect;

  // Send command
  LRequestBytes := TEncoding.UTF8.GetBytes(ACommand);
  LLengthStr := Format('%.6d:', [Length(LRequestBytes)]);
  FClient.IOHandler.Write(LLengthStr);
  FClient.IOHandler.Write(TIdBytes(LRequestBytes));

  // Read response
  LLengthStr := FClient.IOHandler.ReadString(6);
  if not TryStrToInt(LLengthStr, LResponseLength) then
    raise ESlim.CreateFmt('Invalid response length: "%s"', [LLengthStr]);

  // Read colon
  FClient.IOHandler.ReadString(1);

  Result := FClient.IOHandler.ReadString(LResponseLength, IndyTextEncoding_UTF8);
end;

{ TSlimProxyExecutor }

constructor TSlimProxyExecutor.Create(AContext: TSlimStatementContext);
begin
  inherited Create(AContext);
  ManageInstances := True; // Proxy needs to manage instances too
  FTargets := TObjectDictionary<String, TSlimProxyTarget>.Create([doOwnsValues]);
  if FManageInstances then
     FContext.SetInstances(TSlimFixtureDictionary.Create([doOwnsValues]), True);
  FConnectTimeout := 20000; // Default 20s
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

procedure TSlimProxyExecutor.AddTarget(const AName, AHost: String; APort: Integer);
var
  LTarget: TSlimProxyTarget;
begin
  if FTargets.ContainsKey(AName) then
    raise ESlim.CreateFmt('Target with name "%s" already exists.', [AName]);

  LTarget := TSlimProxyTarget.Create(AName, AHost, APort);
  LTarget.ConnectTimeout := FConnectTimeout; // Pass timeout to target
  FTargets.Add(AName, LTarget);
  LTarget.Connect;
end;

procedure TSlimProxyExecutor.SwitchToTarget(const AName: String);
begin
  if not FTargets.TryGetValue(AName, FActiveTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
end;

procedure TSlimProxyExecutor.DisconnectTarget(const AName: String);
var
  LTarget: TSlimProxyTarget;
begin
  if FTargets.TryGetValue(AName, LTarget) then
  begin
    if FActiveTarget = LTarget then
      FActiveTarget := nil;
    FTargets.Remove(AName);
  end;
end;

function TSlimProxyExecutor.TryForwardToTarget(ARawStmt: TSlimList; out AResult: TSlimList): Boolean;
var
  LCommandStr  : String;
  LResponseStr : String;
  LResponseList: TSlimList;
  LId          : String;
begin
  Result := False;
  AResult := nil;
  LResponseList := nil;
  if not Assigned(FActiveTarget) then
    Exit;

  LId := ARawStmt[0].ToString;
  var LForwardList := TSlimList.Create;
  try
    try
      LForwardList.Add(ARawStmt); // Wrap in list as expected by Slim Server
      LCommandStr := SlimListSerialize(LForwardList);
      LResponseStr := FActiveTarget.SendCommand(LCommandStr);
      LResponseList := SlimListUnserialize(LResponseStr);

      // Expecting list of results: [[id, result]]
      if (LResponseList.Count > 0) and (LResponseList[0] is TSlimList) then
      begin
         // Extract the inner list which is the actual result for the statement
         AResult := TSlimList(LResponseList.Extract(LResponseList[0]));
      end
      else
        raise ESlim.Create('Invalid response format from target');

      Result := True;
    except
      on E: Exception do
      begin
        AResult := SlimList([LId, TSlimConsts.ExceptionResponse + E.Message]);
        Result := True; // Handled, but with error result
      end;
    end;
  finally
    // ARawStmt belongs to the caller (ARawStmts list in Execute).
    // LForwardList.Add took ownership. We must extract it back to prevent
    // LForwardList.Free from destroying ARawStmt.
    LForwardList.Extract(ARawStmt);
    LForwardList.Free;
    LResponseList.Free;
  end;
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
        end;

        if LIsLocal then // --- 1. Local Execution ---
        begin
          LStmtResult := inherited ExecuteStmt(LRawStmt, FContext);

          // Inject Executor if it's a make command on a Proxy Fixture
          if (LInstruction = siMake) and Assigned(LStmtResult) and (LStmtResult.Count > 1) and (LStmtResult[1].ToString = 'OK') then
          begin
             var LInstName := LRawStmt[2].ToString;
             if FContext.Instances.TryGetValue(LInstName, LFixture) and (LFixture is TSlimProxyBaseFixture) then
             begin
               (LFixture as TSlimProxyBaseFixture).Executor := Self as ISlimProxyExecutor;
             end;
          end;
        end
        else // --- 2. Remote Execution (Forwarding) ---
        begin
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
             if (LInstruction = siImport) or (LInstruction = siAssign) then
             begin
               LStmtResult.Free;
               LStmtResult := SlimList([LRawStmt[0].ToString, 'OK']);
             end
             else
             begin
               LStmtResult.Free;
               LStmtResult := SlimList([LRawStmt[0].ToString, TSlimConsts.ExceptionResponse + 'No active target selected and not a local proxy command.']);
             end;
          end;
        end;

        if Assigned(LStmtResult) then
          Result.Add(LStmtResult);

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

end.
