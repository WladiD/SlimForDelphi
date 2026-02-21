unit FitNesseMcp.Server;

interface

uses
  System.SysUtils,
  System.Classes,
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
    procedure Log(const AMsg: string);
    procedure HandleRequest(const AJson: RawUtf8);
    procedure SendResponse(const AResponse: RawUtf8);
    procedure SendError(const AId: Variant; ACode: Integer; const AMessage: string);
    
    // MCP Handlers
    procedure HandleInitialize(const AId: Variant; const AParams: Variant);
    procedure HandleListTools(const AId: Variant);
    procedure HandleCallTool(const AId: Variant; const AParams: Variant);
    procedure HandleListResources(const AId: Variant);
    procedure HandleReadResource(const AId: Variant; const AParams: Variant);
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
    Log('Config loaded successfully from: ' + LConfigPath)
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
      SendError(Null, -32603, 'Internal error: ' + E.Message);
    end;
  end;
end;

procedure TFitNesseMcpServer.SendResponse(const AResponse: RawUtf8);
begin
  Log('<< ' + Utf8ToString(AResponse));
  Writeln(Utf8ToString(AResponse));
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
  SendResponse(_Json(LRes));
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
  SendResponse(_Json(LRes));
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
        'description', 'Runs a FitNesse test or suite and returns the result in XML format.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path of the test page or suite'])
          ]),
          'required', _Arr(['instance', 'pagePath'])
        ])
      ]),
      _Obj([
        'name', 'get_page_content',
        'description', 'Gets the wiki source of a FitNesse page.',
        'inputSchema', _Obj([
          'type', 'object',
          'properties', _Obj([
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path of the page'])
          ]),
          'required', _Arr(['instance', 'pagePath'])
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
            'instance', _Obj(['type', 'string', 'description', 'Name of the FitNesse instance']),
            'pagePath', _Obj(['type', 'string', 'description', 'Wiki path to list (empty for root)'])
          ]),
          'required', _Arr(['instance', 'pagePath'])
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
  SendResponse(_Json(LRes));
end;

procedure TFitNesseMcpServer.HandleCallTool(const AId: Variant; const AParams: Variant);
var
  LInstanceName, LPagePath, LToolName: string;
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
      LInstanceName := AParams.arguments.instance;
      if not FConfig.GetInstanceByName(LInstanceName, LInstance) then
      begin
        Log('Error: Instance not found: ' + LInstanceName);
        SendError(AId, -32001, 'Instance not found: ' + LInstanceName);
        Exit;
      end;
      LClient := TFitNesseClient.Create(LInstance);
    end;

    if LToolName = 'run_test' then
    begin
      LPagePath := AParams.arguments.pagePath;
      LResult := LClient.RunTest(LPagePath);
    end
    else if LToolName = 'get_page_content' then
    begin
      LPagePath := AParams.arguments.pagePath;
      LResult := LClient.GetPageContent(LPagePath);
    end
    else if LToolName = 'start_instance' then
    begin
      if LClient.StartInstance then
        LResult := 'Instance started successfully.'
      else
        LResult := 'Failed to start instance. Check server logs (stderr).';
    end
    else if LToolName = 'list_pages' then
    begin
      LPagePath := AParams.arguments.pagePath;
      LResult := LClient.ListPages(LPagePath);
    end
    else if LToolName = 'list_instances' then
    begin
      for var i := 0 to High(FConfig.instances) do
      begin
        LClient := TFitNesseClient.Create(FConfig.instances[i]);
        try
          FConfig.instances[i].isRunning := LClient.CheckIfRunning;
        finally
          LClient.Free;
        end;
      end;
      LResult := RecordSaveJson(FConfig, TypeInfo(TFitNesseConfig));
    end
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
    SendResponse(_Json(LRes));
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
  SendResponse(_Json(LRes));
end;

procedure TFitNesseMcpServer.HandleReadResource(const AId: Variant; const AParams: Variant);
begin
  SendError(AId, -32601, 'Not implemented');
end;

end.
