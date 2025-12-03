unit Slim.Proxy;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Rtti,
  IdTCPClient,
  IdGlobal,
  Slim.Exec,
  Slim.List,
  Slim.Fixture,
  Slim.Proxy.Fixtures;

type

  TSlimProxyTarget = class
  private
    FClient: TIdTCPClient;
    FHost: String;
    FName: String;
    FPort: Integer;
    FConnectTimeout: Integer;
  public
    constructor Create(const AName, AHost: String; APort: Integer);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function  SendCommand(ACommand: String): String;
    property  Name: String read FName;
    property  ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
  end;

  TSlimProxyExecutor = class(TSlimExecutor, ISlimProxyExecutor)
  private
    FActiveTarget: TSlimProxyTarget;
    FTargets: TObjectDictionary<string, TSlimProxyTarget>;
    FConnectTimeout: Integer;
    function TryForwardToTarget(ARawStmt: TSlimList; out AResult: TSlimList): Boolean;
  public
    constructor Create(AContext: TSlimStatementContext); override;
    destructor Destroy; override;
    function Execute(ARawStmts: TSlimList): TSlimList; override;
    property ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
  public // Target Management
    procedure AddTarget(const AName, AHost: string; APort: Integer);
    procedure SwitchToTarget(const AName: string);
    procedure DisconnectTarget(const AName: string);
  end;

implementation

uses
  System.TypInfo,
  Slim.Common;

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
  LStart: Cardinal;
begin
  if FClient.Connected then
    Exit;

  FClient.Host := FHost;
  FClient.Port := FPort;

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
  LRequestBytes: TBytes;
  LLengthStr: String;
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
      if LFixture is TSlimProxyFixture then
        TSlimProxyFixture(LFixture).Executor := nil;
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
  LCommandStr: String;
  LResponseStr: String;
  LResponseList: TSlimList;
  LId: String;
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
  LStmtResult: TSlimList;
  LRawStmt: TSlimList;
  LInstr: String;
  LRawStmtEntry: TSlimEntry;
  I: Integer;
  LIsLocal: Boolean;
  LClass: TRttiInstanceType;
  LFixture: TSlimFixture;
begin
  Result := TSlimList.Create;
  try
    FStopExecute := False;

    for I := 0 to ARawStmts.Count - 1 do
    begin
      LStmtResult := nil;
      LRawStmtEntry := ARawStmts[I];
      if not (LRawStmtEntry is TSlimList) then
        continue;

      LRawStmt := LRawStmtEntry as TSlimList;
      if LRawStmt.Count > 1 then
        LInstr := LRawStmt[1].ToString
      else
        LInstr := '';

      LIsLocal := False;

      // --- Decision Logic: Local or Remote? ---

      if SameText(LInstr, 'import') then
      begin
        // Import is always executed locally AND broadcasted
        LIsLocal := True;
      end
      else if SameText(LInstr, 'make') and (LRawStmt.Count > 3) then
      begin
        // Check if the class exists locally and is a Proxy Fixture
        if FContext.Resolver.TryGetSlimFixture(LRawStmt[3].ToString, FContext.ImportedNamespaces, LClass) then
        begin
          if LClass.MetaclassType.InheritsFrom(TSlimProxyFixture) then
            LIsLocal := True;
        end;
      end
      else if SameText(LInstr, 'call') and (LRawStmt.Count > 2) then
      begin
        // Check if instance is local
        if FContext.Instances.TryGetValue(LRawStmt[2].ToString, LFixture) then
           LIsLocal := True;
      end
      else if SameText(LInstr, 'callAndAssign') and (LRawStmt.Count > 3) then
      begin
        // Check if instance is local
        if FContext.Instances.TryGetValue(LRawStmt[3].ToString, LFixture) then
           LIsLocal := True;
      end
      else if SameText(LInstr, 'assign') then
      begin
         // Assign is usually a local operation (storing symbols)
         LIsLocal := True;
      end;

      // --- 1. Local Execution ---
      if LIsLocal then
      begin
        // Special case: Directly create TSlimProxyFixture to bypass problematic RTTI constructor invocation
        if SameText(LInstr, 'make') and (LRawStmt.Count > 3) and SameText(LRawStmt[3].ToString, 'SlimProxy') then
        begin
          var LInstName := LRawStmt[2].ToString;
          var LProxyFixture: TSlimProxyFixture := TSlimProxyFixture.Create; // Direct instantiation
          FContext.Instances.AddOrSetValue(LInstName, LProxyFixture);
          LProxyFixture.Executor := Self as ISlimProxyExecutor; // Inject executor
          LStmtResult := SlimList([LRawStmt[0].ToString, 'OK']); // Simulate successful make response
        end
        else // Normal local execution
        begin
          LStmtResult := inherited ExecuteStmt(LRawStmt, FContext);

          // Special Post-Execution Logic for 'make' on ProxyFixtures
          if SameText(LInstr, 'make') and Assigned(LStmtResult) and (LStmtResult.Count > 1) and (LStmtResult[1].ToString = 'OK') then
          begin
             var LInstName := LRawStmt[2].ToString;
             if FContext.Instances.TryGetValue(LInstName, LFixture) and (LFixture is TSlimProxyFixture) then
             begin
               (LFixture as TSlimProxyFixture).Executor := Self as ISlimProxyExecutor;
             end;
          end;
        end;
      end;

      // --- 2. Remote Execution (Forwarding) ---
      // Forward if NOT Local OR if it is 'import' (Broadcast)
      if (not LIsLocal) or SameText(LInstr, 'import') then
      begin
        var LRemoteResult: TSlimList;
        if TryForwardToTarget(LRawStmt, LRemoteResult) then
        begin
          if not LIsLocal then
          begin
            // If not local, the remote result is THE result
            LStmtResult.Free;
            LStmtResult := LRemoteResult;
          end
          else
          begin
            // If it was local (e.g. Import), we prioritize local success, but we must free the remote result
            // Ideally, if remote fails, we might want to warn, but for 'import', usually OK is expected.
            if Assigned(LRemoteResult) then LRemoteResult.Free;
          end;
        end
        else if not LIsLocal then
        begin
           // Error: No active target and not handled locally
           LStmtResult.Free;
           LStmtResult := SlimList([LRawStmt[0].ToString, TSlimConsts.ExceptionResponse + 'No active target selected and not a local proxy command.']);
        end;
      end;

      if Assigned(LStmtResult) then
        Result.Add(LStmtResult);

      if FStopExecute then
        Break;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.