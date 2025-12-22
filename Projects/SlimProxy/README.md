# SlimProxy

**SlimProxy** is a specialized Slim server implementation that acts as a router or "man-in-the-middle" between FitNesse and your System Under Test (SUT).

It allows a single FitNesse test execution to control multiple distinct (Delphi) applications (Slim servers) simultaneously, or to bridge architectural gaps (e.g., running tests against both 32-bit and 64-bit applications in the same suite).

## How it works

1.  **FitNesse** connects to **SlimProxy**.
2.  **SlimProxy** runs locally and exposes the `SlimProxy.Core` fixture.
3.  The test script uses `SlimProxy.Core` to launch external applications (your SUTs) and establish TCP connections to them.
4.  When you switch targets, **SlimProxy** transparently forwards all subsequent Slim instructions (creation, method calls, etc.) to the active target application.

## Key Features

*   **Multi-Process Testing**: Orchestrate tests involving multiple executables.
*   **Architecture Bridging**: Test Win32 and Win64 applications within the same Wiki page.
*   **Process Control**: Built-in methods to start external processes (your SUTs).
*   **Dynamic Switching**: Switch the active target context at any point in the test script.

## Getting Started

### Demo

A comprehensive example is available in the **MultiFormExampleProxy** suite. It demonstrates a test that launches and controls both a 32-bit and a 64-bit version of an application.

Run the FitNesse test located at:
`FitNesse/FitNesseRoot/Playground/MultiFormExampleProxy`

### Usage in FitNesse

You use the `SlimProxy.Core` fixture to manage your connections.

```slim
!| script | SlimProxy.Core |
| Start Process | ..\MyApp\Win32\Debug\MyApp.exe | --SlimPort=9001 |
| Connect To Target | App32 | localhost | 9001 |
| Switch To Target | App32 |

# All subsequent calls go to MyApp (App32)
| script | MyFixture |
| Do Something | ... |

| Start Process | ..\MyApp\Win64\Debug\MyApp.exe | --SlimPort=9002 |
| Connect To Target | App64 | localhost | 9002 |
| Switch To Target | App64 |

# Now calls go to the 64-bit app
| script | MyFixture |
| Do Something Else | ... |
```

## Project Structure

*   **Slim.Proxy.pas**: Core logic for the `TSlimProxyExecutor` and `TSlimProxyTarget`. Handles the forwarding of instructions.
*   **Slim.Proxy.Fixtures.pas**: Implements `TSlimProxyCoreFixture` (`SlimProxy.Core`), providing the API for the test script.
*   **Slim.Proxy.Interfaces.pas**: Interface definitions.
*   **SlimProxy.dpr**: The console application entry point.
