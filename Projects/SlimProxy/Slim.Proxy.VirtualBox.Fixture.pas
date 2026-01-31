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
    FLastGuestExecuteOutput: String;
    FVBoxManagePath: String;
    FVmName: String;
    FVmPassword: String;
    FVmUser: String;
    function ExecuteVBoxManage(const AArgs: String; out AOutput: String): Integer;
    function GetVmState: String;
    function GuestExecuteInternal(const AProgramPath, AArguments: String; AWait: Boolean): Boolean;
    function GuestExecuteCmdInternal(const ACmdLine: String; AWait: Boolean): Boolean;
  public
    procedure AfterConstruction; override;
    function  CopyToGuest(const AHostPath, AGuestPath: String): Boolean;
    function  GetVmIp: String;
    function  GuestExecute(const AProgramPath, AArguments: String): Boolean;
    function  GuestExecuteAndWait(const AProgramPath, AArguments: String): Boolean;
    function  GuestExecuteCmd(const ACmdLine: String): Boolean;
    function  GuestExecuteCmdAndWait(const ACmdLine: String): Boolean;
    function  StartVm: Boolean;
    function  WaitForGuest(ATimeoutSeconds: Integer): Boolean;
    property  LastGuestExecuteOutput: String read FLastGuestExecuteOutput;
    property  VBoxManagePath: String read FVBoxManagePath write FVBoxManagePath;
    property  VmName: String read FVmName write FVmName;
    property  VmPassword: String read FVmPassword write FVmPassword;
    property  VmUser: String read FVmUser write FVmUser;
  end;

implementation

{ TSlimProxyVirtualBoxFixture }

procedure TSlimProxyVirtualBoxFixture.AfterConstruction;
begin
  FVBoxManagePath := 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe';
end;

function TSlimProxyVirtualBoxFixture.ExecuteVBoxManage(const AArgs: String; out AOutput: String): Integer;
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
  AOutput := '';

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

    Cmd := Format('"%s" %s', [VBoxManagePath, AArgs]);
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

        AOutput := StrStream.DataString;
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

function TSlimProxyVirtualBoxFixture.GetVmState: String;
var
  Output: String;
  Lines : TStringList;
  Line  : String;
begin
  Result := 'unknown';
  if FVmName = '' then Exit;

  if ExecuteVBoxManage(Format('showvminfo "%s" --machinereadable', [FVmName]), Output) = 0 then
  begin
    Lines := TStringList.Create;
    try
      Lines.Text := Output;
      for Line in Lines do
      begin
        // Look for: VMState="running"
        if StartsText('VMState=', Line) then
        begin
          Result := StringReplace(Line, 'VMState=', '', []);
          Result := StringReplace(Result, '"', '', [rfReplaceAll]);
          Break;
        end;
      end;
    finally
      Lines.Free;
    end;
  end;
end;

function TSlimProxyVirtualBoxFixture.StartVm: Boolean;
var
  Output: String;
  State : String;
begin
  if FVmName = '' then
    raise ESlim.Create('VMName not set');

  State := GetVmState;
  if SameText(State, 'running') then
    Exit(True);

  // Try to start via 'startvm' (lowercase)
  Result := ExecuteVBoxManage(Format('startvm "%s"', [FVmName]), Output) = 0;

  // Verify state again if start command failed or succeeded, to be sure
  if not Result then
  begin
     // Double check if it became running in the meantime or if the error was misleading
     State := GetVmState;
     if SameText(State, 'running') then
       Result := True;
  end;
end;

function TSlimProxyVirtualBoxFixture.WaitForGuest(ATimeoutSeconds: Integer): Boolean;
var
  StartTick : DWORD;
  Output    : String;
  HasVersion: Boolean;
  HasIp     : Boolean;
begin
  if FVmName = '' then
    raise ESlim.Create('VMName not set');

  StartTick := GetTickCount;
  Result := False;

  while (GetTickCount - StartTick) < (ATimeoutSeconds * 1000) do
  begin
    HasVersion := False;
    HasIp := False;

    // 1. Check Guest Additions Version
    if ExecuteVBoxManage(Format('guestproperty get "%s" "/VirtualBox/GuestAdd/Version"', [FVmName]), Output) = 0 then
    begin
       if StartsText('Value: ', Output) and (Trim(Copy(Output, 8, Length(Output))) <> '') then
         HasVersion := True;
    end;

    // 2. Check IP Address
    if GetVmIp <> '' then
      HasIp := True;

    // 3. Active Check: Try to execute a simple command
    if HasVersion and HasIp then
    begin
       // If basic checks pass, try to run a command.
       // We use 'ver' as a lightweight command.
       // If this succeeds, the execution service is ready.
       if GuestExecuteCmdInternal('ver', True) then
       begin
         Result := True;
         Break;
       end;
    end;

    Sleep(1000);
  end;
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

function TSlimProxyVirtualBoxFixture.GuestExecute(const AProgramPath, AArguments: String): Boolean;
begin
  Result := GuestExecuteInternal(AProgramPath, AArguments, false);
end;

function TSlimProxyVirtualBoxFixture.GuestExecuteAndWait(const AProgramPath, AArguments: String): Boolean;
begin
  Result := GuestExecuteInternal(AProgramPath, AArguments, true);
end;

function TSlimProxyVirtualBoxFixture.GuestExecuteCmd(const ACmdLine: String): Boolean;
begin
  Result := GuestExecuteCmdInternal(ACmdLine, false);
end;

function TSlimProxyVirtualBoxFixture.GuestExecuteCmdAndWait(const ACmdLine: String): Boolean;
begin
  Result := GuestExecuteCmdInternal(ACmdLine, true);
end;

function TSlimProxyVirtualBoxFixture.GuestExecuteCmdInternal(const ACmdLine: String; AWait: Boolean): Boolean;
begin
  Result := GuestExecuteInternal('cmd.exe', '/c "' + ACmdLine + '"', AWait);
end;

function TSlimProxyVirtualBoxFixture.GuestExecuteInternal(const AProgramPath, AArguments: String; AWait: Boolean): Boolean;
var
  Args: String;
begin
  FLastGuestExecuteOutput := '';

  if FVmName = '' then
    raise ESlim.Create('VmName not set');
  if FVmUser = '' then
    raise ESlim.Create('VmUser not set');

  Args := Format('guestcontrol "%s" ', [FVmName]);

  if AWait then
    Args := Args + 'run '  // Use 'run' for sync
  else
    Args := Args + 'start '; // Use 'start' for async

  Args := Args + Format('--username "%s" --password "%s" --exe "%s"',
    [FVmUser, FVmPassword, AProgramPath]);

  if AArguments <> '' then
    Args := Args + ' -- ' + AArguments;

  Result := ExecuteVBoxManage(Args, FLastGuestExecuteOutput) = 0;
end;

function TSlimProxyVirtualBoxFixture.CopyToGuest(const AHostPath, AGuestPath: String): Boolean;
var
  Output: String;
begin
  if FVmName = '' then
    raise ESlim.Create('VmName not set');
  if FVmUser = '' then
    raise ESlim.Create('VmUser not set');

  Result := ExecuteVBoxManage(Format('guestcontrol "%s" copyto --username "%s" --password "%s" --target-directory "%s" "%s"',
    [FVmName, FVmUser, FVmPassword, AGuestPath, AHostPath]), Output) = 0;
end;

initialization

RegisterSlimFixture(TSlimProxyVirtualBoxFixture);

end.
