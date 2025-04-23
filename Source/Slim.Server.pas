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
  Slim.List,
  Slim.Symbol;

type

  TStringEvent = procedure(const AValue: String) of object;

  TSlimServer = class(TIdTCPServer)
  private
    FContext        : TSlimStatementContext;
    FOnReadRequest  : TStringEvent;
    FOnWriteResponse: TStringEvent;
  protected
    function  Execute(const ARequest: String): TSlimList;
    function  ReadLength(AIo: TIdIOHandler): Integer;
    procedure SlimServerExecute(AContext: TIdContext);
    procedure WriteLength(AIo: TIdIOHandler; ALength: Integer);
    procedure WriteString(AIo: TIdIOHandler; const AValue: String);
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
    property OnReadRequest: TStringEvent read FOnReadRequest write FOnReadRequest;
    property OnWriteResponse: TStringEvent read FOnWriteResponse write FOnWriteResponse;
  end;

implementation

{ TSlimServer }

procedure TSlimServer.AfterConstruction;
begin
  inherited AfterConstruction;
  OnExecute := SlimServerExecute;
  FContext := TSlimStatementContext.Create;
  FContext.InitMembers([
    TSlimStatementContext.TContextMember.cmLibInstances,
    TSlimStatementContext.TContextMember.cmResolver,
    TSlimStatementContext.TContextMember.cmSymbols]);
end;

destructor TSlimServer.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TSlimServer.Execute(const ARequest: String): TSlimList;
var
  Executor: TSlimExecutor;
  Stmts   : TSlimList;
begin
  Stmts := nil;
  Executor := TSlimExecutor.Create(FContext);
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
  ColonChar: Char;
  IntStr   : String;
begin
  IntStr := AIo.ReadString(6);
  if Length(IntStr) = 6 then
  begin
    ColonChar := AIo.ReadChar;
    if not (TryStrToInt(IntStr, Result) and (ColonChar = ':')) then
      raise Exception.Create('Invalid length');
  end
  else
    Result := -1;
end;

procedure TSlimServer.SlimServerExecute(AContext: TIdContext);
var
  Io: TIdIOHandler;
begin
  Io := AContext.Connection.IOHandler;
  Io.WriteLn('Slim -- V0.5');

  var Stream: TStringStream := TStringStream.Create;
  try
    var LLength: Integer := ReadLength(Io);
    while LLength > 0 do
    begin
      var LMessage: String := Io.ReadString(LLength);
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
      LLength := ReadLength(Io);
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
