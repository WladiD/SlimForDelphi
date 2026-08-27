// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   The watchdog that runs WHILE a forwarded call is pending.
///
///   This is the point where the proxy is structurally superior to an external
///   driver script: the proxy KNOWS when a forwarded call is open. A script
///   next to the run has to guess that from file sizes and CPU deltas.
///
///   One watchdog instance belongs to exactly one pending call. It is started
///   before the command goes out and stopped after the answer came back (or
///   failed to come back), and its findings then belong to the Slim result of
///   that very call.
/// </summary>
unit Slim.Proxy.Watchdog;

interface

uses

  Winapi.Windows,

  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils,

  Slim.Proxy.Config,
  Slim.Proxy.WinTools;

type

  TSlimProxyFindingKind = (
    /// <summary>A message window without an error wording. Reported, never dismissed.</summary>
    fkMessage,
    /// <summary>A message window with an error wording. Captured and dismissed.</summary>
    fkErrorDismissed,
    /// <summary>A window with an error wording that could not be dismissed.</summary>
    fkErrorStuck,
    /// <summary>A fatal report. The process state is not trustworthy any more.</summary>
    fkFatal,
    /// <summary>The process is neither answering nor burning CPU.</summary>
    fkStall);

  TSlimProxyFinding = record
    ElapsedMs: Cardinal;
    Kind     : TSlimProxyFindingKind;
    Text     : String;
    function Describe: String;
  end;

  TSlimProxyFindings = TArray<TSlimProxyFinding>;

  /// <summary>
  ///   Watches the windows of a process while a call is pending. Findings are
  ///   collected thread safe and are read by the owning thread after the
  ///   watchdog has been stopped.
  /// </summary>
  TSlimProxyWatchdog = class(TThread)
  private
    FConfig            : TSlimProxyWindowConfig;
    FFindings          : TSlimProxyFindings;
    FFlatSinceTick     : Cardinal;
    FHandledWindows    : TList<HWND>;
    FHasDismissedError : Boolean;
    FHasFatal          : Boolean;
    FLastCpuMs         : UInt64;
    FLastCpuTick       : Cardinal;
    FLock              : TCriticalSection;
    FPid               : Cardinal;
    FPollIntervalMs    : Integer;
    FStallCpuPercent   : Integer;
    FStallReportAfterMs: Integer;
    FStallReported     : Boolean;
    FStarted           : Boolean;
    FStartTick         : Cardinal;
    procedure AddFinding(AKind: TSlimProxyFindingKind; const AText: String);
    procedure CheckStall;
    procedure CheckWindows;
  protected
    procedure Execute; override;
  public
    constructor Create(APid: Cardinal; const AConfig: TSlimProxyWindowConfig);
    destructor Destroy; override;
    procedure StartWatching;
    procedure StopAndWait;
    function GetFindings: TSlimProxyFindings;
    function Report: String;
    /// <summary>True if an error dialog was dismissed - the result is unreliable then.</summary>
    property HasDismissedError: Boolean read FHasDismissedError;
    /// <summary>True if a fatal report was seen - do not fire any further call.</summary>
    property HasFatal: Boolean read FHasFatal;
    property Pid: Cardinal read FPid;
    property PollIntervalMs: Integer read FPollIntervalMs write FPollIntervalMs;
    property StallCpuPercent: Integer read FStallCpuPercent write FStallCpuPercent;
    property StallReportAfterMs: Integer read FStallReportAfterMs write FStallReportAfterMs;
  end;

function SlimProxyDescribeFindings(const AFindings: TSlimProxyFindings): String;

implementation

const
  FindingKindNames: array[TSlimProxyFindingKind] of String = (
    'MESSAGE', 'ERROR DISMISSED', 'ERROR STUCK', 'FATAL', 'STALL');

{ TSlimProxyFinding }

function TSlimProxyFinding.Describe: String;
begin
  Result := Format('[%s after %dms] %s', [FindingKindNames[Kind], ElapsedMs, Text]);
end;

/// <summary>Describes a list of findings, one per line. Empty if there are none.</summary>
function SlimProxyDescribeFindings(const AFindings: TSlimProxyFindings): String;
begin
  Result := '';
  for var LFinding in AFindings do
  begin
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + LFinding.Describe;
  end;
end;

{ TSlimProxyWatchdog }

constructor TSlimProxyWatchdog.Create(APid: Cardinal; const AConfig: TSlimProxyWindowConfig);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FConfig := AConfig;
  FPid := APid;
  FPollIntervalMs := DefaultWatchdogPollIntervalMs;
  FStallCpuPercent := DefaultStallCpuPercent;
  FStallReportAfterMs := DefaultStallReportAfterMs;
  FHandledWindows := TList<HWND>.Create;
  FLock := TCriticalSection.Create;
  FStartTick := GetTickCount;
  FLastCpuTick := FStartTick;
  FFlatSinceTick := FStartTick;
  FLastCpuMs := SlimProxyProcessCpuTimeMs(APid);
end;

destructor TSlimProxyWatchdog.Destroy;
begin
  inherited;
  FHandledWindows.Free;
  FLock.Free;
end;

/// <summary>Starts watching. Idempotent.</summary>
procedure TSlimProxyWatchdog.StartWatching;
begin
  if FStarted then
    Exit;
  FStarted := True;
  Start;
end;

/// <summary>Stops the thread and waits for it, so the findings are complete.</summary>
procedure TSlimProxyWatchdog.StopAndWait;
begin
  Terminate;
  // WaitFor on a thread that was never started would block forever - the
  // destructor takes care of that case.
  if FStarted then
    WaitFor;
end;

procedure TSlimProxyWatchdog.AddFinding(AKind: TSlimProxyFindingKind; const AText: String);
var
  LFinding: TSlimProxyFinding;
begin
  LFinding.ElapsedMs := GetTickCount - FStartTick;
  LFinding.Kind := AKind;
  LFinding.Text := AText;
  FLock.Enter;
  try
    FFindings := FFindings + [LFinding];
  finally
    FLock.Leave;
  end;
end;

function TSlimProxyWatchdog.GetFindings: TSlimProxyFindings;
begin
  FLock.Enter;
  try
    Result := Copy(FFindings);
  finally
    FLock.Leave;
  end;
end;

/// <summary>All findings as one text, or an empty string.</summary>
function TSlimProxyWatchdog.Report: String;
begin
  Result := SlimProxyDescribeFindings(GetFindings);
end;

procedure TSlimProxyWatchdog.CheckWindows;
begin
  for var LInfo in SlimProxyCollectWindows(FPid, FConfig) do
  begin
    // The main window is not a message window. Clicking inside it would press a
    // button of a legitimate form.
    if LInfo.HasMenu then
      Continue;
    if FHandledWindows.Contains(LInfo.Handle) then
      Continue;

    case LInfo.Kind of
      wkIgnore:
        // On the exemption list and without an error wording: leave it alone.
        FHandledWindows.Add(LInfo.Handle);
      wkMessage:
        begin
          // Report, but NEVER dismiss. A yes/no is a decision of the
          // application, not something to click away - a blind "OK" could let a
          // call run through to a success it never had.
          FHandledWindows.Add(LInfo.Handle);
          AddFinding(fkMessage, 'message window seen but NOT dismissed: ' + LInfo.Describe);
        end;
      wkError:
        begin
          FHandledWindows.Add(LInfo.Handle);
          var LClicked: String := SlimProxyDismissWindow(LInfo.Handle, FConfig);
          if LClicked <> '' then
          begin
            FHasDismissedError := True;
            AddFinding(fkErrorDismissed, Format('%s -> %s', [LInfo.Describe, LClicked]));
          end
          else
            AddFinding(fkErrorStuck,
              'no configured dismiss button found (see --DismissButtons / --ButtonClasses): ' + LInfo.Describe);
        end;
      wkFatal:
        begin
          FHandledWindows.Add(LInfo.Handle);
          // Capture the report INCLUDING its stack first, then unblock the call.
          // The process state is unreliable afterwards, so the run has to stop.
          FHasFatal := True;
          AddFinding(fkFatal, LInfo.Describe);
          var LClicked: String := SlimProxyDismissWindow(LInfo.Handle, FConfig);
          if LClicked <> '' then
            AddFinding(fkFatal, 'dismissed to unblock the pending call -> ' + LClicked);
        end;
    end;
  end;
end;

procedure TSlimProxyWatchdog.CheckStall;
var
  LCpuMs  : UInt64;
  LDeltaMs: UInt64;
  LNow    : Cardinal;
  LPercent: Integer;
  LSpanMs : Cardinal;
begin
  LNow := GetTickCount;
  LSpanMs := LNow - FLastCpuTick;
  if LSpanMs = 0 then
    Exit;

  LCpuMs := SlimProxyProcessCpuTimeMs(FPid);
  // That a window pumps no messages does not say anything - a long calculation
  // on the main thread looks exactly the same. The CPU delta separates them: a
  // busy core means computing, a flat value means blocked.
  // Never subtract downwards: if the process handle could not be opened for one
  // round the value falls back to 0, and with overflow checking on an unsigned
  // underflow would blow up right here.
  if LCpuMs >= FLastCpuMs then
    LDeltaMs := LCpuMs - FLastCpuMs
  else
    LDeltaMs := 0;
  LPercent := Integer(LDeltaMs * 100 div LSpanMs);
  FLastCpuMs := LCpuMs;
  FLastCpuTick := LNow;

  if LPercent > FStallCpuPercent then
  begin
    FFlatSinceTick := LNow;
    Exit;
  end;

  if not FStallReported and (LNow - FFlatSinceTick >= Cardinal(FStallReportAfterMs)) then
  begin
    FStallReported := True;
    AddFinding(fkStall, Format('process %d has been below %d%% CPU for %dms while the call is pending - ' +
      'blocked, not computing', [FPid, FStallCpuPercent, LNow - FFlatSinceTick]));
  end;
end;

procedure TSlimProxyWatchdog.Execute;
begin
  NameThreadForDebugging('SlimProxyWatchdog');
  while not Terminated do
  begin
    if not SlimProxyIsProcessRunning(FPid) then
    begin
      AddFinding(fkFatal, Format('process %d ended while the call was pending', [FPid]));
      FHasFatal := True;
      Break;
    end;

    CheckWindows;
    CheckStall;

    for var I: Integer := 1 to FPollIntervalMs div 50 do
    begin
      if Terminated then
        Break;
      Sleep(50);
    end;
  end;
end;

end.
