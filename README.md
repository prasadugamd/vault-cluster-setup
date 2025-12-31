# Vault Cluster Setup Automation

Complete automation solution for deploying HashiCorp Vault cluster on remote Kubernetes infrastructure.

## Overview

This project automates the deployment of HashiCorp Vault cluster on remote machine `jenkins@ilceatm137` with the following components:
- Prerequisites setup (hashicorp-vault-helm-pre-requisite)
- Vault cluster deployment (HashiCorp-Vault-Cluster)
- Post-installation configuration (hashicorp-vault-post-install-helm-1.1.6)

## Prerequisites

- PowerShell 5.1 or later
- SSH access to remote machine (jenkins@ilceatm137)
- Remote machine must have:
  - kubectl configured
  - Helm 3.x installed
  - Access to Kubernetes cluster

## Project Structure

```
vault-cluster-setup/
├── config.json                      # Configuration file
├── setup-vault-cluster.ps1          # Main orchestration script
├── Deploy-Prerequisites.ps1         # Prerequisites deployment
├── Deploy-VaultCluster.ps1          # Vault cluster deployment
├── Deploy-PostInstall.ps1           # Post-installation tasks
├── modules/
│   ├── SSHConnection.psm1          # SSH connection management
│   └── Logger.psm1                 # Logging utilities
└── logs/                           # Deployment logs (auto-created)
```

## Configuration

Edit `config.json` to customize deployment:

```json
{
  "remote": {
    "host": "ilceatm137",
    "username": "jenkins",
    "password": "Unix11!",
    "basePath": "/jenkins/jenkins/PRASA"
  },
  "deployment": {
    "namespace": "vault",
    "releaseName": "vault",
    "helmTimeout": "10m"
  }
}
```

## Usage

### Complete Setup

Run the full deployment with all steps:

```powershell
.\setup-vault-cluster.ps1
```

### Test Connection

Test SSH connectivity before deployment:

```powershell
.\setup-vault-cluster.ps1 -TestConnection
```

### Selective Deployment

Skip specific steps:

```powershell
# Skip prerequisites
.\setup-vault-cluster.ps1 -SkipPrerequisites

# Skip cluster deployment
.\setup-vault-cluster.ps1 -SkipClusterDeploy

# Skip post-installation
.\setup-vault-cluster.ps1 -SkipPostInstall
```

### Individual Steps

Run deployment steps independently:

```powershell
# Prerequisites only
.\Deploy-Prerequisites.ps1

# Vault cluster only
.\Deploy-VaultCluster.ps1

# Post-install only
.\Deploy-PostInstall.ps1
```

## Deployment Steps

### 1. Prerequisites Deployment
- Installs required Kubernetes resources
- Sets up secrets and ConfigMaps
- Configures storage classes
- Deploys supporting services

### 2. Vault Cluster Deployment
- Deploys Vault StatefulSet
- Configures TLS certificates
- Sets up Vault services
- Configures high availability

### 3. Post-Installation
- Applies additional configurations
- Sets up monitoring and alerts
- Configures backup jobs
- Validates deployment

## Remote Directories

The automation works with these directories on jenkins@ilceatm137:

```
/jenkins/jenkins/PRASA/
├── hashicorp-vault-helm-pre-requisite/
├── HashiCorp-Vault-Cluster/
└── hashicorp-vault-post-install-helm-1.1.6/
```

## Certificate Management

The scripts automatically:
- Detect certificates in the cluster directory
- Create Kubernetes TLS secrets
- Configure Vault to use certificates
- Support both PEM and CRT formats

## Logging

All deployment activities are logged to:
- Console output (color-coded)
- Log files in `logs/` directory
- Format: `vault_setup_YYYYMMDD_HHmmss.log`

Log levels: DEBUG, INFO, WARN, ERROR

## Post-Deployment

After successful deployment:

1. **Initialize Vault**
   ```bash
   kubectl exec -n vault vault-0 -- vault operator init
   ```
   Save the unseal keys and root token securely!

2. **Unseal Vault**
   ```bash
   kubectl exec -n vault vault-0 -- vault operator unseal <key1>
   kubectl exec -n vault vault-0 -- vault operator unseal <key2>
   kubectl exec -n vault vault-0 -- vault operator unseal <key3>
   ```

3. **Check Status**
   ```bash
   kubectl exec -n vault vault-0 -- vault status
   ```

4. **Access Vault UI**
   ```bash
   kubectl port-forward -n vault svc/vault 8200:8200
   ```
   Then open: https://localhost:8200

## Troubleshooting

### SSH Connection Issues
```powershell
# Test connectivity
.\setup-vault-cluster.ps1 -TestConnection

# Check SSH service on remote
ssh jenkins@ilceatm137 "systemctl status sshd"
```

### Helm Deployment Failures
```bash
# Check Helm releases
helm list -n vault

# Get pod logs
kubectl logs -n vault <pod-name>

# Describe pod for events
kubectl describe pod -n vault <pod-name>
```

### Certificate Issues
```bash
# Verify TLS secrets
kubectl get secrets -n vault

# Check certificate validity
kubectl get secret vault-tls -n vault -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text
```

## Security Notes

- Store `config.json` securely (contains credentials)
- Use SSH key authentication instead of passwords when possible
- Rotate passwords regularly
- Store Vault unseal keys in secure location
- Never commit credentials to version control

## Support

For issues or questions:
1. Check log files in `logs/` directory
2. Review deployment output
3. Verify remote machine accessibility
4. Check Kubernetes cluster health

## License

Internal use only - HashiCorp Vault Cluster Setup
