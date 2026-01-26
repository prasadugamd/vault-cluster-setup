# Vault Cluster Setup Automation - Bash Version

Complete Bash automation solution for deploying HashiCorp Vault cluster on Kubernetes/OpenShift.

## 🤖 NEW: AI-Powered Deployment Agent

**Automate your Vault deployments with natural language commands!**

This project now includes an intelligent deployment agent that understands natural language and can execute complex deployment workflows. Simply use:

```
@vault-deployment-agent Deploy complete vault cluster
@vault-deployment-agent Troubleshoot the failed deployment
@vault-deployment-agent Generate certificates for vault-1
```

📖 **Quick Start with Agent**: See [AGENT_USAGE_GUIDE.md](./AGENT_USAGE_GUIDE.md) and [AGENT_QUICK_REFERENCE.md](./AGENT_QUICK_REFERENCE.md)

---

## Overview

This project provides native Bash scripts for deploying HashiCorp Vault cluster directly on Linux/OpenShift environments. The scripts run natively without SSH overhead, making deployment faster and more reliable.

**Components deployed:**
- Prerequisites setup (hashicorp-vault-helm-pre-requisite)
- Vault cluster deployment (HashiCorp-Vault-Cluster)
- Post-installation configuration (hashicorp-vault-post-install-helm-1.1.6)
- OpenShift Route for external access

## Prerequisites

- Bash 4.0 or later
- kubectl or oc CLI configured with cluster access
- Helm 3.x installed
- jq (JSON processor)
- openssl (for certificate generation)
- Access to target Kubernetes/OpenShift cluster

## Project Structure

```
vault-cluster-setup/
├── .github/
│   └── agents/
│       └── vault-deployment-agent.yaml  # AI agent configuration
├── AGENT_USAGE_GUIDE.md             # Comprehensive agent guide
├── AGENT_QUICK_REFERENCE.md         # Quick command reference
├── config.json                      # Configuration file (Bash version - no SSH config)
├── setup-vault-cluster.sh           # Main orchestration script
├── generate-certificates.sh         # TLS certificate generation
├── deploy-prerequisites.sh          # Prerequisites deployment
├── deploy-vault-cluster.sh          # Vault cluster deployment
├── deploy-post-install.sh           # Post-installation tasks
├── modules/
│   └── logger.sh                    # Logging utilities
├── logs/                            # Deployment logs (auto-created)
└── vault-route-template.yaml       # OpenShift Route template

# Legacy PowerShell scripts (for Windows-based remote execution)
├── *.ps1                            # PowerShell versions
└── modules/*.psm1                   # PowerShell modules
```

## Configuration

Edit `config.json` to customize deployment:

```json
{
  "directories": {
    "basePath": "/jenkins/jenkins/PRASA",
    "prerequisite": "hashicorp-vault-helm-pre-requisite",
    "cluster": "HashiCorp-Vault-Cluster",
    "postInstall": "hashicorp-vault-post-install-helm-1.1.6"
  },
  "deployment": {
    "namespace": "vault",
    "releaseName": "vault",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

**Note:** The Bash version does NOT require SSH configuration since scripts run natively on the target server.

## Installation

1. **Copy scripts to target server** (e.g., jenkins@ilceatm137):
   ```bash
   scp -r vault-cluster-setup/ jenkins@ilceatm137:/jenkins/jenkins/PRASA/
   ```

2. **Make scripts executable**:
   ```bash
   chmod +x *.sh modules/*.sh
   ```

3. **Verify prerequisites**:
   ```bash
   ./setup-vault-cluster.sh --test-connection
   ```

## Usage

### Using the AI Deployment Agent (Recommended)

The easiest way to deploy and manage Vault clusters is using the AI agent:

```
# Deploy complete cluster
@vault-deployment-agent Deploy complete vault cluster

# Deploy individual vault
@vault-deployment-agent Deploy unsealer vault

# Troubleshoot issues
@vault-deployment-agent Troubleshoot the failed deployment in vault-1

# Manage configurations
@vault-deployment-agent Create config for vault-2 namespace

# Verify status
@vault-deployment-agent Verify all pods are running in unsealer-vault
```

For comprehensive agent documentation, see:
- [AGENT_USAGE_GUIDE.md](./AGENT_USAGE_GUIDE.md) - Complete usage guide with examples
- [AGENT_QUICK_REFERENCE.md](./AGENT_QUICK_REFERENCE.md) - Quick command reference

### Manual Script Usage

You can also run the scripts manually:

#### Complete Setup

Run the full deployment with all steps:

```bash
./setup-vault-cluster.sh
```

#### Test Connection

Test Kubernetes cluster connectivity:

```bash
./setup-vault-cluster.sh --test-connection
```

### Selective Deployment

Skip specific steps using command-line options:

```bash
# Skip certificate generation (use existing certificates)
./setup-vault-cluster.sh --skip-certs

# Skip prerequisites
./setup-vault-cluster.sh --skip-prereq

# Skip cluster deployment
./setup-vault-cluster.sh --skip-deploy

# Skip post-installation
./setup-vault-cluster.sh --skip-postinstall

# Use custom config file
./setup-vault-cluster.sh --config custom-config.json
```

**Or use the agent**:
```
@vault-deployment-agent Deploy vault-1 but skip certificates
```

### Individual Steps

Run deployment steps independently:

```bash
# Generate certificates only
./generate-certificates.sh [config.json]

# Prerequisites only
./deploy-prerequisites.sh [config.json]

# Vault cluster only
./deploy-vault-cluster.sh [config.json]

# Post-install only
./deploy-post-install.sh [config.json]
```

## Deployment Steps

### 0. TLS Certificate Generation
- Generates CA certificate and private key (4096-bit RSA)
- Creates server certificates with proper SANs for Kubernetes
- Includes all Vault service DNS names
- Creates Kubernetes TLS secrets automatically
- Copies certificates to cluster directory
- Validity: 10 years

### 1. Prerequisites Deployment
- Creates namespace
- **Creates OpenShift Route** for external access (passthrough TLS)
- Installs required Kubernetes resources via Helm
- Sets up secrets and ConfigMaps
- Configures storage classes
- Deploys supporting services

### 2. Vault Cluster Deployment
- Deploys Vault StatefulSet via Helm
- Configures TLS certificates
- Sets up Vault services (vault-active, vault-internal)
- Configures high availability

### 3. Post-Installation
- Applies additional configurations via Helm/scripts
- Verifies OpenShift Route and displays access URL
- Sets up monitoring and alerts
- Configures backup jobs
- Validates deployment

## Certificate Management

**Automatic TLS Certificate Generation**

The script automatically generates production-ready TLS certificates:

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

**Generated files location:**
- `/jenkins/jenkins/PRASA/vault-certs/ca.crt` - CA certificate
- `/jenkins/jenkins/PRASA/vault-certs/vault.crt` - Server certificate
- `/jenkins/jenkins/PRASA/vault-certs/vault.key` - Private key

## OpenShift Route Configuration

**Automatic OpenShift Route Creation**

The prerequisites script automatically creates an OpenShift Route for external Vault access:

**Deployment Order:**
1. ✅ Generate TLS certificates
2. ✅ Create namespace
3. ✅ **Create OpenShift Route** ← Created during prerequisites phase
4. ✅ Install prerequisites (Helm charts)
5. ✅ Deploy Vault cluster
6. ✅ Verify route and display access URL

**Route Specifications:**
- **Service Target:** `vault-active` (active Vault node)
- **Port:** 8200 (HTTPS)
- **TLS Mode:** Passthrough (Vault handles TLS)
- **Insecure Traffic:** Disabled

**Accessing Vault via Route:**
```bash
# Get the route URL
oc get route vault -n vault -o jsonpath='{.spec.host}'

# Or describe for full details
oc describe route vault -n vault

# Access Vault UI/API
VAULT_ADDR=$(oc get route vault -n vault -o jsonpath='https://{.spec.host}')
curl -k $VAULT_ADDR/v1/sys/health
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

## Logging

All deployment activities are logged to:
- Console output (color-coded for easy reading)
- Log files in `logs/` directory
- Format: `vault_setup_YYYYMMDD_HHmmss.log`

Log levels: DEBUG, INFO, WARN, ERROR

## Post-Deployment

After successful deployment:

1. **Initialize Vault**
   ```bash
   kubectl exec -n vault vault-0 -- vault operator init
   ```
   ⚠️ **Save the unseal keys and root token securely!**

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
   VAULT_URL=$(kubectl get route vault -n vault -o jsonpath='https://{.spec.host}')
   echo "Vault UI: $VAULT_URL"
   
   # Or via port-forward
   kubectl port-forward -n vault svc/vault 8200:8200
   ```
   Then open: https://localhost:8200

## Troubleshooting

### Kubernetes Connectivity Issues
```bash
# Test connectivity
./setup-vault-cluster.sh --test-connection

# Check cluster info
kubectl cluster-info
oc cluster-info
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

# Regenerate certificates
./generate-certificates.sh
```

### Script Permissions
```bash
# If you get "Permission denied"
chmod +x *.sh modules/*.sh
```

## Comparison: Bash vs PowerShell Versions

| Feature | Bash Version | PowerShell Version |
|---------|-------------|-------------------|
| **Execution** | Native on Linux | Remote via SSH |
| **Performance** | Faster (direct) | Slower (SSH overhead) |
| **Dependencies** | kubectl, helm, jq, openssl | PowerShell, SSH, modules |
| **Use Case** | Run on target server | Run from Windows workstation |
| **Complexity** | Simpler | More complex (SSH layer) |
| **Debugging** | Direct error messages | SSH abstraction layer |
| **Best For** | Production automation | Windows development environment |

## Security Notes

- Store `config.json` securely (contains sensitive paths)
- Use RBAC to limit script execution permissions
- Store Vault unseal keys in secure location (e.g., password manager)
- Never commit credentials or unseal keys to version control
- Regularly rotate certificates and credentials
- Limit access to log files containing sensitive information

## Support

For issues or questions:
1. Check log files in `logs/` directory
2. Review deployment output for error messages
3. Verify Kubernetes cluster health: `kubectl get nodes`
4. Check pod status: `kubectl get pods -n vault`
5. Review Helm releases: `helm list -n vault`

## License

Internal use only - HashiCorp Vault Cluster Setup Automation
