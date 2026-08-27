# SlimProxy

**SlimProxy** is a specialized Slim server implementation that acts as a router or "man-in-the-middle" between FitNesse and your System Under Test (SUT).

It allows a single FitNesse test execution to control multiple distinct (Delphi) applications (Slim servers) simultaneously, or to bridge architectural gaps (e.g. running tests against both 32-bit and 64-bit applications in the same suite).

Beyond routing it takes care of what makes running a suite against a **GUI application** hard in the first place: such a host is not there right after the process started, it puts up modal windows on the way, it can abort its own start up without dying, and it can die in the middle of a suite. Every one of those failures is turned into a **named, red FitNesse page with a message** instead of a hang or a result block without a page name.

## How it works

1.  **FitNesse** connects to **SlimProxy**.
2.  **SlimProxy** runs locally and exposes the `SlimProxy.*` fixtures.
3.  Targets are either given on the command line (`--Target=`) or established from the test script.
4.  When you switch targets, **SlimProxy** transparently forwards all subsequent Slim instructions (creation, method calls, etc.) to the active target application.

FitNesse opens exactly **one** TCP connection for a whole suite, and `TSlimServer` creates one executor per connection. Targets therefore survive page boundaries, but they have to be created per connection - which is why `--Target=` exists: an existing suite does not have to touch `SlimProxy.Core` just to get a target connected.

## No application knowledge in the code

The proxy must not know anything about a particular application under test. Every application specific
detail is configuration with a usable default:

| instead of | configurable as |
|---|---|
| a known login form class | list of **abort windows** - classes/titles whose appearance proves the host will never serve Slim |
| known button captions | list of **dismiss buttons** |
| known button window classes | list of **button classes** plus a substring heuristic (VCL applications use their own control classes, not `Button`) |
| known error words of one language | list of **error patterns**, multilingual by default, extensible |
| a particular memory manager report | list of **fatal patterns** - text that means: abort the run, the process state is not trustworthy |
| a particular login syntax | the arguments are **passed through unchanged** |

All defaults live as named constants in [Slim.Proxy.Config.pas](Slim.Proxy.Config.pas). There is no branch anywhere in the proxy sources that tests for the name of a concrete product, form or button.

## Command line

```
SlimProxy.exe [options]

  --SlimPort=<port>          Port the proxy itself listens on (default 9000).
  --Target=Name=Host:Port    Target to forward to, may be given more than once.
                             The first one is active. Connected lazily, so the
                             target host may still be starting.
  --ConnectTimeout=<ms>      Wait window for connecting to a target (default 20000).
  --ReadTimeout=<ms>         Time limit for reading an answer, 0 = unlimited (default 0).
  --Watchdog[=on|off]        Watch the target windows while a call is pending (default off).
  --PostStartDismiss=<ms>    Keep dismissing dialogs after the Slim port came up.
  --DismissButtons=<list>    Button captions that may be clicked away.
  --ButtonClasses=<list>     Window classes that count as a push button.
  --ButtonClassContains=<l>  Substrings that mark a class as a push button.
  --AbortWindows=<list>      Classes/titles that prove Slim will never come up.
  --ErrorPatterns=<list>     Wordings that mark a message window as an error.
  --FatalPatterns=<list>     Wordings that mean: abort the run.
  --ExemptWindows=<list>     Windows the watchdog never touches.
  --Help                     Usage text.
```

Lists are semicolon separated. Window class matching is a case insensitive prefix match, wording matching is a case insensitive substring match.

> **`slim.port`:** a wiki define `!define slim.port {9000}` overrides `-Dslim.port` on the java command line. If you run the proxy on a different port, that define is what has to be found - not the command line.
>
> **Target ports can be hard wired.** An application may not make its Slim port configurable. The proxy can therefore be moved to a different port and never assumes it gets 9000 itself.

## Time limits, and why they matter

`--ReadTimeout` is the single most important switch for a GUI host. If the Slim thread of the target
stands in a modal dialog it never answers - and **FitNesse has no read timeout of its own**, so the
whole run hangs until somebody kills it from outside. The proxy is the only place where this is
fixable.

The default is `0` (unlimited), so an existing setup does not change behaviour. Once a limit is set:

*   After **every** read failure the byte stream is in an unknown state (half an answer sits in the buffer). The connection is dropped and the target is marked **broken** - another request on it would otherwise read the answer of the *previous* one and deliver silently wrong results. That is the most dangerous case of all, because it looks green.
*   The **first** cause is kept and named in every following message: `Target X (host:port) is broken since: <cause>`.
*   `Reconnect Target` takes a broken target back into service after the host was restarted.
*   `Set Read Timeout For Next Call` raises the limit for one call only, so a long but legitimate calculation is not cut off by the limit that exists to catch a blocked host.

## Fixtures

### `SlimProxy.Core` - targets, routing and time limits

| Verb | Meaning |
|---|---|
| `Connect To Target;` *name*, *host*, *port* | Register a target and connect right away |
| `Register Target;` *name*, *host*, *port* | Register a target **without** connecting - the connection is made with the first forwarded command, so the host may still be starting |
| `Switch To Target` *name* | Make a target active |
| `Reconnect Target` *name* | Take a target that was marked broken back into service |
| `Disconnect Target` *name* | Drop a target |
| `Active Target` | Name of the active target |
| `Ping Target` *name* | Real round trip to a target. Answers `OK`, or the diagnosis if it failed - it does **not** raise, so a page can assert the state of a broken target instead of just going red |
| `Target Status` | Name, address, process id and broken cause of every target |
| `Set Target Process Id;` *name*, *pid* | Bind a target to the process id of its host (determined automatically for a target on this machine) |
| `Target Process Id` *name* | Process id of that target's host |
| `Set Connect Timeout` *ms* | Wait window for connecting |
| `Set Read Timeout` *ms* | Time limit for reading an answer, 0 = unlimited |
| `Set Read Timeout For Next Call` *ms* | Raise the limit for the next call only |
| `Connect Timeout` / `Read Timeout` | Current values |
| `Last Watchdog Report` | Findings of the watchdog during the last forwarded call |
| `Start Process;` *path*, *args* | Start a process and return immediately. Working directory: the directory of the executable |
| `Start Process In;` *path*, *args*, *dir* | Same with an explicit working directory |
| `Stop Proxy` | Shut the proxy down |

### `SlimProxy.Host` - starting, watching and closing a GUI host

| Verb | Meaning |
|---|---|
| `Start Host And Wait For Slim;` *path*, *args*, *port*, *timeoutSeconds* | Bring a host up and return only once the listening socket on *port* is **owned by this process**. Returns the process id |
| `Start Host And Wait For Slim In;` *path*, *args*, *dir*, *port*, *timeoutSeconds* | Same with an explicit working directory |
| `Close Host;` *pid*, *timeoutSeconds* | Orderly shutdown: `WM_CLOSE` on the main window, dismiss confirmations, wait for the real end. **No** `TerminateProcess` |
| `Kill Host` *pid* | Force the death of a host - deliberately separate and named that way, for test cases that want exactly that |
| `Is Host Running` *pid* | Process state |
| `Last Host Process Id` | Process id of the host started last |
| `Listener Process Id` *port* | Which process is listening on that port, or 0 |
| `Last Startup Log` | Log of the last host start - usable on a red page |
| `Window Dump` *pid* | Class, title, text and button captions of every visible window |
| `Dismiss Dialogs` *pid* | Dismiss the dialogs of a process right now and report what was clicked |
| `Set Working Dir` *dir* | Working directory for the next host start (default: directory of the executable) |
| `Set Dismiss Buttons` *list* | Button captions that may be clicked away |
| `Set Button Classes` *list* | Window classes that count as a push button |
| `Set Button Class Contains` *list* | Substrings that mark a class as a push button |
| `Set Abort Windows` *list* | Classes/titles that prove Slim will never come up |
| `Set Error Patterns` *list* | Wordings that mark a message window as an error box |
| `Set Fatal Patterns` *list* | Wordings that mean: abort the run, state unreliable |
| `Set Exempt Windows` *list* | Windows the watchdog never touches |
| `Set Post Start Dismiss Time` *ms* | How long dismissing continues after the Slim port came up |
| `Enable Watchdog` / `Disable Watchdog` | Switch the watchdog on/off (off by default) |

Pass zero as *pid* to any of the pid based verbs to mean "the host started last".

`Start Host And Wait For Slim` aborts with its own named message for each of these:

*   **Preflight**: somebody is already listening on the port - the foreign PID is named. A run against a foreign process is not a wrong result but *no* result, and it looks green.
*   **Ownership**: the port is checked with `GetExtendedTcpTable` / `TCP_TABLE_OWNER_PID_LISTENER`, not just "somebody is listening".
*   **Host death**: reported with the exit code.
*   **Abort window**: recognized as soon as it appears, instead of letting the wait window run out empty.
*   **Timeout**: the wait window elapsed.

Every one of those messages carries a **window dump** (class, title, text, button captions) and the startup log. If a start stops without a port, that is exactly the information that is otherwise missing.

**Main window or message window?** Not decidable by the title - many applications title their message boxes with `Application.Title`, i.e. exactly like the main window. The shape decides: the main window carries a menu bar (`GetMenu <> 0`), a modal message window never does.

### The watchdog (`Enable Watchdog`)

While a forwarded call is pending, a separate thread observes the windows of the target process. This
is the point where the proxy is structurally superior to an external driver script: **it knows when a
forwarded call is open.** A script next to the run has to guess that from file sizes and CPU deltas.

*   **Occupied error dialogs** - an error wording in title or text - are captured completely and dismissed, so the call unblocks and the page goes red instead of hanging.
*   **Messages without an error wording** are reported but **never** dismissed. A yes/no is a decision of the application, not something to click away; a blind "OK" could let a call run through to a success it never had.
*   **Fatal patterns** (memory corruption and the like) are treated as fatal: the report including its stack is captured, the run is aborted (`ABORT_SLIM_SUITE`), no further call is fired. The process state is unreliable afterwards, every further result would be garbage.
*   **A stall** is told apart from computing. That a window pumps no messages says nothing - a long calculation on the main thread looks exactly the same. The CPU delta separates them: a busy core means computing, a flat value means blocked.
*   Findings land in the **Slim result of the affected call**, not only in the log.
*   A dismissed error dialog makes the result **unreliable** - confirming buttons can let a call run through and the page end up undeservedly green. The result says so.
*   Dismissing is **hwnd exact** on the windows that were recognized as occupied. A process wide click on "OK"/"Yes" would hit a legitimate form on a false alarm.
*   The **exemption list** (`Set Exempt Windows`) leaves windows alone. It has exactly one job, namely to leave legitimate forms *without* an error wording in peace - it can never veto a window that carries a real error wording.

The watchdog needs the process id of the host. For a target on this machine the proxy determines it from the owner of the listening socket; otherwise use `Set Target Process Id`.

## Getting Started

### Demo

A comprehensive example is available in the **MultiFormExampleProxy** suite. It demonstrates a test that launches and controls both a 32-bit and a 64-bit version of an application.

Run the FitNesse test located at:
`FitNesse/FitNesseRoot/Playground/MultiFormExampleProxy`

### Usage in FitNesse

> **Wiki syntax:** start a table with `!|` instead of `|`, otherwise FitNesse rewrites `SlimProxy.Core` into a wiki link and the `make` fails on a class name with HTML in it. And terminate a method name with `;` when more than one argument follows, otherwise FitNesse glues the argument cells onto the name.

Simple routing:

```
!| script | SlimProxy.Core |
| Start Process | ..\MyApp\Win32\Debug\MyApp.exe | --SlimPort=9001 |
| Connect To Target; | App32 | localhost | 9001 |
| Switch To Target | App32 |

# All subsequent calls go to MyApp (App32)
!| script | MyFixture |
| Do Something | ... |
```

A GUI host, brought up and watched:

```
!| script | SlimProxy.Host |
| Set Abort Windows | TLoginForm;already running |
| Set Button Classes | Button;TButton;TBitBtn;TMyAppToolButton |
| Enable Watchdog |
| $pid= | Start Host And Wait For Slim; | C:\MyApp\MyApp.exe | USER:me PASS:secret | 9000 | 420 |

!| script | SlimProxy.Core |
| Set Read Timeout | 60000 |
| Connect To Target; | App | localhost | 9000 |
| Switch To Target | App |

!| script | MyFixture |
| Do Something |

!| script | SlimProxy.Core |
| Set Read Timeout For Next Call | 600000 |

!| script | MyFixture |
| Run The Long Report |

!| script | SlimProxy.Host |
| $closed= | Close Host; | $pid | 60 |
```

An existing suite, without touching any page - the proxy is invisible:

```cmd
SlimProxy.exe --SlimPort=9010 --Target=App=localhost:9000 --ConnectTimeout=600000 --ReadTimeout=60000
```

## Not in scope

The proxy does **not** take over: building the target application, starting and terminating the
FitNesse/java process, collecting and evaluating the result XML, the preflight against competing
runs, or preparing environment and test data. That has to stay outside: the proxy cannot free itself
from a hang, which needs an authority *above* the java process. The value of `--ReadTimeout` is that
this outer termination shrinks from a heuristic to a plain upper bound.

## Project Structure

*   **Slim.Proxy.pas**: `TSlimProxyExecutor` and `TSlimProxyTarget` - forwarding, target state, read timeout, watchdog integration.
*   **Slim.Proxy.Config.pas**: every default as a named constant, plus the window classification with its precedence rules.
*   **Slim.Proxy.WinTools.pas**: port ownership, window enumeration, window dump, hwnd exact dismissing, process state.
*   **Slim.Proxy.Watchdog.pas**: the thread that watches a target while a call is pending.
*   **Slim.Proxy.Core.Fixture.pas**: `SlimProxy.Core`.
*   **Slim.Proxy.Host.Fixture.pas**: `SlimProxy.Host`.
*   **Slim.Proxy.Interfaces.pas**: `ISlimProxyExecutor`.
*   **SlimProxy.dpr**: the console application entry point and the command line.

## Tests

There are two runs, because the two kinds of test have very different costs:

| Script | Contents | Cost |
|---|---|---|
| `Test\_Test.Slim.BuildAndRun.bat` | 90 unit tests, `--exclude:Integration` | ~8 s |
| `Test\_Test.Slim.BuildAndRunAll.bat` | everything, builds SlimVerify first | ~50 s |

The `Integration` category is `Test.SlimProxy.GuiHost.pas`: it starts real host processes and waits
for real ports and real windows. Those tests stay code tests rather than FitNesse pages on purpose -
most of them assert a **raised** exception, one asserts `ABORT_SLIM_SUITE` (which by design stops a
whole FitNesse run), and one drives `TSlimProxyWatchdog` directly with tuned thresholds. As wiki
pages they would need "try and hand the error back" twins of half the verbs, added purely for
testability.

The **SlimVerify** simulation target is what makes the read timeout, the host control and the
watchdog acceptable automatically - no foreign application, no scripts, seconds instead of minutes:

```
SlimVerify.exe --SlimPort=<port> [pathologies]

  --StartupDelay=<ms>     start the Slim server only after this delay
  --StartupDialog=<ms>    modal window with a button on its OWN window class before
                          the Slim server starts (the value is a self close safety net)
  --AbortWindow=<class>   show a window of that class and never start Slim
  --DieAfter=<ms>         terminate the process after that time
  --DieExitCode=<code>    exit code used by --DieAfter (default 3)
  --HoldPort=<port>       occupy that port without serving Slim
  --BlockMax=<ms>         upper bound for the "Block Forever" fixture
```

Its fixtures `Block Forever`, `Show Error Dialog` and `Show Question` cover the pending-call cases.

### Equivalence suite in FitNesse

`FitNesse/FitNesseRoot/WDProject/SlimProxyVerify` proves the two properties that no unit test can
show, using the same three pages twice. Every variant brings its own servers up through its
`COMMAND_PATTERN` - including the builds - so a run needs nothing but a click on **Suite**:

*   **`DirectSuite`** - FitNesse builds and launches the SlimVerify host itself
    (`_SlimVerify.BuildAndRun.bat`) and talks to it without a proxy. This is the reference run.
*   **`ProxySuite`** - FitNesse launches `_SlimVerify.BuildAndRunBehindProxy.bat`, which starts a
    SlimVerify host on `VERIFY_HOST_PORT` (9101) and runs the proxy in front of it. **No page
    mentions the proxy** - the target comes from `--Target=`. Page names, per-page counters and
    `finalCounts` are identical to `DirectSuite`; only the `executionLog` differs, because the two
    variants genuinely launch different things.
*   **`HostDeathSuite`** - same launcher but its **own** host port, and therefore its own test system
    and its own process: FitNesse groups pages by test system, so with the same command line the page
    that shoots the host would take `ProxySuite` down with it. The middle page kills the host and then
    **asserts** what the proxy reports (`Ping Target` hands the cause back instead of raising it), and
    the page after it asserts that it still runs and is still told the *first* cause. So this variant
    is green like the others, and the whole `SlimProxyVerify` suite runs green in one click.

Both proxy variants end the proxy in a `SuiteTearDown` page with `Stop Proxy`; only then does the
launcher reach the clean up that terminates the host behind it. `DirectSuite` uses the same shape
with SlimVerify's own `SlimVerifyControl` / `Shutdown`, so nothing stays behind and the counters of
the two variants remain comparable.

To run the suite in the browser:

```cmd
cd FitNesse && RunFitnesse.bat
```

then open `http://localhost/WDProject.SlimProxyVerify`. For the XML instead of the report append
`?suite&format=xml` to any of the three variants.

Three things make this reliable rather than flaky, and each of them cost a debugging session:

*   **`!define slim.timeout {120}`** - FitNesse waits only **10 seconds** for a Slim server by default. The launchers build their projects before the server even starts listening, and when several variants run in one go the machine is busy with the previous one shutting down. Past 10 seconds FitNesse gives up with *"Error connecting to SLiM server on localhost:&lt;port&gt;"* and *"Testing was interrupted and results are incomplete"* - which looks exactly like a flaky suite and is really a deadline.
*   **Each proxy variant has its own host port**, and therefore its own command line. FitNesse groups pages by test system: with the same command line the page that shoots the host would run in the same process as `ProxySuite` and take it down.
*   **The launchers wait for a previous host/proxy to end** instead of racing it, and never skip a build to dodge a file lock - a skipped build would let a stale binary fake a result. `Stop Proxy` ends the proxy in short poll slices, so the launcher reaches its clean up before FitNesse starts the next test system.

> FitNesse caches the page tree, so a freshly added `.wiki` file needs a restart of the server.
