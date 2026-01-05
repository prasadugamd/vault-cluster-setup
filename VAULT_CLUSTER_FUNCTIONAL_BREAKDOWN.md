# HashiCorp Vault Cluster - Functional Breakdown

**Author:** Prasadu Gamini  
**Date:** January 5, 2026  
**Version:** 1.0  
**Environment:** OpenShift/Kubernetes

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites Component](#1-hashicorp-vault-helm-pre-requisite)
3. [Vault Cluster Component](#2-hashicorp-vault-cluster)
4. [Post-Install Component](#3-hashicorp-vault-post-install-helm)
5. [Deployment Architecture](#deployment-architecture)
6. [Configuration Reference](#configuration-reference)

---

## Overview

This document provides a comprehensive functional breakdown of the HashiCorp Vault deployment on OpenShift/Kubernetes, consisting of three primary Helm chart components that work together to establish a highly available, secure secrets management platform.

The deployment follows a multi-stage approach:
- **Stage 1:** Cluster-level prerequisites and RBAC setup
- **Stage 2:** Unsealer Vault cluster (transit engine for auto-unsealing)
- **Stage 3:** Main Vault cluster (secrets storage)
- **Stage 4:** Post-installation configuration and automation

---

## 1. hashicorp-vault-helm-pre-requisite

**Version:** 1.3.0  
**Chart Type:** Cluster-scoped prerequisites  
**Deployment Scope:** Once per cluster (not namespace-specific)

### Purpose

Establishes cluster-level prerequisites and RBAC (Role-Based Access Control) setup required for Vault operations across all namespaces.

### Key Components

#### 1.1 CSI ClusterRole & ClusterRoleBinding
- **Function:** Enables Vault CSI (Container Storage Interface) driver
- **Purpose:** Allows secrets to be mounted as volumes in application pods
- **Scope:** Cluster-wide secret access pattern

#### 1.2 Injector ClusterRole & ClusterRoleBinding
- **Function:** Grants permissions for Vault agent injection
- **Purpose:** Enables automatic sidecar injection for secret retrieval
- **Pattern:** Mutation webhook-based injection

#### 1.3 Injector MutatingWebhook
- **Function:** Intercepts pod creation requests
- **Purpose:** Automatically injects Vault agent sidecars into annotated pods
- **Trigger:** Pod creation events with Vault annotations

#### 1.4 Server ClusterRoleBinding
- **Function:** Grants Vault server cluster-wide permissions
- **Purpose:** Enables Vault to authenticate and authorize Kubernetes resources
- **Integration:** Kubernetes authentication backend

#### 1.5 Secret Access ClusterRole
- **Function:** Defines access patterns for secret consumption
- **Purpose:** Standardized RBAC policies for applications accessing secrets
- **Scope:** Reusable role for service accounts

### Functionality Summary

- ✅ Creates cluster-scoped permissions before Vault deployment
- ✅ Enables Kubernetes authentication backend integration
- ✅ Sets up webhook infrastructure for automatic secret injection
- ✅ Establishes CSI driver permissions for volume-mounted secrets
- ⚠️ Must be deployed **once per cluster** before namespace-specific Vault installations

### Prerequisites Files

```
fndsec-hashicorp-vault-helm-pre-requisite-1.3.0.tgz
├── templates/
│   ├── _helpers.tpl
│   ├── csi-clusterrole.yaml
│   ├── csi-clusterrolebinding.yaml
│   ├── injector-clusterrole.yaml
│   ├── injector-clusterrolebinding.yaml
│   ├── injector-mutating-webhook.yaml
│   ├── secret-access-cluster-role.yaml
│   └── server-clusterrolebinding.yaml
├── Chart.yaml
├── values.yaml
└── values.openshift.yaml
```

---

## 2. HashiCorp-Vault-Cluster

**Version:** 1.6.0  
**App Version:** 1.19.3  
**Kubernetes Version:** >= 1.20.0-0  
**Derived From:** HashiCorp Helm v0.29.1  
**Platform:** OpenShift-compatible

### Structure

The Vault cluster is organized into two deployment configurations:

```
HashiCorp-Vault-Cluster/
├── Unsealer/
│   └── fndsec-hashicorp-vault-helm/  # Transit engine for auto-unsealing
└── Vault/
    └── fndsec-hashicorp-vault-helm/  # Main secrets storage cluster
```

### Architecture

#### 2.1 Vault Server Components

| Template File | Function | Purpose |
|--------------|----------|---------|
| `server-statefulset.yaml` | Main Vault pods | 3-replica HA cluster with Raft consensus storage |
| `server-config-configmap.yaml` | Vault configuration | Storage backend, listeners, seal configuration |
| `server-headless-service.yaml` | StatefulSet DNS | Individual pod DNS (vault-0, vault-1, vault-2) |
| `server-ha-active-service.yaml` | Active node routing | Routes traffic to current active Vault leader |
| `server-ha-standby-service.yaml` | Standby routing | Routes to standby nodes for read operations |
| `server-service.yaml` | Main service endpoint | Primary Vault API endpoint |
| `ui-service.yaml` | Vault UI access | Web interface for Vault management |
| `server-route.yaml` | OpenShift Route | External access with TLS passthrough |
| `server-serviceaccount.yaml` | Pod identity | Kubernetes identity for Vault pods |
| `server-disruptionbudget.yaml` | PDB | Ensures minimum replicas during disruptions |

#### 2.2 Injector Components

| Template File | Function | Purpose |
|--------------|----------|---------|
| `injector-deployment.yaml` | Webhook server | Vault agent injector deployment |
| `injector-service.yaml` | Webhook endpoint | Service for mutation webhook |
| `injector-certs-secret.yaml` | TLS certificates | Webhook authentication |
| `injector-network-policy.yaml` | Network isolation | Ingress/egress rules for injector |
| `injector-disruptionbudget.yaml` | High availability | PDB for injector pods |

#### 2.3 CSI Provider Components

| Template File | Function | Purpose |
|--------------|----------|---------|
| `csi-daemonset.yaml` | CSI driver pods | Runs on every node for volume mounting |
| `csi-agent-configmap.yaml` | Agent configuration | CSI driver settings |
| `csi-serviceaccount.yaml` | CSI identity | Service account for driver pods |
| `csi-role.yaml` | RBAC permissions | Namespace-scoped permissions |
| `csi-rolebinding.yaml` | Permission binding | Links role to service account |

#### 2.4 Security & Monitoring

| Template File | Function | Purpose |
|--------------|----------|---------|
| `server-network-policy.yaml` | Network isolation | Ingress/egress traffic control |
| `prometheus-servicemonitor.yaml` | Metrics collection | Prometheus scraping configuration |
| `server-psp.yaml` | Pod Security Policy | Security constraints for Vault pods |
| `server-psp-role.yaml` | PSP role | RBAC for PSP |
| `server-psp-rolebinding.yaml` | PSP binding | Links PSP to service account |

### Key Features

#### High Availability Configuration
- **Replicas:** 3 pods in active-standby configuration
- **Storage:** Integrated Raft consensus (no external Consul required)
- **Leader Election:** Automatic failover with Raft protocol
- **Data Replication:** Synchronous replication across all replicas

#### Security Features
- **TLS Encryption:** End-to-end encryption for all communications
- **Auto-Unsealing:** Transit secrets engine eliminates manual unsealing
- **Network Policies:** Pod-level network isolation
- **RBAC Integration:** Kubernetes-native authentication

#### Deployment Modes

1. **Unsealer Mode**
   - Provides transit secrets engine
   - Used for auto-unsealing main Vault clusters
   - Namespace: `unsealer-vault`
   - Purpose: Unsealing service provider

2. **Vault Mode**
   - Main secrets storage cluster
   - Stores application secrets, certificates, keys
   - Namespace: `vault-1`
   - Purpose: Primary secrets management

### Template Count
- **Total Templates:** 43 YAML files
- **Core Server:** 21 templates
- **Injector:** 9 templates
- **CSI Provider:** 6 templates
- **Security/Monitoring:** 7 templates

---

## 3. hashicorp-vault-post-install-helm

**Version:** 1.1.6  
**Chart Type:** Post-installation automation  
**Maintainer:** Amdocs Foundation

### Purpose

Automates Vault initialization, unsealing, configuration, and ongoing operational tasks through Kubernetes Jobs and CronJobs.

### Key Templates

#### 3.1 Initialization & Configuration

| Template File | Function | Execution |
|--------------|----------|-----------|
| `vault-post-install-job.yaml` | One-time initialization | Runs once after deployment |
| `vault-post-install-cron-job.yaml` | Scheduled configuration updates | Periodic execution |
| `vault-ldap-config.yaml` | LDAP authentication setup | ConfigMap for auth method |
| `vault-audit-config.yaml` | Audit logging configuration | ConfigMap for audit devices |
| `vault-admin-policy-config.yaml` | Admin policies | HCL policy definitions |
| `vault-access-config.yaml` | Access control policies | Application access patterns |
| `vault-kms-config.yaml` | KMS encryption configuration | External KMS integration |
| `secret-manager-setup-config.yaml` | Secret management automation | Service broker setup |

#### 3.2 Backup & Storage

| Template File | Function | Purpose |
|--------------|----------|---------|
| `vault-post-install-backup-cronjob.yaml` | Automated backups | Daily backup execution |
| `vault-backup-restore-pvc.yaml` | Backup storage | Persistent volume for backups |

#### 3.3 Security

| Template File | Function | Purpose |
|--------------|----------|---------|
| `secret-access.yaml` | Service account secrets | Authentication tokens |

### Deployment Modes

The post-install chart supports four distinct deployment modes:

#### Mode 1: unsealerVaultClusterSetup
- **Purpose:** Initialize unsealer Vault with transit engine
- **Actions:**
  - Initialize Vault cluster
  - Enable transit secrets engine
  - Configure transit key for unsealing
  - Store transit token in Kubernetes secret
- **Target:** Unsealer namespace (`unsealer-vault`)

#### Mode 2: vaultClusterSetup
- **Purpose:** Initialize main Vault cluster
- **Actions:**
  - Initialize Vault cluster
  - Auto-unseal using transit engine
  - Configure auth methods (LDAP, Kubernetes)
  - Set up audit logging
  - Create admin policies
  - Store unseal keys securely
- **Target:** Vault namespace (`vault-1`)

#### Mode 3: kmsSetup
- **Purpose:** Configure external KMS integration
- **Actions:**
  - Integrate with external KMS providers
  - Configure key encryption keys (KEK)
  - Enable envelope encryption

#### Mode 4: secretManagerServiceBrokerSetup
- **Purpose:** Enable Open Service Broker API
- **Actions:**
  - Deploy service broker
  - Enable dynamic secret provisioning
  - Configure catalog services

### Configuration Options

#### Vault Cluster Settings
```yaml
vault:
  deploymentName: vault
  replicas: 3
  tlsEnabled: true
```

#### Token Time-To-Live
```yaml
clientToken:
  default_ttl: 1h    # Default token lifetime
  max_ttl: 8h        # Maximum token lifetime
  token_ttl: 1h      # Service token TTL
```

#### Audit Devices
- **FILE:** Logs to file system (`/vault/audit/vault_audit.log`)
- **STDOUT:** Logs to standard output
- **SOCKET:** Remote logging via socket connection

#### Backup Configuration
```yaml
vaultPostInstallBackupCronJob:
  enabled: false
  jobSchedule: "0 1 * * *"  # Daily at 1:00 AM
  backoffLimit: 6
  pvc:
    storage: "5Gi"
```

### Functionality

#### Initialization Process
1. ✅ Creates root token and unseal keys
2. ✅ Stores unseal keys in Kubernetes secret `vault-unseal-keys-secret`
3. ✅ Stores transit token in `vault-transit-token-secret`
4. ✅ Configures TLS from `vault-server-tls` secret

#### Auto-Unsealing Process
1. Vault pods start in sealed state
2. Post-install job retrieves transit token
3. Job calls transit engine to unseal each pod
4. Pods become operational and join Raft cluster

#### Authentication Configuration
- **Kubernetes Auth:** Enables service account token authentication
- **LDAP Auth:** Integrates with enterprise directory services
- **Admin Policies:** Creates superuser policies for cluster management

#### Audit Configuration
- Enables audit logging to configured devices
- Tracks all secret access and modifications
- Supports compliance requirements (SOC2, PCI-DSS)

#### Backup Automation
- Scheduled snapshots of Raft storage
- Retention policy management
- PVC-based backup storage
- Configurable backup frequency

### Operational Features

| Feature | Configuration | Default |
|---------|--------------|---------|
| Job Timeout | `activeDeadlineSeconds` | 700 seconds |
| Retry Attempts | `backoffLimit` | 6 attempts |
| Debug Mode | `debug` | false |
| Recovery Mode | `vaultRecovery` | false |

---

## Deployment Architecture

### Multi-Namespace Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift/Kubernetes Cluster              │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Cluster-Scoped Resources (Prerequisites)            │   │
│  │  - CSI ClusterRole/ClusterRoleBinding                │   │
│  │  - Injector ClusterRole/ClusterRoleBinding           │   │
│  │  - Injector MutatingWebhook                          │   │
│  │  - Server ClusterRoleBinding                         │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Namespace: unsealer-vault                           │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │ Vault Pods (3 replicas)                        │  │   │
│  │  │ - Transit Secrets Engine                       │  │   │
│  │  │ - Auto-unseal key provider                     │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │ Post-Install Job                               │  │   │
│  │  │ - Initialize Vault                             │  │   │
│  │  │ - Enable transit engine                        │  │   │
│  │  │ - Create transit key                           │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Namespace: vault-1                                  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │ Vault Pods (3 replicas)                        │  │   │
│  │  │ - Secrets Storage                              │  │   │
│  │  │ - Application Secret Management                │  │   │
│  │  │ - Auto-unsealed by unsealer-vault              │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │ Post-Install Job                               │  │   │
│  │  │ - Initialize Vault                             │  │   │
│  │  │ - Configure LDAP auth                          │  │   │
│  │  │ - Set up audit logging                         │  │   │
│  │  │ - Create admin policies                        │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │ Backup CronJob                                 │  │   │
│  │  │ - Daily backups (1:00 AM)                      │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 0: Generate TLS Certificates                           │
│ - Create CA and server certificates                         │
│ - Generate SANs for all Vault services                      │
│ - Store in certs/ directory                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Deploy Prerequisites (Cluster-scoped)               │
│ - Create namespace                                           │
│ - Create OpenShift Route                                     │
│ - Deploy RBAC resources                                      │
│ - Deploy CSI ClusterRoles                                    │
│ - Deploy Injector webhook                                    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2A: Deploy Unsealer Vault Cluster                      │
│ Config: config-unsealer-vault.json                          │
│ - Namespace: unsealer-vault                                  │
│ - Deploy Vault StatefulSet (3 replicas)                     │
│ - Create Services (active, standby, headless)               │
│ - Deploy Injector                                            │
│ - Deploy CSI DaemonSet                                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3A: Post-Install Unsealer (unsealerVaultClusterSetup)  │
│ - Initialize Vault cluster                                   │
│ - Store unseal keys in Kubernetes secret                    │
│ - Enable transit secrets engine                              │
│ - Create transit encryption key                              │
│ - Store transit token for vault-1 to use                    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2B: Deploy Main Vault Cluster                          │
│ Config: config-vault-1.json                                 │
│ - Namespace: vault-1                                         │
│ - Deploy Vault StatefulSet (3 replicas)                     │
│ - Configure auto-unseal with transit engine                 │
│ - Create Services and Routes                                │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3B: Post-Install Vault-1 (vaultClusterSetup)           │
│ - Initialize Vault cluster                                   │
│ - Auto-unseal using unsealer-vault transit                  │
│ - Configure LDAP authentication                              │
│ - Enable audit logging (FILE/STDOUT/SOCKET)                 │
│ - Create admin policies                                      │
│ - Set up access control policies                            │
│ - Configure backup CronJob                                   │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Auto-Unsealing Process

```
┌──────────────────┐         ┌──────────────────┐
│  vault-1 Pod     │         │ unsealer-vault   │
│  (Sealed)        │         │  Transit Engine  │
└────────┬─────────┘         └─────────┬────────┘
         │                             │
         │  1. Request unseal key      │
         │────────────────────────────>│
         │                             │
         │  2. Return encrypted key    │
         │<────────────────────────────│
         │                             │
         │  3. Decrypt with transit    │
         │────────────────────────────>│
         │                             │
         │  4. Receive decrypted key   │
         │<────────────────────────────│
         │                             │
         │  5. Unseal Vault            │
         └────────────────────────────>│
         
    (Vault becomes operational)
```

---

## Configuration Reference

### Directory Structure on Remote Server

```
/jenkins/jenkins/PRASA/
├── hashicorp-vault-helm-pre-requisite/
│   ├── fndsec-hashicorp-vault-helm-pre-requisite-1.3.0.tgz
│   ├── custom-values.yaml
│   ├── unsealer-vault/          # Namespace-specific overrides
│   └── vault-1/                 # Namespace-specific overrides
│
├── HashiCorp-Vault-Cluster/
│   ├── Unsealer/
│   │   └── fndsec-hashicorp-vault-helm/
│   │       ├── Chart.yaml
│   │       ├── values.yaml
│   │       ├── templates/ (43 files)
│   │       └── certs/           # Generated certificates
│   │
│   └── Vault/
│       └── fndsec-hashicorp-vault-helm/
│           ├── Chart.yaml
│           ├── values.yaml
│           ├── templates/ (43 files)
│           └── certs/           # Generated certificates
│
└── hashicorp-vault-post-install-helm-1.1.6/
    └── fndsec-hashicorp-vault-post-install-helm/
        ├── Chart.yaml
        ├── values.yaml
        ├── kms-values-example.yaml
        ├── templates/ (12 files)
        └── files/
            ├── job-spec.yaml
            └── tls-spec.yaml
```

### Configuration Files

#### config-unsealer-vault.json
```json
{
  "directories": {
    "basePath": "/jenkins/jenkins/PRASA",
    "prerequisite": "hashicorp-vault-helm-pre-requisite",
    "cluster": "HashiCorp-Vault-Cluster/Unsealer/fndsec-hashicorp-vault-helm",
    "postInstall": "hashicorp-vault-post-install-helm-1.1.6"
  },
  "deployment": {
    "namespace": "unsealer-vault",
    "releaseName": "unsealer-hashicorp-vault",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

#### config-vault-1.json
```json
{
  "directories": {
    "basePath": "/jenkins/jenkins/PRASA",
    "prerequisite": "hashicorp-vault-helm-pre-requisite",
    "cluster": "HashiCorp-Vault-Cluster/Vault/fndsec-hashicorp-vault-helm",
    "postInstall": "hashicorp-vault-post-install-helm-1.1.6"
  },
  "deployment": {
    "namespace": "vault-1",
    "releaseName": "hashicorp-vault",
    "helmTimeout": "10m"
  },
  "logging": {
    "logDir": "logs",
    "logLevel": "INFO"
  }
}
```

### Deployment Commands

#### Deploy Unsealer Vault
```bash
./setup-vault-cluster.sh -c config-unsealer-vault.json
```

#### Deploy Main Vault
```bash
./setup-vault-cluster.sh -c config-vault-1.json
```

#### Skip Certificate Generation
```bash
./setup-vault-cluster.sh -c config-vault-1.json --skip-certs
```

#### Skip Prerequisites
```bash
./setup-vault-cluster.sh -c config-vault-1.json --skip-prereq
```

---

## Summary

This HashiCorp Vault deployment provides:

### ✅ High Availability
- 3-replica Raft consensus cluster
- Automatic failover and leader election
- Pod disruption budgets for zero-downtime maintenance

### ✅ Security
- End-to-end TLS encryption
- Auto-unsealing with transit engine
- Network policies and RBAC
- Audit logging for compliance

### ✅ Automation
- Kubernetes-native deployment
- Automated initialization and unsealing
- Scheduled backups
- Self-service secret injection

### ✅ Scalability
- CSI driver for volume-mounted secrets
- Agent injection for sidecar pattern
- Service broker integration
- Multi-namespace isolation

### ✅ Enterprise Features
- LDAP authentication integration
- KMS encryption support
- Admin policy framework
- Backup and restore capabilities

---

**Document Version:** 1.0  
**Last Updated:** January 5, 2026  
**Author:** Prasadu Gamini  
**Status:** Production Ready
