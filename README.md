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
# Skip certificate generation (use existing certificates)
.\setup-vault-cluster.ps1 -SkipCertificates

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
# Generate certificates only
.\Generate-Certificates.ps1

# Prerequisites only
.\Deploy-Prerequisites.ps1

# Vault cluster only
.\Deploy-VaultCluster.ps1

# Post-install only
.\Deploy-PostInstall.ps1
```

## Deployment Steps

### 0. TLS Certificate Generation (NEW!)
- Generates CA certificate and private key
- Creates server certificates with proper SANs
- Includes all Vault service DNS names
- Creates Kubernetes TLS secrets automatically
- Copies certificates to cluster directory
- Validity: 10 years

### 1. Prerequisites Deployment
- Creates namespace
- **Creates OpenShift Route** for external access (passthrough TLS)
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
- Verifies OpenShift Route and displays access URL
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

**NEW: Automatic TLS Certificate Generation!**

The script now automatically generates TLS certificates:
- ✅ **Generates CA certificate** (4096-bit RSA)
- ✅ **Creates server certificates** with proper SANs for Kubernetes
- ✅ **Includes all service DNS names** (vault, vault-0, vault-1, vault-2, etc.)
- ✅ **Creates Kubernetes TLS secret** in vault namespace
- ✅ **Copies to cluster directory** automatically
- ✅ **10-year validity** period

**Certificate SANs include:**
- `vault`, `vault.vault`, `vault.vault.svc.cluster.local`
- `vault-0.vault-internal.vault.svc.cluster.local`
- `vault-1.vault-internal.vault.svc.cluster.local`
- `vault-2.vault-internal.vault.svc.cluster.local`
- `localhost`, `127.0.0.1`

**Generated files:**
- `/jenkins/jenkins/PRASA/vault-certs/ca.crt` - CA certificate
- `/jenkins/jenkins/PRASA/vault-certs/vault.crt` - Server certificate
- `/jenkins/jenkins/PRASA/vault-certs/vault.key` - Private key

**To use existing certificates instead:**
```powershell
.\setup-vault-cluster.ps1 -SkipCertificates
```

## OpenShift Route Configuration

**Automatic OpenShift Route Creation!**

The prerequisites script now automatically creates an OpenShift Route for external Vault access **before** deploying the cluster:

**Deployment Order:**
1. ✅ Generate TLS certificates
2. ✅ Create namespace
3. ✅ **Create OpenShift Route** ← Created during prerequisites phase
4. ✅ Install prerequisites (Helm charts)
5. ✅ Deploy Vault cluster
6. ✅ Verify route and display access URL

- ✅ **Creates Route early** - before Vault cluster deployment
- ✅ **Passthrough TLS** termination (Vault handles TLS)
- ✅ **Auto-generated hostname** by OpenShift router
- ✅ **Secure HTTPS only** (no HTTP redirect)
- ✅ **Service Target:** `vault-active` (will be available after cluster deployment)

**Route Specifications:**
- **Service Target:** `vault-active` (active Vault node)
- **Port:** 8200 (HTTPS)
- **TLS Mode:** Passthrough
- **Insecure Traffic:** Disabled

**Accessing Vault via Route:**
```bash
# Get the route URL
oc get route vault -n vault -o jsonpath='{.spec.host}'

# Or describe for full details
oc describe route vault -n vault

# Access Vault UI/API
curl -k https://<route-hostname>/v1/sys/health
```

**Manual Route Creation (if needed):**
```bash
# Using template file
kubectl apply -f vault-route-template.yaml

# Or create directly
oc create route passthrough vault \
  --service=vault-active \
  --port=8200 \
  --namespace=vault
```

**Custom Hostname (optional):**
Edit [vault-route-template.yaml](vault-route-template.yaml) and uncomment the `host` field:
```yaml
spec:
  host: vault.your-custom-domain.com
```

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
   # Via OpenShift Route (automatically created)
   # Get the route URL
   kubectl get route vault -n vault -o jsonpath='{.spec.host}'
   # Access: https://<route-host>
   
   # Or via port-forward
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
