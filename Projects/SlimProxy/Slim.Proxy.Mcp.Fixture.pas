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
  SI.hStdError := hStdoutWrite;
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
  LReqStr, LLine: RawUtf8;
  LBytesWritten, LBytesRead, LBytesAvail: DWORD;
  LBuffer: array[0..4095] of AnsiChar;
  LResponse: string;
  LStart: Cardinal;
begin
  if not IsRunning then Exit('Error: MCP Server not running');

  TDocVariant.New(LReq);
  LReq.jsonrpc := '2.0';
  LReq.id := FRequestId;
  LReq.method := StringToUtf8(AMethod);
  
  if AParamsJson <> '' then
    LReq.params := _Json(StringToUtf8(AParamsJson))
  else
    LReq.params := _Obj([]);

  LReqStr := VariantSaveJSON(LReq) + #10;
  Inc(FRequestId);

  if not WriteFile(FhStdinWrite, LReqStr[1], Length(LReqStr), LBytesWritten, nil) then
    Exit('Error: Failed to write to stdin');

  LResponse := '';
  LStart := GetTickCount;
  
  // Wait for response (simplified: wait for a full line)
  while GetTickCount - LStart < 5000 do
  begin
    LBytesAvail := 0;
    if PeekNamedPipe(FhStdoutRead, nil, 0, nil, @LBytesAvail, nil) and (LBytesAvail > 0) then
    begin
      if ReadFile(FhStdoutRead, LBuffer, SizeOf(LBuffer) - 1, LBytesRead, nil) and (LBytesRead > 0) then
      begin
        LBuffer[LBytesRead] := #0;
        LResponse := LResponse + Utf8ToString(RawUtf8(LBuffer));
        if Pos(#10, LResponse) > 0 then Break;
      end;
    end;
    Sleep(50);
  end;

  Result := LResponse.Trim;
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
end;

initialization
  RegisterSlimFixture(TSlimProxyMcpFixture);

end.
