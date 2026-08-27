// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

/// <summary>
///   Central configuration of the SlimProxy.
///
///   The proxy must not know anything about a particular application under
///   test. Every application specific detail - window classes, button
///   captions, error wordings - lives here as a NAMED DEFAULT CONSTANT that
///   can be overridden from the command line or from a fixture verb at
///   runtime. There is deliberately no branch anywhere in the proxy sources
///   that tests for the name of a concrete product, form or button.
/// </summary>
unit Slim.Proxy.Config;

interface

uses

  System.StrUtils,
  System.SysUtils;

const

  /// <summary>Wait window for establishing a connection to a target, in ms (--ConnectTimeout=).</summary>
  DefaultConnectTimeoutMs = 20000;

  /// <summary>
  ///   Time limit for READING an answer from a target, in ms (--ReadTimeout=).
  ///   0 = unlimited and is the default for backwards compatibility: a modal
  ///   dialog inside the target then blocks the proxy along with it.
  /// </summary>
  DefaultReadTimeoutMs = 0;

  /// <summary>
  ///   Captions of buttons that may be pressed to get rid of a start up or
  ///   shutdown dialog. Semicolon separated, the ampersand of an accelerator
  ///   is ignored while matching, matching is case insensitive.
  /// </summary>
  DefaultDismissButtonCaptions = 'OK;Yes;Ja;Oui;Continue;Weiter;Close';

  /// <summary>
  ///   Window classes that are treated as a push button. VCL and third party
  ///   applications use their own control classes, so a search that only knows
  ///   the native class "Button" never reaches their buttons and the host stays
  ///   behind its modal dialog forever. Prefix match, case insensitive.
  /// </summary>
  DefaultButtonWindowClasses = 'Button;TButton;TBitBtn;TSpeedButton;TToolButton;TcxButton;TdxButton';

  /// <summary>
  ///   Substrings that mark a window class as a push button regardless of its
  ///   prefix. This is the application agnostic catch all for custom control
  ///   classes whose name nobody can know up front.
  /// </summary>
  DefaultButtonClassContains = 'button;btn';

  /// <summary>
  ///   Window classes or titles whose appearance proves that the host will
  ///   never serve Slim (a login mask, a licence notice, an "already running"
  ///   box). Empty by default - the proxy must not assume anything here.
  ///   Configure with --AbortWindows= or "Set Abort Windows".
  /// </summary>
  DefaultAbortWindowPatterns = '';

  /// <summary>
  ///   Wordings that mark a message window as an ERROR box. Such a box is
  ///   occupying the message loop of the target and is therefore captured and
  ///   dismissed, so the pending call fails instead of hanging. Multilingual by
  ///   default and extensible.
  /// </summary>
  DefaultErrorPatterns = 'error;fehler;exception;erreur;errore;fout;fallo;failure';

  /// <summary>
  ///   Wordings that mean: abort the run, the process state is not trustworthy
  ///   any more. Everything measured after such a report would be garbage.
  /// </summary>
  DefaultFatalPatterns = 'memory manager;memory corruption;heap corruption;buffer overrun;stack overflow';

  /// <summary>
  ///   Windows that are never touched even if they match. This list has exactly
  ///   one job: leave legitimate forms without an error wording alone. It can
  ///   NOT veto a window that carries a real error wording - see
  ///   TSlimProxyWindowConfig.ClassifyWindow.
  /// </summary>
  DefaultExemptWindowPatterns = '';

  /// <summary>
  ///   How long dismissing continues AFTER the Slim port of the host came up.
  ///   Building up the user interface can raise a modal window only after that
  ///   point, and the first forwarded call would then hang.
  /// </summary>
  DefaultPostStartDismissMs = 5000;

  /// <summary>Interval between two dismiss/observe rounds while waiting, in ms.</summary>
  DefaultDismissPollIntervalMs = 500;

  /// <summary>
  ///   Number of poll rounds before abort windows are evaluated. In the very
  ///   first moment a window may be standing that the dismiss round is about to
  ///   click away.
  /// </summary>
  DefaultAbortWindowGraceRounds = 3;

  /// <summary>Interval between two watchdog rounds while a call is pending, in ms.</summary>
  DefaultWatchdogPollIntervalMs = 500;

  /// <summary>
  ///   CPU load of the target process below which it is considered stalled, in
  ///   percent of one core. A long calculation on the main thread looks exactly
  ///   like a blocked message loop - only the CPU delta separates them.
  /// </summary>
  DefaultStallCpuPercent = 2;

  /// <summary>
  ///   How long the CPU delta has to stay flat before a stall is reported, in ms.
  /// </summary>
  DefaultStallReportAfterMs = 20000;

type

  /// <summary>
  ///   A target given on the command line (--Target=Name=Host:Port). Such
  ///   targets are created for EVERY incoming Slim connection without a test
  ///   page having to touch the SlimProxy.Core fixture, which makes the proxy
  ///   invisible to an existing suite.
  /// </summary>
  TSlimProxyStartupTarget = record
    Name: String;
    Host: String;
    Port: Integer;
  end;

  /// <summary>How a window found in the target process is to be treated.</summary>
  TSlimProxyWindowKind = (
    /// <summary>No message window, or a window that must not be touched.</summary>
    wkIgnore,
    /// <summary>Message window without an error wording: report, never dismiss.</summary>
    wkMessage,
    /// <summary>Message window with an error wording: capture and dismiss.</summary>
    wkError,
    /// <summary>Fatal report: capture, abort the run, do not fire any further call.</summary>
    wkFatal);

  /// <summary>
  ///   The window related configuration as a value, so that every helper can be
  ///   called with an explicit configuration instead of reading globals. That is
  ///   what makes the window logic testable.
  /// </summary>
  TSlimProxyWindowConfig = record
    AbortWindows       : String;
    ButtonClassContains: String;
    ButtonClasses      : String;
    DismissButtons     : String;
    ErrorPatterns      : String;
    ExemptWindows      : String;
    FatalPatterns      : String;
    class function CreateDefaults: TSlimProxyWindowConfig; static;
    class function CreateFromGlobals: TSlimProxyWindowConfig; static;
    function ClassifyWindow(const AClassName, ATitle, AText: String; out AHit: String): TSlimProxyWindowKind;
    function IsAbortWindow(const AClassName, ATitle: String; out AHit: String): Boolean;
    function IsButtonClass(const AClassName: String): Boolean;
  end;

var

  /// <summary>
  ///   Set by SlimProxy.Core "Stop Proxy" to shut the server down. In
  ///   COMMAND_PATTERN mode a SuiteTearDown page is what ends the proxy after a
  ///   run.
  /// </summary>
  SlimProxyStopRequested: Boolean = False;

  /// <summary>Targets from the command line (--Target=Name=Host:Port).</summary>
  SlimProxyStartupTargets: TArray<TSlimProxyStartupTarget>;

  SlimProxyAbortWindows       : String  = DefaultAbortWindowPatterns;
  SlimProxyButtonClassContains: String  = DefaultButtonClassContains;
  SlimProxyButtonClasses      : String  = DefaultButtonWindowClasses;
  SlimProxyConnectTimeout     : Integer = DefaultConnectTimeoutMs;
  SlimProxyDismissButtons     : String  = DefaultDismissButtonCaptions;
  SlimProxyErrorPatterns      : String  = DefaultErrorPatterns;
  SlimProxyExemptWindows      : String  = DefaultExemptWindowPatterns;
  SlimProxyFatalPatterns      : String  = DefaultFatalPatterns;
  SlimProxyPostStartDismissMs : Integer = DefaultPostStartDismissMs;
  SlimProxyReadTimeout        : Integer = DefaultReadTimeoutMs;

  /// <summary>
  ///   The watchdog (see Slim.Proxy.Watchdog) is OFF by default: it clicks
  ///   inside a foreign process, which an existing setup must not get without
  ///   asking for it. Enable with --Watchdog or "Enable Watchdog".
  /// </summary>
  SlimProxyWatchdogEnabled: Boolean = False;

function SlimProxySplitList(const AList: String): TArray<String>;

function SlimProxyMatchPrefix(const AValue, AList: String): String;

function SlimProxyMatchSubstring(const AValue, AList: String): String;

function SlimProxyNormalizeCaption(const AValue: String): String;

implementation

/// <summary>Splits a semicolon separated list and drops empty entries.</summary>
function SlimProxySplitList(const AList: String): TArray<String>;
begin
  Result := [];
  for var LEntry in SplitString(AList, ';') do
  begin
    var LTrimmed: String := LEntry.Trim;
    if LTrimmed <> '' then
      Result := Result + [LTrimmed];
  end;
end;

/// <summary>
///   Returns the list entry that AValue starts with (case insensitive), or an
///   empty string. Used for window class lists.
/// </summary>
function SlimProxyMatchPrefix(const AValue, AList: String): String;
begin
  Result := '';
  if AValue = '' then
    Exit;
  for var LEntry in SlimProxySplitList(AList) do
    if AValue.StartsWith(LEntry, True) then
      Exit(LEntry);
end;

/// <summary>
///   Returns the list entry that occurs inside AValue (case insensitive), or an
///   empty string. Used for wording lists.
/// </summary>
function SlimProxyMatchSubstring(const AValue, AList: String): String;
var
  LLower: String;
begin
  Result := '';
  if AValue = '' then
    Exit;
  LLower := AValue.ToLower;
  for var LEntry in SlimProxySplitList(AList) do
    if LLower.Contains(LEntry.ToLower) then
      Exit(LEntry);
end;

/// <summary>Strips accelerator ampersands so captions compare predictably.</summary>
function SlimProxyNormalizeCaption(const AValue: String): String;
begin
  Result := AValue.Replace('&', '', [rfReplaceAll]).Trim;
end;

{ TSlimProxyWindowConfig }

class function TSlimProxyWindowConfig.CreateDefaults: TSlimProxyWindowConfig;
begin
  Result.AbortWindows := DefaultAbortWindowPatterns;
  Result.ButtonClassContains := DefaultButtonClassContains;
  Result.ButtonClasses := DefaultButtonWindowClasses;
  Result.DismissButtons := DefaultDismissButtonCaptions;
  Result.ErrorPatterns := DefaultErrorPatterns;
  Result.ExemptWindows := DefaultExemptWindowPatterns;
  Result.FatalPatterns := DefaultFatalPatterns;
end;

class function TSlimProxyWindowConfig.CreateFromGlobals: TSlimProxyWindowConfig;
begin
  Result.AbortWindows := SlimProxyAbortWindows;
  Result.ButtonClassContains := SlimProxyButtonClassContains;
  Result.ButtonClasses := SlimProxyButtonClasses;
  Result.DismissButtons := SlimProxyDismissButtons;
  Result.ErrorPatterns := SlimProxyErrorPatterns;
  Result.ExemptWindows := SlimProxyExemptWindows;
  Result.FatalPatterns := SlimProxyFatalPatterns;
end;

/// <summary>
///   Decides how a window has to be treated. Precedence, and this order is
///   the whole point:
///   1. a fatal wording always wins,
///   2. an error wording always wins over the exemption list,
///   3. the exemption list only suppresses windows WITHOUT an error wording.
/// </summary>
function TSlimProxyWindowConfig.ClassifyWindow(const AClassName, ATitle, AText: String;
  out AHit: String): TSlimProxyWindowKind;
var
  LHaystack: String;
begin
  LHaystack := ATitle + ' ' + AText;

  AHit := SlimProxyMatchSubstring(LHaystack, FatalPatterns);
  if AHit <> '' then
    Exit(wkFatal);

  AHit := SlimProxyMatchSubstring(LHaystack, ErrorPatterns);
  if AHit <> '' then
    Exit(wkError);

  // Only now may the exemption list speak: it exists to leave legitimate forms
  // alone, not to throw away a window that carries a real error wording.
  AHit := SlimProxyMatchPrefix(AClassName, ExemptWindows);
  if AHit = '' then
    AHit := SlimProxyMatchSubstring(ATitle, ExemptWindows);
  if AHit <> '' then
    Exit(wkIgnore);

  AHit := '';
  Result := wkMessage;
end;

function TSlimProxyWindowConfig.IsAbortWindow(const AClassName, ATitle: String; out AHit: String): Boolean;
begin
  AHit := SlimProxyMatchPrefix(AClassName, AbortWindows);
  if AHit = '' then
    AHit := SlimProxyMatchSubstring(ATitle, AbortWindows);
  Result := AHit <> '';
end;

function TSlimProxyWindowConfig.IsButtonClass(const AClassName: String): Boolean;
begin
  Result := (SlimProxyMatchPrefix(AClassName, ButtonClasses) <> '') or
            (SlimProxyMatchSubstring(AClassName, ButtonClassContains) <> '');
end;

end.
