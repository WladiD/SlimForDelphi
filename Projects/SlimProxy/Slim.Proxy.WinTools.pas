// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Windows helpers for the host control and for the watchdog.
///
///   Everything in here is application agnostic: the callers pass a
///   TSlimProxyWindowConfig, nothing is decided by the name of a concrete
///   product, form or button.
/// </summary>
unit Slim.Proxy.WinTools;

interface

uses

  Winapi.Messages,
  Winapi.Windows,

  System.Classes,
  System.SysUtils,

  Slim.Proxy.Config;

type

  /// <summary>Result of a window visit. Return False to stop enumerating.</summary>
  TSlimProxyWindowVisitor = reference to function(AWnd: HWND): Boolean;

  /// <summary>Everything that is known about one top level window of a process.</summary>
  TSlimProxyWindowInfo = record
    Buttons  : String;
    ClassName: String;
    Handle   : HWND;
    HasMenu  : Boolean;
    Hit      : String;
    Kind     : TSlimProxyWindowKind;
    Text     : String;
    Title    : String;
    function Describe: String;
  end;

  TSlimProxyWindowInfos = TArray<TSlimProxyWindowInfo>;

function SlimProxyGetListenerPid(APort: Integer): Cardinal;

procedure SlimProxyForEachTopWindow(APid: Cardinal; const AVisitor: TSlimProxyWindowVisitor);

procedure SlimProxyForEachChild(AParent: HWND; const AVisitor: TSlimProxyWindowVisitor);

function SlimProxyWindowClassName(AWnd: HWND): String;

function SlimProxyWindowText(AWnd: HWND): String;

function SlimProxyCollectChildText(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;

function SlimProxyCollectButtonCaptions(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;

function SlimProxyReadWindowInfo(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): TSlimProxyWindowInfo;

function SlimProxyCollectWindows(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): TSlimProxyWindowInfos;

function SlimProxyDumpWindows(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): String;

function SlimProxyDismissWindow(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;

function SlimProxyDismissDialogs(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): String;

function SlimProxyFindMainWindow(APid: Cardinal): HWND;

function SlimProxyProcessCpuTimeMs(APid: Cardinal): UInt64;

function SlimProxyIsProcessRunning(APid: Cardinal): Boolean;

function SlimProxyTryGetExitCode(AHandle: THandle; out AExitCode: DWORD): Boolean;

implementation

uses
  Winapi.Winsock2;

{ ----------------------------------------------------------------------- }
{ Port ownership                                                          }
{ ----------------------------------------------------------------------- }

const
  // Not declared by the RTL.
  ProcessQueryLimitedInformation = $1000;

  TcpTableOwnerPidListener = 3; // TCP_TABLE_OWNER_PID_LISTENER
  MibTcpStateListen        = 2; // MIB_TCP_STATE_LISTEN

type
  TMibTcpRowOwnerPid = record
    dwState     : DWORD;
    dwLocalAddr : DWORD;
    dwLocalPort : DWORD;
    dwRemoteAddr: DWORD;
    dwRemotePort: DWORD;
    dwOwningPid : DWORD;
  end;

  PMibTcpRowOwnerPid = ^TMibTcpRowOwnerPid;

function GetExtendedTcpTable(pTcpTable: Pointer; var pdwSize: DWORD; bOrder: BOOL;
  ulAf: ULONG; TableClass: Integer; Reserved: ULONG): DWORD; stdcall;
  external 'iphlpapi.dll' name 'GetExtendedTcpTable';

/// <summary>
///   Returns the process id that is LISTENING on APort, or 0. A plain "somebody
///   listens" is no information at all: a foreign host on the same port lets a
///   run look green and proves nothing.
/// </summary>
function SlimProxyGetListenerPid(APort: Integer): Cardinal;
var
  LBuf  : TBytes;
  LCount: DWORD;
  LRow  : PMibTcpRowOwnerPid;
  LSize : DWORD;
begin
  Result := 0;
  LSize := 0;
  GetExtendedTcpTable(nil, LSize, False, AF_INET, TcpTableOwnerPidListener, 0);
  if LSize = 0 then
    Exit;
  SetLength(LBuf, LSize);
  if GetExtendedTcpTable(@LBuf[0], LSize, False, AF_INET, TcpTableOwnerPidListener, 0) <> NO_ERROR then
    Exit;

  // Pointer arithmetic instead of indexing an "array[0..0]" pseudo table: with
  // range checking on (Debug) every index > 0 into such a table raises
  // ERangeError.
  LCount := PDWord(@LBuf[0])^;
  if LCount = 0 then
    Exit;
  LRow := PMibTcpRowOwnerPid(PByte(@LBuf[0]) + SizeOf(DWORD));
  for var I: DWORD := 0 to LCount - 1 do
  begin
    // dwLocalPort carries the port in NETWORK byte order in its lower 16 bits,
    // the upper ones are not necessarily 0. A plain Word() cast raises
    // ERangeError with range checking on.
    if (LRow.dwState = MibTcpStateListen) and
       (ntohs(u_short(LRow.dwLocalPort and $FFFF)) = APort) then
      Exit(LRow.dwOwningPid);
    Inc(LRow);
  end;
end;

{ ----------------------------------------------------------------------- }
{ Window enumeration                                                      }
{ ----------------------------------------------------------------------- }

type
  PSlimProxyEnumRec = ^TSlimProxyEnumRec;
  TSlimProxyEnumRec = record
    Pid    : Cardinal;
    Visitor: TSlimProxyWindowVisitor;
  end;

function SlimProxyEnumTopProc(AWnd: HWND; AParam: LPARAM): BOOL; stdcall;
var
  LPid: DWORD;
  LRec: PSlimProxyEnumRec;
begin
  LRec := PSlimProxyEnumRec(AParam);
  Result := True;
  LPid := 0;
  GetWindowThreadProcessId(AWnd, @LPid);
  if LPid = LRec.Pid then
    Result := LRec.Visitor(AWnd);
end;

function SlimProxyEnumChildProc(AWnd: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  Result := PSlimProxyEnumRec(AParam).Visitor(AWnd);
end;

/// <summary>Enumerates the top level windows that belong to APid.</summary>
procedure SlimProxyForEachTopWindow(APid: Cardinal; const AVisitor: TSlimProxyWindowVisitor);
var
  LRec: TSlimProxyEnumRec;
begin
  // The enumeration state travels in the LPARAM, not in a global: the watchdog
  // enumerates from its own thread while a fixture may be doing the same.
  LRec.Pid := APid;
  LRec.Visitor := AVisitor;
  EnumWindows(@SlimProxyEnumTopProc, LPARAM(@LRec));
end;

/// <summary>Enumerates all descendants of AParent.</summary>
procedure SlimProxyForEachChild(AParent: HWND; const AVisitor: TSlimProxyWindowVisitor);
var
  LRec: TSlimProxyEnumRec;
begin
  LRec.Pid := 0;
  LRec.Visitor := AVisitor;
  EnumChildWindows(AParent, @SlimProxyEnumChildProc, LPARAM(@LRec));
end;

function SlimProxyWindowClassName(AWnd: HWND): String;
var
  LBuf: array[0..255] of Char;
begin
  SetString(Result, LBuf, GetClassName(AWnd, LBuf, Length(LBuf)));
end;

/// <summary>
///   Window text across process boundaries. GetWindowText is not guaranteed to
///   reach a control of a foreign process, so WM_GETTEXT is used as fallback -
///   with a timeout, because the caller may be watching a process whose main
///   thread is stuck.
/// </summary>
function SlimProxyWindowText(AWnd: HWND): String;
const
  GetTextTimeoutMs = 300;
var
  LBuf   : array[0..1023] of Char;
  LResult: DWORD_PTR;
begin
  SetString(Result, LBuf, GetWindowText(AWnd, LBuf, Length(LBuf)));
  if Result <> '' then
    Exit;

  // GetWindowText does not reach a control of a foreign process. Ask the window
  // itself - with a timeout, the target may be stuck.
  LBuf[0] := #0;
  LResult := 0;
  if SendMessageTimeout(AWnd, WM_GETTEXT, Length(LBuf), LPARAM(@LBuf[0]),
       SMTO_ABORTIFHUNG, GetTextTimeoutMs, @LResult) <> 0 then
    Result := String(PChar(@LBuf[0]));
end;

/// <summary>Collects the texts of all child controls, i.e. the message of a dialog.</summary>
function SlimProxyCollectChildText(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    SlimProxyForEachChild(AWnd,
      function(AChild: HWND): Boolean
      var
        LText: String;
      begin
        Result := True;
        // Button captions are collected separately - taking them as message text
        // would let an "OK" caption satisfy a wording search.
        if AConfig.IsButtonClass(SlimProxyWindowClassName(AChild)) then
          Exit;
        LText := SlimProxyWindowText(AChild);
        if LText <> '' then
        begin
          if LSb.Length > 0 then
            LSb.Append(' | ');
          LSb.Append(LText);
        end;
      end);
    Result := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

/// <summary>Collects the captions of all button like child controls.</summary>
function SlimProxyCollectButtonCaptions(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    SlimProxyForEachChild(AWnd,
      function(AChild: HWND): Boolean
      var
        LText: String;
      begin
        Result := True;
        if not AConfig.IsButtonClass(SlimProxyWindowClassName(AChild)) then
          Exit;
        LText := SlimProxyWindowText(AChild);
        if LText = '' then
          Exit;
        if LSb.Length > 0 then
          LSb.Append(', ');
        LSb.Append('"').Append(LText).Append('"');
      end);
    Result := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

/// <summary>Reads one top level window into a TSlimProxyWindowInfo and classifies it.</summary>
function SlimProxyReadWindowInfo(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): TSlimProxyWindowInfo;
begin
  Result.Handle := AWnd;
  Result.ClassName := SlimProxyWindowClassName(AWnd);
  Result.Title := SlimProxyWindowText(AWnd);
  Result.Text := SlimProxyCollectChildText(AWnd, AConfig);
  Result.Buttons := SlimProxyCollectButtonCaptions(AWnd, AConfig);
  Result.HasMenu := GetMenu(AWnd) <> 0;
  Result.Kind := AConfig.ClassifyWindow(Result.ClassName, Result.Title, Result.Text, Result.Hit);
end;

/// <summary>All visible top level windows of APid, classified.</summary>
function SlimProxyCollectWindows(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): TSlimProxyWindowInfos;
var
  LResult: TSlimProxyWindowInfos;
begin
  LResult := [];
  SlimProxyForEachTopWindow(APid,
    function(AWnd: HWND): Boolean
    begin
      Result := True;
      if not IsWindowVisible(AWnd) then
        Exit;
      LResult := LResult + [SlimProxyReadWindowInfo(AWnd, AConfig)];
    end);
  Result := LResult;
end;

/// <summary>One line for a log entry or an error message.</summary>
function TSlimProxyWindowInfo.Describe: String;
const
  KindNames: array[TSlimProxyWindowKind] of String = ('ignore', 'message', 'error', 'fatal');
begin
  Result := Format('cls=%s title="%s"', [ClassName, Title]);
  if Text <> '' then
    Result := Result + Format(' text="%s"', [Text]);
  if Buttons <> '' then
    Result := Result + ' buttons=' + Buttons;
  if HasMenu then
    Result := Result + ' menu=yes';
  Result := Result + ' kind=' + KindNames[Kind];
  if Hit <> '' then
    Result := Result + Format(' pattern="%s"', [Hit]);
end;

/// <summary>
///   Class, title, text and button captions of every visible window - exactly
///   the information that is missing when a start up stops without a port.
/// </summary>
function SlimProxyDumpWindows(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): String;
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    for var LInfo in SlimProxyCollectWindows(APid, AConfig) do
      LSb.AppendLine(LInfo.Describe);
    if LSb.Length = 0 then
      Result := '(no visible window)'
    else
      Result := LSb.ToString.TrimRight;
  finally
    LSb.Free;
  end;
end;

{ ----------------------------------------------------------------------- }
{ Clicking                                                               }
{ ----------------------------------------------------------------------- }

/// <summary>
///   Clicks the first matching dismiss button INSIDE AWnd. Dismissing is always
///   hwnd exact: a process wide click on "OK" would hit a legitimate form on a
///   false alarm.
/// </summary>
function SlimProxyDismissWindow(AWnd: HWND; const AConfig: TSlimProxyWindowConfig): String;
const
  ClickTimeoutMs = 1000;
var
  LFound  : HWND;
  LCaption: String;
begin
  Result := '';
  LFound := 0;
  LCaption := '';

  SlimProxyForEachChild(AWnd,
    function(AChild: HWND): Boolean
    var
      LText: String;
    begin
      Result := True;
      if not AConfig.IsButtonClass(SlimProxyWindowClassName(AChild)) then
        Exit;
      if not (IsWindowVisible(AChild) and IsWindowEnabled(AChild)) then
        Exit;
      LText := SlimProxyNormalizeCaption(SlimProxyWindowText(AChild));
      if LText = '' then
        Exit;
      for var LWanted in SlimProxySplitList(AConfig.DismissButtons) do
        if SameText(LText, SlimProxyNormalizeCaption(LWanted)) then
        begin
          LFound := AChild;
          LCaption := LText;
          Exit(False);
        end;
    end);

  if LFound = 0 then
    Exit;

  // Send the click both ways: some controls only react to the mouse messages,
  // others only to BM_CLICK. BM_CLICK goes out with a timeout, otherwise a
  // follow up dialog raised by the click would block the calling thread.
  PostMessage(LFound, WM_LBUTTONDOWN, MK_LBUTTON, 0);
  PostMessage(LFound, WM_LBUTTONUP, 0, 0);
  SendMessageTimeout(LFound, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, ClickTimeoutMs, nil);
  Result := Format('clicked "%s" in cls=%s title="%s"',
    [LCaption, SlimProxyWindowClassName(AWnd), SlimProxyWindowText(AWnd)]);
end;

/// <summary>
///   Dismisses the start up dialogs of a process: every visible window WITHOUT
///   a menu bar is treated as a message window (see SlimProxyFindMainWindow).
///   Returns a description of what was clicked, or an empty string.
/// </summary>
function SlimProxyDismissDialogs(APid: Cardinal; const AConfig: TSlimProxyWindowConfig): String;
var
  LResult: String;
begin
  LResult := '';
  SlimProxyForEachTopWindow(APid,
    function(AWnd: HWND): Boolean
    var
      LClicked: String;
    begin
      Result := True;
      if not IsWindowVisible(AWnd) then
        Exit;
      // A window with a menu bar is the main window, not a dialog. Clicking
      // inside it would press a button of a legitimate form.
      if GetMenu(AWnd) <> 0 then
        Exit;
      LClicked := SlimProxyDismissWindow(AWnd, AConfig);
      if LClicked <> '' then
      begin
        if LResult <> '' then
          LResult := LResult + '; ';
        LResult := LResult + LClicked;
      end;
    end);
  Result := LResult;
end;

/// <summary>
///   The main window of a process. Not decidable by the title - many
///   applications title their message boxes with Application.Title, i.e.
///   exactly like the main window. The shape decides: the main window carries a
///   menu bar, a modal message window never does. If nothing carries a menu, an
///   unowned visible window is taken as second best.
/// </summary>
function SlimProxyFindMainWindow(APid: Cardinal): HWND;
var
  LFallback: HWND;
  LMain    : HWND;
begin
  LMain := 0;
  LFallback := 0;
  SlimProxyForEachTopWindow(APid,
    function(AWnd: HWND): Boolean
    begin
      Result := True;
      if not IsWindowVisible(AWnd) then
        Exit;
      if GetMenu(AWnd) <> 0 then
      begin
        LMain := AWnd;
        Exit(False);
      end;
      // Second best: a visible window that is not owned by another one. Message
      // boxes are owned, so they are ruled out by this.
      if (LFallback = 0) and (GetWindow(AWnd, GW_OWNER) = 0) then
        LFallback := AWnd;
    end);
  if LMain <> 0 then
    Result := LMain
  else
    Result := LFallback;
end;

{ ----------------------------------------------------------------------- }
{ Process state                                                          }
{ ----------------------------------------------------------------------- }

/// <summary>Total CPU time (kernel + user) of a process in ms, or 0 if unknown.</summary>
function SlimProxyProcessCpuTimeMs(APid: Cardinal): UInt64;
var
  LCreation: TFileTime;
  LExit    : TFileTime;
  LHandle  : THandle;
  LKernel  : TFileTime;
  LUser    : TFileTime;
begin
  Result := 0;
  LHandle := OpenProcess(ProcessQueryLimitedInformation, False, APid);
  if LHandle = 0 then
    LHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, APid);
  if LHandle = 0 then
    Exit;
  try
    if GetProcessTimes(LHandle, LCreation, LExit, LKernel, LUser) then
      Result := (UInt64(LKernel.dwHighDateTime) shl 32 + LKernel.dwLowDateTime +
                 UInt64(LUser.dwHighDateTime) shl 32 + LUser.dwLowDateTime) div 10000;
  finally
    CloseHandle(LHandle);
  end;
end;

function SlimProxyIsProcessRunning(APid: Cardinal): Boolean;
var
  LCode  : DWORD;
  LHandle: THandle;
begin
  Result := False;
  if APid = 0 then
    Exit;
  LHandle := OpenProcess(ProcessQueryLimitedInformation, False, APid);
  if LHandle = 0 then
    LHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, APid);
  if LHandle = 0 then
    Exit;
  try
    Result := GetExitCodeProcess(LHandle, LCode) and (LCode = STILL_ACTIVE);
  finally
    CloseHandle(LHandle);
  end;
end;

/// <summary>True if the process has ended; AExitCode then carries its exit code.</summary>
function SlimProxyTryGetExitCode(AHandle: THandle; out AExitCode: DWORD): Boolean;
begin
  AExitCode := 0;
  Result := GetExitCodeProcess(AHandle, AExitCode) and (AExitCode <> STILL_ACTIVE);
end;

end.
