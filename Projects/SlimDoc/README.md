# SlimDoc

**SlimDoc** is a powerful documentation generator extension for **SlimForDelphi**. It leverages Delphi's RTTI (Run-Time Type Information) to automatically inspect registered Slim Fixtures and generate comprehensive, interactive HTML documentation.

Beyond simple API listing, SlimDoc includes a **Usage Analyzer** that scans your FitNesse Wiki pages to identify exactly where and how your fixtures are being used in tests.

## Features

*   **Automatic Discovery**: Automatically finds all classes registered via `RegisterSlimFixture`.
*   **RTTI Extraction**: Extracts methods, properties, parameter types, return types, and `[SlimFixture]` attributes.
*   **Noise Filtering**: Automatically hides standard `TObject` methods (like `Free`, `ClassName`, etc.) to focus on your business logic.
*   **Usage Analysis**: Scans your `FitNesseRoot` (files like `.wiki` and `content.txt`) to cross-reference fixture usage. The generated report includes links back to the specific wiki pages where methods are called.
*   **Interactive HTML**: The output is a single-page HTML file with:
    *   Search/Filter functionality.
    *   Table of Contents.
    *   Collapsible "Used in..." sections.
    *   Toggle for inherited members.

## Getting Started

SlimDoc works as a Slim Fixture itself, allowing you to generate documentation as part of your test suite or a dedicated "Documentation" page.

### Demo

A complete working example is available in the **MultiFormExample**. Use FitNesse to run the test page located at:

`FitNesse/FitNesseRoot/Playground/MultiFormExample.wiki`

### Usage in FitNesse

You can invoke the generator using the `SlimDoc.Generator` fixture (implemented by `TSlimDocGeneratorFixture`).

```slim
!3 Documentation
|script                |!-SlimDoc.Generator-!                                                                      |
|show                  |analyze usage |!-..\..\FitNesse\FitNesseRoot-!                                             |
|generate documentation|!-..\..\FitNesse\FitNesseRoot\files\SlimFixturesDocs.html-!                                |
|check                 |generated link|<a href="files/SlimFixturesDocs.html" target="_blank">Open Documentation</a>|
```

**Steps:**
1.  **analyze usage**: (Optional) Scans the provided directory path for fixture usage.
2.  **generate documentation**: Generates the HTML file at the specified path.
3.  **generated link**: Returns an HTML link to the generated file, which can be clicked directly in the FitNesse result.

## Project Structure

*   **Slim.Doc.Extractor.pas**: Handles RTTI extraction and filtering.
*   **Slim.Doc.Generator.pas**: Generates the HTML content, CSS, and JavaScript.
*   **Slim.Doc.UsageAnalyzer.pas**: Parses Wiki files to find Slim tables and method calls.
*   **Slim.Doc.Fixtures.pas**: The entry point fixture (`TSlimDocGeneratorFixture`).
