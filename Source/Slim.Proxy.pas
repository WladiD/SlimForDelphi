unit Slim.Proxy;

interface

uses
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
    FName: string;
    FHost: string;
    FPort: Integer;
  public
    constructor Create(const AName, AHost: string; APort: Integer);
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    function SendCommand(ACommand: string): string;

    property Name: string read FName;
  end;

  TSlimProxyExecutor = class(TSlimExecutor, ISlimProxyExecutor)
  private
    FProxyFixtureNames: TStringList;
    FTargets: TObjectDictionary<string, TSlimProxyTarget>;
    FActiveTarget: TSlimProxyTarget;
    function IsProxyCommand(ARawStmt: TSlimList): Boolean;
    procedure GetProxyFixtureNames;
  public
    constructor Create(AContext: TSlimStatementContext); override;
    destructor Destroy; override;
    function Execute(ARawStmts: TSlimList): TSlimList; override;

    // Target Management
    procedure AddTarget(const AName, AHost: string; APort: Integer);
    procedure SwitchToTarget(const AName: string);
    procedure DisconnectTarget(const AName: string);
  end;

implementation

uses
  System.TypInfo,
  Slim.Common;

{ TSlimProxyTarget }

constructor TSlimProxyTarget.Create(const AName, AHost: string; APort: Integer);
begin
  inherited Create;
  FName := AName;
  FHost := AHost;
  FPort := APort;
  FClient := TIdTCPClient.Create(nil);
end;

destructor TSlimProxyTarget.Destroy;
begin
  Disconnect;
  FClient.Free;
  inherited;
end;

procedure TSlimProxyTarget.Connect;
begin
  if FClient.Connected then
    Exit;

  FClient.Host := FHost;
  FClient.Port := FPort;
  FClient.Connect;
end;

procedure TSlimProxyTarget.Disconnect;
begin
  if FClient.Connected then
    FClient.Disconnect;
end;

function TSlimProxyTarget.SendCommand(ACommand: string): string;
var
  LRequestBytes: TBytes;
  LLengthStr: string;
  LResponseLength: Integer;
begin
  Connect; // Ensure connection

  // Send command
  LRequestBytes := TEncoding.UTF8.GetBytes(ACommand);
  LLengthStr := Format('%.6x:', [Length(LRequestBytes)]);
  FClient.IOHandler.Write(LLengthStr);
  FClient.IOHandler.Write(TIdBytes(LRequestBytes));

  // Read response
  LLengthStr := FClient.IOHandler.ReadString(6);
  if not TryStrToInt('$' + LLengthStr, LResponseLength) then
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
  FTargets := TObjectDictionary<string, TSlimProxyTarget>.Create([doOwnsValues]);
  GetProxyFixtureNames;
end;

destructor TSlimProxyExecutor.Destroy;
begin
  FActiveTarget := nil;
  FreeAndNil(FTargets);
  FProxyFixtureNames.Free;
  inherited;
end;

procedure TSlimProxyExecutor.AddTarget(const AName, AHost: string; APort: Integer);
var
  LTarget: TSlimProxyTarget;
begin
  if FTargets.ContainsKey(AName) then
    raise ESlim.CreateFmt('Target with name "%s" already exists.', [AName]);

  LTarget := TSlimProxyTarget.Create(AName, AHost, APort);
  FTargets.Add(AName, LTarget);
end;

procedure TSlimProxyExecutor.SwitchToTarget(const AName: string);
begin
  if not FTargets.TryGetValue(AName, FActiveTarget) then
    raise ESlim.CreateFmt('Target with name "%s" not found.', [AName]);
end;

procedure TSlimProxyExecutor.DisconnectTarget(const AName: string);
var
  LTargetName: string;
  LTarget: TSlimProxyTarget;
begin
  LTargetName := AName;
  if (LTargetName = '') and Assigned(FActiveTarget) then
    LTargetName := FActiveTarget.Name;

  if FTargets.TryGetValue(LTargetName, LTarget) then
  begin
    if FActiveTarget = LTarget then
      FActiveTarget := nil;

    FTargets.Remove(LTargetName);
  end;
end;

function TSlimProxyExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  LStmtResult: TSlimList;
  LRawStmt: TSlimList;
  LId, LCommandStr, LResponseStr: string;
  LRawStmtEntry: TSlimEntry;
  I: Integer;
begin
  LStmtResult := nil;
  Result := TSlimList.Create;
  try
    FStopExecute := False;
    for I := 0 to ARawStmts.Count - 1 do
    begin
      LRawStmtEntry := ARawStmts[I];
      if not (LRawStmtEntry is TSlimList) then
        continue;

      LRawStmt := LRawStmtEntry as TSlimList;
      LId := LRawStmt[0].ToString;

      if IsProxyCommand(LRawStmt) then
      begin
        LStmtResult := inherited ExecuteStmt(LRawStmt, FContext);
        // Post-execution logic: Inject executor into newly created proxy fixtures
        if SameText(LRawStmt[1].ToString, 'make') then
        begin
          var LInstanceName := LRawStmt[2].ToString;
          var LClassName := LRawStmt[3].ToString;
          if FProxyFixtureNames.IndexOf(LClassName) > -1 then
          begin
            var LFixture: TSlimFixture;
            if FContext.Instances.TryGetValue(LInstanceName, LFixture) and (LFixture is TSlimProxyFixture) then
            begin
              (LFixture as TSlimProxyFixture).Executor := Self as ISlimProxyExecutor;
            end;
          end;
        end;
      end
      else
      begin
        if Assigned(FActiveTarget) then
        begin
          var LForwardList := TSlimList.Create;
          try
            try
              LForwardList.Add(LRawStmt);
              LCommandStr := SlimListSerialize(LForwardList);
              LResponseStr := FActiveTarget.SendCommand(LCommandStr);
              LStmtResult := SlimListUnserialize(LResponseStr);
              // The result from a single command is a list containing the result list
              // e.g. [[<id>, OK]] -> we need to extract the inner list
              if (LStmtResult.Count > 0) and (LStmtResult[0] is TSlimList) then
                LStmtResult := LStmtResult[0] as TSlimList
              else
                raise ESlim.Create('Invalid response format from target');
            except
              on E: Exception do
                LStmtResult := SlimList([LId, TSlimConsts.ExceptionResponse + E.Message]);
            end;
          finally
            LForwardList.Free;
          end;
        end
        else
        begin
          LStmtResult := SlimList([LId, TSlimConsts.ExceptionResponse + 'No active target selected.']);
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

procedure TSlimProxyExecutor.GetProxyFixtureNames;
var
  LType: TRttiType;
  LAttribute: TCustomAttribute;
  LRttiContext: TRttiContext;
  LFixtureAttr: SlimFixtureAttribute;
begin
  FProxyFixtureNames := TStringList.Create;
  LRttiContext := TRttiContext.Create;
  try
    LType := LRttiContext.GetType(TSlimProxyFixture);
    if Assigned(LType) then
    begin
      FProxyFixtureNames.Add(LType.Name); // Add the class name, e.g., 'TSlimProxyFixture'
      for LAttribute in LType.GetAttributes do
      begin
        if LAttribute is SlimFixtureAttribute then
        begin
          LFixtureAttr := LAttribute as SlimFixtureAttribute;
          FProxyFixtureNames.Add(LFixtureAttr.Name); // Add the fixture name, e.g., 'SlimProxy'
          if LFixtureAttr.Namespace <> '' then
            FProxyFixtureNames.Add(LFixtureAttr.Namespace + '.' + LFixtureAttr.Name);
        end;
      end;
    end;
  finally
    LRttiContext.Free;
  end;
end;

function TSlimProxyExecutor.IsProxyCommand(ARawStmt: TSlimList): Boolean;
var
  Instr, ClassOrInstanceName: string;
  LFixture: TSlimFixture;
begin
  Result := False;
  if ARawStmt.Count < 2 then
    Exit;

  Instr := ARawStmt[1].ToString;

  if SameText(Instr, 'import') then
  begin
    // Imports are always handled by the current context (proxy)
    Result := True;
    Exit;
  end;

  if (ARawStmt.Count < 3) then
    Exit;

  if SameText(Instr, 'make') then
  begin
    // Check class name: [<id>, make, <instance>, <class>, ...]
    if ARawStmt.Count > 3 then
    begin
      ClassOrInstanceName := ARawStmt[3].ToString;
      Result := FProxyFixtureNames.IndexOf(ClassOrInstanceName) > -1;
    end;
  end
  else if SameText(Instr, 'call') or SameText(Instr, 'callAndAssign') then
  begin
    // Check instance name: [<id>, call, <instance>, <function>, ...]
    ClassOrInstanceName := ARawStmt[2].ToString;

    // Is the instance one of the proxy's instances?
    if FContext.Instances.TryGetValue(ClassOrInstanceName, LFixture) then
    begin
      // It's a proxy command if the fixture instance is one of our proxy fixture types.
      Result := (LFixture is TSlimProxyFixture);
    end;
  end;
end;

end.
