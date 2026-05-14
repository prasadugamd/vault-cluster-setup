# Example Usage Scenarios

This document provides detailed examples of how to use the Vault Cluster MCP Server through an AI assistant like Claude.

## Scenario 1: Complete Fresh Deployment

**Goal**: Deploy a complete vault cluster from scratch with unsealer and data vault.

### Commands to Use

1. **Check cluster connectivity**:
   ```
   Check if I'm connected to the OpenShift cluster
   ```

2. **List available configurations**:
   ```
   List all vault configuration files
   ```

3. **Validate configurations**:
   ```
   Validate config-unsealer-vault.json and config-vault-1.json
   ```

4. **Deploy the cluster**:
   ```
   Deploy a complete vault cluster using config-unsealer-vault.json and config-vault-1.json
   ```

5. **Initialize unsealer vault**:
   ```
   Initialize the unsealer vault in namespace vault-unsealer with release name unsealer-vault
   ```
   
   **Important**: Save the unseal keys and root token securely!

6. **Unseal the unsealer vault**:
   ```
   Unseal the vault in namespace vault-unsealer with these keys: [key1, key2, key3]
   ```

7. **Enable transit**:
   ```
   Enable transit secrets engine on unsealer vault in namespace vault-unsealer
   ```

8. **Check deployment status**:
   ```
   Check the status of the vault cluster in namespace vault-unsealer and vault-1
   ```

## Scenario 2: Update Configuration and Redeploy

**Goal**: Change the namespace and replica count for an existing configuration.

### Commands to Use

1. **Read current configuration**:
   ```
   Show me the contents of config-vault-1.json
   ```

2. **Update configuration**:
   ```
   Update config-vault-1.json to change namespace to vault-production and set replicas to 5
   ```

3. **Validate updated configuration**:
   ```
   Validate config-vault-1.json
   ```

4. **Deploy with new configuration**:
   ```
   Deploy vault-1 using the updated config-vault-1.json
   ```

## Scenario 3: Create New Data Vault

**Goal**: Add a third vault (vault-2) to an existing cluster.

### Commands to Use

1. **Create new configuration**:
   ```
   Create a new configuration file config-vault-2.json based on config-vault-1.json
   ```

2. **Update the new configuration**:
   ```
   Update config-vault-2.json to set namespace to vault-2 and release name to vault-2
   ```

3. **Generate certificates**:
   ```
   Generate certificates for namespace vault-2 with release name vault-2
   ```

4. **Deploy the new vault**:
   ```
   Deploy vault using config-vault-2.json
   ```

5. **Verify auto-unseal**:
   ```
   Check the seal status of vault-2 in namespace vault-2
   ```

## Scenario 4: Troubleshooting Failed Deployment

**Goal**: Diagnose and fix a deployment that failed.

### Commands to Use

1. **Run comprehensive troubleshooting**:
   ```
   Troubleshoot the deployment in namespace vault-1
   ```

2. **Check specific pod logs**:
   ```
   Show me the logs for pod vault-1-0 in namespace vault-1
   ```

3. **Check helm release**:
   ```
   Check the helm release status for vault-1 in namespace vault-1
   ```

4. **Verify certificates**:
   ```
   Verify certificates for namespace vault-1
   ```

5. **Check route accessibility**:
   ```
   Check the route status for namespace vault-1
   ```

## Scenario 5: Certificate Regeneration

**Goal**: Regenerate certificates for a vault that has certificate issues.

### Commands to Use

1. **Verify current certificates**:
   ```
   Verify certificates for namespace vault-1 with release name vault-1
   ```

2. **Regenerate certificates**:
   ```
   Regenerate certificates for namespace vault-1 with release name vault-1 and route vault-1.apps.example.com
   ```

3. **Delete existing pods to pick up new certs** (do this manually or via kubectl):
   ```bash
   oc delete pods -n vault-1 -l app.kubernetes.io/instance=vault-1
   ```

4. **Verify deployment recovered**:
   ```
   Check cluster status for namespace vault-1
   ```

## Scenario 6: Monitoring and Health Checks

**Goal**: Regular health monitoring of vault deployments.

### Commands to Use

1. **Overall cluster health**:
   ```
   Check detailed cluster status for namespace vault-unsealer and vault-1
   ```

2. **Check vault seal status**:
   ```
   Check seal status for all vaults
   ```

3. **Verify all pods are running**:
   ```
   Show me all pods in namespace vault-unsealer and their status
   ```

## Scenario 7: Creating Namespace and Route First

**Goal**: Set up the namespace and route before deploying.

### Commands to Use

1. **Create namespace and route**:
   ```
   Create namespace vault-prod with release name vault-prod and route vault-prod.apps.example.com
   ```

2. **Check namespace and route created**:
   ```
   Check namespace and route status for vault-prod
   ```

3. **Generate certificates**:
   ```
   Generate certificates for namespace vault-prod with release name vault-prod
   ```

4. **Deploy vault**:
   ```
   Deploy vault using config-vault-prod.json skipping namespace creation
   ```

## Tips for Using with AI Assistants

### Be Specific
Instead of: "Deploy vault"  
Use: "Deploy a complete vault cluster using config-unsealer-vault.json and config-vault-1.json"

### Break Down Complex Tasks
For complex operations, ask the AI to do them step by step:
```
First check my cluster connection, then list my configuration files, 
then validate config-vault-1.json, and finally deploy it
```

### Ask for Explanations
```
What will happen if I deploy vault-1 without initializing the unsealer vault first?
```

### Request Status Checks
After deployments, always verify:
```
After deploying, check the cluster status and show me any issues
```

### Use Natural Language
The MCP server tools are designed to work with natural language, so you can say:
- "Show me what's wrong with my vault deployment"
- "Create a new config for vault-3 based on vault-1"
- "Why are my vault pods not starting?"

## Common Workflows

### Quick Deployment Check
```
1. List configuration files
2. Check cluster connectivity
3. Deploy using my configs
4. Check status
```

### Complete Setup from Scratch
```
1. Check prerequisites
2. Validate all configs
3. Deploy complete cluster
4. Initialize unsealer
5. Unseal unsealer vault
6. Enable transit
7. Verify data vaults auto-unsealed
8. Check overall cluster health
```

### Routine Maintenance
```
1. Check cluster status for all namespaces
2. Verify all vaults are unsealed
3. Check certificate expiration
4. Review pod health
```

## Error Recovery Patterns

### Pods Not Starting
```
1. Troubleshoot deployment in the namespace
2. Check pod logs
3. Verify certificates
4. Check helm release status
5. Follow remediation suggestions
```

### Vault Sealed After Restart
```
1. Check seal status
2. Unseal with saved keys
3. Verify transit auto-unseal is working
```

### Certificate Issues
```
1. Verify current certificates
2. Regenerate if needed
3. Restart pods
4. Verify vault accessible
```

These examples demonstrate the natural language interface of the MCP server through AI assistants. The actual commands may vary based on your specific deployment needs.
