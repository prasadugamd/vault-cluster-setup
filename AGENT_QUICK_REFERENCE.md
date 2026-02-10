# Vault Deployment Agent - Quick Reference

## Agent Invocation
```
@vault-deployment-agent <your command>
```

## Core Commands

### Deployment
| Command | Action |
|---------|--------|
| Deploy complete vault cluster | Deploys unsealer + data vaults |
| Deploy unsealer vault | Deploys only unsealer vault |
| Deploy vault-1 | Deploys vault-1 with auto-unseal |
| Deploy vault-1 but skip certificates | Uses existing certs |

### Configuration
| Command | Action |
|---------|--------|
| Create config for vault-2 | Creates new config file |
| Update vault-1 namespace to vault-prod | Modifies existing config |
| Validate config-vault-1.json | Checks config validity |
| List all configuration files | Shows available configs |

### Certificates
| Command | Action |
|---------|--------|
| Generate certificates for vault-1 | Creates TLS certs |
| Verify certificates in vault-1 | Checks cert validity |
| Regenerate certificates | Recreates certs |

### Initialization & Operations
| Command | Action |
|---------|--------|
| Initialize unsealer vault | Runs vault operator init |
| Initialize and unseal unsealer vault | Init + unseal all pods |
| Fix unsealer vault | Quick init/unseal using fix-unsealer-vault.sh |
| Enable transit on unsealer vault | Sets up auto-unseal |

### Troubleshooting
| Command | Action |
|---------|--------|
| Troubleshoot vault-1 deployment | Diagnoses issues |
| Check vault cluster health | Verifies all components |
| Show deployment logs | Displays log files |
| Why did the deployment fail? | Analyzes errors |
| Show me pod logs for vault-1 | Gets pod logs |

### Status & Verification
| Command | Action |
|---------|--------|
| Verify all pods are running | Checks pod status |
| Check route for unsealer-vault | Shows route info |
| Test cluster connectivity | Tests oc access |
| Give me complete status report | Full cluster status |

### Git Operations
| Command | Action |
|---------|--------|
| Commit config changes | Git commit + push |
| Commit vault-2 configuration | Specific config commit |
| Show git status | Current git state |

## Deployment Flags

Add these to deployment commands:

- `skip certificates` - Use existing certificates
- `skip namespace` - Don't create namespace
- `skip prerequisites` - Skip prereq install
- `skip post-installation` - Skip post-install

Example:
```
@vault-deployment-agent Deploy vault-1 but skip certificates and prerequisites
```

## Configuration Structure

```json
{
  "directories": {
    "basePath": "/jenkins_home/vault-cluster-setup",
    "cluster": "fndsec-hashicorp-vault-helm-1.6.0/hashicorp-vault"
  },
  "deployment": {
    "namespace": "vault-1",
    "releaseName": "hashicorp-vault",
    "routeName": "vault",
    "helmTimeout": "10m"
  }
}
```

## Typical Workflows

### New Vault Setup
```
1. @vault-deployment-agent Test cluster connectivity
2. @vault-deployment-agent Deploy complete vault cluster
3. @vault-deployment-agent Initialize unsealer vault
4. @vault-deployment-agent Verify all pods are running
5. @vault-deployment-agent Commit configuration
```

### Add New Data Vault
```
1. @vault-deployment-agent Create config for vault-3
2. @vault-deployment-agent Validate vault-3 config
3. @vault-deployment-agent Deploy vault-3
4. @vault-deployment-agent Verify vault-3 auto-unsealed
```

### Troubleshoot Failure
```
1. @vault-deployment-agent What went wrong?
2. @vault-deployment-agent Show me the error logs
3. @vault-deployment-agent Check pod status in vault-1
4. @vault-deployment-agent Suggest remediation steps
```

### Certificate Rotation
```
1. @vault-deployment-agent Regenerate certificates for vault-1
2. @vault-deployment-agent Verify new certificates
3. @vault-deployment-agent Restart vault-1 pods
```

## Common Issues & Solutions

| Issue | Command |
|-------|---------|
| Pods not starting | `@vault-deployment-agent Troubleshoot vault-1 deployment` |
| Vault sealed | `@vault-deployment-agent Unseal vault in unsealer-vault` |
| Route not working | `@vault-deployment-agent Check route for vault-1` |
| Cert errors | `@vault-deployment-agent Verify certificates in vault-1` |
| Can't connect | `@vault-deployment-agent Test cluster connectivity` |

## Script Locations

Agent has access to these scripts:
- `setup-vault-cluster.sh` - Main orchestration
- `create-namespace-route.sh` - Namespace setup
- `generate-certificates.sh` - TLS certificates
- `deploy-prerequisites.sh` - Prerequisites
- `deploy-vault-cluster.sh` - Cluster deployment
- `deploy-post-install.sh` - Post-install tasks
- `fix-unsealer-vault.sh` - Quick initialize/unseal unsealer vault

## Configuration Files

- `config-unsealer-vault.json` - Unsealer vault config
- `config-vault-1.json` - Vault-1 config
- `config.example.json` - Template for new configs

## Logs

Deployment logs are in: `logs/vault_setup_YYYYMMDD_HHmmss.log`

View with: `@vault-deployment-agent Show deployment logs`

## Next Steps After Deployment

1. Initialize vault (if not auto-initialized)
2. Save unseal keys securely
3. Login with root token
4. Configure auth methods
5. Set up policies
6. Enable secrets engines
7. Test access via route

## Security Notes

- Never share unseal keys in chat
- Save keys to secure password manager
- Don't commit secrets to git
- Use TLS for all connections
- Rotate credentials regularly

## Getting Help

```
@vault-deployment-agent Help me with <topic>
@vault-deployment-agent How do I <action>
@vault-deployment-agent What should I do next?
```

## Examples by Role

### DevOps Engineer
```
@vault-deployment-agent Deploy vault-prod environment
@vault-deployment-agent Setup auto-unseal for vault-prod
@vault-deployment-agent Verify vault-prod is production ready
```

### Platform Administrator
```
@vault-deployment-agent Show status of all vaults
@vault-deployment-agent Rotate certificates for all vaults
@vault-deployment-agent Generate compliance report
```

### Developer
```
@vault-deployment-agent Deploy dev vault for testing
@vault-deployment-agent Show me how to access vault UI
@vault-deployment-agent Help me configure app authentication
```

## Advanced Usage

### Parallel Deployments
```
@vault-deployment-agent Deploy vault-2 and vault-3 simultaneously
```

### Conditional Deployment
```
@vault-deployment-agent Deploy vault-1 only if unsealer vault is healthy
```

### Custom Configuration
```
@vault-deployment-agent Create vault config with namespace vault-qa, release name qa-vault, and custom route vault-qa.example.com
```

## Emergency Commands

| Emergency | Command |
|-----------|---------|
| Production down | `@vault-deployment-agent Emergency status check all vaults` |
| Need rollback | `@vault-deployment-agent Rollback vault-1 to previous version` |
| Cluster issues | `@vault-deployment-agent Full diagnostic of cluster health` |
| Cert expired | `@vault-deployment-agent Emergency certificate regeneration vault-prod` |

## Pro Tips

1. **Be specific**: Include namespace/config names
2. **Use natural language**: Agent understands context
3. **Chain operations**: Ask for multiple steps
4. **Verify first**: Test before production deploys
5. **Check logs**: Always review logs after deployment

## Feedback

Agent learns from usage. Provide feedback:
```
@vault-deployment-agent That worked perfectly
@vault-deployment-agent That didn't work as expected
```

---

For detailed guide: See [AGENT_USAGE_GUIDE.md](./AGENT_USAGE_GUIDE.md)

For deployment details: See [README-BASH.md](./README-BASH.md)
