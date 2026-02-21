unit FitNesseMcp.FitNesseClient;

interface

uses
  System.SysUtils,
  System.Net.HttpClient,
  System.IOUtils,
  System.Types,
  Winapi.Windows,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.json,
  mormot.core.data,
  mormot.core.variants,
  FitNesseMcp.Config;

type
  TFitNesseClient = class
  private
    FInstance: TFitNesseInstance;
    procedure Log(const AMsg: string);
    function GetFitNesseRoot: string;
    function GetBaseUrl: string;
    function GetPageType(const APagePath: string): string;
  public
    constructor Create(const AInstance: TFitNesseInstance);
    function StartInstance: Boolean;
    function RunTest(const APagePath: string): RawUtf8;
    function GetPageContent(const APagePath: string): RawUtf8;
    function ListPages(const AParentPath: string): RawUtf8;
    function CheckIfRunning: Boolean;
  end;

implementation

{ TFitNesseClient }

constructor TFitNesseClient.Create(const AInstance: TFitNesseInstance);
begin
  inherited Create;
  FInstance := AInstance;
end;

procedure TFitNesseClient.Log(const AMsg: string);
begin
  Writeln(ErrOutput, Format('[%s] %s', [FInstance.name, AMsg]));
  Flush(ErrOutput);
end;

function TFitNesseClient.GetBaseUrl: string;
begin
  if FInstance.baseUrl <> '' then
  begin
    Result := FInstance.baseUrl;
    if Result.EndsWith('/') then
      Delete(Result, Length(Result), 1);
  end
  else
    Result := Format('http://localhost:%d', [FInstance.port]);
end;

function TFitNesseClient.CheckIfRunning: Boolean;
var
  LClient: THTTPClient;
  LUrl: string;
begin
  Result := False;
  LUrl := GetBaseUrl + '/root';
  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 500; // Fast check
    LClient.ResponseTimeout := 500;
    try
      Result := LClient.Get(LUrl).StatusCode = 200;
    except
      Result := False;
    end;
  finally
    LClient.Free;
  end;
end;

function TFitNesseClient.GetFitNesseRoot: string;
var
  LRootName: string;
begin
  LRootName := FInstance.fitnesseRoot;
  if LRootName = '' then
    LRootName := 'FitNesseRoot';
  Result := TPath.Combine(FInstance.rootPath, LRootName);
end;

function TFitNesseClient.StartInstance: Boolean;
var
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LCommandLine: string;
  LCurrentDir: string;
  LJarPath: string;
begin
  LCurrentDir := StringReplace(FInstance.rootPath, '/', '\', [rfReplaceAll]);

  if FInstance.startCmdLine <> '' then
  begin
    Log('Using configured start command...');
    LCommandLine := FInstance.startCmdLine;
  end
  else
  begin
    Log('Preparing to start FitNesse (Default mode)...');
    LJarPath := TPath.Combine(LCurrentDir, 'fitnesse-standalone.jar');
    
    if not FileExists(LJarPath) then 
    begin 
      Log('ERROR: JAR not found in rootPath: ' + LJarPath); 
      Exit(False); 
    end;

    LCommandLine := Format('java -jar "fitnesse-standalone.jar" -p %d -e 0', [FInstance.port]);
    
    if FInstance.fitnesseRoot <> '' then
      LCommandLine := LCommandLine + ' -r "' + FInstance.fitnesseRoot + '"';
  end;

  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);

  Result := CreateProcess(nil, PChar(LCommandLine), nil, nil, False,
    CREATE_NO_WINDOW or CREATE_BREAKAWAY_FROM_JOB, nil, PChar(LCurrentDir), LStartupInfo, LProcessInfo);

  if Result then
  begin
    CloseHandle(LProcessInfo.hProcess);
    CloseHandle(LProcessInfo.hThread);
    Log('Process spawned successfully.');
  end;
end;

function TFitNesseClient.ListPages(const AParentPath: string): RawUtf8;
var
  LRoot, LSearchPath: string;
  LDirs: TArray<string>;
  LDir, LName: string;
  LRes: Variant;
  LPageType: string;
  LPropsPath: string;
  LPropsXml: string;
begin
  LRoot := GetFitNesseRoot;
  LSearchPath := TPath.Combine(LRoot, StringReplace(AParentPath, '.', '\', [rfReplaceAll]));
  
  TDocVariant.New(LRes);
  LRes.path := StringToUtf8(AParentPath);
  LRes.pages := _Arr([]);

  if DirectoryExists(LSearchPath) then
  begin
    LDirs := TDirectory.GetDirectories(LSearchPath);
    Log('Found ' + IntToStr(Length(LDirs)) + ' directories in ' + LSearchPath);
    for LDir in LDirs do
    begin
      LName := TPath.GetFileName(LDir);
      Log('Checking directory: ' + LName);
      if LName.StartsWith('.') or LName.StartsWith('files') then Continue;
      
      if FileExists(TPath.Combine(LDir, 'content.txt')) or FileExists(TPath.Combine(LDir, '_root.wiki')) then
      begin
        LPageType := GetPageType(AParentPath + '.' + LName);
        LRes.pages.Add(_Obj(['name', StringToUtf8(LName), 'type', StringToUtf8(LPageType)]));
      end;
    end;
  end;
  Result := _Json(LRes);
end;

function TFitNesseClient.GetPageContent(const APagePath: string): RawUtf8;
var
  LClient: THTTPClient;
  LUrl: string;
begin
  LUrl := Format('%s/%s?responder=edit', [GetBaseUrl, APagePath]);
  LClient := THTTPClient.Create;
  try
    Result := StringToUtf8(LClient.Get(LUrl).ContentAsString);
  finally
    LClient.Free;
  end;
end;

function TFitNesseClient.GetPageType(const APagePath: string): string;
var
  LRoot, LPath, LFilePath, LContent: string;
begin
  Result := 'Test'; // Default
  LRoot := GetFitNesseRoot;
  LPath := TPath.Combine(LRoot, StringReplace(APagePath, '.', '\', [rfReplaceAll]));

  if DirectoryExists(LPath) then
  begin
    // Check properties.xml
    LFilePath := TPath.Combine(LPath, 'properties.xml');
    if FileExists(LFilePath) then
    begin
      LContent := TFile.ReadAllText(LFilePath);
      if (Pos('<Suite/>', LContent) > 0) or (Pos('<Suite />', LContent) > 0) then
        Exit('Suite');
      if (Pos('<Test/>', LContent) > 0) or (Pos('<Test />', LContent) > 0) then
        Exit('Test');
    end;

    // Check _root.wiki frontmatter
    LFilePath := TPath.Combine(LPath, '_root.wiki');
    if FileExists(LFilePath) then
    begin
      LContent := TFile.ReadAllText(LFilePath);
      LContent := StringReplace(LContent, #13#10, #10, [rfReplaceAll]);
      if Pos('---'#10'Suite'#10'---', LContent) > 0 then
        Exit('Suite');
      if Pos('---'#10'Test'#10'---', LContent) > 0 then
        Exit('Test');
    end;
  end;
end;

function TFitNesseClient.RunTest(const APagePath: string): RawUtf8;
var
  LClient: THTTPClient;
  LUrl: string;
  LResponder: string;
begin
  if GetPageType(APagePath) = 'Suite' then
    LResponder := 'suite'
  else
    LResponder := 'test';

  Log('Running ' + LResponder + ': ' + APagePath);
  LUrl := Format('%s/%s?responder=%s&format=xml', [GetBaseUrl, APagePath, LResponder]);
  LClient := THTTPClient.Create;
  try
    Result := StringToUtf8(LClient.Get(LUrl).ContentAsString);
  finally
    LClient.Free;
  end;
end;

end.
