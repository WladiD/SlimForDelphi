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

  Slim.Exec,
  Slim.List;

type

  TStringEvent = procedure(const AValue: String) of object;

  TSlimServer = class(TIdTCPServer)
  private
    FOnReadRequest: TStringEvent;
    FOnWriteResponse: TStringEvent;
  protected
    function  Execute(const ARequest: String): TSlimList;
    function  ReadLength(AIo: TIdIOHandler): Integer;
    procedure SlimServerExecute(AContext: TIdContext);
    procedure WriteLength(AIo: TIdIOHandler; ALength: Integer);
    procedure WriteString(AIo: TIdIOHandler; const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
    property OnReadRequest: TStringEvent read FOnReadRequest write FOnReadRequest;
    property OnWriteResponse: TStringEvent read FOnWriteResponse write FOnWriteResponse;
  end;

implementation

{ TSlimServer }

constructor TSlimServer.Create(AOwner: TComponent);
begin
  inherited;
  OnExecute := SlimServerExecute;
end;

function TSlimServer.Execute(const ARequest: String): TSlimList;
var
  Executor: TSlimExecutor;
  Stmts   : TSlimList;
begin
  Stmts := nil;
  Executor := TSlimExecutor.Create;
  try
    Stmts := SlimListUnserialize(ARequest);
    Result := Executor.Execute(Stmts);
  finally
    Stmts.Free;
    Executor.Free;
  end;
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
var
  Io: TIdIOHandler;
begin
  Io := AContext.Connection.IOHandler;
  Io.WriteLn('Slim -- V0.5');

  var Stream: TStringStream:=TStringStream.Create;
  try
    try
      var LLength: Integer:=ReadLength(Io);
      while LLength>0 do
      begin
        var LMessage: String:=Io.ReadString(LLength);
        if Assigned(FOnReadRequest) then
          FOnReadRequest(LMessage);
        if LMessage = 'bye' then
          Break;
        var Response: TSlimList := Execute(LMessage);
        try
          WriteString(Io, SlimListSerialize(Response));
        finally
          Response.Free;
        end;
        LLength:=ReadLength(Io);
      end;
    except
      on E: Exception do
      begin
        var ExceptMsg: String := E.Message;
        var TempMsg:=ExceptMsg;
      end;
    end;
  finally
    Stream.Free;
  end;
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
  if Assigned(FOnWriteResponse) then
    FOnWriteResponse(AValue);
end;

end.
