unit FitNesseMcp.FitNesseClient;

interface

uses
  System.SysUtils,
  System.Classes,
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
    function RunTest(const APagePath: string; const AFormat: string = 'junit'): RawUtf8;
    function GetTestResult(const APagePath, AResultDate: string): RawUtf8;
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
    
    if (Pos('cmd', LowerCase(LCommandLine)) <> 1) and 
       ((Pos('.bat', LowerCase(LCommandLine)) > 0) or (Pos('.cmd', LowerCase(LCommandLine)) > 0)) then
    begin
       LCommandLine := 'cmd /c ' + LCommandLine;
       Log('Prepended cmd /c to batch file command.');
    end;
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
  LWikiFiles: TArray<string>;
  LDir, LName, LWikiFile: string;
  LRes: Variant;
  LPageType: string;
  LPropsPath: string;
  LPropsXml: string;
  LProcessed: TStringList;
begin
  LRoot := GetFitNesseRoot;
  if AParentPath = '' then
    LSearchPath := LRoot
  else
    LSearchPath := TPath.Combine(LRoot, StringReplace(AParentPath, '.', '\', [rfReplaceAll]));
  
  TDocVariant.New(LRes);
  LRes.path := StringToUtf8(AParentPath);
  LRes.pages := _Arr([]);

  LProcessed := TStringList.Create;
  LProcessed.CaseSensitive := False;
  try
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
          // Fix: If AParentPath is empty, don't add dot
          if AParentPath = '' then
             LPageType := GetPageType(LName)
          else
             LPageType := GetPageType(AParentPath + '.' + LName);

          LRes.pages.Add(_Obj(['name', StringToUtf8(LName), 'type', StringToUtf8(LPageType)]));
          LProcessed.Add(LName);
        end;
      end;

      LWikiFiles := TDirectory.GetFiles(LSearchPath, '*.wiki');
      for LWikiFile in LWikiFiles do
      begin
        LName := TPath.GetFileNameWithoutExtension(LWikiFile);
        if LName.StartsWith('_') then Continue; // Skip _root.wiki
        
        if LProcessed.IndexOf(LName) < 0 then
        begin
          if AParentPath = '' then
             LPageType := GetPageType(LName)
          else
             LPageType := GetPageType(AParentPath + '.' + LName);
             
          LRes.pages.Add(_Obj(['name', StringToUtf8(LName), 'type', StringToUtf8(LPageType)]));
        end;
      end;
    end;
  finally
    LProcessed.Free;
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
    LClient.ConnectionTimeout := 2000;
    try
      Result := StringToUtf8(LClient.Get(LUrl).ContentAsString);
    except
      on E: Exception do
      begin
        Log('Error getting page content: ' + E.Message);
        Result := StringToUtf8('Error: FitNesse unreachable: ' + E.Message);
      end;
    end;
  finally
    LClient.Free;
  end;
end;

function TFitNesseClient.GetPageType(const APagePath: string): string;
var
  LRoot, LPath, LFilePath, LContent: string;
  LIsSuite, LIsTest: Boolean;
  
  procedure CheckContent(const AContent: string);
  begin
    if (Pos('<Suite/>', AContent) > 0) or (Pos('<Suite />', AContent) > 0) or
       (Pos('---'#10'Suite'#10'---', StringReplace(AContent, #13#10, #10, [rfReplaceAll])) > 0) then
      LIsSuite := True;
      
    if (Pos('<Test/>', AContent) > 0) or (Pos('<Test />', AContent) > 0) or
       (Pos('---'#10'Test'#10'---', StringReplace(AContent, #13#10, #10, [rfReplaceAll])) > 0) then
      LIsTest := True;
  end;

begin
  Result := 'Test'; // Default
  LRoot := GetFitNesseRoot;
  LPath := TPath.Combine(LRoot, StringReplace(APagePath, '.', '\', [rfReplaceAll]));
  
  LIsSuite := False;
  LIsTest := False;

  if DirectoryExists(LPath) then
  begin
    // Check properties.xml
    LFilePath := TPath.Combine(LPath, 'properties.xml');
    if FileExists(LFilePath) then
      CheckContent(TFile.ReadAllText(LFilePath));

    // Check _root.wiki frontmatter
    LFilePath := TPath.Combine(LPath, '_root.wiki');
    if FileExists(LFilePath) then
      CheckContent(TFile.ReadAllText(LFilePath));
  end;
  
  // Check .wiki file
  if FileExists(LPath + '.wiki') then
     CheckContent(TFile.ReadAllText(LPath + '.wiki'));

  if LIsSuite then Result := 'Suite'
  else if LIsTest then Result := 'Test'
  else Result := 'Static'; // Assuming static if not explicitly defined
end;

function TFitNesseClient.GetTestResult(const APagePath, AResultDate: string): RawUtf8;
var
  LHistoryDir: string;
  LFiles: TArray<string>;
begin
  LHistoryDir := TPath.Combine(GetFitNesseRoot, 'files\testResults\' + APagePath);
  if not DirectoryExists(LHistoryDir) then
    Exit(StringToUtf8('Error: History directory not found: ' + LHistoryDir));

  LFiles := TDirectory.GetFiles(LHistoryDir, AResultDate + '*.xml');
  if Length(LFiles) = 0 then
    Exit(StringToUtf8('Error: No result file found for date ' + AResultDate + ' in ' + LHistoryDir));
  
  Result := StringToUtf8(TFile.ReadAllText(LFiles[0]));
end;

function TFitNesseClient.RunTest(const APagePath: string; const AFormat: string = 'junit'): RawUtf8;
var
  LClient: THTTPClient;
  LUrl: string;
  LResponder: string;
begin
  if GetPageType(APagePath) = 'Suite' then
    LResponder := 'suite'
  else
    LResponder := 'test';

  Log('Running ' + LResponder + ': ' + APagePath + ' (' + AFormat + ')');
  LUrl := Format('%s/%s?responder=%s&format=%s', [GetBaseUrl, APagePath, LResponder, AFormat]);
  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 2000;
    try
      Result := StringToUtf8(LClient.Get(LUrl).ContentAsString);
    except
      on E: Exception do
      begin
        Log('Error executing test: ' + E.Message);
        Result := StringToUtf8(Format('<testResults><error>FitNesse unreachable: %s</error></testResults>', [E.Message]));
      end;
    end;
  finally
    LClient.Free;
  end;
end;

end.
