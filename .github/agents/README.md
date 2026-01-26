# Vault Deployment Agent

This directory contains the configuration for the Vault Deployment Automation Agent, an AI-powered assistant for managing HashiCorp Vault cluster deployments.

## Agent File

- **vault-deployment-agent.yaml**: Complete agent definition with instructions, capabilities, and workflows

## What is This Agent?

The Vault Deployment Agent is a specialized AI assistant that:

1. **Understands Vault Deployments**: Deep knowledge of Vault architecture, deployment patterns, and best practices
2. **Executes Scripts Automatically**: Can run deployment scripts, generate certificates, and manage configurations
3. **Handles Natural Language**: Responds to commands like "Deploy unsealer vault" or "Troubleshoot the failed deployment"
4. **Provides Expert Guidance**: Offers troubleshooting advice, next steps, and deployment strategies
5. **Manages Git Operations**: Commits and pushes configuration changes
6. **Ensures Security**: Follows security best practices and reminds users to secure sensitive data

## Agent Capabilities

### Core Functions

1. **Deployment Orchestration**
   - Complete vault cluster deployment (unsealer + data vaults)
   - Individual vault deployment
   - Selective step deployment (skip certs, prereqs, etc.)
   - Multi-vault deployments

2. **Configuration Management**
   - Create new configurations from templates
   - Modify existing configurations
   - Validate configuration files
   - Commit and push changes

3. **Certificate Operations**
   - Generate TLS certificates
   - Verify certificate validity
   - Rotate certificates
   - Manage Kubernetes secrets

4. **Vault Operations**
   - Initialize vault clusters
   - Unseal vault pods
   - Setup transit auto-unseal
   - Configure authentication and policies

5. **Troubleshooting**
   - Diagnose deployment failures
   - Check pod status and logs
   - Verify routes and connectivity
   - Provide remediation steps

6. **Status & Monitoring**
   - Verify deployment health
   - Check vault cluster status
   - Display route information
   - Report raft peer status

## Using the Agent

### Basic Invocation

```
@vault-deployment-agent <your command>
```

### Example Commands

```
# Deploy complete cluster
@vault-deployment-agent Deploy complete vault cluster

# Deploy single vault
@vault-deployment-agent Deploy unsealer vault

# Generate certificates
@vault-deployment-agent Generate certificates for vault-1

# Troubleshoot
@vault-deployment-agent Troubleshoot the failed deployment in vault-1

# Check status
@vault-deployment-agent Verify all pods are running

# Configuration
@vault-deployment-agent Create config for vault-2 namespace

# Git operations
@vault-deployment-agent Commit and push configuration changes
```

## Documentation

For complete documentation, see:

- **[AGENT_USAGE_GUIDE.md](../AGENT_USAGE_GUIDE.md)**: Comprehensive usage guide with detailed examples
- **[AGENT_QUICK_REFERENCE.md](../AGENT_QUICK_REFERENCE.md)**: Quick reference for common commands
- **[AGENT_TEST_SCENARIOS.md](../AGENT_TEST_SCENARIOS.md)**: Test scenarios and expected behaviors
- **[README-BASH.md](../README-BASH.md)**: Main project documentation

## Agent Configuration

The agent is configured with:

### Knowledge Areas

- HashiCorp Vault architecture and operations
- Kubernetes/OpenShift resource management
- TLS certificate generation and management
- Helm chart deployments
- Bash scripting and automation
- Git version control

### Available Scripts

The agent has access to:
- `setup-vault-cluster.sh` - Main orchestration
- `create-namespace-route.sh` - Namespace setup
- `generate-certificates.sh` - Certificate generation
- `deploy-prerequisites.sh` - Prerequisites
- `deploy-vault-cluster.sh` - Cluster deployment
- `deploy-post-install.sh` - Post-installation

### Configuration Files

The agent works with:
- `config-unsealer-vault.json` - Unsealer vault configuration
- `config-vault-1.json` - Data vault configuration
- `config.example.json` - Template for new configurations

## Deployment Workflows

The agent supports these primary workflows:

### 1. Complete New Deployment
```
Test connectivity → Deploy cluster → Initialize vault → Verify → Commit
```

### 2. Individual Vault Deployment
```
Validate config → Generate certs → Deploy → Initialize → Verify
```

### 3. Configuration Management
```
Create/modify config → Validate → Deploy → Commit
```

### 4. Troubleshooting
```
Detect issue → Check logs → Diagnose → Suggest fix → Verify
```

### 5. Certificate Management
```
Generate certs → Verify → Update secrets → Restart pods
```

## Security Considerations

The agent follows these security practices:

1. **Never exposes sensitive data**: Unseal keys and tokens are never displayed in full
2. **Reminds users to secure data**: Always prompts to save keys securely
3. **Validates configurations**: Checks for security misconfigurations
4. **Uses secure connections**: Enforces TLS for all communications
5. **Follows least privilege**: Only performs requested operations

## Agent Response Format

The agent provides structured responses:

1. **Acknowledgment**: Confirms what it will do
2. **Validation**: Checks prerequisites
3. **Execution**: Runs commands and shows output
4. **Interpretation**: Explains results
5. **Next Steps**: Suggests what to do next

Example:
```
I'll deploy the unsealer vault for you.

First, validating configuration...
✓ config-unsealer-vault.json is valid

Checking cluster connectivity...
✓ Cluster is accessible

Executing: ./setup-vault-cluster.sh config-unsealer-vault.json

[Output displayed]

✓ Deployment completed successfully!

Next steps:
1. Initialize vault: oc exec vault-0 -n unsealer-vault -- vault operator init
2. Save the unseal keys securely
3. Enable transit secrets engine
```

## Troubleshooting the Agent

### Agent Not Responding

- Ensure proper invocation: `@vault-deployment-agent <command>`
- Check you're in the correct repository
- Verify agent file exists: `.github/agents/vault-deployment-agent.yaml`

### Agent Doesn't Understand

- Be more specific: Include namespace, config file names
- Use terminology from the documentation
- Reference specific scripts or operations

### Commands Fail

- Check prerequisites are installed (oc, helm, jq, openssl)
- Verify cluster connectivity
- Check configuration files exist
- Review logs in `logs/` directory

## Contributing to the Agent

To modify the agent:

1. Edit `.github/agents/vault-deployment-agent.yaml`
2. Update instructions or capabilities
3. Test changes with sample commands
4. Update documentation
5. Commit changes

## Version Information

- **Agent Version**: 1.0
- **Created**: 2026-01-26
- **Last Updated**: 2026-01-26
- **Maintainer**: Vault Cluster Setup Automation Team

## Support

For issues or questions:

1. Check documentation in this directory
2. Review test scenarios for examples
3. Check deployment logs: `logs/`
4. Ask the agent: `@vault-deployment-agent Help me with <topic>`

## License

Internal use only - HashiCorp Vault Cluster Setup Automation

---

**Quick Links**:
- [Usage Guide](../AGENT_USAGE_GUIDE.md)
- [Quick Reference](../AGENT_QUICK_REFERENCE.md)
- [Test Scenarios](../AGENT_TEST_SCENARIOS.md)
- [Main README](../README-BASH.md)
