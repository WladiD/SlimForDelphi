// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.Interfaces;

interface

type

  /// <summary>
  ///   Everything the fixtures need from the executor. One executor exists per
  ///   incoming TCP connection (see TSlimServer.SlimServerExecute), and FitNesse
  ///   opens exactly ONE connection for a whole suite - so targets survive page
  ///   boundaries, but have to be created per connection.
  /// </summary>
  ISlimProxyExecutor = interface
    ['{1C4E9A0C-4E2E-4C0E-9C13-6A7B1E4D2F31}']
    procedure AddTarget(const AName, AHost: String; APort: Integer);
    /// <summary>
    ///   Registers a target WITHOUT connecting. The connection is established on
    ///   the first forwarded command, so the target host may still be starting.
    /// </summary>
    procedure AddTargetDeferred(const AName, AHost: String; APort: Integer);
    procedure DisconnectTarget(const AName: String);
    /// <summary>
    ///   Takes a target that was marked broken back into service, e.g. after the
    ///   host was restarted.
    /// </summary>
    procedure ReconnectTarget(const AName: String);
    procedure SwitchToTarget(const AName: String);
    function  ActiveTargetName: String;
    /// <summary>
    ///   Sends a harmless round trip to a target and returns 'OK', or the
    ///   diagnosis if it failed - it does NOT raise. That is what lets a test page
    ///   assert the state of a broken target instead of just going red, and it is
    ///   the way to ask "is my target still there, and if not, why".
    /// </summary>
    function  PingTarget(const AName: String): String;
    /// <summary>Report of the last watchdog run, or an empty string.</summary>
    function  LastWatchdogReport: String;
    /// <summary>Name, address, connection state and broken cause of every target.</summary>
    function  TargetStatus: String;
    /// <summary>
    ///   Binds a target to the process id of its host, so the watchdog knows
    ///   whose windows to observe. For a target on the local machine the proxy
    ///   determines this itself from the owner of the listening socket.
    /// </summary>
    procedure SetTargetProcessId(const AName: String; APid: Cardinal);
    function  GetTargetProcessId(const AName: String): Cardinal;
    function  GetConnectTimeout: Integer;
    procedure SetConnectTimeout(AValue: Integer);
    function  GetReadTimeout: Integer;
    procedure SetReadTimeout(AValue: Integer);
    /// <summary>
    ///   Raises the read timeout for the NEXT forwarded call only. A long but
    ///   legitimate calculation must not be cut off by the limit that exists to
    ///   catch a blocked host.
    /// </summary>
    procedure SetReadTimeoutForNextCall(AValue: Integer);
    property ConnectTimeout: Integer read GetConnectTimeout write SetConnectTimeout;
    property ReadTimeout: Integer read GetReadTimeout write SetReadTimeout;
  end;

implementation

end.
