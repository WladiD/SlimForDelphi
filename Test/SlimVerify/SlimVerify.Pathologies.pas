// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   The simulation target.
///
///   SlimVerify simulates the pathologies of a GUI Slim host, so that the read
///   timeout, the host control and the watchdog can be accepted automatically -
///   without any foreign application, without scripts, in seconds instead of
///   minutes.
///
///   Command line:
///     --StartupDelay=&lt;ms&gt;     start the Slim server only after this delay
///     --StartupDialog=&lt;ms&gt;    show a modal window with a button on its OWN
///                             window class before the Slim server starts; the
///                             value is a self close safety net
///     --AbortWindow=&lt;class&gt;   show a window of that class and never start Slim
///     --DieAfter=&lt;ms&gt;         terminate the process after that time
///     --DieExitCode=&lt;code&gt;    exit code used by --DieAfter (default 3)
///     --HoldPort=&lt;port&gt;       occupy that port without serving Slim
///     --BlockMax=&lt;ms&gt;         upper bound for the "Block Forever" fixture
/// </summary>
unit SlimVerify.Pathologies;

interface

uses

  Winapi.Messages,
  Winapi.Windows,

  System.Classes,
  System.SysUtils;

const

  /// <summary>
  ///   Window class of the simulated dialogs. Deliberately its own class - a
  ///   proxy that only knows the native class would not find them.
  /// </summary>
  SlimVerifyDialogClass = 'SlimVerifyDialog';

  /// <summary>
  ///   Class of the button in the START UP dialog. Deliberately a name that
  ///   neither the class list nor the substring heuristic of the proxy defaults
  ///   matches, so that the start up test really proves the configurability of
  ///   the button class list.
  /// </summary>
  SlimVerifyCustomControlClass = 'SlimVerifyPushControl';

  /// <summary>Default exit code of --DieAfter.</summary>
  SlimVerifyDefaultDieExitCode = 3;

  /// <summary>Default upper bound of the "Block Forever" fixture.</summary>
  SlimVerifyDefaultBlockMaxMs = 60000;

  /// <summary>
  ///   Delay before a "Shutdown" really closes the window. Long enough for the
  ///   answer to that very call and the closing Slim handshake to get through.
  /// </summary>
  SlimVerifyShutdownDelayMs = 1500;

type

  TSlimVerifyOptions = record
    AbortWindowClass: String;
    BlockMaxMs      : Integer;
    DieAfterMs      : Integer;
    DieExitCode     : Integer;
    HoldPort        : Integer;
    StartupDelayMs  : Integer;
    StartupDialogMs : Integer;
    class function FromCommandLine: TSlimVerifyOptions; static;
    function SuppressesSlimServer: Boolean;
  end;

function SlimVerifyShowModalWindow(const AWindowClass, AButtonClass, ATitle, AMessage: String;
  const AButtonCaptions: TArray<String>; AAutoCloseMs: Integer): String;

function SlimVerifyShowStandingWindow(const AClassName, ATitle: String): HWND;

procedure SlimVerifyHoldPort(APort: Integer);

procedure SlimVerifyDieAfter(ADelayMs, AExitCode: Integer);

procedure SlimVerifyCloseWindowAfter(AWnd: HWND; ADelayMs: Integer);

procedure SlimVerifyPumpFor(ADurationMs: Integer);

function SlimVerifyOptions: TSlimVerifyOptions;

implementation

uses
  Winapi.Winsock2;

{ TSlimVerifyOptions }

/// <summary>Reads the options from the command line of this process.</summary>
class function TSlimVerifyOptions.FromCommandLine: TSlimVerifyOptions;

  function TryGetSwitch(const AParam, AName: String; out AValue: String): Boolean;
  begin
    Result := AParam.StartsWith('--' + AName + '=', True);
    if Result then
      AValue := AParam.Substring(Length(AName) + 3);
  end;

var
  LNum  : Integer;
  LValue: String;
begin
  Result := Default(TSlimVerifyOptions);
  Result.DieExitCode := SlimVerifyDefaultDieExitCode;
  Result.BlockMaxMs := SlimVerifyDefaultBlockMaxMs;

  for var I: Integer := 1 to ParamCount do
  begin
    var LParam: String := ParamStr(I);
    if TryGetSwitch(LParam, 'StartupDelay', LValue) and TryStrToInt(LValue, LNum) then
      Result.StartupDelayMs := LNum
    else if TryGetSwitch(LParam, 'StartupDialog', LValue) and TryStrToInt(LValue, LNum) then
      Result.StartupDialogMs := LNum
    else if TryGetSwitch(LParam, 'AbortWindow', LValue) then
      Result.AbortWindowClass := LValue
    else if TryGetSwitch(LParam, 'DieAfter', LValue) and TryStrToInt(LValue, LNum) then
      Result.DieAfterMs := LNum
    else if TryGetSwitch(LParam, 'DieExitCode', LValue) and TryStrToInt(LValue, LNum) then
      Result.DieExitCode := LNum
    else if TryGetSwitch(LParam, 'HoldPort', LValue) and TryStrToInt(LValue, LNum) then
      Result.HoldPort := LNum
    else if TryGetSwitch(LParam, 'BlockMax', LValue) and TryStrToInt(LValue, LNum) then
      Result.BlockMaxMs := LNum;
  end;
end;

/// <summary>True if the Slim server must not be started at all.</summary>
function TSlimVerifyOptions.SuppressesSlimServer: Boolean;
begin
  Result := (HoldPort > 0) or (AbortWindowClass <> '');
end;

var
  GOptions     : TSlimVerifyOptions;
  GOptionsValid: Boolean = False;

/// <summary>The options of this process, read from the command line once.</summary>
function SlimVerifyOptions: TSlimVerifyOptions;
begin
  if not GOptionsValid then
  begin
    GOptions := TSlimVerifyOptions.FromCommandLine;
    GOptionsValid := True;
  end;
  Result := GOptions;
end;

{ ----------------------------------------------------------------------- }
{ Simulated dialogs                                                       }
{ ----------------------------------------------------------------------- }

type
  PSlimVerifyDialogState = ^TSlimVerifyDialogState;
  TSlimVerifyDialogState = record
    Clicked: String;
    Closed : Boolean;
  end;

var
  GRegisteredClasses: TStringList;

function SlimVerifyWindowText(AWnd: HWND): String;
var
  LBuf: array[0..255] of Char;
begin
  SetString(Result, LBuf, GetWindowText(AWnd, LBuf, Length(LBuf)));
end;

function SlimVerifyDialogProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  LState: PSlimVerifyDialogState;
begin
  case AMsg of
    WM_COMMAND:
      begin
        // A NATIVE button does not close anything by itself - it notifies its
        // parent with WM_COMMAND. Without handling that here the dialog would
        // ignore every click and only disappear on its own self close timeout,
        // which makes a dismissed dialog look like one that was never dismissed.
        LState := PSlimVerifyDialogState(GetWindowLongPtr(AWnd, GWLP_USERDATA));
        if Assigned(LState) and (ALParam <> 0) then
          LState.Clicked := SlimVerifyWindowText(HWND(ALParam));
        PostMessage(AWnd, WM_CLOSE, 0, 0);
        Exit(0);
      end;
    WM_CLOSE:
      begin
        DestroyWindow(AWnd);
        Exit(0);
      end;
    WM_DESTROY:
      begin
        LState := PSlimVerifyDialogState(GetWindowLongPtr(AWnd, GWLP_USERDATA));
        if Assigned(LState) then
          LState.Closed := True;
        Exit(0);
      end;
  end;
  Result := DefWindowProc(AWnd, AMsg, AWParam, ALParam);
end;

function SlimVerifyControlProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  LParent: HWND;
  LState : PSlimVerifyDialogState;
begin
  // A custom control is not a button as far as Windows is concerned, so BM_CLICK
  // has to be handled explicitly - just like the mouse messages. The proxy sends
  // both, because some controls only react to the one and some only to the other.
  if (AMsg = WM_LBUTTONUP) or (AMsg = BM_CLICK) then
  begin
    LParent := GetParent(AWnd);
    LState := PSlimVerifyDialogState(GetWindowLongPtr(LParent, GWLP_USERDATA));
    if Assigned(LState) then
      LState.Clicked := SlimVerifyWindowText(AWnd);
    PostMessage(LParent, WM_CLOSE, 0, 0);
    Exit(0);
  end;
  Result := DefWindowProc(AWnd, AMsg, AWParam, ALParam);
end;

procedure SlimVerifyRegisterClass(const AClassName: String; AProc: TFNWndProc);
var
  LClass: TWndClass;
begin
  if GRegisteredClasses.IndexOf(AClassName) >= 0 then
    Exit;

  ZeroMemory(@LClass, SizeOf(LClass));
  LClass.lpfnWndProc := AProc;
  LClass.hInstance := HInstance;
  LClass.hCursor := LoadCursor(0, IDC_ARROW);
  LClass.hbrBackground := GetSysColorBrush(COLOR_BTNFACE);
  LClass.lpszClassName := PChar(AClassName);
  if Winapi.Windows.RegisterClass(LClass) = 0 then
    RaiseLastOSError;
  GRegisteredClasses.Add(AClassName);
end;

/// <summary>Pumps the message queue of the calling thread for ADurationMs.</summary>
procedure SlimVerifyPumpFor(ADurationMs: Integer);
var
  LMsg  : TMsg;
  LStart: Cardinal;
begin
  LStart := GetTickCount;
  while (GetTickCount - LStart) < Cardinal(ADurationMs) do
  begin
    if PeekMessage(LMsg, 0, 0, 0, PM_REMOVE) then
    begin
      TranslateMessage(LMsg);
      DispatchMessage(LMsg);
    end
    else
      Sleep(10);
  end;
end;

/// <summary>
///   Shows a window of AWindowClass with a static text and one button per
///   caption on AButtonClass, and pumps messages until the window is closed or
///   AAutoCloseMs elapsed. Returns the caption that was clicked, or an empty
///   string on a self close.
/// </summary>
function SlimVerifyShowModalWindow(const AWindowClass, AButtonClass, ATitle, AMessage: String;
  const AButtonCaptions: TArray<String>; AAutoCloseMs: Integer): String;
const
  DialogWidth  = 460;
  DialogHeight = 180;
var
  LDialog: HWND;
  LMsg   : TMsg;
  LStart : Cardinal;
  LState : TSlimVerifyDialogState;
begin
  SlimVerifyRegisterClass(AWindowClass, @SlimVerifyDialogProc);
  if not SameText(AButtonClass, 'Button') then
    SlimVerifyRegisterClass(AButtonClass, @SlimVerifyControlProc);

  LState.Clicked := '';
  LState.Closed := False;

  LDialog := CreateWindowEx(WS_EX_TOPMOST, PChar(AWindowClass), PChar(ATitle),
    WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_VISIBLE,
    (GetSystemMetrics(SM_CXSCREEN) - DialogWidth) div 2,
    (GetSystemMetrics(SM_CYSCREEN) - DialogHeight) div 2,
    DialogWidth, DialogHeight, 0, 0, HInstance, nil);
  if LDialog = 0 then
    RaiseLastOSError;
  SetWindowLongPtr(LDialog, GWLP_USERDATA, NativeInt(@LState));

  CreateWindowEx(0, 'Static', PChar(AMessage), WS_CHILD or WS_VISIBLE,
    20, 20, DialogWidth - 40, 60, LDialog, 0, HInstance, nil);

  for var I: Integer := 0 to High(AButtonCaptions) do
    CreateWindowEx(0, PChar(AButtonClass), PChar(AButtonCaptions[I]),
      WS_CHILD or WS_VISIBLE or WS_TABSTOP,
      20 + I * 120, 100, 100, 30, LDialog, 0, HInstance, nil);

  ShowWindow(LDialog, SW_SHOW);
  UpdateWindow(LDialog);

  LStart := GetTickCount;
  while not LState.Closed do
  begin
    if (AAutoCloseMs > 0) and ((GetTickCount - LStart) >= Cardinal(AAutoCloseMs)) then
    begin
      if IsWindow(LDialog) then
        DestroyWindow(LDialog);
      Break;
    end;
    if PeekMessage(LMsg, 0, 0, 0, PM_REMOVE) then
    begin
      TranslateMessage(LMsg);
      DispatchMessage(LMsg);
    end
    else
      Sleep(10);
  end;

  // The state record lives on this stack frame - make sure no window can reach
  // it any more.
  if IsWindow(LDialog) then
  begin
    SetWindowLongPtr(LDialog, GWLP_USERDATA, 0);
    DestroyWindow(LDialog);
  end;

  Result := LState.Clicked;
end;

/// <summary>Shows a window of AClassName and leaves it standing. Non blocking.</summary>
function SlimVerifyShowStandingWindow(const AClassName, ATitle: String): HWND;
begin
  SlimVerifyRegisterClass(AClassName, @SlimVerifyDialogProc);
  Result := CreateWindowEx(0, PChar(AClassName), PChar(ATitle),
    WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_VISIBLE,
    100, 100, 420, 160, 0, 0, HInstance, nil);
  if Result = 0 then
    RaiseLastOSError;
  ShowWindow(Result, SW_SHOW);
  UpdateWindow(Result);
end;

{ ----------------------------------------------------------------------- }
{ Port holder and self termination                                        }
{ ----------------------------------------------------------------------- }

var
  GHeldSocket: TSocket = INVALID_SOCKET;

/// <summary>
///   Occupies APort with a listening socket that never speaks Slim. Checks the
///   preflight and the ownership check of the host control.
/// </summary>
procedure SlimVerifyHoldPort(APort: Integer);
var
  LAddr: TSockAddrIn;
  LData: TWSAData;
begin
  if WSAStartup($0202, LData) <> 0 then
    RaiseLastOSError;
  GHeldSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if GHeldSocket = INVALID_SOCKET then
    RaiseLastOSError;
  ZeroMemory(@LAddr, SizeOf(LAddr));
  LAddr.sin_family := AF_INET;
  LAddr.sin_port := htons(u_short(APort));
  LAddr.sin_addr.S_addr := 0; // INADDR_ANY
  if bind(GHeldSocket, PSockAddr(@LAddr)^, SizeOf(LAddr)) <> 0 then
    RaiseLastOSError;
  if listen(GHeldSocket, 5) <> 0 then
    RaiseLastOSError;
  // The socket stays open for the lifetime of the process: it occupies the port
  // and never answers a Slim greeting.
end;

/// <summary>
///   Closes AWnd after ADelayMs from a background thread. Used by the "Shutdown"
///   fixture: a suite that launched this host through its COMMAND_PATTERN ends it
///   in a SuiteTearDown page, and the delay lets the pending Slim conversation
///   finish first.
/// </summary>
procedure SlimVerifyCloseWindowAfter(AWnd: HWND; ADelayMs: Integer);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(ADelayMs);
      // WM_CLOSE, not TerminateProcess: this is the orderly counterpart of
      // "Stop Proxy", not the simulated death of a host.
      PostMessage(AWnd, WM_CLOSE, 0, 0);
    end).Start;
end;

/// <summary>
///   Terminates this process after ADelayMs from a background thread, so the
///   death is detected even when the main thread is blocked.
/// </summary>
procedure SlimVerifyDieAfter(ADelayMs, AExitCode: Integer);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(ADelayMs);
      // TerminateProcess instead of Halt: the death has to happen even if the
      // main thread is stuck in a fixture.
      TerminateProcess(GetCurrentProcess, Cardinal(AExitCode));
    end).Start;
end;

initialization

GRegisteredClasses := TStringList.Create;

finalization

if GHeldSocket <> INVALID_SOCKET then
  closesocket(GHeldSocket);
GRegisteredClasses.Free;

end.
