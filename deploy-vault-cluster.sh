#!/bin/bash
# deploy-vault-cluster.sh
# Script to deploy HashiCorp Vault Cluster

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Function to initialize and unseal unsealer vault
initialize_unsealer_vault() {
    local NAMESPACE="$1"
    local LOG_FILE="$2"
    local INIT_FILE="${3:-/tmp/vault-init-keys.json}"
    
    log_message "INFO" "Initializing unsealer vault in namespace: $NAMESPACE"
    
    # Check if vault is already initialized
    if oc exec vault-0 -n "$NAMESPACE" -- vault status 2>&1 | grep -q "Initialized.*true"; then
        log_message "WARN" "Vault already initialized in $NAMESPACE"
        if [[ -f "$INIT_FILE" ]]; then
            log_message "INFO" "Using existing init file: $INIT_FILE"
            return 0
        else
            log_message "ERROR" "Vault is initialized but init file not found: $INIT_FILE"
            return 1
        fi
    fi
    
    # Initialize vault with 5 key shares and 3 threshold
    log_message "INFO" "Initializing Vault with 5 key shares, 3 threshold..."
    if oc exec vault-0 -n "$NAMESPACE" -- vault operator init -key-shares=5 -key-threshold=3 -format=json > "$INIT_FILE" 2>&1; then
        log_message "INFO" "✓ Vault initialized successfully"
        log_message "INFO" "Init keys saved to: $INIT_FILE"
    else
        log_message "ERROR" "✗ Vault initialization failed"
        return 1
    fi
    
    # Extract unseal keys
    KEY1=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
    KEY2=$(jq -r '.unseal_keys_b64[1]' "$INIT_FILE")
    KEY3=$(jq -r '.unseal_keys_b64[2]' "$INIT_FILE")
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    
    log_message "INFO" "Root Token: $ROOT_TOKEN"
    
    # Unseal all vault pods
    for POD in vault-0 vault-1 vault-2; do
        log_message "INFO" "Unsealing $POD..."
        oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY1" >> "$LOG_FILE" 2>&1
        oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY2" >> "$LOG_FILE" 2>&1
        oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY3" >> "$LOG_FILE" 2>&1
        log_message "INFO" "✓ $POD unsealed"
    done
    
    # Verify cluster status
    log_message "INFO" "Verifying vault cluster status..."
    oc get pods -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    oc exec vault-0 -n "$NAMESPACE" -- vault status >> "$LOG_FILE" 2>&1
    
    # Login with root token
    log_message "INFO" "Logging in with root token..."
    oc exec vault-0 -n "$NAMESPACE" -- vault login "$ROOT_TOKEN" >> "$LOG_FILE" 2>&1
    
    # Check raft peers
    log_message "INFO" "Checking Raft cluster peers..."
    oc exec vault-0 -n "$NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault operator raft list-peers >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "✓ Unsealer vault initialized and unsealed successfully"
    return 0
}

# Function to setup transit auto-unseal on unsealer vault
setup_transit_autounseal() {
    local UNSEALER_NAMESPACE="$1"
    local DATA_NAMESPACE="$2"
    local LOG_FILE="$3"
    local UNSEALER_INIT_FILE="${4:-/tmp/vault-init-keys.json}"
    local TRANSIT_KEY="${5:-autounseal_1}"
    
    log_message "INFO" "Setting up Transit auto-unseal for $DATA_NAMESPACE"
    
    # Get root token from unsealer vault
    if [[ ! -f "$UNSEALER_INIT_FILE" ]]; then
        log_message "ERROR" "Unsealer vault init file not found: $UNSEALER_INIT_FILE"
        return 1
    fi
    
    ROOT_TOKEN=$(jq -r '.root_token' "$UNSEALER_INIT_FILE")
    
    # Enable transit secrets engine
    log_message "INFO" "Enabling transit secrets engine..."
    if oc exec vault-0 -n "$UNSEALER_NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable transit 2>&1 | grep -q "path is already in use"; then
        log_message "WARN" "Transit engine already enabled"
    else
        log_message "INFO" "✓ Transit engine enabled"
    fi
    
    # Create transit encryption key
    log_message "INFO" "Creating transit key: $TRANSIT_KEY"
    oc exec vault-0 -n "$UNSEALER_NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault write -f "transit/keys/$TRANSIT_KEY" >> "$LOG_FILE" 2>&1
    
    # Create autounseal policy
    log_message "INFO" "Creating autounseal policy..."
    POLICY_FILE="/tmp/autounseal-policy-$DATA_NAMESPACE.hcl"
    cat > "$POLICY_FILE" << EOF
path "transit/encrypt/$TRANSIT_KEY" {
  capabilities = [ "update" ]
}

path "transit/decrypt/$TRANSIT_KEY" {
  capabilities = [ "update" ]
}
EOF
    
    oc exec vault-0 -n "$UNSEALER_NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault policy write autounseal - < "$POLICY_FILE" >> "$LOG_FILE" 2>&1
    log_message "INFO" "✓ Autounseal policy created"
    
    # Create token for autounseal
    log_message "INFO" "Creating autounseal token..."
    TOKEN_FILE="/tmp/${DATA_NAMESPACE}-autounseal-token.json"
    oc exec vault-0 -n "$UNSEALER_NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault token create -policy=autounseal -orphan -format=json > "$TOKEN_FILE" 2>&1
    
    TRANSIT_TOKEN=$(jq -r '.auth.client_token' "$TOKEN_FILE")
    if [[ -z "$TRANSIT_TOKEN" || "$TRANSIT_TOKEN" == "null" ]]; then
        log_message "ERROR" "Failed to create transit token"
        return 1
    fi
    
    log_message "INFO" "Transit Token: $TRANSIT_TOKEN"
    
    # Create secret in data vault namespace
    log_message "INFO" "Creating vault-transit-token-secret in $DATA_NAMESPACE..."
    oc create secret generic vault-transit-token-secret \
        --from-literal=token="$TRANSIT_TOKEN" \
        -n "$DATA_NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f - >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "✓ Transit auto-unseal configured successfully"
    return 0
}

# Function to initialize vault with transit auto-unseal (data vault)
initialize_data_vault() {
    local NAMESPACE="$1"
    local LOG_FILE="$2"
    local INIT_FILE="${3:-/tmp/${NAMESPACE}-init-keys.json}"
    
    log_message "INFO" "Initializing data vault in namespace: $NAMESPACE"
    
    # Check if vault is already initialized
    if oc exec vault-0 -n "$NAMESPACE" -- vault status 2>&1 | grep -q "Initialized.*true"; then
        log_message "WARN" "Vault already initialized in $NAMESPACE"
        if [[ -f "$INIT_FILE" ]]; then
            log_message "INFO" "Using existing init file: $INIT_FILE"
            return 0
        else
            log_message "ERROR" "Vault is initialized but init file not found: $INIT_FILE"
            return 1
        fi
    fi
    
    # Initialize with recovery keys (transit auto-unseal)
    log_message "INFO" "Initializing Vault with transit auto-unseal (recovery keys)..."
    if oc exec vault-0 -n "$NAMESPACE" -- vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json > "$INIT_FILE" 2>&1; then
        log_message "INFO" "✓ Vault initialized successfully with transit auto-unseal"
        log_message "INFO" "Recovery keys saved to: $INIT_FILE"
    else
        log_message "ERROR" "✗ Vault initialization failed"
        return 1
    fi
    
    # Extract root token
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    log_message "INFO" "Root Token: $ROOT_TOKEN"
    
    # Wait for pods to be ready
    sleep 5
    
    # Verify vault status
    log_message "INFO" "Verifying vault status..."
    oc get pods -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    oc exec vault-0 -n "$NAMESPACE" -- vault status >> "$LOG_FILE" 2>&1
    
    # Login with root token
    log_message "INFO" "Logging in with root token..."
    oc exec vault-0 -n "$NAMESPACE" -- vault login "$ROOT_TOKEN" >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "✓ Data vault initialized successfully"
    return 0
}

# Function to enable basic vault features
enable_vault_features() {
    local NAMESPACE="$1"
    local LOG_FILE="$2"
    local INIT_FILE="$3"
    
    log_message "INFO" "Enabling basic Vault features in $NAMESPACE"
    
    # Get root token
    if [[ ! -f "$INIT_FILE" ]]; then
        log_message "ERROR" "Init file not found: $INIT_FILE"
        return 1
    fi
    
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    
    # Enable KV v2 secrets engine
    log_message "INFO" "Enabling KV v2 secrets engine..."
    if oc exec vault-0 -n "$NAMESPACE" -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2 2>&1 | grep -q "path is already in use"; then
        log_message "WARN" "KV v2 engine already enabled"
    else
        log_message "INFO" "✓ KV v2 secrets engine enabled"
    fi
    
    log_message "INFO" "✓ Basic features enabled successfully"
    return 0
}

# Function to deploy a single vault cluster
deploy_vault_cluster() {
    local CONFIG_FILE="$1"
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Parse configuration using jq
    BASE_PATH=$(jq -r '.directories.basePath // "/jenkins_home/vault-cluster-setup"' "$CONFIG_FILE" 2>/dev/null || echo "/jenkins_home/vault-cluster-setup")
    CLUSTER_DIR=$(jq -r '.directories.cluster' "$CONFIG_FILE")
    NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
    RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
    ROUTE_URL=$(jq -r '.deployment.routeUrl // ""' "$CONFIG_FILE")
    HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
    LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
    LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")
    
    # Initialize logger
    initialize_logger "$LOG_DIR" "$LOG_LEVEL"
    
    # Get absolute path of log file to use after directory changes
    LOG_FILE="$(cd "$(dirname "$LOG_FILE")" && pwd)/$(basename "$LOG_FILE")"
    
    write_section_header "VAULT CLUSTER DEPLOYMENT - $NAMESPACE"
    
    log_message "INFO" "Config File: $CONFIG_FILE"
    log_message "INFO" "Cluster Directory: $CLUSTER_DIR"
    log_message "INFO" "Namespace: $NAMESPACE"
    log_message "INFO" "Release Name: $RELEASE_NAME"
    
    # Navigate to cluster directory
    CLUSTER_PATH="$BASE_PATH/$CLUSTER_DIR"
    log_message "INFO" "Checking cluster directory: $CLUSTER_PATH"
    
    if [[ ! -d "$CLUSTER_PATH" ]]; then
        log_message "ERROR" "Cluster directory not found: $CLUSTER_PATH"
        return 1
    fi
    
    log_message "INFO" "Cluster directory found"
    
    # List contents
    log_message "INFO" "Listing cluster directory contents..."
    ls -la "$CLUSTER_PATH" | tee -a "$LOG_FILE"
    
    # Check for certificates
    log_message "INFO" "Checking for certificates..."
    CERT_DIR="$BASE_PATH/$NAMESPACE-certs"
    if [[ -d "$CERT_DIR" ]]; then
        log_message "INFO" "Certificate directory found: $CERT_DIR"
        log_message "INFO" "Certificates found:"
        ls -la "$CERT_DIR" | tee -a "$LOG_FILE"
        log_message "INFO" "TLS secret 'vault-server-tls' should already exist (created by generate-certificates.sh)"
    else
        log_message "WARN" "Certificate directory not found: $CERT_DIR"
        log_message "WARN" "Run generate-certificates.sh first to create certificates and TLS secret"
    fi
    
    # Detect Helm chart (either .tgz or unpacked Chart.yaml)
    log_message "INFO" "Detecting Helm chart..."
    CHART_SOURCE=""
    
    # Check for .tgz chart files
    TGZ_CHARTS=($(find "$CLUSTER_PATH" -maxdepth 1 -type f -name "*.tgz" 2>/dev/null))
    
    if [[ ${#TGZ_CHARTS[@]} -gt 0 ]]; then
        # If multiple .tgz files, use the most recently modified one
        if [[ ${#TGZ_CHARTS[@]} -gt 1 ]]; then
            log_message "WARN" "Multiple .tgz files found, using most recent:"
            ls -lt "$CLUSTER_PATH"/*.tgz | head -n 5 | tee -a "$LOG_FILE"
            CHART_SOURCE=$(ls -t "$CLUSTER_PATH"/*.tgz | head -n 1)
        else
            CHART_SOURCE="${TGZ_CHARTS[0]}"
        fi
        log_message "INFO" "Using packaged Helm chart: $(basename "$CHART_SOURCE")"
    elif [[ -f "$CLUSTER_PATH/Chart.yaml" ]]; then
        CHART_SOURCE="$CLUSTER_PATH"
        log_message "INFO" "Using unpacked Helm chart directory"
    else
        log_message "ERROR" "No Helm chart found in cluster directory"
        log_message "ERROR" "Expected either *.tgz file or Chart.yaml at: $CLUSTER_PATH"
        return 1
    fi
    
    # Check for values files
    VALUES_FLAG=""
    if [[ -f "$CLUSTER_PATH/custom-values.yaml" ]]; then
        log_message "INFO" "Found custom-values.yaml"
        VALUES_FLAG="$VALUES_FLAG -f $CLUSTER_PATH/custom-values.yaml"
    fi
    
    if [[ -f "$CLUSTER_PATH/values.openshift.yaml" ]]; then
        log_message "INFO" "Found values.openshift.yaml"
        VALUES_FLAG="$VALUES_FLAG -f $CLUSTER_PATH/values.openshift.yaml"
    fi
    
    if [[ -f "$CLUSTER_PATH/values.yaml" ]]; then
        log_message "INFO" "Found values.yaml"
        VALUES_FLAG="$VALUES_FLAG -f $CLUSTER_PATH/values.yaml"
    fi
    
    if [[ -z "$VALUES_FLAG" ]]; then
        log_message "WARN" "No values files found, using default Helm chart values"
    else
        log_message "INFO" "Using values files:$VALUES_FLAG"
    fi
    
    # Deploy Vault cluster
    log_message "INFO" "Deploying Vault cluster with Helm..."
    log_message "INFO" "Release Name: $RELEASE_NAME"
    log_message "INFO" "Namespace: $NAMESPACE"
    log_message "INFO" "Chart Source: $CHART_SOURCE"
    
    # Build Helm command with route override if routeUrl is specified
    HELM_EXTRA_ARGS=""
    if [[ -n "$ROUTE_URL" ]]; then
        HELM_EXTRA_ARGS="--set server.route.enabled=true --set server.route.host=$ROUTE_URL"
        log_message "INFO" "Route URL: $ROUTE_URL"
    fi
    
    if helm upgrade --install "$RELEASE_NAME" "$CHART_SOURCE" --namespace "$NAMESPACE" $VALUES_FLAG $HELM_EXTRA_ARGS --timeout "$HELM_TIMEOUT" --wait >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "✓ Vault cluster deployed successfully"
    else
        log_message "ERROR" "✗ Vault cluster deployment failed"
        log_message "ERROR" "Check log file for details: $LOG_FILE"
        return 1
    fi
    
    # Wait for pods to be ready
    log_message "INFO" "Waiting for Vault pods to be ready..."
    if oc wait --for=condition=Ready pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" --timeout=5m >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "✓ Vault pods are ready"
    else
        log_message "WARN" "Pods may still be initializing..."
    fi
    
    # Get pods status
    log_message "INFO" "Vault pods status:"
    oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide >> "$LOG_FILE" 2>&1
    
    # Get services
    log_message "INFO" "Vault services:"
    oc get svc -n "$NAMESPACE" -l app.kubernetes.io/name=vault >> "$LOG_FILE" 2>&1
    
    write_section_header "VAULT CLUSTER DEPLOYMENT COMPLETED - $NAMESPACE"
    log_message "INFO" "Log file: $(get_log_file_path)"
    log_message "INFO" ""
    log_message "INFO" "Next steps:"
    log_message "INFO" "  1. Run deploy-post-install.sh for post-installation tasks"
    log_message "INFO" "  2. Initialize Vault: oc exec -n $NAMESPACE vault-0 -- vault operator init"
    log_message "INFO" "  3. Unseal Vault nodes with the unseal keys"
    
    return 0
}

# Main execution
# Check if at least one config file is provided
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <config-file-1> [config-file-2] ..."
    echo "Example: $0 config-unsealer-vault.json config-vault-1.json"
    exit 1
fi

# Arrays to track deployments
declare -a SUCCESSFUL_DEPLOYMENTS=()
declare -a FAILED_DEPLOYMENTS=()

echo "========================================"
echo "VAULT CLUSTER MULTI-DEPLOYMENT"
echo "========================================"
echo "Total config files to process: $#"
echo ""

# Process each config file
for CONFIG_FILE in "$@"; do
    echo ""
    echo "========================================" 
    echo "Processing: $CONFIG_FILE"
    echo "========================================" 
    echo ""
    
    if deploy_vault_cluster "$CONFIG_FILE"; then
        SUCCESSFUL_DEPLOYMENTS+=("$CONFIG_FILE")
        echo "✓ SUCCESS: $CONFIG_FILE"
    else
        FAILED_DEPLOYMENTS+=("$CONFIG_FILE")
        echo "✗ FAILED: $CONFIG_FILE"
    fi
    
    echo ""
done

# Print summary
echo ""
echo "========================================"
echo "DEPLOYMENT SUMMARY"
echo "========================================"
echo "Total processed: $#"
echo "Successful: ${#SUCCESSFUL_DEPLOYMENTS[@]}"
echo "Failed: ${#FAILED_DEPLOYMENTS[@]}"
echo ""

if [[ ${#SUCCESSFUL_DEPLOYMENTS[@]} -gt 0 ]]; then
    echo "✓ Successful deployments:"
    for config in "${SUCCESSFUL_DEPLOYMENTS[@]}"; do
        echo "  - $config"
    done
    echo ""
fi

if [[ ${#FAILED_DEPLOYMENTS[@]} -gt 0 ]]; then
    echo "✗ Failed deployments:"
    for config in "${FAILED_DEPLOYMENTS[@]}"; do
        echo "  - $config"
    done
    echo ""
    exit 1
fi

echo "All deployments completed successfully!"
exit 0


