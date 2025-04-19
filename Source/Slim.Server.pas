// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Server;

interface

uses

  System.Classes,
  System.SysUtils,

  IdBaseComponent,
  IdComponent,
  IdContext,
  IdCustomTCPServer,
  IdIOHandler,
  IdServerIOHandler,
  IdServerIOHandlerSocket,
  IdServerIOHandlerStack,
  IdTCPServer,

  Slim.Exec;

type

  TSlimServer = class(TIdTCPServer)
  protected
    function  ReadLength(AIo: TIdIOHandler): Integer;
    procedure SlimServerExecute(AContext: TIdContext);
    procedure WriteLength(AIo: TIdIOHandler; ALength: Integer);
    procedure WriteString(AIo: TIdIOHandler; const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{ TSlimServer }

constructor TSlimServer.Create(AOwner: TComponent);
begin
  inherited;
  OnExecute := SlimServerExecute;
end;

function TSlimServer.ReadLength(AIo: TIdIOHandler): Integer;
var
  IntStr: String;
  ColonChar: Char;
begin
  IntStr:=AIo.ReadString(6);
  if Length(IntStr)=6 then
  begin
    ColonChar:=AIo.ReadChar;
    if not (TryStrToInt(IntStr, Result) and (ColonChar=':'))
      then raise Exception.Create('Invalid length');
  end
  else Result:=-1;
end;

procedure TSlimServer.SlimServerExecute(AContext: TIdContext);
begin

end;

procedure TSlimServer.WriteLength(AIo: TIdIOHandler; ALength: Integer);
begin
  var LenStr: String := Format('%.6d:', [ALength]);
  AIo.Write(LenStr);
end;

procedure TSlimServer.WriteString(AIo: TIdIOHandler; const AValue: String);
begin
  WriteLength(AIo, Length(AValue));
  AIo.Write(AValue);
end;

end.
