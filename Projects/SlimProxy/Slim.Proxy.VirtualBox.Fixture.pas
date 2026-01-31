// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.VirtualBox.Fixture;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.StrUtils,
  System.SysUtils,

  Slim.Common,
  Slim.Fixture,
  Slim.Proxy.Base;

type

  [SlimFixture('VirtualBox', 'SlimProxy')]
  TSlimProxyVirtualBoxFixture = class(TSlimProxyBaseFixture)
  private
    FVBoxManagePath: String;
    FVmName: String;
    FVmPassword: String;
    FVmUser: String;
    function ExecuteVBoxManage(const Args: String; out Output: String): Integer;
  public
    constructor Create;
    function  CopyToGuest(const HostPath, GuestPath: String): Boolean;
    function  GetVmIp: String;
    function  GuestExecute(const ProgramPath, Arguments: String; NoWait: Boolean): Boolean;
    function  StartVm: Boolean;
    property  VBoxManagePath: String read FVBoxManagePath write FVBoxManagePath;
    property  VmName: String read FVmName write FVmName;
    property  VmPassword: String read FVmPassword write FVmPassword;
    property  VmUser: String read FVmUser write FVmUser;
  end;

implementation

{ TSlimProxyVirtualBoxFixture }

constructor TSlimProxyVirtualBoxFixture.Create;
begin
  FVBoxManagePath := 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe';
end;

function TSlimProxyVirtualBoxFixture.ExecuteVBoxManage(const Args: String; out Output: String): Integer;
var
  Buffer    : Array[0..4095] of AnsiChar;
  BytesAvail: DWORD;
  BytesRead : DWORD;
  Cmd       : String;
  hRead     : THandle;
  hWrite    : THandle;
  PI        : TProcessInformation;
  SA        : TSecurityAttributes;
  SI        : TStartupInfo;
  StrStream : TStringStream;
  WaitRes   : DWORD;
begin
  Result := -1;
  Output := '';

  SA.nLength := SizeOf(TSecurityAttributes);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(hRead, hWrite, @SA, 0) then
    RaiseLastOSError;

  try
    ZeroMemory(@SI, SizeOf(SI));
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := hWrite;
    SI.hStdError := hWrite;

    Cmd := Format('"%s" %s', [VBoxManagePath, Args]);
    UniqueString(Cmd);

    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, 0, nil, nil, SI, PI) then
      RaiseLastOSError;

    CloseHandle(hWrite); // Close write end in this process

    try
      StrStream := TStringStream.Create('', TEncoding.ANSI);
      try
        repeat
          WaitRes := WaitForSingleObject(PI.hProcess, 50);

          while True do
          begin
             BytesAvail := 0;
             if not PeekNamedPipe(hRead, nil, 0, nil, @BytesAvail, nil) then Break;
             if BytesAvail = 0 then Break;

             if not ReadFile(hRead, Buffer, SizeOf(Buffer), BytesRead, nil) then Break;
             if BytesRead > 0 then StrStream.Write(Buffer, BytesRead);
          end;
        until WaitRes <> WAIT_TIMEOUT;

        Output := StrStream.DataString;
      finally
        StrStream.Free;
      end;

      GetExitCodeProcess(PI.hProcess, DWORD(Result));
    finally
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
    end;
  finally
    CloseHandle(hRead);
  end;
end;

function TSlimProxyVirtualBoxFixture.StartVm: Boolean;
var
  Output: String;
begin
  if FVmName = '' then
    raise ESlim.Create('VMName not set');

  // Try to start via 'StartVm'
  Result := ExecuteVBoxManage(Format('StartVm "%s"', [FVmName]), Output) = 0;
  if not Result and (Pos('is already locked', Output) > 0) then
    Result := True;
end;

function TSlimProxyVirtualBoxFixture.GetVmIp: String;
var
  Output: String;
begin
  if FVmName = '' then
    raise ESlim.Create('VMName not set');

  if ExecuteVBoxManage(Format('guestproperty get "%s" "/VirtualBox/GuestInfo/Net/0/V4/IP"', [FVmName]), Output) = 0 then
  begin
    // Output format: "Value: 192.168.x.x"
    if StartsText('Value: ', Output) then
    begin
      Result := Trim(Copy(Output, 8, Length(Output)));
      Exit;
    end;
  end;
  Result := '';
end;

function TSlimProxyVirtualBoxFixture.GuestExecute(const ProgramPath, Arguments: String; NoWait: Boolean): Boolean;
var
  Args, Output: String;
begin
  if FVmName = '' then
    raise ESlim.Create('VmName not set');
  if FVmUser = '' then
    raise ESlim.Create('VmUser not set');

  Args := Format('guestcontrol "%s" ', [FVmName]);

  if NoWait then
    Args := Args + 'start ' // Use 'start' for async
  else
    Args := Args + 'run ';  // Use 'run' for sync

  Args := Args + Format('--username "%s" --password "%s" --exe "%s"',
    [FVmUser, FVmPassword, ProgramPath]);

  if Arguments <> '' then
    Args := Args + ' -- ' + Arguments;

  Result := ExecuteVBoxManage(Args, Output) = 0;
end;

function TSlimProxyVirtualBoxFixture.CopyToGuest(const HostPath, GuestPath: String): Boolean;
var
  Output: String;
begin
  if FVmName = '' then
    raise ESlim.Create('VmName not set');
  if FVmUser = '' then
    raise ESlim.Create('VmUser not set');

  Result := ExecuteVBoxManage(Format('guestcontrol "%s" copyto --username "%s" --password "%s" --target-directory "%s" "%s"',
    [FVmName, FVmUser, FVmPassword, GuestPath, HostPath]), Output) = 0;
end;

initialization

RegisterSlimFixture(TSlimProxyVirtualBoxFixture);

end.
