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
  IdGlobal,
  IdIOHandler,
  IdServerIOHandler,
  IdServerIOHandlerSocket,
  IdServerIOHandlerStack,
  IdTCPServer,

  Slim.Exec,
  Slim.List,
  Slim.Symbol;

{$IFNDEF DEBUG}
  {$MESSAGE WARN 'Do not run the SLIM server on a production application!'}
{$ENDIF}

type

  TStringEvent = procedure(const AValue: String) of object;

  TSlimExecutorClass = class of TSlimExecutor;

  TSlimServer = class(TIdTCPServer)
  private
    FContext        : TSlimStatementContext;
    FExecutorClass  : TSlimExecutorClass;
    FOnReadRequest  : TStringEvent;
    FOnWriteResponse: TStringEvent;
  protected
    function  Execute(AExecutor: TSlimExecutor; const ARequest: String): TSlimList;
    function  ReadLength(AIo: TIdIOHandler): Integer;
    procedure SlimServerExecute(AContext: TIdContext);
    procedure WriteLength(AIo: TIdIOHandler; ALength: Integer);
    procedure WriteString(AIo: TIdIOHandler; const AValue: String);
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
    property ExecutorClass: TSlimExecutorClass read FExecutorClass write FExecutorClass;
    property OnReadRequest: TStringEvent read FOnReadRequest write FOnReadRequest;
    property OnWriteResponse: TStringEvent read FOnWriteResponse write FOnWriteResponse;
  end;

implementation

{ TSlimServer }

procedure TSlimServer.AfterConstruction;
begin
  inherited AfterConstruction;
  FExecutorClass := TSlimExecutor;
  OnExecute := SlimServerExecute;
  FContext := TSlimStatementContext.Create;
  FContext.InitMembers([
    TSlimStatementContext.TContextMember.cmInstances,
    TSlimStatementContext.TContextMember.cmLibInstances,
    TSlimStatementContext.TContextMember.cmResolver,
    TSlimStatementContext.TContextMember.cmSymbols,
    TSlimStatementContext.TContextMember.cmImportedNamespaces]);
end;

destructor TSlimServer.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TSlimServer.Execute(AExecutor: TSlimExecutor; const ARequest: String): TSlimList;
var
  Stmts: TSlimList;
begin
  Stmts := nil;
  try
    Stmts := SlimListUnserialize(ARequest);
    Result := AExecutor.Execute(Stmts);
  finally
    Stmts.Free;
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
  Io       : TIdIOHandler;
  LExecutor: TSlimExecutor;
  Stream   : TStringStream;
begin
  Io := AContext.Connection.IOHandler;
  Io.WriteLn('Slim -- V0.5');

  Stream := nil;
  LExecutor := FExecutorClass.Create(FContext);
  try
    Stream := TStringStream.Create;
    var LLength: Integer := ReadLength(Io);
    while LLength > 0 do
    begin
      var LMessage: String := Io.ReadString(LLength, IndyTextEncoding_UTF8);
      if Assigned(FOnReadRequest) then
        FOnReadRequest(LMessage);
      if LMessage = 'bye' then
        Break;
      var Response: TSlimList := Execute(LExecutor, LMessage);
      try
        WriteString(Io, SlimListSerialize(Response));
      finally
        Response.Free;
      end;
      LLength := ReadLength(Io);
    end;
  finally
    Stream.Free;
    LExecutor.Free;
  end;
end;

procedure TSlimServer.WriteLength(AIo: TIdIOHandler; ALength: Integer);
begin
  var LenStr: String := Format('%.6d:', [ALength]);
  AIo.Write(LenStr);
end;

procedure TSlimServer.WriteString(AIo: TIdIOHandler; const AValue: String);
var
  Value      : UTF8String;
  ValueLength: Integer;
  Bytes      : TIdBytes;
begin
  Value := UTF8Encode(AValue);
  ValueLength := Length(Value);
  WriteLength(AIo, ValueLength);
  if ValueLength > 0 then
  begin
    SetLength(Bytes, ValueLength);
    Move(Value[1], Bytes[0], ValueLength);
    AIo.Write(Bytes);
  end;
  if Assigned(FOnWriteResponse) then
    FOnWriteResponse(AValue);
end;

end.

