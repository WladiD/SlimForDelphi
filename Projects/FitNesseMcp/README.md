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
      "port": 9001,
      "jarPath": "C:/Projects/MyProject/FitNesse/fitnesse-standalone.jar"
    },
    {
      "name": "RemoteServer",
      "baseUrl": "http://testserver:8080",
      "rootPath": "\\\\testserver\\share\\FitNesse",
      "port": 8080,
      "jarPath": "" 
    }
  ]
}
```

### Fields

*   **name**: Unique name of the instance (used for selection in the MCP client).
*   **rootPath**: Path to the directory containing the `FitNesseRoot` folder.
*   **port**: The port on which FitNesse is running (or should be started).
*   **jarPath**: Absolute path to the `fitnesse-standalone.jar`. Required to start the instance via the MCP server.
*   **baseUrl** (Optional): The full base URL of the FitNesse instance (e.g., `http://myserver:8080` or `https://secure.example.com`).
    *   If **not** specified, `http://localhost:<port>` is used by default.
    *   Useful for instances on other machines or behind HTTPS/proxies.

## Usage

The server provides the following tools:

*   `list_instances`: Lists all configured instances and their status.
*   `start_instance`: Starts a local FitNesse instance (requires `jarPath` and Java in the path).
*   `list_pages`: Lists suites and tests under a specific wiki path.
*   `run_test`: Executes a test or suite and returns the result as XML.
*   `get_page_content`: Reads the source content of a wiki page.
