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
    log_message "INFO" "Checking if namespace exists: $NAMESPACE"
    if oc get namespace "$NAMESPACE" &>/dev/null; then
        log_message "INFO" "✓ Namespace $NAMESPACE already exists"
    else
        log_message "INFO" "Creating namespace: $NAMESPACE"
        oc create namespace "$NAMESPACE" >> "$LOG_FILE" 2>&1
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "✓ Namespace created successfully"
        else
            log_message "ERROR" "✗ Failed to create namespace"
            exit 1
        fi
    fi
    
    # Check for certificates
    log_message "INFO" "Checking for certificates..."
    CERT_DIR="$BASE_PATH/$NAMESPACE-certs"
    if [[ -d "$CERT_DIR" ]]; then
        log_message "INFO" "Certificate directory found: $CERT_DIR"
        log_message "INFO" "Certificates found:"
        ls -la "$CERT_DIR" | tee -a "$LOG_FILE"
        
        # Create TLS secret if certificates exist
        log_message "INFO" "Creating/updating TLS secret from certificates..."
        oc create secret generic vault-tls -n "$NAMESPACE" \
            --from-file=ca.crt="$BASE_PATH/CA-certs/ca.crt" \
            --from-file=tls.crt="$CERT_DIR/vault.crt" \
            --from-file=tls.key="$CERT_DIR/vault.key" \
            --from-file=vault.crt="$CERT_DIR/vault.crt" \
            --from-file=vault.key="$CERT_DIR/vault.key" \
            --dry-run=client -o yaml | oc apply -f - >> "$LOG_FILE" 2>&1
        log_message "INFO" "TLS secret created/updated"
    else
        log_message "WARN" "Certificate directory not found: $CERT_DIR"
        log_message "WARN" "Run generate-certificates.sh first to create certificates"
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
    cd "$CLUSTER_PATH"
    
    if helm upgrade --install "$RELEASE_NAME" . --namespace "$NAMESPACE" $VALUES_FLAG --timeout "$HELM_TIMEOUT" --wait >> "$LOG_FILE" 2>&1; then
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

write_section_header "VAULT CLUSTER DEPLOYMENT COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next steps:"
log_message "INFO" "  1. Run deploy-post-install.sh for post-installation tasks"
log_message "INFO" "  2. Initialize Vault: oc exec -n $NAMESPACE vault-0 -- vault operator init"
log_message "INFO" "  3. Unseal Vault nodes with the unseal keys"

exit 0


