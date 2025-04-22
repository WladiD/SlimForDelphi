# SlimForDelphi

SlimForDelphi is a [Slim](https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM.html) Protocol implementation for Delphi. It enables the creation of test fixtures in Delphi, which can then be driven by FitNesse. This allows for writing and executing automated acceptance tests in FitNesse using Delphi code.

## Features

* Implements the Slim Protocol.
* Allows the use of Delphi classes as FitNesse fixtures.
* Supports data types such as Integer, Float, String, and Slim lists.
* Includes helper classes for serializing and deserializing Slim lists.
* Comprehensive testing with DUnitX.

## Usage

### Setting up the Slim Server

1.  Compile and run your Delphi application that uses `TSlimServer`. This application will act as the Slim server, listening for connections from FitNesse.
2.  Start FitNesse with the appropriate port and required parameters. For example:

    ```bash
    java -Dslim.port=9000 -Dslim.pool.size=1 -jar fitnesse-standalone.jar
    ```

### Creating Fixtures

1.  Create Delphi classes that inherit from `TSlimFixture`.
2.  Use the `[SlimFixture]` attribute to define the fixture's name for FitNesse.
3.  Implement the methods that FitNesse will call (e.g., `Set...`, `Execute`, `Quotient` in the example).

```delphi
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
```
