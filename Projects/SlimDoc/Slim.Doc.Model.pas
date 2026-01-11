// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
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

  TSlimDocParameter = class
  public
    Name     : String;
    ParamType: String;
    constructor Create(const AName, AParamType: String);
  end;

  TSlimDocMember = class
  public
    DeclaringClass: String;
    Description: String;
    IsInherited: Boolean;
    Name       : String;
    Origin     : String;
    SyncMode   : String;
    UnitPath   : String;
  end;

  TSlimDocMethod = class(TSlimDocMember)
  public
    Parameters : TObjectList<TSlimDocParameter>;
    ReturnType : String;
    constructor Create;
    destructor Destroy; override;
    function GetParamsString: String;
  end;

  TSlimDocProperty = class(TSlimDocMember)
  public
    Access      : String;
    PropertyType: String;
  end;

  TSlimDocFixture = class
  public
    DelphiClass     : String;
    Description     : String;
    InheritanceChain: TStringList;
    Methods         : TObjectList<TSlimDocMethod>;
    Constructors    : TObjectList<TSlimDocMethod>;
    Name            : String;
    Namespace       : String;
    Properties      : TObjectList<TSlimDocProperty>;
    UnitName        : String;
    UnitPath        : String;
    OpenUnitLink    : String;
    constructor Create;
    destructor Destroy; override;
    function Id: String;
  end;

implementation

{ TSlimDocParameter }

constructor TSlimDocParameter.Create(const AName, AParamType: String);
begin
  inherited Create;
  Name := AName;
  ParamType := AParamType;
end;

{ TSlimDocMethod }

constructor TSlimDocMethod.Create;
begin
  inherited Create;
  Parameters := TObjectList<TSlimDocParameter>.Create;
end;

destructor TSlimDocMethod.Destroy;
begin
  Parameters.Free;
  inherited;
end;

function TSlimDocMethod.GetParamsString: String;
begin
  Result := '';
  for var P: TSlimDocParameter in Parameters do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + P.Name + ': ' + P.ParamType;
  end;
end;

{ TSlimDocFixture }

constructor TSlimDocFixture.Create;
begin
  inherited Create;
  InheritanceChain := TStringList.Create;
  Methods := TObjectList<TSlimDocMethod>.Create;
  Constructors := TObjectList<TSlimDocMethod>.Create;
  Properties := TObjectList<TSlimDocProperty>.Create;
end;

destructor TSlimDocFixture.Destroy;
begin
  InheritanceChain.Free;
  Methods.Free;
  Constructors.Free;
  Properties.Free;
  inherited;
end;

function TSlimDocFixture.Id: String;
begin
  Result := Format('%s.%s', [Namespace, Name]);
end;

end.
