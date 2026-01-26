# Vault Deployment Agent - Test Scenarios & Examples

This document provides practical test scenarios and examples for using the Vault Deployment Agent.

## Test Scenario 1: First-Time Complete Deployment

**Goal**: Deploy a complete vault cluster from scratch (unsealer + vault-1).

### Prerequisites Check

```
@vault-deployment-agent Test cluster connectivity
```

**Expected Response**:
- Executes `oc cluster-info`
- Reports cluster is accessible
- Shows cluster URL and version

### Step-by-Step Deployment

#### Step 1: Validate Configurations

```
@vault-deployment-agent Validate config-unsealer-vault.json and config-vault-1.json
```

**Expected Response**:
- Confirms files exist
- Checks JSON syntax
- Validates required fields
- Reports configuration is valid

#### Step 2: Deploy Complete Cluster

```
@vault-deployment-agent Deploy complete vault cluster with unsealer and vault-1
```

**Expected Response**:
- Confirms it will deploy both vaults
- Shows command: `./setup-vault-cluster.sh config-unsealer-vault.json config-vault-1.json`
- Executes deployment
- Monitors progress through logs
- Reports completion status

**Expected Output**:
```
Executing deployment:
✓ Namespace & Route: SUCCESS
✓ Certificates: SUCCESS
✓ Prerequisites: SUCCESS
✓ Vault Cluster: SUCCESS
✓ Post-Install: SUCCESS

Deployed Vaults:
  - unsealer-vault
  - vault-1

Next Steps:
1. Initialize unsealer vault
2. Setup transit auto-unseal
3. Verify vault-1 auto-unsealed
```

#### Step 3: Initialize Unsealer Vault

```
@vault-deployment-agent Initialize and unseal the unsealer vault
```

**Expected Response**:
- Checks if already initialized
- Runs `vault operator init` on vault-0
- Saves unseal keys
- Unseals all three pods
- Verifies cluster status
- **Reminds to save keys securely**

#### Step 4: Verify Deployment

```
@vault-deployment-agent Verify all pods are running
```

**Expected Response**:
- Lists pods in unsealer-vault namespace
- Lists pods in vault-1 namespace
- Shows pod status (Running)
- Checks vault status (unsealed)
- Verifies raft peers

---

## Test Scenario 2: Deploy Single Vault

**Goal**: Deploy only the unsealer vault.

### Commands

```
@vault-deployment-agent Deploy unsealer vault only
```

**Expected Response**:
- Validates config-unsealer-vault.json
- Executes: `./setup-vault-cluster.sh config-unsealer-vault.json`
- Reports progress
- Provides initialization instructions

### Verify Deployment

```
@vault-deployment-agent Check if unsealer vault is healthy
```

**Expected Response**:
- Pod status check
- Route verification
- Service endpoint check
- Health status report

---

## Test Scenario 3: Certificate Operations

**Goal**: Generate and verify certificates.

### Generate Certificates

```
@vault-deployment-agent Generate certificates for vault-1 namespace
```

**Expected Response**:
- Executes: `./generate-certificates.sh config-vault-1.json`
- Creates CA certificate
- Creates server certificate with SANs
- Creates Kubernetes TLS secret
- Reports success

### Verify Certificates

```
@vault-deployment-agent Verify certificates in vault-1 are valid
```

**Expected Response**:
- Checks secret exists
- Extracts certificate
- Verifies validity period
- Checks SANs include required DNS names
- Reports expiration date

---

## Test Scenario 4: Configuration Management

**Goal**: Create and manage configuration files.

### Create New Configuration

```
@vault-deployment-agent Create configuration for vault-2 namespace with release name hashicorp-vault-2
```

**Expected Response**:
- Copies config.example.json
- Updates namespace to "vault-2"
- Updates releaseName to "hashicorp-vault-2"
- Generates route URL
- Saves as config-vault-2.json
- Displays configuration

### Modify Existing Configuration

```
@vault-deployment-agent Update vault-1 configuration to use helm timeout of 15m
```

**Expected Response**:
- Reads config-vault-1.json
- Updates helmTimeout to "15m"
- Saves file
- Shows diff

### Commit Configuration

```
@vault-deployment-agent Commit the vault-2 configuration changes
```

**Expected Response**:
- Stages config-vault-2.json
- Creates commit message: "Add vault-2 configuration"
- Commits changes
- Pushes to origin

---

## Test Scenario 5: Troubleshooting

**Goal**: Diagnose and resolve deployment issues.

### Check Deployment Failure

```
@vault-deployment-agent Troubleshoot the failed deployment in vault-1
```

**Expected Response**:
1. Checks pod status
2. Retrieves pod logs
3. Checks Helm release
4. Verifies certificates
5. Checks secrets exist
6. Identifies root cause
7. Provides remediation steps

**Example Output**:
```
Diagnosing vault-1 deployment failure...

Pod Status:
  vault-0: CrashLoopBackOff
  vault-1: Pending
  vault-2: Pending

Checking logs for vault-0:
  Error: certificate verify failed

Root Cause: Invalid TLS certificate

Remediation Steps:
1. Regenerate certificates
2. Verify secret is created
3. Restart pods

Would you like me to regenerate certificates?
```

### Check Pod Logs

```
@vault-deployment-agent Show me the logs for vault-0 pod in vault-1 namespace
```

**Expected Response**:
- Executes: `oc logs vault-0 -n vault-1`
- Displays recent log entries
- Highlights errors
- Suggests next steps

---

## Test Scenario 6: Selective Deployment

**Goal**: Deploy with specific steps skipped.

### Skip Certificate Generation

```
@vault-deployment-agent Deploy vault-1 but skip certificate generation
```

**Expected Response**:
- Executes: `./setup-vault-cluster.sh --skip-certs config-vault-1.json`
- Uses existing certificates
- Proceeds with deployment

### Skip Prerequisites

```
@vault-deployment-agent Deploy vault-2 but skip prerequisites and namespace creation
```

**Expected Response**:
- Executes with: `--skip-prereq --skip-namespace`
- Assumes namespace exists
- Deploys vault cluster only

---

## Test Scenario 7: Multi-Vault Deployment

**Goal**: Deploy multiple data vaults with auto-unseal.

### Deploy Unsealer First

```
@vault-deployment-agent Deploy unsealer vault and initialize it
```

### Deploy Multiple Data Vaults

```
@vault-deployment-agent Deploy vault-1 and vault-2 with auto-unseal from unsealer vault
```

**Expected Response**:
- Validates unsealer vault is ready
- Deploys vault-1
- Waits for completion
- Deploys vault-2
- Verifies both auto-unseal correctly
- Reports status

---

## Test Scenario 8: Status and Monitoring

**Goal**: Get comprehensive status of deployments.

### Overall Status

```
@vault-deployment-agent Give me a complete status report of all deployed vaults
```

**Expected Response**:
- Lists all vault namespaces
- Shows pod status for each
- Checks vault status (sealed/unsealed)
- Displays route URLs
- Reports raft cluster health
- Provides summary

### Check Specific Vault

```
@vault-deployment-agent What is the status of unsealer vault?
```

**Expected Response**:
- Pod list and status
- Vault status on each pod
- Raft peers
- Route information
- Service endpoints
- Overall health: HEALTHY/UNHEALTHY

---

## Test Scenario 9: Route Management

**Goal**: Verify and troubleshoot routes.

### Check Route

```
@vault-deployment-agent Check the OpenShift route for unsealer vault
```

**Expected Response**:
- Gets route details
- Shows route URL
- Tests connectivity
- Provides access command

**Example Output**:
```
Route Details:
  Name: vault
  Namespace: unsealer-vault
  URL: https://vault-unsealer-vault.apps.example.com
  Service: vault-active:8200
  TLS: Passthrough

Testing connectivity...
✓ Route is accessible

Access Vault:
  export VAULT_ADDR=https://vault-unsealer-vault.apps.example.com
  vault status
```

### Troubleshoot Route Issues

```
@vault-deployment-agent The route is not working for vault-1
```

**Expected Response**:
- Checks route exists
- Verifies service exists
- Checks service endpoints
- Tests pod connectivity
- Diagnoses issue
- Suggests fix

---

## Test Scenario 10: Certificate Rotation

**Goal**: Rotate TLS certificates for a vault.

### Backup and Regenerate

```
@vault-deployment-agent Rotate certificates for vault-1
```

**Expected Response**:
1. Backs up current certificates (optional)
2. Generates new certificates
3. Updates Kubernetes secret
4. Suggests pod restart
5. Verifies new certificates

### Restart Pods

```
@vault-deployment-agent Restart vault pods in vault-1 to use new certificates
```

**Expected Response**:
- Deletes pods (StatefulSet recreates)
- Waits for pods to be ready
- Verifies vault status
- Confirms certificates are updated

---

## Test Scenario 11: Git Workflow

**Goal**: Manage configuration changes with git.

### Check Status

```
@vault-deployment-agent Show git status
```

**Expected Response**:
- Executes: `git status`
- Shows modified files
- Shows untracked files

### Commit Changes

```
@vault-deployment-agent Commit all configuration changes with message "Update vault configurations for production"
```

**Expected Response**:
- Stages all config files
- Creates commit with provided message
- Shows commit hash
- Pushes to origin

### View History

```
@vault-deployment-agent Show recent git commits
```

**Expected Response**:
- Displays last 5-10 commits
- Shows commit messages
- Shows dates and authors

---

## Test Scenario 12: Logs and Debugging

**Goal**: Access and analyze deployment logs.

### Show Latest Logs

```
@vault-deployment-agent Show me the latest deployment logs
```

**Expected Response**:
- Lists log files in logs/
- Displays most recent log
- Highlights errors/warnings

### Analyze Errors

```
@vault-deployment-agent What errors are in the deployment logs?
```

**Expected Response**:
- Searches logs for ERROR entries
- Lists all errors found
- Groups similar errors
- Suggests solutions for each

---

## Test Scenario 13: Transit Auto-Unseal Setup

**Goal**: Configure transit auto-unseal between vaults.

### Setup Transit on Unsealer

```
@vault-deployment-agent Setup transit auto-unseal on unsealer vault for vault-1
```

**Expected Response**:
1. Verifies unsealer vault is initialized
2. Enables transit secrets engine
3. Creates transit key
4. Creates policy
5. Creates token for vault-1
6. Provides configuration for vault-1

---

## Test Scenario 14: Rollback and Recovery

**Goal**: Rollback failed deployment.

### Rollback

```
@vault-deployment-agent Rollback the failed vault-2 deployment
```

**Expected Response**:
- Checks Helm release
- Executes: `helm rollback vault-2`
- Verifies rollback success
- Cleans up resources if needed

---

## Expected Agent Behaviors

### 1. Validation Before Execution

Agent should always:
- Validate prerequisites
- Check configuration files exist
- Verify cluster connectivity
- Confirm actions with user

### 2. Clear Communication

Agent provides:
- Clear explanation of what it will do
- Command being executed
- Progress updates
- Success/failure status
- Next steps

### 3. Error Handling

When errors occur:
- Identify root cause
- Provide specific error message
- Suggest remediation steps
- Offer to help fix issue

### 4. Security Awareness

Agent should:
- Never expose unseal keys in output
- Remind to save keys securely
- Warn about sensitive operations
- Use secure practices

### 5. Contextual Help

Agent understands:
- Natural language variations
- Context from previous commands
- Deployment state
- User intent

---

## Integration Tests

### Test 1: End-to-End Deployment

```bash
# Using agent
@vault-deployment-agent Test connection
@vault-deployment-agent Deploy complete cluster
@vault-deployment-agent Initialize unsealer vault
@vault-deployment-agent Verify all pods running
@vault-deployment-agent Commit deployment
```

**Success Criteria**:
- All commands execute successfully
- All pods are running
- Vaults are unsealed
- Routes are accessible
- Changes are committed

### Test 2: Recovery from Failure

```bash
# Simulate failure, then recover
@vault-deployment-agent Deploy vault-3 (will fail if config missing)
@vault-deployment-agent Create config for vault-3
@vault-deployment-agent Deploy vault-3 (should succeed)
```

**Success Criteria**:
- Agent detects missing config
- Creates configuration
- Retries deployment successfully

### Test 3: Multi-Step Workflow

```bash
@vault-deployment-agent Create config for vault-test with namespace test-vault
@vault-deployment-agent Generate certificates for vault-test
@vault-deployment-agent Deploy vault-test but skip prerequisites
@vault-deployment-agent Check if vault-test is healthy
@vault-deployment-agent Commit vault-test configuration
```

**Success Criteria**:
- Configuration created correctly
- Certificates generated
- Deployment successful
- Health check passes
- Changes committed

---

## Performance Expectations

| Operation | Expected Time | Timeout |
|-----------|--------------|---------|
| Configuration validation | < 1s | 5s |
| Certificate generation | 5-10s | 30s |
| Prerequisites deployment | 2-5 min | 10 min |
| Vault cluster deployment | 3-7 min | 15 min |
| Post-installation | 1-3 min | 10 min |
| Complete deployment | 8-15 min | 30 min |

---

## Common Issues and Solutions

### Issue 1: Agent doesn't understand command

**Solution**: Be more specific
```
Instead of: "Deploy the thing"
Try: "Deploy unsealer vault using config-unsealer-vault.json"
```

### Issue 2: Command fails silently

**Solution**: Check logs
```
@vault-deployment-agent Show deployment logs
@vault-deployment-agent What went wrong?
```

### Issue 3: Configuration not found

**Solution**: Verify file exists
```
@vault-deployment-agent List all configuration files
@vault-deployment-agent Create config for <namespace>
```

### Issue 4: Deployment hangs

**Solution**: Check cluster and pods
```
@vault-deployment-agent Check pod status in <namespace>
@vault-deployment-agent Show pod logs
```

---

## Success Metrics

Agent is working correctly when:
- ✅ Understands natural language commands
- ✅ Validates before executing
- ✅ Provides clear feedback
- ✅ Handles errors gracefully
- ✅ Suggests next steps
- ✅ Completes deployments successfully
- ✅ Maintains security best practices
- ✅ Provides helpful diagnostics

---

## Conclusion

These test scenarios cover the full range of agent capabilities. Use them to:
1. Verify agent is working correctly
2. Learn agent capabilities
3. Practice deployment workflows
4. Troubleshoot issues
5. Train new users

For more information, see:
- [AGENT_USAGE_GUIDE.md](./AGENT_USAGE_GUIDE.md)
- [AGENT_QUICK_REFERENCE.md](./AGENT_QUICK_REFERENCE.md)
- [README-BASH.md](./README-BASH.md)
