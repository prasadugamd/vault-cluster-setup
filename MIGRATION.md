# Migration Guide: From Copilot Agent to MCP Server

This guide explains the differences between the original GitHub Copilot agent implementation and the new MCP server, helping you understand which to use and how they compare.

## Overview Comparison

| Aspect | Copilot Agent | MCP Server |
|--------|---------------|------------|
| **Platform** | GitHub Copilot / VS Code | Any MCP-compatible client |
| **Format** | YAML configuration + Markdown docs | Running Node.js server |
| **Invocation** | `@vault-deployment-agent` | Natural language via MCP client |
| **Tools** | Inferred from instructions | Explicitly defined with schemas |
| **Distribution** | Git repository files | npm package |
| **Setup** | Copy `.github/agents/` folder | Install and configure server |
| **Portability** | GitHub ecosystem only | Works with Claude Desktop, VS Code (future), etc. |

## Feature Comparison

### Copilot Agent (Original)

**Location**: `vault-cluster-setup-copilot-create-vault-cluster-agent/`

**Strengths**:
- ✅ Simple setup (just copy files)
- ✅ Integrated with GitHub Copilot Chat
- ✅ Works in VS Code out of the box
- ✅ No server process to manage
- ✅ Documentation-driven approach

**Limitations**:
- ❌ Only works in GitHub Copilot
- ❌ Limited to VS Code/GitHub ecosystem
- ❌ Tool capabilities inferred, not structured
- ❌ Cannot be used in Claude Desktop or other AI platforms

**Files**:
```
.github/agents/vault-deployment-agent.yaml
AGENT_USAGE_GUIDE.md
AGENT_QUICK_REFERENCE.md
AGENT_TEST_SCENARIOS.md
```

**Usage Example**:
```
@vault-deployment-agent Deploy complete vault cluster
```

### MCP Server (New)

**Location**: `vault-cluster-mcp-server/`

**Strengths**:
- ✅ Works with multiple AI platforms (Claude Desktop, potentially VS Code, etc.)
- ✅ Structured, schema-based tools
- ✅ Professional Node.js/TypeScript implementation
- ✅ Can be published to npm
- ✅ Explicit error handling and validation
- ✅ Reusable across different AI assistants

**Limitations**:
- ❌ Requires Node.js and build process
- ❌ More complex setup
- ❌ Requires MCP client configuration
- ❌ Server process needs to be running

**Files**:
```
src/index.ts (main server)
src/tools/*.ts (tool implementations)
package.json
README.md, QUICKSTART.md, etc.
```

**Usage Example**:
```
Deploy complete vault cluster using config-unsealer-vault.json
```
(Same natural language, but through MCP client like Claude Desktop)

## When to Use Each

### Use Copilot Agent When:

1. You work primarily in VS Code with GitHub Copilot
2. You want the simplest setup possible
3. You don't need support for other AI platforms
4. You prefer a file-based configuration approach
5. Your team is already using GitHub Copilot Chat

### Use MCP Server When:

1. You want to use Claude Desktop or other MCP clients
2. You need a professional, structured tool interface
3. You want to distribute the tools as a package
4. You need explicit tool schemas and validation
5. You want maximum portability across AI platforms
6. You're building for enterprise use with multiple AI platforms

## Migration Path

If you're currently using the Copilot agent and want to migrate to MCP:

### Step 1: Install MCP Server

```bash
cd vault-cluster-mcp-server
npm install
npm run build
```

### Step 2: Configure Your MCP Client

For Claude Desktop, add to config:
```json
{
  "mcpServers": {
    "vault-cluster": {
      "command": "node",
      "args": ["/path/to/vault-cluster-mcp-server/dist/index.js"],
      "cwd": "/path/to/deployment-scripts"
    }
  }
}
```

### Step 3: Test the Tools

Open Claude Desktop and ask:
```
What vault deployment tools are available?
```

### Step 4: Use Natural Language

The commands work the same way, just without the `@vault-deployment-agent` prefix:

**Before (Copilot)**:
```
@vault-deployment-agent Deploy unsealer vault
```

**After (MCP)**:
```
Deploy unsealer vault
```

## Tool Mapping

Both implementations provide the same core capabilities:

| Capability | Copilot Agent | MCP Server Tool |
|------------|---------------|-----------------|
| Deploy cluster | Natural language interpretation | `deploy_vault_cluster` |
| Manage configs | Natural language interpretation | `manage_vault_config` |
| Generate certificates | Natural language interpretation | `generate_certificates` |
| Initialize vault | Natural language interpretation | `initialize_vault` |
| Troubleshoot | Natural language interpretation | `troubleshoot_deployment` |
| Check status | Natural language interpretation | `check_cluster_status` |
| Manage namespace | Natural language interpretation | `manage_namespace_route` |

## Coexistence

**Good news**: You can use both simultaneously!

- Keep the Copilot agent for VS Code development
- Use the MCP server with Claude Desktop for operations
- They share the same underlying bash scripts
- Both read/write the same configuration files

## Choosing for Your Team

### Small Team Using VS Code

**Recommendation**: Start with Copilot Agent

- Simpler setup
- Works immediately in your existing workflow
- Less maintenance

### Enterprise or Multi-Platform

**Recommendation**: Use MCP Server

- Professional implementation
- Works across AI platforms
- Better for standardization
- Can be packaged and distributed

### Power Users

**Recommendation**: Use Both!

- Copilot agent for quick development tasks in VS Code
- MCP server for operations via Claude Desktop
- Get the best of both worlds

## Future Considerations

### MCP Server Advantages Going Forward

- **Broader adoption**: MCP is gaining support across platforms
- **Standardization**: MCP provides a standard protocol
- **Extensibility**: Easier to add new tools and features
- **Professional**: Better for enterprise and production use

### Copilot Agent Advantages Going Forward

- **Integration**: Deep VS Code/GitHub integration
- **Simplicity**: Less infrastructure to manage
- **Development focused**: Better for development workflows

## Technical Differences

### Error Handling

**Copilot Agent**: Errors handled by AI interpretation  
**MCP Server**: Structured error responses with `isError` flag

### Tool Invocation

**Copilot Agent**: AI decides which bash scripts to run  
**MCP Server**: Explicit tool calls with validated parameters

### Validation

**Copilot Agent**: AI validates based on instructions  
**MCP Server**: JSON schema validation built-in

### Output Format

**Copilot Agent**: Free-form text responses  
**MCP Server**: Structured markdown with consistent formatting

## Conclusion

Both implementations are valuable:

- **Copilot Agent**: Perfect for developers working in VS Code
- **MCP Server**: Best for operations teams and multi-platform use

Choose based on your needs, or use both for maximum flexibility!

## Getting Help

- Copilot Agent docs: See `AGENT_USAGE_GUIDE.md` in the agent directory
- MCP Server docs: See `README.md` and `QUICKSTART.md` in the server directory
- Both share the same deployment scripts and bash documentation

## Contributing

Both implementations are open for contributions:
- Copilot Agent: Update YAML and documentation
- MCP Server: Contribute TypeScript tools and features
