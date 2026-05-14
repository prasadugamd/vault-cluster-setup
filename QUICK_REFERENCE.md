# Quick Reference Card

## 7 Available Tools

### 1. deploy_vault_cluster
**Purpose**: Deploy vault clusters  
**Key Params**: configFiles, deploymentType  
**Example**: `Deploy complete cluster with unsealer and vault-1`

### 2. manage_vault_config
**Purpose**: Manage configuration files  
**Operations**: read, create, update, validate, list  
**Example**: `Update config-vault-1.json namespace to vault-prod`

### 3. generate_certificates
**Purpose**: Generate TLS certificates  
**Key Params**: namespace, releaseName, route  
**Example**: `Generate certificates for vault-1 in vault-prod`

### 4. initialize_vault
**Purpose**: Initialize and unseal vaults  
**Operations**: init, unseal, enable-transit, check-seal-status  
**Example**: `Initialize unsealer vault with 5 key shares`

### 5. troubleshoot_deployment
**Purpose**: Diagnose issues  
**Check Types**: all, pods, logs, helm, route  
**Example**: `Troubleshoot deployment in namespace vault-prod`

### 6. check_cluster_status
**Purpose**: Monitor cluster health  
**Key Params**: namespace, releaseName, detailed  
**Example**: `Check detailed status of vault-1 cluster`

### 7. manage_namespace_route
**Purpose**: Manage namespaces and routes  
**Operations**: create, delete, check  
**Example**: `Create namespace vault-prod with route`

## Common Workflows

### New Deployment
```
1. List configs
2. Validate configs
3. Deploy cluster
4. Initialize unsealer
5. Enable transit
6. Check status
```

### Troubleshooting
```
1. Troubleshoot namespace
2. Check pod logs
3. Verify certificates
4. Review remediation
```

### Configuration Changes
```
1. Read config
2. Update config
3. Validate config
4. Redeploy
```

## Quick Commands

| Task | Natural Language |
|------|-----------------|
| Deploy | `Deploy vault using config-vault-1.json` |
| Status | `Check vault cluster status` |
| Logs | `Show logs for vault pod` |
| Initialize | `Initialize vault in namespace vault-prod` |
| Troubleshoot | `What's wrong with my vault deployment?` |
| Config | `Update vault config namespace to prod` |
| Certificates | `Generate certificates for vault-1` |

## Environment Setup

```bash
# Build server
npm install && npm run build

# Configure Claude Desktop
# Edit: ~/.config/Claude/claude_desktop_config.json (Linux)
#       ~/Library/Application Support/Claude/claude_desktop_config.json (macOS)
#       %APPDATA%\Claude\claude_desktop_config.json (Windows)

# Add:
{
  "mcpServers": {
    "vault-cluster": {
      "command": "node",
      "args": ["/path/to/vault-cluster-mcp-server/dist/index.js"],
      "cwd": "/path/to/vault-scripts"
    }
  }
}
```

## Prerequisites

- [ ] Node.js 18+
- [ ] oc CLI
- [ ] Helm 3
- [ ] Cluster access
- [ ] Deployment scripts
- [ ] Valid configs

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Tools not found | Check MCP client config, restart client |
| Script errors | Verify working directory, check permissions |
| Cluster errors | Run `oc login`, verify credentials |
| Build errors | Run `npm run build`, check TypeScript |

## Tips

1. **Be Specific**: Include namespace and release names
2. **Check First**: Always check status before and after
3. **Save Keys**: Store unseal keys and tokens securely
4. **Use Natural Language**: No need for exact syntax
5. **Step by Step**: Break complex tasks into steps

## Documentation

- Full docs: `README.md`
- Quick start: `QUICKSTART.md`
- Examples: `EXAMPLES.md`
- Claude setup: `CLAUDE_SETUP.md`
- Migration: `MIGRATION.md`

## Support

- Check logs in working directory
- Verify prerequisites installed
- Review error messages carefully
- Test bash scripts manually if needed

---

**Version**: 1.0.0  
**Protocol**: MCP (Model Context Protocol)  
**Platform**: Any MCP-compatible client
