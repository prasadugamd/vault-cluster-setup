# Vault Deployment Agent Usage Guide

## Overview

The Vault Deployment Agent is a comprehensive automation agent designed to simplify and automate HashiCorp Vault cluster deployments on OpenShift/Kubernetes. This guide explains how to interact with the agent and leverage its capabilities.

## What is the Vault Deployment Agent?

The agent is an AI-powered automation assistant that understands your deployment needs expressed in natural language and executes the appropriate scripts and commands. It has deep knowledge of:

- Vault architecture and deployment patterns
- OpenShift/Kubernetes operations
- TLS certificate management
- Vault initialization and configuration
- Troubleshooting and diagnostics

## Activating the Agent

To use the Vault Deployment Agent, reference it in your GitHub Copilot chat:

```
@vault-deployment-agent <your command or question>
```

## Common Usage Scenarios

### 1. Complete Vault Cluster Deployment

**Scenario**: Deploy both unsealer vault and data vault from scratch.

**Command**:
```
@vault-deployment-agent Deploy complete vault cluster with unsealer and vault-1
```

**What the agent does**:
1. Validates configuration files (config-unsealer-vault.json, config-vault-1.json)
2. Tests cluster connectivity
3. Executes: `./setup-vault-cluster.sh config-unsealer-vault.json config-vault-1.json`
4. Monitors deployment progress
5. Reports final status and next steps

### 2. Deploy Unsealer Vault Only

**Scenario**: Deploy just the unsealer vault for transit encryption.

**Command**:
```
@vault-deployment-agent Deploy unsealer vault
```

**What the agent does**:
1. Validates config-unsealer-vault.json
2. Executes: `./setup-vault-cluster.sh config-unsealer-vault.json`
3. Provides initialization instructions

### 3. Deploy Data Vault with Auto-Unseal

**Scenario**: Deploy a data vault that uses transit auto-unseal from unsealer vault.

**Command**:
```
@vault-deployment-agent Deploy vault-1 with auto-unseal from unsealer vault
```

**What the agent does**:
1. Verifies unsealer vault is ready
2. Validates config-vault-1.json
3. Deploys vault-1 with transit auto-unseal configured
4. Verifies auto-unseal is working

### 4. Certificate Generation

**Scenario**: Generate or regenerate TLS certificates for a vault namespace.

**Command**:
```
@vault-deployment-agent Generate certificates for vault-1 namespace
```

**What the agent does**:
1. Executes: `./generate-certificates.sh config-vault-1.json`
2. Verifies certificates are created with proper SANs
3. Confirms Kubernetes secrets are updated

### 5. Configuration Management

**Scenario**: Create or modify configuration for a new vault deployment.

**Command**:
```
@vault-deployment-agent Create configuration for vault-2 namespace with release name hashicorp-vault-2
```

**What the agent does**:
1. Copies config.example.json
2. Updates namespace to "vault-2"
3. Updates releaseName to "hashicorp-vault-2"
4. Generates appropriate route URL
5. Saves as config-vault-2.json

**Or to modify existing configuration**:
```
@vault-deployment-agent Update vault-1 config to use namespace vault-prod
```

### 6. Troubleshooting Failed Deployments

**Scenario**: A deployment failed and you need diagnostics.

**Command**:
```
@vault-deployment-agent Troubleshoot the failed deployment in vault-1
```

**What the agent does**:
1. Checks pod status: `oc get pods -n vault-1`
2. Reviews pod logs for errors
3. Checks Helm release status
4. Verifies certificates and secrets
5. Provides specific remediation steps

### 7. Verify Deployment Health

**Scenario**: Check if your vault cluster is healthy and operational.

**Command**:
```
@vault-deployment-agent Verify all vault pods are running in unsealer-vault
```

**What the agent does**:
1. Lists pods: `oc get pods -n unsealer-vault`
2. Checks vault status on each pod
3. Verifies raft cluster peers
4. Tests route connectivity
5. Reports overall health status

### 8. Initialize and Unseal Vault

**Scenario**: Initialize a new vault cluster and unseal all pods.

**Command**:
```
@vault-deployment-agent Initialize and unseal the unsealer vault
```

**What the agent does**:
1. Checks if vault is already initialized
2. Runs: `vault operator init` with appropriate parameters
3. Saves unseal keys securely
4. Unseals all three vault pods
5. Verifies cluster status
6. **Important**: Reminds you to save keys securely

### 9. Selective Deployment Steps

**Scenario**: Run deployment but skip certain steps.

**Command**:
```
@vault-deployment-agent Deploy vault-1 but skip certificate generation
```

**What the agent does**:
1. Executes: `./setup-vault-cluster.sh --skip-certs config-vault-1.json`
2. Uses existing certificates
3. Proceeds with rest of deployment

**Other skip options**:
- "skip namespace creation"
- "skip prerequisites"
- "skip post-installation"

### 10. Git Operations

**Scenario**: Commit and push configuration changes.

**Command**:
```
@vault-deployment-agent Commit the configuration changes for vault-2 setup
```

**What the agent does**:
1. Stages changed config files
2. Creates descriptive commit message
3. Commits changes
4. Pushes to remote repository

### 11. Check Deployment Logs

**Scenario**: Review logs from a previous deployment.

**Command**:
```
@vault-deployment-agent Show me the latest deployment logs
```

**What the agent does**:
1. Lists log files in logs/ directory
2. Displays the most recent log file
3. Highlights errors or warnings
4. Suggests actions if issues found

### 12. Route Management

**Scenario**: Verify or troubleshoot OpenShift route for vault access.

**Command**:
```
@vault-deployment-agent Check the OpenShift route for unsealer-vault
```

**What the agent does**:
1. Gets route: `oc get route vault -n unsealer-vault`
2. Shows route details
3. Tests connectivity to route URL
4. Provides access URL for UI

## Advanced Usage Examples

### Multi-Vault Orchestration

Deploy multiple vaults in sequence with dependencies:

```
@vault-deployment-agent Deploy unsealer vault first, then vault-1 and vault-2 with auto-unseal
```

### Configuration Validation

Validate configuration before deployment:

```
@vault-deployment-agent Validate config-vault-1.json for deployment
```

### Certificate Verification

Check certificate validity and SANs:

```
@vault-deployment-agent Verify TLS certificates in vault-1 namespace are valid
```

### Rollback Scenario

Handle rollback of failed deployment:

```
@vault-deployment-agent Rollback the failed vault-1 deployment and clean up resources
```

### Status Report

Get comprehensive status report:

```
@vault-deployment-agent Give me a complete status report of all deployed vaults
```

## Best Practices

### 1. Always Validate First

Before major operations, ask the agent to validate:
```
@vault-deployment-agent Validate prerequisites for vault deployment
```

### 2. Test Connectivity

Before deployment, test cluster access:
```
@vault-deployment-agent Test Kubernetes cluster connectivity
```

### 3. Incremental Deployment

Deploy in stages for easier troubleshooting:
```
@vault-deployment-agent Deploy unsealer vault only
# After verifying unsealer works:
@vault-deployment-agent Deploy vault-1 with auto-unseal
```

### 4. Save Deployment Artifacts

Always ask agent to save important information:
```
@vault-deployment-agent Save the vault initialization keys to a secure location
```

### 5. Monitor Progress

Ask for status during long operations:
```
@vault-deployment-agent Show deployment progress
```

## Understanding Agent Responses

The agent provides structured responses:

1. **Acknowledgment**: Confirms what it will do
2. **Execution**: Shows commands being run
3. **Output**: Displays relevant command output
4. **Interpretation**: Explains what the output means
5. **Next Steps**: Suggests what to do next

Example response:
```
I'll deploy the unsealer vault for you.

Executing: ./setup-vault-cluster.sh config-unsealer-vault.json

[Command output shown]

✓ Deployment completed successfully!

Next steps:
1. Initialize vault: oc exec vault-0 -n unsealer-vault -- vault operator init
2. Save the unseal keys securely
3. Enable transit secrets engine for auto-unseal
```

## Troubleshooting Agent Usage

### Agent Not Understanding Command

If the agent doesn't understand your request:
- Be more specific about what you want
- Reference configuration files by name
- Use terms from the scripts (e.g., "unsealer vault", "vault-1")

**Instead of**: "Deploy the thing"
**Try**: "Deploy unsealer vault using config-unsealer-vault.json"

### Agent Can't Find Files

If the agent reports missing files:
- Verify you're in the correct directory
- Check file names are exact (case-sensitive)
- List files: `@vault-deployment-agent List all configuration files`

### Command Execution Fails

If commands fail:
- Ask agent to troubleshoot: `@vault-deployment-agent Why did that fail?`
- Check prerequisites: `@vault-deployment-agent Verify all prerequisites are installed`
- Review logs: `@vault-deployment-agent Show me the error logs`

## Natural Language Tips

The agent understands natural language. You can phrase requests conversationally:

✅ **Good examples**:
- "Deploy both vaults"
- "Create certificates for vault-1"
- "What went wrong with the deployment?"
- "Show me the pods in unsealer-vault"
- "Update the namespace in vault-2 config"

✅ **Also works**:
- Formal: "Execute deployment script for unsealer vault"
- Casual: "Deploy the unsealer thing"
- Technical: "Initialize vault cluster in namespace unsealer-vault"

## Quick Reference Card

| Task | Example Command |
|------|----------------|
| Full deployment | `@vault-deployment-agent Deploy complete vault cluster` |
| Deploy one vault | `@vault-deployment-agent Deploy unsealer vault` |
| Generate certs | `@vault-deployment-agent Generate certificates for vault-1` |
| Initialize vault | `@vault-deployment-agent Initialize unsealer vault` |
| Check status | `@vault-deployment-agent Check vault cluster health` |
| Troubleshoot | `@vault-deployment-agent Troubleshoot vault-1 deployment` |
| Update config | `@vault-deployment-agent Update vault-1 namespace to vault-prod` |
| Commit changes | `@vault-deployment-agent Commit and push config changes` |
| View logs | `@vault-deployment-agent Show deployment logs` |
| Test connection | `@vault-deployment-agent Test cluster connectivity` |

## Security Reminders

When working with the agent:

1. **Never share unseal keys or tokens in chat** - Agent will remind you to save securely
2. **Review commands before execution** - Agent shows commands before running
3. **Don't commit secrets** - Agent validates this, but be aware
4. **Use secure channels** - For sensitive operations, use secure communication
5. **Rotate credentials** - Regularly rotate vault credentials

## Getting Help

If you need help with the agent:

1. **Ask the agent**: `@vault-deployment-agent How do I deploy a vault with auto-unseal?`
2. **Check documentation**: Review README-BASH.md and VAULT_DEPLOYMENT_GUIDE.md
3. **View logs**: Check logs/ directory for detailed information
4. **Describe your goal**: Tell the agent what you're trying to achieve

## Limitations

The agent can:
- ✅ Execute deployment scripts
- ✅ Manage configurations
- ✅ Run kubectl/oc commands
- ✅ Generate certificates
- ✅ Perform git operations
- ✅ Troubleshoot deployments

The agent cannot:
- ❌ Access external resources not in the cluster
- ❌ Modify Helm charts directly (uses provided charts)
- ❌ Change cluster-level permissions
- ❌ Bypass Kubernetes RBAC

## Support

For issues:
1. Check logs: `@vault-deployment-agent Show latest logs`
2. Verify prerequisites: `@vault-deployment-agent Check prerequisites`
3. Test connectivity: `@vault-deployment-agent Test connection`
4. Ask agent: `@vault-deployment-agent Help me troubleshoot`

## Examples of Complex Scenarios

### Scenario: New Production Deployment

```
@vault-deployment-agent Create config for vault-prod namespace
@vault-deployment-agent Validate vault-prod configuration
@vault-deployment-agent Test cluster connectivity
@vault-deployment-agent Deploy vault-prod with all steps
@vault-deployment-agent Initialize vault-prod
@vault-deployment-agent Verify vault-prod is healthy
@vault-deployment-agent Commit vault-prod configuration
```

### Scenario: Certificate Rotation

```
@vault-deployment-agent Backup current certificates for vault-1
@vault-deployment-agent Regenerate certificates for vault-1
@vault-deployment-agent Verify new certificates are valid
@vault-deployment-agent Restart vault pods to use new certificates
```

### Scenario: Disaster Recovery

```
@vault-deployment-agent Show me the status of all vaults
@vault-deployment-agent Check what's failing in vault-1
@vault-deployment-agent Show me the pod logs for vault-1
@vault-deployment-agent Redeploy vault-1 cluster
@vault-deployment-agent Verify vault-1 is operational
```

## Conclusion

The Vault Deployment Agent is designed to make your Vault deployments easier, faster, and more reliable. Use natural language to express your intentions, and the agent will handle the technical details. Always review what the agent plans to do, and don't hesitate to ask for clarification or help.

Happy deploying! 🚀
