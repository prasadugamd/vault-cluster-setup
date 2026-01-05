#!/bin/bash
# deploy-vault-cluster.sh
# Script to deploy HashiCorp Vault Cluster

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Default config file
CONFIG_FILE="${1:-config.json}"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Parse configuration using jq
BASE_PATH=$(jq -r '.directories.basePath // "/jenkins/jenkins/PRASA"' "$CONFIG_FILE" 2>/dev/null || echo "/jenkins/jenkins/PRASA")
CLUSTER_DIR=$(jq -r '.directories.cluster' "$CONFIG_FILE")
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

write_section_header "VAULT CLUSTER DEPLOYMENT"

log_message "INFO" "Cluster Directory: $CLUSTER_DIR"
log_message "INFO" "Namespace: $NAMESPACE"
log_message "INFO" "Release Name: $RELEASE_NAME"

# Navigate to cluster directory
CLUSTER_PATH="$BASE_PATH/$CLUSTER_DIR"
log_message "INFO" "Checking cluster directory: $CLUSTER_PATH"

if [[ ! -d "$CLUSTER_PATH" ]]; then
    log_message "ERROR" "Cluster directory not found: $CLUSTER_PATH"
    exit 1
fi

log_message "INFO" "Cluster directory found"

# List contents
log_message "INFO" "Listing cluster directory contents..."
ls -la "$CLUSTER_PATH" | tee -a "$LOG_FILE"

# Check for Helm chart
log_message "INFO" "Checking for Helm chart..."
if [[ -f "$CLUSTER_PATH/Chart.yaml" ]]; then
    log_message "INFO" "Helm chart detected"
    
    # Ensure namespace exists
    log_message "INFO" "Ensuring namespace exists: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
    
    # Check for certificates
    log_message "INFO" "Checking for certificates..."
    if find "$CLUSTER_PATH" -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.key' \) | grep -q .; then
        log_message "INFO" "Certificates found:"
        find "$CLUSTER_PATH" -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.key' \) | tee -a "$LOG_FILE"
        
        # Create TLS secret if certificates exist
        CERT_DIR="$CLUSTER_PATH/certs"
        if [[ -d "$CERT_DIR" ]]; then
            log_message "INFO" "Creating/updating TLS secret from certificates..."
            kubectl create secret generic vault-tls -n "$NAMESPACE" \
                --from-file="$CERT_DIR" \
                --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
            log_message "INFO" "TLS secret created/updated"
        fi
    fi
    
    # Check for values.yaml
    VALUES_FLAG=""
    if [[ -f "$CLUSTER_PATH/values.yaml" ]]; then
        log_message "INFO" "Using custom values.yaml"
        VALUES_FLAG="-f $CLUSTER_PATH/values.yaml"
    fi
    
    # Deploy Vault cluster
    log_message "INFO" "Deploying Vault cluster with Helm..."
    cd "$CLUSTER_PATH"
    
    if helm upgrade --install "$RELEASE_NAME" . --namespace "$NAMESPACE" $VALUES_FLAG --timeout "$HELM_TIMEOUT" --wait 2>&1 | tee -a "$LOG_FILE"; then
        log_message "INFO" "✓ Vault cluster deployed successfully"
    else
        log_message "ERROR" "✗ Vault cluster deployment failed"
        exit 1
    fi
    
else
    log_message "ERROR" "No Helm chart found in cluster directory"
    log_message "ERROR" "Expected Chart.yaml at: $CLUSTER_PATH/Chart.yaml"
    exit 1
fi

# Wait for pods to be ready
log_message "INFO" "Waiting for Vault pods to be ready..."
if kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" --timeout=5m 2>&1 | tee -a "$LOG_FILE"; then
    log_message "INFO" "✓ Vault pods are ready"
else
    log_message "WARN" "Pods may still be initializing..."
fi

# Get pods status
log_message "INFO" "Vault pods status:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide 2>&1 | tee -a "$LOG_FILE"

# Get services
log_message "INFO" "Vault services:"
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=vault 2>&1 | tee -a "$LOG_FILE"

write_section_header "VAULT CLUSTER DEPLOYMENT COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next steps:"
log_message "INFO" "  1. Run deploy-post-install.sh for post-installation tasks"
log_message "INFO" "  2. Initialize Vault: kubectl exec -n $NAMESPACE vault-0 -- vault operator init"
log_message "INFO" "  3. Unseal Vault nodes with the unseal keys"

exit 0
