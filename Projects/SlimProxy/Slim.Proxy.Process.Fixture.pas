// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.Process.Fixture;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.RegularExpressions,
  System.SysUtils,

  Slim.Fixture,
  Slim.Proxy.Base;

type

  [SlimFixture('Process', 'SlimProxy')]
  TSlimProxyProcessFixture = class(TSlimProxyBaseFixture)
  private
    FLastExitCode: Integer;
    FLastOutput  : String;
    function RunCommand(const ACommandLine: String; out AOutput: String): Integer;
  public
    function LastExitCode: Integer;
    function LastOutput: String;
    function OutputContains(const AText: String): Boolean;
    function OutputMatches(const APattern: String): Boolean;
    function OutputMatchCount(const APattern: String): Integer;
    function Run(const ACommand: String): Boolean;
  end;

implementation

{ TSlimProxyProcessFixture }

function TSlimProxyProcessFixture.OutputMatchCount(const APattern: String): Integer;
begin
  Result := TRegEx.Matches(FLastOutput, APattern, [roIgnoreCase, roMultiLine]).Count;
end;

function TSlimProxyProcessFixture.OutputMatches(const APattern: String): Boolean;
begin
  Result := TRegEx.IsMatch(FLastOutput, APattern, [roIgnoreCase, roMultiLine]);
end;

function TSlimProxyProcessFixture.RunCommand(const ACommandLine: String; out AOutput: String): Integer;
var
  Buffer    : Array[0..4095] of AnsiChar;
  Bytes     : TBytes;
  BytesAvail: DWORD;
  BytesRead : DWORD;
  Cmd       : String;
  ExitCode  : DWORD;
  hNullInput: THandle;
  hRead     : THandle;
  hWrite    : THandle;
  MemStream : TMemoryStream;
  PI        : TProcessInformation;
  SA        : TSecurityAttributes;
  SI        : TStartupInfo;
  WaitRes   : DWORD;
begin
  Result := -1;
  SA.nLength := SizeOf(TSecurityAttributes);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  // Create pipe for stdout/stderr
  if not CreatePipe(hRead, hWrite, @SA, 0) then
    RaiseLastOSError;

  // Create handle to NUL for stdin
  hNullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @SA, OPEN_EXISTING, 0, 0);
  if hNullInput = INVALID_HANDLE_VALUE then
  begin
    CloseHandle(hRead);
    CloseHandle(hWrite);
    RaiseLastOSError;
  end;

  try
    FillChar(SI, SizeOf(TStartupInfo), 0);
    SI.cb := SizeOf(TStartupInfo);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := hWrite;
    SI.hStdError := hWrite;
    SI.hStdInput := hNullInput;

    Cmd := ACommandLine;
    UniqueString(Cmd);

    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, 0, nil, nil, SI, PI) then
      RaiseLastOSError;

    CloseHandle(hWrite);
    CloseHandle(hNullInput);

    try
      MemStream := TMemoryStream.Create;
      try
        repeat
          // Check if the process is still running
          WaitRes := WaitForSingleObject(PI.hProcess, 50);

          // Read all available data
          while True do
          begin
            BytesAvail := 0;
            if not PeekNamedPipe(hRead, nil, 0, nil, @BytesAvail, nil) then
              Break; // Error or pipe broken

            if BytesAvail = 0 then
              Break; // No data available right now

            if not ReadFile(hRead, Buffer, SizeOf(Buffer), BytesRead, nil) then
              Break;

            if BytesRead > 0 then
              MemStream.Write(Buffer, BytesRead)
            else
              Break;
          end;

        until (WaitRes <> WAIT_TIMEOUT);

        if MemStream.Size > 0 then
        begin
          SetLength(Bytes, MemStream.Size);
          MemStream.Position := 0;
          MemStream.Read(Bytes, 0, MemStream.Size);
          try
            AOutput := TEncoding.UTF8.GetString(Bytes);
          except
            // Fallback if UTF-8 decoding fails (e.g. mixed output)
            AOutput := TEncoding.ANSI.GetString(Bytes);
          end;
        end
        else
          AOutput := '';
      finally
        MemStream.Free;
      end;

      if GetExitCodeProcess(PI.hProcess, ExitCode) then
        Result := Integer(ExitCode);

    finally
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
    end;
  finally
    CloseHandle(hRead);
  end;
end;

function TSlimProxyProcessFixture.Run(const ACommand: String): Boolean;
begin
  FLastExitCode := RunCommand(ACommand, FLastOutput);
  Result := FLastExitCode = 0;
end;

function TSlimProxyProcessFixture.LastExitCode: Integer;
begin
  Result := FLastExitCode;
end;

function TSlimProxyProcessFixture.LastOutput: String;
begin
  Result := FLastOutput;
end;

function TSlimProxyProcessFixture.OutputContains(const AText: String): Boolean;
begin
  Result := Pos(AText, FLastOutput) > 0;
end;

initialization

RegisterSlimFixture(TSlimProxyProcessFixture);

end.
