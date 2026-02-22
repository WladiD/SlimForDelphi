// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.Mcp.Fixture;

interface

uses
  Winapi.Windows,
  System.Classes,
  System.SysUtils,
  System.JSON,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.json,
  mormot.core.data,
  mormot.core.text,
  mormot.core.variants,
  Slim.Fixture,
  Slim.Proxy.Base;

type
  [SlimFixture('Mcp', 'SlimProxy')]
  TSlimProxyMcpFixture = class(TSlimProxyBaseFixture)
  private
    FProcessInfo: TProcessInformation;
    FhStdinWrite: THandle;
    FhStdoutRead: THandle;
    FRequestId: Integer;
    FReadBuffer: string;
    procedure Log(const AMsg: string);
    function IsRunning: Boolean;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;

    function McpStart(const AExecutable: string): Boolean;
    function McpCall(const AMethod: string; const AParamsJson: string): string;
    procedure McpStop;
  end;

implementation

{ TSlimProxyMcpFixture }

procedure TSlimProxyMcpFixture.AfterConstruction;
begin
  inherited;
  FRequestId := 1;
end;

destructor TSlimProxyMcpFixture.Destroy;
begin
  McpStop;
  inherited;
end;

procedure TSlimProxyMcpFixture.Log(const AMsg: string);
begin
  Writeln(ErrOutput, '[McpFixture] ' + AMsg);
  Flush(ErrOutput);
end;

function TSlimProxyMcpFixture.IsRunning: Boolean;
var
  LExitCode: DWORD;
begin
  Result := (FProcessInfo.hProcess <> 0) and GetExitCodeProcess(FProcessInfo.hProcess, LExitCode) and (LExitCode = STILL_ACTIVE);
end;

function TSlimProxyMcpFixture.McpStart(const AExecutable: string): Boolean;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  hStdinRead, hStdoutWrite: THandle;
  LCmd: string;
begin
  McpStop;

  SA.nLength := SizeOf(TSecurityAttributes);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(FhStdoutRead, hStdoutWrite, @SA, 0) then RaiseLastOSError;
  if not SetHandleInformation(FhStdoutRead, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;

  if not CreatePipe(hStdinRead, FhStdinWrite, @SA, 0) then RaiseLastOSError;
  if not SetHandleInformation(FhStdinWrite, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;

  FillChar(SI, SizeOf(TStartupInfo), 0);
  SI.cb := SizeOf(TStartupInfo);
  SI.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  SI.hStdOutput := hStdoutWrite;
  SI.hStdInput := hStdinRead;
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;

  LCmd := AExecutable;
  UniqueString(LCmd);

  Result := CreateProcess(nil, PChar(LCmd), nil, nil, True, 0, nil, nil, SI, FProcessInfo);
  
  CloseHandle(hStdoutWrite);
  CloseHandle(hStdinRead);

  if Result then
    Log('MCP Server started: ' + AExecutable)
  else
    Log('Failed to start MCP Server: ' + AExecutable);
end;

function TSlimProxyMcpFixture.McpCall(const AMethod: string; const AParamsJson: string): string;
var
  LReq, LParams: Variant;
  LReqStr: RawUtf8;
  LBytesWritten, LBytesRead, LBytesAvail: DWORD;
  LBuffer: array[0..4095] of AnsiChar;
  LStart: Cardinal;
  LPos: Integer;
begin
  if not IsRunning then Exit('Error: MCP Server not running');

  TDocVariant.New(LReq);
  LReq.jsonrpc := '2.0';
  LReq.id := FRequestId;

  // Smart dispatch: If method is standard MCP or contains slash, send as is. Otherwise wrap as tool call.
  if (AMethod = 'initialize') or (Pos('/', AMethod) > 0) then
  begin
    LReq.method := StringToUtf8(AMethod);
    if AParamsJson <> '' then
      LReq.params := _Json(StringToUtf8(AParamsJson))
    else
      LReq.params := _Obj([]);
  end
  else
  begin
    // Assume Tool Call
    LReq.method := 'tools/call';
    if AParamsJson <> '' then
       LParams := _Json(StringToUtf8(AParamsJson))
    else
       LParams := _Obj([]);
       
    LReq.params := _Obj(['name', StringToUtf8(AMethod), 'arguments', LParams]);
  end;

  LReqStr := VariantSaveJSON(LReq) + #10;
  Inc(FRequestId);

  if not WriteFile(FhStdinWrite, LReqStr[1], Length(LReqStr), LBytesWritten, nil) then
    Exit('Error: Failed to write to stdin');

  Result := '';
  LStart := GetTickCount;
  
  while GetTickCount - LStart < 20000 do
  begin
    // Check if we already have a line in the buffer
    LPos := Pos(#10, FReadBuffer);
    if LPos > 0 then
    begin
      Result := Copy(FReadBuffer, 1, LPos - 1).Trim;
      Delete(FReadBuffer, 1, LPos);
      if Result <> '' then Exit;
      Continue;
    end;

    // Read more data
    LBytesAvail := 0;
    if PeekNamedPipe(FhStdoutRead, nil, 0, nil, @LBytesAvail, nil) and (LBytesAvail > 0) then
    begin
      if ReadFile(FhStdoutRead, LBuffer, SizeOf(LBuffer) - 1, LBytesRead, nil) and (LBytesRead > 0) then
      begin
        LBuffer[LBytesRead] := #0;
        FReadBuffer := FReadBuffer + Utf8ToString(RawUtf8(LBuffer));
        // Continue loop to process the buffer immediately
        Continue;
      end;
    end;
    
    // Check if server is still alive
    if not IsRunning then
    begin
       Result := 'Error: MCP Server terminated unexpectedly during call to ' + AMethod;
       Exit;
    end;

    Sleep(10);
  end;

  if Result = '' then
  begin
    Result := 'Error: Timeout waiting for response to ' + AMethod;
    Log(Result + '. Current buffer: ' + FReadBuffer);
  end;
end;

procedure TSlimProxyMcpFixture.McpStop;
begin
  if FhStdinWrite <> 0 then CloseHandle(FhStdinWrite);
  if FhStdoutRead <> 0 then CloseHandle(FhStdoutRead);
  if FProcessInfo.hProcess <> 0 then
  begin
    TerminateProcess(FProcessInfo.hProcess, 0);
    CloseHandle(FProcessInfo.hProcess);
    CloseHandle(FProcessInfo.hThread);
  end;
  FillChar(FProcessInfo, SizeOf(FProcessInfo), 0);
  FhStdinWrite := 0;
  FhStdoutRead := 0;
  FReadBuffer := '';
end;

initialization
  RegisterSlimFixture(TSlimProxyMcpFixture);

end.
