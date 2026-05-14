# Claude Desktop Configuration Example

This file shows how to configure the Vault Cluster MCP Server for use with Claude Desktop.

## Configuration File Location

### macOS
`~/Library/Application Support/Claude/claude_desktop_config.json`

### Windows
`%APPDATA%\Claude\claude_desktop_config.json`

### Linux
`~/.config/Claude/claude_desktop_config.json`

## Configuration

```json
{
  "mcpServers": {
    "vault-cluster": {
      "command": "node",
      "args": [
        "/absolute/path/to/vault-cluster-mcp-server/dist/index.js"
      ],
      "cwd": "/absolute/path/to/your/vault-deployment-scripts",
      "env": {
        "KUBECONFIG": "/path/to/.kube/config"
      }
    }
  }
}
```

## Configuration Options

- **command**: The command to run the server (use `node` for the built JavaScript)
- **args**: Array containing the path to the compiled server entry point
- **cwd**: Working directory where your vault deployment scripts are located
- **env** (optional): Environment variables, such as KUBECONFIG for cluster access

## Multiple Environments

You can configure multiple instances for different environments:

```json
{
  "mcpServers": {
    "vault-cluster-dev": {
      "command": "node",
      "args": ["/path/to/vault-cluster-mcp-server/dist/index.js"],
      "cwd": "/path/to/dev/vault-scripts"
    },
    "vault-cluster-prod": {
      "command": "node",
      "args": ["/path/to/vault-cluster-mcp-server/dist/index.js"],
      "cwd": "/path/to/prod/vault-scripts"
    }
  }
}
```

## After Configuration

1. Save the configuration file
2. Restart Claude Desktop
3. The vault cluster tools should now be available
4. You can ask Claude to deploy vaults, manage configs, etc.

## Verifying It Works

After restarting Claude Desktop, try asking:

```
What vault deployment tools are available?
```

Claude should list the 7 available tools from the MCP server.

## Troubleshooting

If the tools don't appear:

1. Check the paths in your configuration are absolute and correct
2. Ensure the server is built: `npm run build` in the server directory
3. Verify Node.js is in your PATH
4. Check Claude Desktop logs for connection errors
5. Ensure the working directory contains the vault deployment scripts
