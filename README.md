# SlimForDelphi

SlimForDelphi is a [Slim](https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM.html) Protocol implementation for Delphi. It enables the creation of test fixtures in Delphi, which can then be driven by FitNesse. This allows for writing and executing automated acceptance tests in FitNesse using Delphi code.

## Features

*   **Slim Protocol Implementation:** Full support for the Slim protocol to communicate with FitNesse.
*   **Delphi Fixtures:** Allows the use of Delphi classes as FitNesse fixtures.
*   **Type Support:** Supports standard data types (Integer, Float, String) and Slim lists.
*   **Serialization:** Includes helper classes for serializing and deserializing Slim lists.
*   **Slim Proxy:** Includes a proxy capability to forward Slim commands to other Slim servers (e.g. for remote execution).
*   **Unit Testing:** Comprehensive testing with DUnitX.

## Prerequisites

*   **Delphi:** The project is configured for modern Delphi versions (e.g., Delphi 12).
*   **Java Runtime:** Required to run the FitNesse server.

## Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/WladiD/SlimForDelphi.git
    ```
2.  Initialize submodules (required for dependencies like `WDDelphiTools`):
    ```bash
    git submodule update --init --recursive
    ```

## Usage

### Setting up the Slim Server

1.  Create a Delphi application and instantiate `TSlimServer`. This acts as the listener for FitNesse connections.

    ```delphi
    uses {...}, Slim.Server;

    procedure TMainForm.AfterConstruction;
    begin
      inherited;
      var SlimServer := TSlimServer.Create(Self);
      SlimServer.DefaultPort := 9000;
      SlimServer.Active := True;
    end;
    ```
2.  Start FitNesse (ensure you have the `fitnesse-standalone.jar`):

    ```bash
    java -Dslim.port=9000 -Dslim.pool.size=1 -jar fitnesse-standalone.jar
    ```

### Creating Fixtures

1.  Create a Delphi class inheriting from `TSlimFixture`.
2.  Annotate it with `[SlimFixture]`.
3.  Implement your logic.
4.  **Register the fixture** in the initialization section.

```delphi
uses Slim.Fixture;

type
  [SlimFixture('Division', 'eg')]
  TSlimDivisionFixture = class(TSlimFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
  public
    procedure SetNumerator(ANumerator: Double);
    procedure SetDenominator(ADenominator: Double);
    function Quotient: Double;
  end;

{ ... Implementation of methods ... }

initialization
  RegisterSlimFixture(TSlimDivisionFixture);
end.

```
