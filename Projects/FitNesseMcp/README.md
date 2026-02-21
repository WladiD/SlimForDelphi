# FitNesse MCP Server

An MCP (Model Context Protocol) Server enabling access to FitNesse instances. It allows listing pages, reading content, and executing tests directly via MCP clients.

## Configuration

Configuration is handled via the `fitnesse-config.json` file located in the same directory as the executable. This file should **not** be checked into version control as it contains local paths.

### Example `fitnesse-config.json`

```json
{
  "instances": [
    {
      "name": "LocalDev",
      "rootPath": "C:/Projects/MyProject/FitNesse",
      "port": 9001
    },
    {
      "name": "CustomStart",
      "rootPath": "C:/Projects/OtherProject",
      "port": 9002,
      "startCmdLine": "java -jar fitnesse-standalone.jar -p 9002 -e 0"
    },
    {
      "name": "RemoteServer",
      "baseUrl": "http://testserver:8080",
      "rootPath": "\\\\testserver\\share\\FitNesse",
      "port": 8080
    }
  ]
}
```

### Fields

*   **name**: Unique name of the instance (used for selection in the MCP client).
*   **rootPath**: Path to the directory containing the `FitNesseRoot` folder.
*   **port**: The port on which FitNesse is running (or should be started).
*   **fitnesseRoot** (Optional): The name of the FitNesse root directory (e.g. `MyWiki`). If not specified, `FitNesseRoot` is used by default.
*   **startCmdLine** (Optional): The full command line to start the FitNesse instance (e.g. `java -jar my-fitnesse.jar -p 8080`).
    *   If **not** specified, the server attempts to launch `java -jar fitnesse-standalone.jar -p <port> -e 0` in the `rootPath`.
*   **baseUrl** (Optional): The full base URL of the FitNesse instance (e.g., `http://myserver:8080` or `https://secure.example.com`).
    *   If **not** specified, `http://localhost:<port>` is used by default.
    *   Useful for instances on other machines or behind HTTPS/proxies.

## Usage

The server provides the following tools:

*   **`list_instances`**: Lists all configured instances and their status (including whether they are currently running).
*   **`start_instance`**: Starts a local FitNesse instance (using the configured `startCmdLine` or the default Java command).
*   **`list_pages`**: Lists suites and tests under a specific wiki path. Supports recursive listing and includes the page type (Suite, Test, Static).
*   **`run_test`**: Executes a test or suite.
    *   `format`: "junit" (default, compact summary) or "xml" (verbose details).
    *   Returns the result directly. Use the timestamp in the output to retrieve historical results via `get_test_result`.
*   **`get_test_result`**: Retrieves the full execution log (verbose XML) for a specific past test run using its timestamp (`YYYYMMDDHHMMSS`).
*   **`get_page_content`**: Reads the wiki source of a page using the `?edit` responder.
