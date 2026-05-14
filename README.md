# Vault Cluster MCP Server

Model Context Protocol (MCP) server for automating HashiCorp Vault cluster deployments on OpenShift/Kubernetes platforms.

## Overview

This MCP server provides AI assistants with tools to deploy, configure, and manage HashiCorp Vault clusters. It wraps the bash automation scripts from the original project and exposes them as structured MCP tools.

## Features

- **Deploy Vault Clusters**: Complete deployment orchestration for unsealer and data vaults
- **Configuration Management**: Create, read, update, and validate JSON configuration files
- **Certificate Generation**: Generate and verify TLS certificates for secure communications
- **Vault Initialization**: Initialize vaults, manage unseal keys, and enable transit auto-unseal
- **Troubleshooting**: Comprehensive diagnostic tools for pod, helm, and vault status
- **Status Checking**: Monitor cluster health and deployment status
- **Namespace Management**: Create and manage OpenShift namespaces and routes

## Available Tools

### 1. `deploy_vault_cluster`
Deploy a complete Vault cluster or individual components.

**Parameters:**
- `configFiles`: Array of configuration file paths
- `deploymentType`: Type of deployment (complete, unsealer-only, data-vault)
- `skipCertificates`: Skip certificate generation (optional)
- `skipPrerequisites`: Skip prerequisites deployment (optional)
- `workingDirectory`: Working directory path (optional)

**Example:**
```json
{
  "configFiles": ["config-unsealer-vault.json", "config-vault-1.json"],
  "deploymentType": "complete"
}
```

### 2. `manage_vault_config`
Manage Vault configuration files.

**Operations:** read, create, update, validate, list

**Parameters:**
- `operation`: Operation to perform
- `configFile`: Configuration file path
- `updates`: Key-value pairs to update (for update operation)
- `template`: Template file for creating new configs
- `workingDirectory`: Working directory path (optional)

**Example:**
```json
{
  "operation": "update",
  "configFile": "config-vault-1.json",
  "updates": {
    "namespace": "vault-prod",
    "replicas": 3
  }
}
```

### 3. `generate_certificates`
Generate TLS certificates for Vault.

**Parameters:**
- `namespace`: Kubernetes namespace
- `releaseName`: Helm release name
- `route`: OpenShift route hostname (optional)
- `operation`: generate, verify, or regenerate (default: generate)
- `workingDirectory`: Working directory path (optional)

### 4. `initialize_vault`
Initialize and configure Vault clusters.

**Operations:** init, unseal, init-and-unseal, enable-transit, check-seal-status

**Parameters:**
- `namespace`: Kubernetes namespace
- `releaseName`: Helm release name
- `operation`: Initialization operation to perform
- `unsealKeys`: Array of unseal keys (for unseal operation)
- `keyShares`: Number of key shares (default: 5)
- `keyThreshold`: Number of keys required to unseal (default: 3)

### 5. `troubleshoot_deployment`
Diagnose deployment issues.

**Check Types:** all, pods, logs, helm, route, certificates, vault-status

**Parameters:**
- `namespace`: Kubernetes namespace
- `releaseName`: Helm release name (optional)
- `checkType`: Type of diagnostic check (default: all)
- `podName`: Specific pod name for logs (optional)

### 6. `check_cluster_status`
Check overall cluster health.

**Parameters:**
- `namespace`: Kubernetes namespace (optional)
- `releaseName`: Helm release name (optional)
- `detailed`: Provide detailed information (default: false)

### 7. `manage_namespace_route`
Create or manage OpenShift namespaces and routes.

**Operations:** create, delete, check

**Parameters:**
- `operation`: Operation to perform
- `namespace`: Kubernetes namespace
- `releaseName`: Helm release name (optional)
- `route`: OpenShift route hostname (optional)
- `workingDirectory`: Working directory path (optional)

## Installation

### Prerequisites

- Node.js 18 or higher
- OpenShift CLI (`oc`) installed and configured
- Helm 3 installed
- Access to an OpenShift/Kubernetes cluster
- The vault deployment scripts in your working directory

### Install from Source

```bash
# Clone the repository
cd vault-cluster-mcp-server

# Install dependencies
npm install

# Build the TypeScript code
npm run build

# Link globally (optional)
npm link
```

### Install from npm (when published)

```bash
npm install -g vault-cluster-mcp-server
```

## Configuration

### For Claude Desktop

Add to your Claude Desktop config file:

**MacOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`  
**Windows:** `%APPDATA%/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "vault-cluster": {
      "command": "node",
      "args": [
        "/path/to/vault-cluster-mcp-server/dist/index.js"
      ],
      "cwd": "/path/to/your/vault-deployment-scripts"
    }
  }
}
```

### For Other MCP Clients

Configure your MCP client to connect to the server using stdio transport:

```bash
node /path/to/vault-cluster-mcp-server/dist/index.js
```

The `cwd` should be set to the directory containing your vault deployment scripts.

## Usage Examples

### Deploy a Complete Vault Cluster

```
Deploy a complete vault cluster using config-unsealer-vault.json and config-vault-1.json
```

The AI assistant will use the `deploy_vault_cluster` tool with appropriate parameters.

### Initialize Unsealer Vault

```
Initialize the unsealer vault in namespace vault-unsealer with release name unsealer-vault
```

The AI assistant will use the `initialize_vault` tool.

### Troubleshoot Failed Deployment

```
Troubleshoot the deployment in namespace vault-prod
```

The AI assistant will use the `troubleshoot_deployment` tool to check pods, logs, and provide remediation suggestions.

### Update Configuration

```
Update config-vault-1.json to change namespace to vault-production and set replicas to 5
```

The AI assistant will use the `manage_vault_config` tool.

## Development

### Building

```bash
npm run build
```

### Watch Mode

```bash
npm run watch
```

### Running Locally

```bash
npm run dev
```

## Project Structure

```
vault-cluster-mcp-server/
├── src/
│   ├── index.ts                 # Main server implementation
│   └── tools/
│       ├── deploy-vault-cluster.ts
│       ├── manage-config.ts
│       ├── generate-certificates.ts
│       ├── initialize-vault.ts
│       ├── troubleshoot.ts
│       ├── check-status.ts
│       └── namespace-route.ts
├── dist/                        # Compiled JavaScript (generated)
├── package.json
├── tsconfig.json
└── README.md
```

## Error Handling

All tools include comprehensive error handling and return structured error responses when operations fail. Errors include helpful messages to guide troubleshooting.

## Security Considerations

- **Unseal Keys**: The server outputs unseal keys and root tokens. Store these securely and never expose them in logs or version control.
- **Cluster Access**: Ensure the server runs with appropriate OpenShift/Kubernetes credentials.
- **Working Directory**: The server executes bash scripts from the working directory. Ensure this directory is trusted.

## Requirements

The deployment scripts must be present in the working directory:
- `setup-vault-cluster.sh`
- `generate-certificates.sh`
- `create-namespace-route.sh`
- `deploy-prerequisites.sh`
- `deploy-vault-cluster.sh`
- `deploy-post-install.sh`
- Configuration JSON files

## Troubleshooting

### Server Won't Start

- Check Node.js version: `node --version` (should be 18+)
- Verify TypeScript compilation: `npm run build`
- Check for build errors in the output

### Tools Return Errors

- Verify OpenShift CLI is installed: `oc version`
- Check cluster connectivity: `oc cluster-info`
- Ensure deployment scripts have execute permissions
- Verify working directory contains all required scripts

### Connection Issues

- Check MCP client configuration
- Verify the server path in the config
- Check the working directory is correct
- Review MCP client logs for connection errors

## License

MIT

## Contributing

Contributions are welcome! Please submit issues and pull requests on the project repository.

## Original Project

This MCP server is based on the Vault Cluster Setup Automation project. See the original bash scripts and documentation in the parent directory.

## Version History

- **1.0.0**: Initial release with 7 core tools for vault deployment automation
