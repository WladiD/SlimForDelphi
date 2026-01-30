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

  Slim.Fixture,
  Slim.Proxy.Base;

type
  [SlimFixture('VirtualBox', 'SlimProxy')]
  TSlimProxyVirtualBoxFixture = class(TSlimProxyBaseFixture)
  private
    FVBoxManagePath: String;
    function ExecuteVBoxManage(const Args: String; out Output: String): Integer;
    function GetVBoxManagePath: String;
  public
    procedure SetVBoxManagePath(const Path: String);
    function GetVMIP(const VMName: String): String;
    function StartVM(const VMName: String): Boolean;
    function GuestExecute(const VMName, User, Password, ProgramPath, Arguments: String; NoWait: Boolean): Boolean;
    function CopyToGuest(const VMName, User, Password, HostPath, GuestPath: String): Boolean;
  end;

implementation

{ TSlimProxyVirtualBoxFixture }

function TSlimProxyVirtualBoxFixture.GetVBoxManagePath: String;
begin
  if FVBoxManagePath = '' then
    Result := 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
  else
    Result := FVBoxManagePath;
end;

procedure TSlimProxyVirtualBoxFixture.SetVBoxManagePath(const Path: String);
begin
  FVBoxManagePath := Path;
end;

function TSlimProxyVirtualBoxFixture.ExecuteVBoxManage(const Args: String; out Output: String): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  hRead, hWrite: THandle;
  Cmd: String;
  BytesRead, BytesAvail: DWORD;
  Buffer: array[0..4095] of AnsiChar;
  StrStream: TStringStream;
  WaitRes: DWORD;
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

    Cmd := Format('"%s" %s', [GetVBoxManagePath, Args]);
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

function TSlimProxyVirtualBoxFixture.StartVM(const VMName: String): Boolean;
var
  Output: String;
begin
  // Try to start via 'startvm'
  Result := ExecuteVBoxManage(Format('startvm "%s"', [VMName]), Output) = 0;
  // If it fails, it might be already running. We could check that, but for now strict check.
  // Actually, 'startvm' fails if already running. We might want to tolerate that?
  if not Result and (Pos('is already locked', Output) > 0) then
    Result := True;
end;

function TSlimProxyVirtualBoxFixture.GetVMIP(const VMName: String): String;
var
  Output: String;
  P: Integer;
begin
  // guestproperty get "VM" "/VirtualBox/GuestInfo/Net/0/V4/IP"
  if ExecuteVBoxManage(Format('guestproperty get "%s" "/VirtualBox/GuestInfo/Net/0/V4/IP"', [VMName]), Output) = 0 then
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

function TSlimProxyVirtualBoxFixture.GuestExecute(const VMName, User, Password, ProgramPath, Arguments: String; NoWait: Boolean): Boolean;
var
  Args, Output: String;
begin
  // guestcontrol run --username ... --password ... --exe ... -- ...
  Args := Format('guestcontrol "%s" ', [VMName]);
  
  if NoWait then
    Args := Args + 'start ' // Use 'start' for async
  else
    Args := Args + 'run ';  // Use 'run' for sync
    
  Args := Args + Format('--username "%s" --password "%s" --exe "%s"', 
    [User, Password, ProgramPath]);
    
  if Arguments <> '' then
    Args := Args + ' -- ' + Arguments;
    
  Result := ExecuteVBoxManage(Args, Output) = 0;
end;

function TSlimProxyVirtualBoxFixture.CopyToGuest(const VMName, User, Password, HostPath, GuestPath: String): Boolean;
var
  Output: String;
begin
  // guestcontrol copyto --username ... --password ... target "source"
  Result := ExecuteVBoxManage(Format('guestcontrol "%s" copyto --username "%s" --password "%s" --target-directory "%s" "%s"', 
    [VMName, User, Password, GuestPath, HostPath]), Output) = 0;
end;

initialization
  RegisterSlimFixture(TSlimProxyVirtualBoxFixture);

end.
