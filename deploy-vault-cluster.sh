#!/bin/bash
# deploy-vault-cluster.sh
# Script to deploy HashiCorp Vault Cluster

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

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


