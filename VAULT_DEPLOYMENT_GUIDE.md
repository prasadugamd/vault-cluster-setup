# HashiCorp Vault HA Cluster Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying two HashiCorp Vault HA clusters on OpenShift:
- **unsealer-vault**: Base cluster with Shamir seal (manual unseal) providing Transit auto-unseal service
- **vault-1**: Application cluster with Transit auto-unseal (automatic unsealing)

## Architecture
- **Storage**: Raft consensus with 3 replicas per cluster
- **High Availability**: Active-standby with automatic failover
- **TLS**: Full end-to-end encryption
- **Auto-unseal**: vault-1 uses Transit secrets engine from unsealer-vault

## Prerequisites

### Required Software
- OpenShift CLI (`oc`) - version 4.14+
- Helm 3.x
- jq (JSON processor)
- bash 4.x+

### Required Files
```
vault-cluster-setup/
├── deploy-vault-cluster.sh              # Main deployment script
├── config-unsealer-vault.json           # unsealer-vault configuration
├── config-vault-1.json                  # vault-1 configuration
├── modules/
│   └── logger.sh                        # Logging module
└── fndsec-hashicorp-vault-helm-1.6.0/
    ├── unsealer-hashicorp-vault/
    │   ├── fndsec-hashicorp-vault-helm-1.6.0.tgz  # Fixed Helm chart
    │   ├── custom-values.yaml           # Unsealer vault config
    │   └── values.openshift.yaml        # OpenShift overrides
    └── hashicorp-vault/
        ├── fndsec-hashicorp-vault-helm-1.6.0.tgz  # Fixed Helm chart
        ├── custom-values.yaml           # Vault-1 config
        └── values.openshift.yaml        # OpenShift overrides
```

### Certificate Setup
Certificates must be generated before deployment:
```bash
# Generate certificates for unsealer-vault
./generate-certificates.sh config-unsealer-vault.json

# Generate certificates for vault-1
./generate-certificates.sh config-vault-1.json
```

This creates:
- `/jenkins_home/vault-cluster-setup/unsealer-vault-certs/` - unsealer-vault certificates
- `/jenkins_home/vault-cluster-setup/vault-1-certs/` - vault-1 certificates
- TLS secrets in respective namespaces

## Part 1: unsealer-vault Deployment

### Step 1: Verify Configuration Files

**config-unsealer-vault.json**:
```json
{
  "directories": {
    "basePath": "/jenkins_home/vault-cluster-setup",
    "cluster": "fndsec-hashicorp-vault-helm-1.6.0/unsealer-hashicorp-vault"
  },
  "deployment": {
    "namespace": "unsealer-vault",
    "releaseName": "unsealer-hashicorp-vault",
    "routeUrl": "vault-unsealer-vault.apps.indelocpbmatm1059.ocpd.corp.amdocs.com",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

**custom-values.yaml key settings**:
```yaml
fullnameOverride: "vault"  # Creates pods: vault-0, vault-1, vault-2

server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        storage "raft" {
          path = "/vault/data"
          retry_join {
            leader_api_addr = "https://vault-0.vault-internal:8200"
            # ... TLS certificates ...
          }
          # ... vault-1, vault-2 retry_join blocks ...
        }
```

### Step 2: Deploy unsealer-vault Cluster

```bash
cd /jenkins_home/Vault-repo/vault-cluster-setup-vault-cluster-setup-bash
./deploy-vault-cluster.sh config-unsealer-vault.json
```

**Expected Output**:
```
========================================
VAULT CLUSTER MULTI-DEPLOYMENT
========================================
Total config files to process: 1

========================================
Processing: config-unsealer-vault.json
========================================

[2026-01-08 XX:XX:XX] [INFO] VAULT CLUSTER DEPLOYMENT - unsealer-vault
[2026-01-08 XX:XX:XX] [INFO] Cluster directory found
[2026-01-08 XX:XX:XX] [INFO] Using packaged Helm chart: fndsec-hashicorp-vault-helm-1.6.0.tgz
[2026-01-08 XX:XX:XX] [INFO] ✓ Vault cluster deployed successfully

✓ SUCCESS: config-unsealer-vault.json
```

**Deployment Time**: ~2-3 minutes

### Step 3: Verify Pod Status

```bash
oc get pods -n unsealer-vault
```

**Expected Output** (pods will be 0/1 initially - uninitialized):
```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   0/1     Running   0          2m
vault-1   0/1     Running   0          2m
vault-2   0/1     Running   0          2m
```

### Step 4: Initialize Vault

```bash
oc exec vault-0 -n unsealer-vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json | tee /tmp/vault-init-keys.json
```

**Output**: 5 unseal keys and 1 root token (SAVE SECURELY!)

**Extract Credentials**:
```bash
# View unseal keys
cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[]'

# View root token
cat /tmp/vault-init-keys.json | jq -r '.root_token'
```

**Example Output**:
```
Root Token: hvs.XXXXXXXXXXXXXXXXXXXXXXXX
Unseal Keys:
  Key 1: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Key 2: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Key 3: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Key 4: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Key 5: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### Step 5: Unseal All Vault Pods

Extract unseal keys:
```bash
KEY1=$(cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[0]')
KEY2=$(cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[1]')
KEY3=$(cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[2]')
```

**Unseal vault-0**:
```bash
oc exec vault-0 -n unsealer-vault -- vault operator unseal $KEY1
oc exec vault-0 -n unsealer-vault -- vault operator unseal $KEY2
oc exec vault-0 -n unsealer-vault -- vault operator unseal $KEY3
```

**Unseal vault-1**:
```bash
oc exec vault-1 -n unsealer-vault -- vault operator unseal $KEY1
oc exec vault-1 -n unsealer-vault -- vault operator unseal $KEY2
oc exec vault-1 -n unsealer-vault -- vault operator unseal $KEY3
```

**Unseal vault-2**:
```bash
oc exec vault-2 -n unsealer-vault -- vault operator unseal $KEY1
oc exec vault-2 -n unsealer-vault -- vault operator unseal $KEY2
oc exec vault-2 -n unsealer-vault -- vault operator unseal $KEY3
```

### Step 6: Verify unsealer-vault is Ready

```bash
oc get pods -n unsealer-vault
```

**Expected Output** (all pods 1/1):
```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   1/1     Running   0          5m
vault-1   1/1     Running   0          5m
vault-2   1/1     Running   0          5m
```

**Check Vault Status**:
```bash
oc exec vault-0 -n unsealer-vault -- vault status
```

**Expected Output**:
```
Seal Type               shamir
Initialized             true
Sealed                  false
HA Enabled              true
HA Mode                 active
```

### Step 7: Verify Raft Cluster

```bash
ROOT_TOKEN=$(cat /tmp/vault-init-keys.json | jq -r '.root_token')
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN vault operator raft list-peers
```

**Expected Output**:
```
Node       Address                        State       Voter
----       -------                        -----       -----
vault-0    vault-0.vault-internal:8201    leader      true
vault-1    vault-1.vault-internal:8201    follower    true
vault-2    vault-2.vault-internal:8201    follower    true
```

### Step 8: Enable Transit Secrets Engine (for vault-1 auto-unseal)

```bash
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN vault secrets enable transit
```

**Create Transit Key**:
```bash
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN vault write -f transit/keys/autounseal_1
```

### Step 9: Create Auto-unseal Policy

```bash
cat > /tmp/autounseal-policy.hcl << 'EOF'
path "transit/encrypt/autounseal_1" {
  capabilities = [ "update" ]
}

path "transit/decrypt/autounseal_1" {
  capabilities = [ "update" ]
}

path "transit/keys/autounseal_1" {
  capabilities = [ "read" ]
}
EOF

cat /tmp/autounseal-policy.hcl | oc exec -i vault-0 -n unsealer-vault -- \
  env VAULT_TOKEN=$ROOT_TOKEN vault policy write autounseal -
```

### Step 10: Create Transit Token for vault-1

```bash
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN \
  vault token create -policy=autounseal -orphan -format=json | \
  tee /tmp/vault1-autounseal-token.json
```

**Extract and Create Kubernetes Secret**:
```bash
TRANSIT_TOKEN=$(cat /tmp/vault1-autounseal-token.json | jq -r '.auth.client_token')

oc create secret generic vault-transit-token-secret \
  --from-literal=token=$TRANSIT_TOKEN \
  -n vault-1
```

### Step 11: Enable KV Secrets Engine (Optional)

```bash
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN \
  vault secrets enable -path=secret kv-v2
```

**Test Secret Storage**:
```bash
# Write secret
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN \
  vault kv put secret/test message="unsealer-vault is working!"

# Read secret
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=$ROOT_TOKEN \
  vault kv get secret/test
```

---

## Part 2: vault-1 Deployment (Auto-unseal)

### Step 1: Verify Configuration Files

**config-vault-1.json**:
```json
{
  "directories": {
    "basePath": "/jenkins_home/vault-cluster-setup",
    "cluster": "fndsec-hashicorp-vault-helm-1.6.0/hashicorp-vault"
  },
  "deployment": {
    "namespace": "vault-1",
    "releaseName": "hashicorp-vault",
    "routeUrl": "vault-vault-1.apps.indelocpbmatm1059.ocpd.corp.amdocs.com",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

**custom-values.yaml key settings**:
```yaml
fullnameOverride: "vault"
sealType: transit
unsealerVaultNamespace: unsealer-vault

server:
  ha:
    raft:
      enabled: true
      config: |
        seal "transit" {
          address = "https://vault-unsealer-vault.apps.indelocpbmatm1059.ocpd.corp.amdocs.com"
          key_name = "autounseal_1"
          mount_path = "transit/"
          tls_ca_cert = "/vault/userconfig/vault-server-tls/vault.ca"
          # ... TLS configuration ...
        }
        storage "raft" {
          path = "/vault/data"
          retry_join {
            leader_api_addr = "https://vault-0.vault-internal.vault-1.svc.cluster.local:8200"
            # ... TLS certificates ...
          }
          # ... vault-1, vault-2 retry_join blocks ...
        }
  
  extraSecretEnvironmentVars:
    - envName: VAULT_TOKEN
      secretName: vault-transit-token-secret
      secretKey: token
```

### Step 2: Verify Prerequisites

**Check Transit Token Secret**:
```bash
oc get secret vault-transit-token-secret -n vault-1
```

**Check TLS Certificates**:
```bash
oc get secret vault-server-tls -n vault-1
ls -la /jenkins_home/vault-cluster-setup/vault-1-certs/
```

### Step 3: Deploy vault-1 Cluster

```bash
cd /jenkins_home/Vault-repo/vault-cluster-setup-vault-cluster-setup-bash
./deploy-vault-cluster.sh config-vault-1.json
```

**Expected Output**:
```
========================================
VAULT CLUSTER MULTI-DEPLOYMENT
========================================
Total config files to process: 1

========================================
Processing: config-vault-1.json
========================================

[2026-01-08 XX:XX:XX] [INFO] VAULT CLUSTER DEPLOYMENT - vault-1
[2026-01-08 XX:XX:XX] [INFO] Using packaged Helm chart: fndsec-hashicorp-vault-helm-1.6.0.tgz
[2026-01-08 XX:XX:XX] [INFO] ✓ Vault cluster deployed successfully

✓ SUCCESS: config-vault-1.json
```

**Deployment Time**: ~2-3 minutes

### Step 4: Verify Pod Status

```bash
oc get pods -n vault-1
```

**Expected Output** (pods should be Running with 0/1 - uninitialized):
```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   0/1     Running   0          2m
vault-1   0/1     Running   0          2m
vault-2   0/1     Running   0          2m
```

**Check Pod Logs** (should show "Vault is sealed" - transit working):
```bash
oc logs vault-0 -n vault-1 --tail=10
```

### Step 5: Initialize vault-1 (with Recovery Keys)

Since vault-1 uses auto-unseal, it requires **recovery keys** instead of unseal keys:

```bash
oc exec vault-0 -n vault-1 -- vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json | tee /tmp/vault1-init-keys.json
```

**Output**: 5 recovery keys and 1 root token (SAVE SECURELY!)

**Extract Credentials**:
```bash
# View recovery keys
cat /tmp/vault1-init-keys.json | jq -r '.recovery_keys_b64[]'

# View root token
cat /tmp/vault1-init-keys.json | jq -r '.root_token'
```

### Step 6: Verify vault-1 Auto-unseals

After initialization, vault-1 pods should **automatically unseal** and become ready:

```bash
oc get pods -n vault-1
```

**Expected Output** (all pods 1/1 - auto-unsealed!):
```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   1/1     Running   0          4m
vault-1   1/1     Running   0          4m
vault-2   1/1     Running   0          4m
```

**Check Vault Status**:
```bash
oc exec vault-0 -n vault-1 -- vault status
```

**Expected Output**:
```
Seal Type              transit
Recovery Seal Type     shamir
Initialized            true
Sealed                 false
HA Enabled             true
HA Mode                active
```

### Step 7: Verify Raft Cluster

```bash
VAULT1_TOKEN=$(cat /tmp/vault1-init-keys.json | jq -r '.root_token')
oc exec vault-0 -n vault-1 -- env VAULT_TOKEN=$VAULT1_TOKEN vault operator raft list-peers
```

**Expected Output**:
```
Node                                    Address                        State       Voter
----                                    -------                        -----       -----
e57d8dea-8897-02c1-ce7d-3b2a7ba45cb1    vault-0.vault-internal:8201    leader      true
e51fad05-608f-f700-60e2-8c5136dbcdb7    vault-2.vault-internal:8201    follower    true
881ced3e-9bd2-71f5-16cb-509a63a8e210    vault-1.vault-internal:8201    follower    true
```

### Step 8: Enable KV Secrets Engine (Optional)

```bash
oc exec vault-0 -n vault-1 -- env VAULT_TOKEN=$VAULT1_TOKEN \
  vault secrets enable -path=secret kv-v2
```

**Test Secret Storage**:
```bash
# Write secret
oc exec vault-0 -n vault-1 -- env VAULT_TOKEN=$VAULT1_TOKEN \
  vault kv put secret/test-vault1 message="vault-1 auto-unseal working!" cluster="vault-1"

# Read secret
oc exec vault-0 -n vault-1 -- env VAULT_TOKEN=$VAULT1_TOKEN \
  vault kv get secret/test-vault1
```

---

## Validation & Testing

### Complete Validation Script

```bash
#!/bin/bash

echo "=========================================="
echo "VAULT CLUSTER VALIDATION"
echo "=========================================="

# unsealer-vault validation
echo ""
echo "=== UNSEALER-VAULT CLUSTER ==="
oc get pods -n unsealer-vault
oc exec vault-0 -n unsealer-vault -- vault status
oc get route -n unsealer-vault

# vault-1 validation
echo ""
echo "=== VAULT-1 CLUSTER ==="
oc get pods -n vault-1
oc exec vault-0 -n vault-1 -- vault status
oc get route -n vault-1

echo ""
echo "✅ Validation Complete!"
```

### Expected Final State

**unsealer-vault**:
- ✅ 3 pods Running (1/1 each)
- ✅ Seal Type: Shamir (manual unseal)
- ✅ HA Mode: Active
- ✅ Transit engine enabled
- ✅ Route: https://vault-unsealer-vault.apps.indelocpbmatm1059.ocpd.corp.amdocs.com

**vault-1**:
- ✅ 3 pods Running (1/1 each)
- ✅ Seal Type: Transit (auto-unseal)
- ✅ HA Mode: Active
- ✅ Auto-unseals on restart
- ✅ Route: https://vault-vault-1.apps.indelocpbmatm1059.ocpd.corp.amdocs.com

---

## Multi-Cluster Deployment

You can deploy both clusters in one command:

```bash
./deploy-vault-cluster.sh config-unsealer-vault.json config-vault-1.json
```

**Note**: This only deploys the infrastructure. You still need to:
1. Initialize and unseal unsealer-vault (Steps 4-7 in Part 1)
2. Configure Transit auto-unseal (Steps 8-10 in Part 1)
3. Initialize vault-1 (Step 5 in Part 2)

---

## Troubleshooting

### Common Issues

#### Issue: Pods stuck in 0/1 Running
**Cause**: Vault not initialized or sealed

**Solution**: 
```bash
# Check if initialized
oc exec vault-0 -n <namespace> -- vault status

# If "Initialized: false" - run init
oc exec vault-0 -n <namespace> -- vault operator init ...

# If "Sealed: true" - unseal
oc exec vault-0 -n <namespace> -- vault operator unseal <key>
```

#### Issue: vault-1 pods CrashLoopBackOff
**Cause**: Transit token missing or invalid permissions

**Solution**:
```bash
# Check secret exists
oc get secret vault-transit-token-secret -n vault-1

# Verify policy on unsealer-vault
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=<root_token> \
  vault policy read autounseal

# Recreate token if needed
oc exec vault-0 -n unsealer-vault -- env VAULT_TOKEN=<root_token> \
  vault token create -policy=autounseal -orphan -format=json
```

#### Issue: "no such host" DNS errors
**Cause**: Service names don't match configuration

**Solution**: Verify `fullnameOverride: "vault"` in custom-values.yaml creates correct service names:
```bash
oc get svc -n <namespace>
# Should see: vault, vault-internal, vault-active, vault-standby
```

#### Issue: Empty ConfigMap
**Cause**: Helm chart template bug (vault.config helper)

**Solution**: Ensure using the FIXED chart (42619 bytes):
```bash
ls -lh fndsec-hashicorp-vault-helm-1.6.0.tgz
# Should be 42619 bytes (not 43049)
```

The fixed chart includes the template patch:
```
Line 1106 in templates/_helpers.tpl:
{{- tpl $config . | nindent 4 | trim}}
```

---

## Important Credentials

### Save These Securely!

**unsealer-vault**:
```bash
# Root Token
cat /tmp/vault-init-keys.json | jq -r '.root_token'

# Unseal Keys (5 keys, need 3 to unseal)
cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[]'
```

**vault-1**:
```bash
# Root Token
cat /tmp/vault1-init-keys.json | jq -r '.root_token'

# Recovery Keys (5 keys, for disaster recovery)
cat /tmp/vault1-init-keys.json | jq -r '.recovery_keys_b64[]'
```

**⚠️ CRITICAL**: Store these credentials in a secure vault or secrets manager. They cannot be recovered if lost!

---

## Post-Deployment Tasks

### 1. Configure Authentication Methods
```bash
# Enable LDAP/AD
vault auth enable ldap

# Enable Kubernetes
vault auth enable kubernetes
```

### 2. Create Policies
```bash
# Application policy
vault policy write app-policy - <<EOF
path "secret/data/app/*" {
  capabilities = ["read"]
}
EOF
```

### 3. Enable Audit Logging
```bash
vault audit enable file file_path=/vault/audit/vault_audit.log
```

### 4. Configure Monitoring
- Enable Prometheus telemetry
- Set up ServiceMonitor
- Configure alerting

---

## Maintenance

### Restarting Pods

**unsealer-vault** (requires manual unseal):
```bash
oc delete pod vault-0 -n unsealer-vault
# Wait for pod to start
oc exec vault-0 -n unsealer-vault -- vault operator unseal <key1>
oc exec vault-0 -n unsealer-vault -- vault operator unseal <key2>
oc exec vault-0 -n unsealer-vault -- vault operator unseal <key3>
```

**vault-1** (auto-unseals):
```bash
oc delete pod vault-0 -n vault-1
# Pod automatically unseals on restart!
```

### Upgrading Vault

```bash
# Update image tag in custom-values.yaml
vim custom-values.yaml
# Change: tag: "1.17.2-ubi" to tag: "1.18.0-ubi"

# Apply upgrade
helm upgrade <release-name> <chart> -n <namespace> -f custom-values.yaml
```

---

## Appendix: Configuration Reference

### Script Options

**deploy-vault-cluster.sh**:
- Supports multiple config files
- Automatic chart detection (.tgz or unpacked)
- Route URL override
- Configurable timeout
- Detailed logging

**Configuration JSON**:
```json
{
  "directories": {
    "basePath": "<base-path>",
    "cluster": "<helm-chart-directory>"
  },
  "deployment": {
    "namespace": "<k8s-namespace>",
    "releaseName": "<helm-release-name>",
    "routeUrl": "<openshift-route-url>",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

### Key Helm Values

**Common Settings**:
- `fullnameOverride`: Override pod naming
- `server.ha.enabled`: Enable HA mode
- `server.ha.replicas`: Number of replicas
- `server.ha.raft.enabled`: Enable Raft storage
- `server.dataStorage.size`: Data volume size
- `server.auditStorage.size`: Audit volume size

**unsealer-vault Specific**:
- Raft storage with manual unseal
- Transit secrets engine

**vault-1 Specific**:
- Transit seal configuration
- Transit token secret reference
- Unsealer vault route

---

## Support & Resources

### Log Files
- Deployment logs: `logs/vault_setup_<timestamp>.log`
- Pod logs: `oc logs <pod-name> -n <namespace>`
- Audit logs: `/vault/audit/vault_audit.log` (inside pod)

### Useful Commands
```bash
# View all Vault resources
oc get all -n <namespace> -l app.kubernetes.io/name=vault

# Check Helm release
helm list -n <namespace>

# View Helm values
helm get values <release-name> -n <namespace>

# Describe pod issues
oc describe pod <pod-name> -n <namespace>
```

### Documentation
- HashiCorp Vault: https://www.vaultproject.io/docs
- Raft Storage: https://www.vaultproject.io/docs/configuration/storage/raft
- Auto-unseal: https://www.vaultproject.io/docs/concepts/seal#auto-unseal

---

## Summary

This guide provides complete procedures for deploying two production-ready Vault HA clusters:

1. **unsealer-vault**: Foundation cluster providing Transit auto-unseal service
2. **vault-1**: Application cluster with automatic unsealing

Both clusters feature:
- ✅ High Availability (3 replicas)
- ✅ Raft consensus storage
- ✅ TLS encryption
- ✅ OpenShift integration
- ✅ Production-ready configuration

**Total Deployment Time**: ~15-20 minutes for both clusters
