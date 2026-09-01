// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   SlimProxy.Host - starting, watching and closing a GUI Slim host.
///
///   A Slim server that sits inside a desktop application has properties
///   FitNesse structurally cannot see: it is not there right after the process
///   started, it puts up modal windows on the way, it can abort its own start up
///   without dying, and it can die in the middle of a suite. This fixture turns
///   each of those into a named, red FitNesse page with a message instead of a
///   hang or a result block without a page name.
///
///   Nothing in here knows a particular application. Window classes, button
///   captions and wordings come from Slim.Proxy.Config and can be overridden by
///   the Set... verbs below or on the command line.
/// </summary>
unit Slim.Proxy.Host.Fixture;

interface

uses

  Winapi.Messages,
  Winapi.Windows,

  System.Classes,
  System.SysUtils,

  Slim.Common,
  Slim.Fixture,
  Slim.Proxy.Base,
  Slim.Proxy.Config,
  Slim.Proxy.Interfaces,
  Slim.Proxy.WinTools;

type

  [SlimFixture('Host', 'SlimProxy')]
  TSlimProxyHostFixture = class(TSlimProxyBaseFixture)
  private
    FLastHostHandle: THandle;
    FLastHostPid   : Cardinal;
    FStartupLog    : String;
    FWorkingDir    : String;
    function  Config: TSlimProxyWindowConfig;
    function  EffectivePid(APid: Integer): Cardinal;
    procedure Log(const AText: String);
    procedure RaiseHostError(APid: Cardinal; const AMessage: String);
    procedure ReleaseLastHostHandle;
  public
    destructor Destroy; override;
  public // Host control
    function StartHostAndWaitForSlim(const APath, AArgs: String; APort, ATimeoutSeconds: Integer): Integer;
    function StartHostAndWaitForSlimIn(const APath, AArgs, AWorkingDir: String;
      APort, ATimeoutSeconds: Integer): Integer;
    function CloseHost(APid, ATimeoutSeconds: Integer): Boolean;
    function KillHost(APid: Integer): Boolean;
    function IsHostRunning(APid: Integer): Boolean;
    function WaitForHostExit(APid, ATimeoutSeconds: Integer): Boolean;
    function LastHostProcessId: Integer;
    function ListenerProcessId(APort: Integer): Integer;
  public // Diagnostics
    function LastStartupLog: String;
    function WindowDump(APid: Integer): String;
    function DismissDialogs(APid: Integer): String;
  public // Configuration - no application knowledge in the code
    procedure SetWorkingDir(const ADir: String);
    procedure SetDismissButtons(const AList: String);
    procedure SetButtonClasses(const AList: String);
    procedure SetButtonClassContains(const AList: String);
    procedure SetAbortWindows(const AList: String);
    procedure SetErrorPatterns(const AList: String);
    procedure SetFatalPatterns(const AList: String);
    procedure SetExemptWindows(const AList: String);
    procedure SetPostStartDismissTime(AMilliseconds: Integer);
    procedure EnableWatchdog;
    procedure DisableWatchdog;
  end;

implementation

{ TSlimProxyHostFixture }

destructor TSlimProxyHostFixture.Destroy;
begin
  ReleaseLastHostHandle;
  inherited;
end;

procedure TSlimProxyHostFixture.ReleaseLastHostHandle;
begin
  if FLastHostHandle <> 0 then
  begin
    CloseHandle(FLastHostHandle);
    FLastHostHandle := 0;
  end;
end;

function TSlimProxyHostFixture.Config: TSlimProxyWindowConfig;
begin
  Result := TSlimProxyWindowConfig.CreateFromGlobals;
end;

function TSlimProxyHostFixture.EffectivePid(APid: Integer): Cardinal;
begin
  if APid > 0 then
    Result := Cardinal(APid)
  else
    Result := FLastHostPid;
end;

procedure TSlimProxyHostFixture.Log(const AText: String);
begin
  FStartupLog := FStartupLog + Format('[%s] %s', [FormatDateTime('hh:nn:ss.zzz', Now), AText]) + sLineBreak;
  if IsConsole then
  begin
    Writeln('[host] ' + AText);
    Flush(Output);
  end;
end;

/// <summary>Raises a named ESlim carrying the window dump and the start up log.</summary>
procedure TSlimProxyHostFixture.RaiseHostError(APid: Cardinal; const AMessage: String);
begin
  // Every error message carries a window dump and the start up log. If a start
  // stops without a port, that is exactly the missing information.
  Log('window dump: ' + sLineBreak + SlimProxyDumpWindows(APid, Config));
  raise ESlim.CreateFmt('%s' + sLineBreak + '%s', [AMessage, FStartupLog]);
end;

/// <summary>
///   Brings a host up and only returns once the listening socket on APort is
///   OWNED BY THIS PROCESS. Dismisses start up dialogs while waiting and
///   aborts with a named message if the port belongs to somebody else, if the
///   host dies or if it puts up one of the configured abort windows.
///   Returns the process id of the host.
/// </summary>
function TSlimProxyHostFixture.StartHostAndWaitForSlim(const APath, AArgs: String;
  APort, ATimeoutSeconds: Integer): Integer;
begin
  Result := StartHostAndWaitForSlimIn(APath, AArgs, FWorkingDir, APort, ATimeoutSeconds);
end;

/// <summary>Like Start Host And Wait For Slim, with an explicit working directory.</summary>
function TSlimProxyHostFixture.StartHostAndWaitForSlimIn(const APath, AArgs, AWorkingDir: String;
  APort, ATimeoutSeconds: Integer): Integer;
var
  LAbortHit  : String;
  LCmd       : String;
  LConfig    : TSlimProxyWindowConfig;
  LExitCode  : DWORD;
  LForeignPid: Cardinal;
  LOwnerPid  : Cardinal;
  LPi        : TProcessInformation;
  LRounds    : Integer;
  LSi        : TStartupInfo;
  LStartTick : Cardinal;
  LWorkingDir: String;
begin
  FStartupLog := '';
  LConfig := Config;

  // Preflight: if somebody is already listening there, a run against it is not a
  // wrong result but NO result - and it looks green.
  LForeignPid := SlimProxyGetListenerPid(APort);
  if LForeignPid <> 0 then
    raise ESlim.CreateFmt('Port %d is already in use by PID %d - aborting instead of measuring a foreign host.',
      [APort, LForeignPid]);

  LWorkingDir := AWorkingDir;
  if LWorkingDir = '' then
    LWorkingDir := ExcludeTrailingPathDelimiter(ExtractFilePath(APath));

  ZeroMemory(@LSi, SizeOf(LSi));
  LSi.cb := SizeOf(LSi);
  ZeroMemory(@LPi, SizeOf(LPi));
  LCmd := '"' + APath + '" ' + AArgs;

  // GUI applications look for configuration, logs and database access relative
  // to their own directory; with the working directory of the proxy the host
  // would start in a foreign environment.
  if not CreateProcess(nil, PChar(LCmd), nil, nil, False, 0, nil, PChar(LWorkingDir), LSi, LPi) then
    RaiseLastOSError;
  CloseHandle(LPi.hThread);

  ReleaseLastHostHandle;
  FLastHostHandle := LPi.hProcess;
  FLastHostPid := LPi.dwProcessId;
  Result := Integer(LPi.dwProcessId);
  Log(Format('started "%s" %s in "%s" -> PID %d, waiting up to %ds for port %d',
    [APath, AArgs, LWorkingDir, LPi.dwProcessId, ATimeoutSeconds, APort]));

  LStartTick := GetTickCount;
  LRounds := 0;
  while True do
  begin
    TThread.Sleep(DefaultDismissPollIntervalMs);
    Inc(LRounds);

    // Ownership check, not just "somebody is listening on the port".
    LOwnerPid := SlimProxyGetListenerPid(APort);
    if LOwnerPid = LPi.dwProcessId then
    begin
      Log(Format('slim port %d up after %dms and owned by PID %d',
        [APort, GetTickCount - LStartTick, LOwnerPid]));

      // Building up the user interface can raise a modal window only AFTER the
      // Slim server came up. Without this trailing dismissing the first
      // forwarded call hangs.
      var LDismissStart: Cardinal := GetTickCount;
      while (GetTickCount - LDismissStart) < Cardinal(SlimProxyPostStartDismissMs) do
      begin
        var LClicked: String := SlimProxyDismissDialogs(LPi.dwProcessId, LConfig);
        if LClicked <> '' then
          Log('post-start dismiss: ' + LClicked);
        TThread.Sleep(DefaultDismissPollIntervalMs);
      end;
      Exit;
    end;

    if SlimProxyTryGetExitCode(LPi.hProcess, LExitCode) then
      RaiseHostError(LPi.dwProcessId, Format(
        'Host died with exit code %d after %dms - no slim server on port %d.',
        [LExitCode, GetTickCount - LStartTick, APort]));

    if (LOwnerPid <> 0) and (LOwnerPid <> LPi.dwProcessId) then
      RaiseHostError(LPi.dwProcessId, Format(
        'Port %d is owned by FOREIGN process %d (our host is %d) - aborting.',
        [APort, LOwnerPid, LPi.dwProcessId]));

    var LClicked: String := SlimProxyDismissDialogs(LPi.dwProcessId, LConfig);
    if LClicked <> '' then
      Log('auto-dismiss: ' + LClicked);

    // Recognize an abort window at once instead of letting the whole wait window
    // run out empty. Only from the configured round on, because in the very first
    // moment a window may be standing that the dismiss round just clicked away.
    if LRounds >= DefaultAbortWindowGraceRounds then
      for var LInfo in SlimProxyCollectWindows(LPi.dwProcessId, LConfig) do
        if LConfig.IsAbortWindow(LInfo.ClassName, LInfo.Title, LAbortHit) then
          RaiseHostError(LPi.dwProcessId, Format(
            'ABORT WINDOW after %dms: the application shows "%s" (matched "%s"). ' +
            'Slim will never come up behind it.',
            [GetTickCount - LStartTick, LInfo.Describe, LAbortHit]));

    if (LRounds mod 20) = 0 then
      Log(Format('still waiting for port %d - %dms elapsed' + sLineBreak + '%s',
        [APort, GetTickCount - LStartTick, SlimProxyDumpWindows(LPi.dwProcessId, LConfig)]));

    if (GetTickCount - LStartTick) >= Cardinal(ATimeoutSeconds) * 1000 then
      RaiseHostError(LPi.dwProcessId, Format(
        'Startup window of %ds elapsed - port %d never came up.', [ATimeoutSeconds, APort]));
  end;
end;

/// <summary>
///   Orderly shutdown: WM_CLOSE on the main window, dismiss confirmations,
///   wait for the process to really end. Deliberately NO TerminateProcess - a
///   hard killed process can leave locks or half states behind and the next
///   start then fails without a visible reason.
/// </summary>
function TSlimProxyHostFixture.CloseHost(APid, ATimeoutSeconds: Integer): Boolean;
var
  LConfig: TSlimProxyWindowConfig;
  LHandle: THandle;
  LMain  : HWND;
  LPid   : Cardinal;
begin
  LPid := EffectivePid(APid);
  LConfig := Config;

  LMain := SlimProxyFindMainWindow(LPid);
  if LMain <> 0 then
    PostMessage(LMain, WM_CLOSE, 0, 0);

  LHandle := OpenProcess(SYNCHRONIZE, False, LPid);
  if LHandle = 0 then
    Exit(True); // already gone
  try
    for var I: Integer := 1 to ATimeoutSeconds * 2 do
    begin
      // A confirmation may be standing in the way of the shutdown - it has to be
      // clicked away, otherwise the wait just runs out.
      SlimProxyDismissDialogs(LPid, LConfig);
      if WaitForSingleObject(LHandle, 500) = WAIT_OBJECT_0 then
        Exit(True);
    end;
    Result := False;
  finally
    CloseHandle(LHandle);
  end;
end;

/// <summary>
///   Kills the host. Separate from Close Host and deliberately named that
///   way: only for test cases that want to force the death of a host.
/// </summary>
function TSlimProxyHostFixture.KillHost(APid: Integer): Boolean;
var
  LHandle: THandle;
  LPid   : Cardinal;
begin
  LPid := EffectivePid(APid);
  LHandle := OpenProcess(PROCESS_TERMINATE or SYNCHRONIZE, False, LPid);
  if LHandle = 0 then
    Exit(True); // already gone
  try
    Result := TerminateProcess(LHandle, 1);
    if Result then
      Result := WaitForSingleObject(LHandle, 5000) = WAIT_OBJECT_0;
  finally
    CloseHandle(LHandle);
  end;
end;

function TSlimProxyHostFixture.IsHostRunning(APid: Integer): Boolean;
begin
  Result := SlimProxyIsProcessRunning(EffectivePid(APid));
end;

/// <summary>
///   Passively waits until the host has exited on its own - True once it is
///   gone (an already dead pid counts as gone), False if it is still alive
///   after ATimeoutSeconds. Unlike Close Host nothing is sent to the process:
///   made for hosts that end themselves, e.g. an application restarting into
///   another client, where the successor reuses the same port and a reconnect
///   must not hit the dying predecessor.
/// </summary>
function TSlimProxyHostFixture.WaitForHostExit(APid, ATimeoutSeconds: Integer): Boolean;
var
  LHandle: THandle;
  LPid   : Cardinal;
begin
  LPid := EffectivePid(APid);
  LHandle := OpenProcess(SYNCHRONIZE, False, LPid);
  if LHandle = 0 then
    Exit(True); // already gone
  try
    Result := WaitForSingleObject(LHandle, Cardinal(ATimeoutSeconds) * 1000) = WAIT_OBJECT_0;
  finally
    CloseHandle(LHandle);
  end;
end;

/// <summary>Process id of the host started last.</summary>
function TSlimProxyHostFixture.LastHostProcessId: Integer;
begin
  Result := Integer(FLastHostPid);
end;

/// <summary>Process id that is listening on APort, or 0.</summary>
function TSlimProxyHostFixture.ListenerProcessId(APort: Integer): Integer;
begin
  Result := Integer(SlimProxyGetListenerPid(APort));
end;

/// <summary>Log of the last host start - usable on a red page.</summary>
function TSlimProxyHostFixture.LastStartupLog: String;
begin
  if FStartupLog = '' then
    Result := '(no host started yet)'
  else
    Result := FStartupLog;
end;

/// <summary>Class, title, text and button captions of every visible window.</summary>
function TSlimProxyHostFixture.WindowDump(APid: Integer): String;
begin
  Result := SlimProxyDumpWindows(EffectivePid(APid), Config);
end;

/// <summary>Dismisses the dialogs of a process right now and reports what was clicked.</summary>
function TSlimProxyHostFixture.DismissDialogs(APid: Integer): String;
begin
  Result := SlimProxyDismissDialogs(EffectivePid(APid), Config);
  if Result = '' then
    Result := '(nothing to dismiss)';
end;

/// <summary>Working directory for the next host start. Default: directory of the executable.</summary>
procedure TSlimProxyHostFixture.SetWorkingDir(const ADir: String);
begin
  FWorkingDir := ADir;
end;

/// <summary>Semicolon list of button captions that may be clicked away.</summary>
procedure TSlimProxyHostFixture.SetDismissButtons(const AList: String);
begin
  SlimProxyDismissButtons := AList;
end;

/// <summary>Semicolon list of window classes that count as a push button.</summary>
procedure TSlimProxyHostFixture.SetButtonClasses(const AList: String);
begin
  SlimProxyButtonClasses := AList;
end;

/// <summary>Semicolon list of substrings that mark a window class as a push button.</summary>
procedure TSlimProxyHostFixture.SetButtonClassContains(const AList: String);
begin
  SlimProxyButtonClassContains := AList;
end;

/// <summary>
///   Semicolon list of window classes or titles whose appearance proves that
///   the host will never serve Slim (login mask, licence notice, "already
///   running").
/// </summary>
procedure TSlimProxyHostFixture.SetAbortWindows(const AList: String);
begin
  SlimProxyAbortWindows := AList;
end;

/// <summary>Semicolon list of wordings that mark a message window as an error box.</summary>
procedure TSlimProxyHostFixture.SetErrorPatterns(const AList: String);
begin
  SlimProxyErrorPatterns := AList;
end;

/// <summary>Semicolon list of wordings that mean: abort the run, state unreliable.</summary>
procedure TSlimProxyHostFixture.SetFatalPatterns(const AList: String);
begin
  SlimProxyFatalPatterns := AList;
end;

/// <summary>
///   Semicolon list of windows that are never touched. Cannot veto a window
///   with a real error wording - it only leaves legitimate forms alone.
/// </summary>
procedure TSlimProxyHostFixture.SetExemptWindows(const AList: String);
begin
  SlimProxyExemptWindows := AList;
end;

/// <summary>How long dismissing continues after the Slim port came up, in ms.</summary>
procedure TSlimProxyHostFixture.SetPostStartDismissTime(AMilliseconds: Integer);
begin
  SlimProxyPostStartDismissMs := AMilliseconds;
end;

/// <summary>
///   Switches the watchdog on. It is off by default because it clicks inside
///   a foreign process.
/// </summary>
procedure TSlimProxyHostFixture.EnableWatchdog;
begin
  SlimProxyWatchdogEnabled := True;
end;

procedure TSlimProxyHostFixture.DisableWatchdog;
begin
  SlimProxyWatchdogEnabled := False;
end;

initialization

RegisterSlimFixture(TSlimProxyHostFixture);

end.
