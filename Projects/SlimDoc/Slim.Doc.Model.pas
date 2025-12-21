// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Model;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils;

type

  TSlimParameterDoc = class
  public
    Name: String;
    ParamType: String;
    constructor Create(const AName, AParamType: String);
  end;

  TSlimMethodDoc = class
  public
    Name: String;
    Parameters: TObjectList<TSlimParameterDoc>;
    ReturnType: String;
    SyncMode: String;
    Origin: String;
    IsInherited: Boolean;
    constructor Create;
    destructor Destroy; override;
    function GetParamsString: String;
  end;

  TSlimPropertyDoc = class
  public
    Name: String;
    PropertyType: String;
    Access: String;
    Origin: String;
    IsInherited: Boolean;
    constructor Create;
  end;

  TSlimFixtureDoc = class
  public
    Name: String;
    Namespace: String;
    DelphiClass: String;
    UnitName: String;
    Methods: TObjectList<TSlimMethodDoc>;
    Properties: TObjectList<TSlimPropertyDoc>;
    constructor Create;
    destructor Destroy; override;
    function Id: String;
  end;

implementation

{ TSlimParameterDoc }

constructor TSlimParameterDoc.Create(const AName, AParamType: String);
begin
  inherited Create;
  Name := AName;
  ParamType := AParamType;
end;

{ TSlimMethodDoc }

constructor TSlimMethodDoc.Create;
begin
  inherited Create;
  Parameters := TObjectList<TSlimParameterDoc>.Create;
end;

destructor TSlimMethodDoc.Destroy;
begin
  Parameters.Free;
  inherited;
end;

function TSlimMethodDoc.GetParamsString: String;
var
  P: TSlimParameterDoc;
begin
  Result := '';
  for P in Parameters do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + P.Name + ': ' + P.ParamType;
  end;
end;

{ TSlimPropertyDoc }

constructor TSlimPropertyDoc.Create;
begin
  inherited Create;
end;

{ TSlimFixtureDoc }

constructor TSlimFixtureDoc.Create;
begin
  inherited Create;
  Methods := TObjectList<TSlimMethodDoc>.Create;
  Properties := TObjectList<TSlimPropertyDoc>.Create;
end;

destructor TSlimFixtureDoc.Destroy;
begin
  Methods.Free;
  Properties.Free;
  inherited;
end;

function TSlimFixtureDoc.Id: String;
begin
  Result := Format('%s.%s', [Namespace, Name]);
end;

end.
