unit FitNesseMcp.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.json,
  mormot.core.data,
  mormot.core.text,
  mormot.core.variants,
  mormot.core.rtti,
  FitNesseMcp.Config,
  FitNesseMcp.FitNesseClient;

type
  TFitNesseMcpServer = class
  private
    FConfig: TFitNesseConfig;
    FIsRunning: Boolean;
    FLastStartedInstance: string;
    procedure Log(const AMsg: string);
    procedure HandleRequest(const AJson: RawUtf8);
    procedure SendResponse(const AResponse: String);
    procedure SendError(const AId: Variant; ACode: Integer; const AMessage: string);
    
    // MCP Handlers
    procedure HandleInitialize(const AId: Variant; const AParams: Variant);
    procedure HandleListTools(const AId: Variant);
    procedure HandleCallTool(const AId: Variant; const AParams: Variant);
    procedure HandleListResources(const AId: Variant);
    procedure HandleReadResource(const AId: Variant; const AParams: Variant);

    // Tool Implementations
    function DoRunTest(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
    function DoGetTestResult(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
    function DoGetPageContent(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
    function DoStartInstance(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
    function DoListPages(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
    function DoListInstances: RawUtf8;
  public
    constructor Create;
    procedure Run;
  end;

implementation

{ TFitNesseMcpServer }

constructor TFitNesseMcpServer.Create;
var
  LConfigPath: string;
begin
  inherited Create;
  LConfigPath := ExtractFilePath(ParamStr(0)) + 'fitnesse-config.json';
  if FConfig.LoadFromFile(LConfigPath) then
  begin
    Log('Config loaded successfully from: ' + LConfigPath);
    if Length(FConfig.instances) > 0 then
      FLastStartedInstance := FConfig.instances[0].name;
  end
  else
    Log('WARNING: Could not load fitnesse-config.json from: ' + LConfigPath);
end;

procedure TFitNesseMcpServer.Log(const AMsg: string);
begin
  Writeln(ErrOutput, '[Server] ' + AMsg);
  Flush(ErrOutput);
end;

procedure TFitNesseMcpServer.Run;
var
  LInput: string;
begin
  Log('Entering Run loop...');
  FIsRunning := True;
  
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);

  while FIsRunning and not Eof(Input) do
  begin
    Readln(LInput);
    if LInput <> '' then
    begin
      Log('>> ' + LInput);
      HandleRequest(StringToUtf8(LInput));
    end;
  end;
  Log('Exiting Run loop.');
end;

procedure TFitNesseMcpServer.HandleRequest(const AJson: RawUtf8);
var
  LDoc: Variant;
  LMethod: string;
  LId: Variant;
begin
  try
    LDoc := _Json(AJson);
    LMethod := LDoc.method;
    LId := LDoc.id;

    Log('Method: ' + LMethod);

    if LMethod = 'initialize' then
      HandleInitialize(LId, LDoc.params)
    else if LMethod = 'tools/list' then
      HandleListTools(LId)
    else if LMethod = 'tools/call' then
      HandleCallTool(LId, LDoc.params)
    else if LMethod = 'resources/list' then
      HandleListResources(LId)
    else if LMethod = 'resources/read' then
      HandleReadResource(LId, LDoc.params)
    else if LMethod = 'notifications/initialized' then
      Log('Initialized notification received.')
    else
      SendError(LId, -32601, 'Method not found: ' + LMethod);
  except
    on E: Exception do
    begin
      Log('EXCEPTION in HandleRequest: ' + E.Message);
      if VarIsEmptyOrNull(LId) then
        LId := Null;
      SendError(LId, -32603, 'Internal error: ' + E.Message);
    end;
  end;
end;

procedure TFitNesseMcpServer.SendResponse(const AResponse: String);
begin
  Log('<< ' + AResponse);
  Writeln(AResponse);
  Flush(Output);
end;

procedure TFitNesseMcpServer.SendError(const AId: Variant; ACode: Integer; const AMessage: string);
var
  LRes: Variant;
begin
  TDocVariant.New(LRes);
  LRes.jsonrpc := '2.0';
  LRes.id := AId;
  LRes.error := _Obj(['code', ACode, 'message', AMessage]);
  SendResponse(VariantToString(_Json(VariantToUtf8(LRes))));
end;

procedure TFitNesseMcpServer.HandleInitialize(const AId: Variant; const AParams: Variant);
var
  LRes: Variant;
begin
  TDocVariant.New(LRes);
  LRes.jsonrpc := '2.0';
  LRes.id := AId;
  LRes.result := _Obj([
    'protocolVersion', '2024-11-05',
    'capabilities', _Obj([
      'tools', _Obj([]),
      'resources', _Obj([])
    ]),
    'serverInfo', _Obj([
      'name', 'FitNesseMcpServer',
      'version', '1.0.0'
    ])
  ]);
  SendResponse(VariantToString(_Json(VariantToUtf8(LRes))));
end;

procedure TFitNesseMcpServer.HandleListTools(const AId: Variant);
var
  LRes: Variant;
begin
  TDocVariant.New(LRes);
  LRes.jsonrpc := '2.0';
  LRes.id := AId;
  LRes.result := _Obj([
    'tools', _Arr([
      _Obj([
        'name', 'run_test',
        'description', 'Executes a FitNesse test or suite. Returns a compact JUnit XML report by default. Use ''xml'' format for full details or inspect historical results via ''get_test_result'' using the timestamp from the output.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance (optional, defaults to first configured instance)']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path of the test page or suite']),
            'format', _Obj(['type', 'string', 'description', 'Output format: "junit" (default, compact summary) or "xml" (verbose details).', 'default', 'junit'])
          ]),
          'required', _Arr(['pagePath'])
        ])
      ]),
      _Obj([
        'name', 'get_test_result',
        'description', 'Retrieves the full execution log (verbose XML) for a specific past test run. Use the timestamp found in the ''run_test'' output.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance (optional, defaults to first configured instance)']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path of the test page or suite']),
            'resultDate', _Obj(['type', 'string', 'description', 'Timestamp of the result (YYYYMMDDHHMMSS)'])
          ]),
          'required', _Arr(['pagePath', 'resultDate'])
        ])
      ]),
      _Obj([
        'name', 'get_page_content',
        'description', 'Gets the wiki source of a FitNesse page directly from the filesystem. Returns the full file path and the content.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance (optional, defaults to first configured instance)']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path of the page'])
          ]),
          'required', _Arr(['pagePath'])
        ])
      ]),
      _Obj([
        'name', 'start_instance',
        'description', 'Starts a FitNesse instance by running the java process.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance'])
          ]),
          'required', _Arr(['instance'])
        ])
      ]),
      _Obj([
        'name', 'list_pages',
        'description', 'Lists all suites and tests at a given wiki path.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance (optional, defaults to first configured instance)']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path to list (empty for root)']),
            'recursive', _Obj(['type', 'boolean', 'description', 'If true, lists all pages recursively.', 'default', false])
          ]),
          'required', _Arr(['pagePath'])
        ])
      ]),
      _Obj([
        'name', 'list_instances',
        'description', 'Lists all configured FitNesse instances and their status.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([]),
          'required', _Arr([])
        ])
      ])
    ])
  ]);
  SendResponse(VariantToString(_Json(VariantToUtf8(LRes))));
end;

function TFitNesseMcpServer.DoRunTest(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
var
  LPagePath: string;
begin
  LPagePath := VarToStr(AArgs.pagePath);
  if AArgs.Exists('format') then
    Result := AClient.RunTest(LPagePath, VarToStr(AArgs.format))
  else
    Result := AClient.RunTest(LPagePath, 'junit');
end;

function TFitNesseMcpServer.DoGetTestResult(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
begin
  Result := AClient.GetTestResult(VarToStr(AArgs.pagePath), VarToStr(AArgs.resultDate));
end;

function TFitNesseMcpServer.DoGetPageContent(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
var
  LRes: Variant;
begin
  LRes := _Json(AClient.GetPageContent(VarToStr(AArgs.pagePath)));
  if LRes.Exists('error') then
    Result := VariantToUtf8(LRes.error)
  else
    Result := 'File: ' + VariantToUtf8(LRes.filePath) + StringToUtf8(#13#10'---'#13#10) + VariantToUtf8(LRes.content);
end;

function TFitNesseMcpServer.DoStartInstance(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
begin
  if AClient.CheckIfRunning then
  begin
    FLastStartedInstance := VarToStr(AArgs.instance);
    Result := 'Instance is already running.';
  end
  else if AClient.StartInstance then
  begin
    FLastStartedInstance := VarToStr(AArgs.instance);
    Result := 'Instance started successfully.';
  end
  else
    Result := 'Failed to start instance. Check server logs (stderr).';
end;

function TFitNesseMcpServer.DoListPages(const AClient: TFitNesseClient; const AArgs: Variant): RawUtf8;
var
  LPagePath: string;
begin
  LPagePath := VarToStr(AArgs.pagePath);
  if AArgs.Exists('recursive') then
    Result := AClient.ListPages(LPagePath, Boolean(AArgs.recursive))
  else
    Result := AClient.ListPages(LPagePath, False);
end;

function TFitNesseMcpServer.DoListInstances: RawUtf8;
var
  LRes: Variant;
  LClient: TFitNesseClient;
begin
  TDocVariant.New(LRes);
  LRes.instances := _Arr([]);
  for var i := 0 to High(FConfig.instances) do
  begin
    LClient := TFitNesseClient.Create(FConfig.instances[i]);
    try
      FConfig.instances[i].isRunning := LClient.CheckIfRunning;
      LRes.instances.Add(_Obj([
        'name', FConfig.instances[i].name,
        'baseUrl', FConfig.instances[i].GetEffectiveBaseUrl,
        'rootPath', FConfig.instances[i].rootPath,
        'fitnesseRoot', FConfig.instances[i].GetEffectiveFitNesseRoot,
        'port', FConfig.instances[i].port,
        'startCmdLine', FConfig.instances[i].startCmdLine,
        'isRunning', FConfig.instances[i].isRunning
      ]));
    finally
      LClient.Free;
    end;
  end;
  Result := VariantSaveJSON(LRes);
end;

procedure TFitNesseMcpServer.HandleCallTool(const AId: Variant; const AParams: Variant);
var
  LInstanceName, LToolName: string;
  LInstance: TFitNesseInstance;
  LClient: TFitNesseClient;
  LResult: RawUtf8;
  LRes: Variant;
  LNeedsInstance: Boolean;
begin
  LToolName := AParams.name;
  Log('Calling Tool: ' + LToolName);

  LNeedsInstance := (LToolName <> 'list_instances');
  
  LClient := nil;
  try
    if LNeedsInstance then
    begin
      if not AParams.arguments.Exists('instance') or (VarToStr(AParams.arguments.instance) = '') then
      begin
        if LToolName = 'start_instance' then
        begin
          SendError(AId, -32602, 'Invalid params: "instance" is required for start_instance');
          Exit;
        end;

        if (FLastStartedInstance <> '') and FConfig.GetInstanceByName(FLastStartedInstance, LInstance) then
        begin
          Log('No instance specified, using default/last started: ' + LInstance.name);
        end
        else
        begin
          SendError(AId, -32002, 'No FitNesse instances configured or default instance not found.');
          Exit;
        end;
      end
      else
      begin
        LInstanceName := VarToStr(AParams.arguments.instance);
        if not FConfig.GetInstanceByName(LInstanceName, LInstance) then
        begin
          Log('Error: Instance not found: ' + LInstanceName);
          SendError(AId, -32001, 'Instance not found: ' + LInstanceName);
          Exit;
        end;
      end;
      LClient := TFitNesseClient.Create(LInstance);
    end;

    if LToolName = 'run_test' then
      LResult := DoRunTest(LClient, AParams.arguments)
    else if LToolName = 'get_test_result' then
      LResult := DoGetTestResult(LClient, AParams.arguments)
    else if LToolName = 'get_page_content' then
      LResult := DoGetPageContent(LClient, AParams.arguments)
    else if LToolName = 'start_instance' then
      LResult := DoStartInstance(LClient, AParams.arguments)
    else if LToolName = 'list_pages' then
      LResult := DoListPages(LClient, AParams.arguments)
    else if LToolName = 'list_instances' then
      LResult := DoListInstances
    else
    begin
      SendError(AId, -32601, 'Tool not found: ' + LToolName);
      Exit;
    end;

    TDocVariant.New(LRes);
    LRes.jsonrpc := '2.0';
    LRes.id := AId;
    LRes.result := _Obj([
      'content', _Arr([
        _Obj(['type', 'text', 'text', Utf8ToString(LResult)])
      ])
    ]);
    SendResponse(VariantToString(_Json(VariantToUtf8(LRes))));
  finally
    LClient.Free;
  end;
end;

procedure TFitNesseMcpServer.HandleListResources(const AId: Variant);
var
  LRes: Variant;
begin
  TDocVariant.New(LRes);
  LRes.jsonrpc := '2.0';
  LRes.id := AId;
  LRes.result := _Obj(['resources', _Arr([])]);
  SendResponse(VariantToString(_Json(VariantToUtf8(LRes))));
end;

procedure TFitNesseMcpServer.HandleReadResource(const AId: Variant; const AParams: Variant);
begin
  SendError(AId, -32601, 'Not implemented');
end;

end.
