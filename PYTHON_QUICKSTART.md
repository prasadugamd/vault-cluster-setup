# Python MCP Server Quickstart

## Install

```bash
pip install -r requirements-python.txt
```

## Run

```bash
python -m python_src.index
```

## MCP Client Config Example

```json
{
  "mcpServers": {
    "vault-cluster-python": {
      "command": "python",
      "args": [
        "-m",
        "python_src.index"
      ],
      "cwd": "/absolute/path/to/vault-cluster-mcp-server"
    }
  }
}
```

## Notes

- The Python implementation preserves the same 7 tool names as the TypeScript server.
- The deployment and operations still rely on your existing shell scripts and CLIs (`oc`, `helm`, and shell support for `.sh` scripts).
- On Linux, commands are executed with `/bin/bash` when available for consistent shell behavior.
