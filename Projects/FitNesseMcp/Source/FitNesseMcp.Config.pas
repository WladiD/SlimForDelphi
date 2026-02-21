unit FitNesseMcp.Config;

interface

uses
  System.SysUtils,
  System.IOUtils,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.json,
  mormot.core.data,
  mormot.core.text,
  mormot.core.variants;

type
  TFitNesseInstance = record
    name: string;
    baseUrl: string;
    rootPath: string;
    fitnesseRoot: string;
    port: Integer;
    startCmdLine: string;
    isRunning: Boolean;
  end;

  TFitNesseConfig = record
    instances: array of TFitNesseInstance;
    function LoadFromFile(const AFileName: string): Boolean;
    function GetInstanceByName(const AName: string; out AInstance: TFitNesseInstance): Boolean;
  end;

implementation

{ TFitNesseConfig }

function TFitNesseConfig.GetInstanceByName(const AName: string; out AInstance: TFitNesseInstance): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(instances) do
  begin
    if SameText(instances[i].name, AName) then
    begin
      AInstance := instances[i];
      Exit(True);
    end;
  end;
end;

function TFitNesseConfig.LoadFromFile(const AFileName: string): Boolean;
var
  LContent: RawUtf8;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  LContent := StringToUtf8(TFile.ReadAllText(AFileName));
  Result := RecordLoadJson(Self, LContent, TypeInfo(TFitNesseConfig));
end;

end.
