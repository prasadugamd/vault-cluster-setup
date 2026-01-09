#!/bin/bash
# deploy-post-install.sh
# Script to run post-installation tasks

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Function to update user policies to admin policy
update_user_admin_policies() {
    local NAMESPACE="$1"
    local ROOT_TOKEN="$2"
    local LOG_FILE="$3"
    
    log_message "INFO" "Updating user policies to vault-admin-policy in namespace: $NAMESPACE"
    
    # Check if vault-admin-policy exists
    log_message "INFO" "Checking for vault-admin-policy..."
    if ! oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault policy list" 2>&1 | grep -q "vault-admin-policy"; then
        log_message "WARN" "vault-admin-policy not found, skipping user policy updates"
        return 0
    fi
    
    log_message "INFO" "✓ vault-admin-policy found"
    
    # Read vault-admin-policy content for logging
    log_message "INFO" "vault-admin-policy content:"
    oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault policy read vault-admin-policy" >> "$LOG_FILE" 2>&1
    
    # Check if userpass auth is enabled
    if ! oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault auth list" 2>&1 | grep -q "userpass"; then
        log_message "WARN" "userpass authentication not enabled, skipping user policy updates"
        return 0
    fi
    
    # Update vault-secrets-migration-user
    log_message "INFO" "Updating vault-secrets-migration-user policy..."
    if oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault read auth/userpass/users/vault-secrets-migration-user" >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "Current policy for vault-secrets-migration-user:"
        oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault read auth/userpass/users/vault-secrets-migration-user" 2>&1 | grep "policies" >> "$LOG_FILE"
        
        if oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault write auth/userpass/users/vault-secrets-migration-user policies=\"vault-admin-policy\"" >> "$LOG_FILE" 2>&1; then
            log_message "INFO" "✓ vault-secrets-migration-user updated to vault-admin-policy"
        else
            log_message "WARN" "Failed to update vault-secrets-migration-user policy"
        fi
    else
        log_message "WARN" "vault-secrets-migration-user not found, skipping"
    fi
    
    # Update vault-secrets-management-user
    log_message "INFO" "Updating vault-secrets-management-user policy..."
    if oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault read auth/userpass/users/vault-secrets-management-user" >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "Current policy for vault-secrets-management-user:"
        oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault read auth/userpass/users/vault-secrets-management-user" 2>&1 | grep "policies" >> "$LOG_FILE"
        
        if oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; vault write auth/userpass/users/vault-secrets-management-user policies=\"vault-admin-policy\"" >> "$LOG_FILE" 2>&1; then
            log_message "INFO" "✓ vault-secrets-management-user updated to vault-admin-policy"
        else
            log_message "WARN" "Failed to update vault-secrets-management-user policy"
        fi
    else
        log_message "WARN" "vault-secrets-management-user not found, skipping"
    fi
    
    # Verify updates
    log_message "INFO" "Verifying policy updates..."
    oc exec vault-0 -n "$NAMESPACE" -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN ; echo \"=== Migration User ===\" ; vault read auth/userpass/users/vault-secrets-migration-user ; echo \"\" ; echo \"=== Management User ===\" ; vault read auth/userpass/users/vault-secrets-management-user" >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "✓ User policy updates completed"
    log_message "INFO" "Both users now have vault-admin-policy (full admin access: create, read, update, delete, list, sudo on all paths)"
    
    return 0
}

# Default config file
CONFIG_FILE="${1:-config.json}"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Usage: $0 <config-file> [root-token]"
    echo "Example: $0 config-vault-1.json hvs.xxxxx"
    echo "Or set VAULT_ROOT_TOKEN environment variable"
    exit 1
fi

# Parse configuration using jq
BASE_PATH=$(jq -r '.directories.basePath // "/jenkins_home/vault-cluster-setup"' "$CONFIG_FILE" 2>/dev/null || echo "/jenkins_home/vault-cluster-setup")
POST_INSTALL_DIR=$(jq -r '.directories.postInstall' "$CONFIG_FILE")
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

# Get absolute path of log file to use after directory changes
LOG_FILE="$(cd "$(dirname "$LOG_FILE")" && pwd)/$(basename "$LOG_FILE")"

# Define consistent post-install release name
POST_INSTALL_RELEASE="${RELEASE_NAME}-post-install"

write_section_header "VAULT POST-INSTALLATION"

log_message "INFO" "Post-Install Directory: $POST_INSTALL_DIR"
log_message "INFO" "Namespace: $NAMESPACE"

# Determine deployment mode based on namespace
if [[ "$NAMESPACE" == "unsealer-vault" ]]; then
    DEPLOYMENT_MODE="unsealerVaultClusterSetup"
    UNSEALER_VAULT_URL=""
    VAULT_CLUSTER_NAMESPACES="vault-1"  # Data vaults managed by unsealer
    log_message "INFO" "Deployment Mode: $DEPLOYMENT_MODE (unsealer vault)"
    log_message "INFO" "Managed Vault Namespaces: $VAULT_CLUSTER_NAMESPACES"
else
    DEPLOYMENT_MODE="vaultClusterSetup"
    UNSEALER_VAULT_URL="https://vault-active.unsealer-vault.svc.cluster.local:8200"
    VAULT_CLUSTER_NAMESPACES=""  # Empty for data vaults
    log_message "INFO" "Deployment Mode: $DEPLOYMENT_MODE (data vault with transit auto-unseal)"
    log_message "INFO" "Unsealer Vault URL: $UNSEALER_VAULT_URL"
fi

# Navigate to post-install directory
POST_INSTALL_PATH="$BASE_PATH/$POST_INSTALL_DIR"
log_message "INFO" "Checking post-install directory: $POST_INSTALL_PATH"

if [[ ! -d "$POST_INSTALL_PATH" ]]; then
    log_message "ERROR" "Post-install directory not found: $POST_INSTALL_PATH"
    exit 1
fi

log_message "INFO" "Post-install directory found"

# List contents
log_message "INFO" "Listing post-install directory contents..."
ls -la "$POST_INSTALL_PATH" | tee -a "$LOG_FILE"

# Detect Helm chart (either .tgz or unpacked Chart.yaml)
log_message "INFO" "Detecting post-install Helm chart..."
CHART_SOURCE=""

# Check for .tgz chart files
TGZ_CHARTS=($(find "$POST_INSTALL_PATH" -maxdepth 1 -type f -name "*.tgz" 2>/dev/null))

if [[ ${#TGZ_CHARTS[@]} -gt 0 ]]; then
    # If multiple .tgz files, use the most recently modified one
    if [[ ${#TGZ_CHARTS[@]} -gt 1 ]]; then
        log_message "WARN" "Multiple .tgz files found, using most recent:"
        ls -lt "$POST_INSTALL_PATH"/*.tgz | head -n 5 | tee -a "$LOG_FILE"
        CHART_SOURCE=$(ls -t "$POST_INSTALL_PATH"/*.tgz | head -n 1)
    else
        CHART_SOURCE="${TGZ_CHARTS[0]}"
    fi
    log_message "INFO" "Using packaged Helm chart: $(basename "$CHART_SOURCE")"
    
    # Build Helm arguments array
    HELM_ARGS=("upgrade" "--install" "$POST_INSTALL_RELEASE" "$CHART_SOURCE" "--namespace" "$NAMESPACE")
    
    # Check if values.yaml exists
    if [[ -f "$POST_INSTALL_PATH/values.yaml" ]]; then
        log_message "INFO" "Using custom values.yaml"
        HELM_ARGS+=("--values" "$POST_INSTALL_PATH/values.yaml")
    fi
    
    # Override deployment mode dynamically
    HELM_ARGS+=("--set" "vaultPostInstallJob.deploymentMode=$DEPLOYMENT_MODE")
    
    # Set vault cluster namespaces
    if [[ -n "$VAULT_CLUSTER_NAMESPACES" ]]; then
        HELM_ARGS+=("--set" "vaultPostInstallJob.vaultClusterNamespaces=$VAULT_CLUSTER_NAMESPACES")
    fi
    
    # Set unsealer vault URL for data vaults
    if [[ -n "$UNSEALER_VAULT_URL" ]]; then
        HELM_ARGS+=("--set" "vaultClusterSecretEncryptionConfig.transit.unsealerVaultUrl=$UNSEALER_VAULT_URL")
    fi
    
    HELM_ARGS+=("--timeout" "$HELM_TIMEOUT" "--wait")
    
    # Install post-install chart
    log_message "INFO" "Running post-installation with Helm (release: $POST_INSTALL_RELEASE)..."
    
    if helm "${HELM_ARGS[@]}" >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "✓ Post-installation completed successfully"
    else
        log_message "ERROR" "✗ Post-installation failed"
        exit 1
    fi
    
elif [[ -f "$POST_INSTALL_PATH/Chart.yaml" ]]; then
    log_message "INFO" "Using unpacked Helm chart directory"
    CHART_SOURCE="$POST_INSTALL_PATH"
    
    # Build Helm arguments array
    HELM_ARGS=("upgrade" "--install" "$POST_INSTALL_RELEASE" "." "--namespace" "$NAMESPACE")
    
    # Check if values.yaml exists
    if [[ -f "$POST_INSTALL_PATH/values.yaml" ]]; then
        log_message "INFO" "Using custom values.yaml"
        HELM_ARGS+=("--values" "$POST_INSTALL_PATH/values.yaml")
    fi
    
    # Override deployment mode dynamically
    HELM_ARGS+=("--set" "vaultPostInstallJob.deploymentMode=$DEPLOYMENT_MODE")
    
    # Set vault cluster namespaces
    if [[ -n "$VAULT_CLUSTER_NAMESPACES" ]]; then
        HELM_ARGS+=("--set" "vaultPostInstallJob.vaultClusterNamespaces=$VAULT_CLUSTER_NAMESPACES")
    fi
    
    # Set unsealer vault URL for data vaults
    if [[ -n "$UNSEALER_VAULT_URL" ]]; then
        HELM_ARGS+=("--set" "vaultClusterSecretEncryptionConfig.transit.unsealerVaultUrl=$UNSEALER_VAULT_URL")
    fi
    
    HELM_ARGS+=("--timeout" "$HELM_TIMEOUT" "--wait")
    
    # Install post-install chart
    log_message "INFO" "Running post-installation with Helm (release: $POST_INSTALL_RELEASE)..."
    cd "$POST_INSTALL_PATH"
    
    if helm "${HELM_ARGS[@]}" >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "✓ Post-installation completed successfully"
    else
        log_message "ERROR" "✗ Post-installation failed"
        exit 1
    fi
    
else
    log_message "WARN" "No Helm chart found. Checking for post-install scripts..."
    
    # Look for post-install script
    POST_SCRIPT=$(find "$POST_INSTALL_PATH" -maxdepth 2 -type f \( -name 'post-install.sh' -o -name 'configure.sh' -o -name 'setup.sh' \) | head -1)
    
    if [[ -n "$POST_SCRIPT" ]]; then
        log_message "INFO" "Found post-install script: $POST_SCRIPT"
        
        # Run post-install script
        chmod +x "$POST_SCRIPT"
        cd "$POST_INSTALL_PATH"
        
        if bash "$POST_SCRIPT" >> "$LOG_FILE" 2>&1; then
            log_message "INFO" "✓ Post-install script executed successfully"
        else
            log_message "ERROR" "✗ Post-install script failed"
            exit 1
        fi
    else
        log_message "WARN" "No automated post-install found."
    fi
fi

# Verify OpenShift Route and display access information
log_message "INFO" "Verifying OpenShift Route for external access..."

# Get route name from config
ROUTE_NAME=$(jq -r '.deployment.routeName // "vault"' "$CONFIG_FILE")

ROUTE_HOST=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)

if [[ -n "$ROUTE_HOST" ]]; then
    log_message "INFO" "✓ Vault Route is active"
    log_message "INFO" "Vault External URL: https://$ROUTE_HOST"
    log_message "INFO" "Use this URL to access Vault UI and API from outside the cluster"
else
    log_message "WARN" "Route not found or not accessible yet"
    log_message "INFO" "Route should have been created during prerequisites phase"
fi

# Check Vault initialization status
log_message "INFO" "Checking Vault initialization status..."

POD_NAME=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "$POD_NAME" ]]; then
    log_message "INFO" "Vault pod: $POD_NAME"
    
    log_message "INFO" "Vault status:"
    oc exec -n "$NAMESPACE" "$POD_NAME" -- vault status >> "$LOG_FILE" 2>&1 || log_message "WARN" "Vault may not be initialized yet"
    
    # Check if Vault is initialized and update user policies if ROOT_TOKEN is provided
    if oc exec -n "$NAMESPACE" "$POD_NAME" -- vault status 2>&1 | grep -q "Initialized.*true"; then
        log_message "INFO" "Vault is initialized"
        
        # Only update user policies for data vaults (not unsealer-vault)
        if [[ "$NAMESPACE" != "unsealer-vault" ]]; then
            # Check if ROOT_TOKEN is provided via environment variable or second argument
            ROOT_TOKEN="${VAULT_ROOT_TOKEN:-${2:-}}"
            
            if [[ -n "$ROOT_TOKEN" ]]; then
                log_message "INFO" "Root token provided, updating user admin policies..."
                update_user_admin_policies "$NAMESPACE" "$ROOT_TOKEN" "$LOG_FILE"
            else
                log_message "INFO" "No root token provided, skipping user policy updates"
                log_message "INFO" "To update user policies, run:"
                log_message "INFO" "  export VAULT_ROOT_TOKEN=<your-root-token>"
                log_message "INFO" "  $0 $CONFIG_FILE"
                log_message "INFO" "Or provide as second argument: $0 $CONFIG_FILE <root-token>"
            fi
        else
            log_message "INFO" "Unsealer vault detected - user policy updates not required"
        fi
    else
        log_message "WARN" "Vault not initialized yet, skipping user policy updates"
    fi
else
    log_message "WARN" "No Vault pods found"
fi

# Final verification
log_message "INFO" "Final cluster verification..."
oc get all -n "$NAMESPACE" >> "$LOG_FILE" 2>&1

write_section_header "POST-INSTALLATION COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next Steps:"
if [[ -z "$ROOT_TOKEN" ]]; then
    log_message "INFO" "  1. Initialize Vault: oc exec -n $NAMESPACE $POD_NAME -- vault operator init"
    log_message "INFO" "  2. Save unseal keys and root token securely"
    log_message "INFO" "  3. Unseal Vault: oc exec -n $NAMESPACE $POD_NAME -- vault operator unseal <key>"
    log_message "INFO" "  4. Update user policies: $0 $CONFIG_FILE <root-token>"
    log_message "INFO" "  5. Access Vault UI: https://$ROUTE_HOST (if route is configured)"
else
    log_message "INFO" "  ✓ User admin policies updated successfully"
    log_message "INFO" "  - vault-secrets-migration-user: vault-admin-policy"
    log_message "INFO" "  - vault-secrets-management-user: vault-admin-policy"
    log_message "INFO" "  Access Vault UI: https://$ROUTE_HOST (if route is configured)"
fi

exit 0


