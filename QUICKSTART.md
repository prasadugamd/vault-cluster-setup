# Quick Start Guide

Get the Vault Cluster MCP Server up and running in minutes.

## Step 1: Install Dependencies

```bash
cd vault-cluster-mcp-server
npm install
```

## Step 2: Build the Server

```bash
npm run build
```

This compiles the TypeScript code to JavaScript in the `dist/` directory.

## Step 3: Prepare Deployment Scripts

Ensure you have the vault deployment scripts in a directory. These should include:

- `setup-vault-cluster.sh`
- `generate-certificates.sh`
- `create-namespace-route.sh`
- `deploy-prerequisites.sh`
- `deploy-vault-cluster.sh`
- `deploy-post-install.sh`
- Configuration JSON files (e.g., `config-unsealer-vault.json`)

Example directory structure:
```
/home/user/vault-deployment/
├── setup-vault-cluster.sh
├── generate-certificates.sh
├── config-unsealer-vault.json
├── config-vault-1.json
└── ... (other scripts and configs)
```

## Step 4: Configure Your MCP Client

### For Claude Desktop

1. Find your Claude Desktop config file:
   - **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

2. Add the server configuration:

```json
{
  "mcpServers": {
    "vault-cluster": {
      "command": "node",
      "args": [
        "/absolute/path/to/vault-cluster-mcp-server/dist/index.js"
      ],
      "cwd": "/absolute/path/to/your/vault-deployment-scripts"
    }
  }
}
```

**Important**: Use absolute paths, not relative paths!

3. Restart Claude Desktop

### For VS Code with Copilot (if supported)

Configuration steps will vary based on VS Code's MCP implementation.

## Step 5: Test the Connection

Open Claude Desktop and ask:

```
What vault cluster tools are available?
```

You should see a list of 7 tools:
- deploy_vault_cluster
- manage_vault_config
- generate_certificates
- initialize_vault
- troubleshoot_deployment
- check_cluster_status
- manage_namespace_route

## Step 6: Deploy Your First Vault

Try a simple command:

```
List all vault configuration files in the working directory
```

Then deploy:

```
Deploy a complete vault cluster using config-unsealer-vault.json and config-vault-1.json
```

## Common Commands to Try

1. **Check cluster connectivity**:
   ```
   Check the status of my OpenShift cluster
   ```

2. **View configuration**:
   ```
   Show me the contents of config-vault-1.json
   ```

3. **Deploy unsealer vault**:
   ```
   Deploy only the unsealer vault using config-unsealer-vault.json
   ```

4. **Generate certificates**:
   ```
   Generate certificates for namespace vault-unsealer with release name unsealer-vault
   ```

5. **Troubleshoot**:
   ```
   Troubleshoot deployment issues in namespace vault-unsealer
   ```

## Prerequisites Checklist

Before using the server, ensure you have:

- [ ] Node.js 18+ installed (`node --version`)
- [ ] OpenShift CLI installed (`oc version`)
- [ ] Helm 3 installed (`helm version`)
- [ ] Connected to your OpenShift cluster (`oc cluster-info`)
- [ ] Deployment scripts in working directory
- [ ] Valid configuration JSON files
- [ ] MCP server built (`npm run build`)
- [ ] MCP client configured with correct paths

## Troubleshooting

### "Tool not found" errors

- The MCP server is not connected properly
- Check your MCP client configuration
- Restart your MCP client after making config changes

### "Script not found" errors

- The `cwd` in your config doesn't point to the deployment scripts
- Verify the working directory is correct
- Ensure scripts have execute permissions: `chmod +x *.sh`

### "Cluster not connected" errors

- Run `oc login` to connect to your OpenShift cluster
- Verify with `oc cluster-info`
- Check your KUBECONFIG environment variable

### Permission errors

- Ensure you have appropriate cluster permissions
- You may need cluster-admin or similar roles for namespace creation

## Next Steps

- Read the full [README.md](README.md) for detailed tool documentation
- Check [CLAUDE_SETUP.md](CLAUDE_SETUP.md) for Claude Desktop-specific configuration
- Review the original vault deployment documentation

## Getting Help

If you encounter issues:

1. Check the troubleshooting sections in README.md
2. Verify all prerequisites are met
3. Review MCP client logs
4. Test deployment scripts manually first
5. Open an issue in the project repository

Happy deploying! 🚀
