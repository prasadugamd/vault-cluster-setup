#!/bin/bash
# deploy-prerequisites.sh
# Script to deploy Vault Helm prerequisites

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Default config file
CONFIG_FILE="${1:-config-bash.json}"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Parse configuration using jq
BASE_PATH=$(jq -r '.directories.basePath // "/jenkins_home/vault-cluster-setup"' "$CONFIG_FILE" 2>/dev/null || echo "/jenkins_home/vault-cluster-setup")
PREREQ_DIR=$(jq -r '.directories.prerequisite' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Hardcoded namespace for prerequisites to avoid conflicts
PREREQ_NAMESPACE="ms360-platform-crd"

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

# Get absolute path of log file to use after directory changes
LOG_FILE="$(cd "$(dirname "$LOG_FILE")" && pwd)/$(basename "$LOG_FILE")"

write_section_header "VAULT HELM PREREQUISITES DEPLOYMENT"

log_message "INFO" "Base Path: $BASE_PATH"
log_message "INFO" "Prerequisite Directory: $PREREQ_DIR"
log_message "INFO" "Target Namespace: $PREREQ_NAMESPACE"

# Navigate to prerequisite directory
PREREQ_PATH="$BASE_PATH/$PREREQ_DIR"
log_message "INFO" "Checking prerequisite directory: $PREREQ_PATH"

if [[ ! -d "$PREREQ_PATH" ]]; then
    log_message "ERROR" "Prerequisite directory not found: $PREREQ_PATH"
    exit 1
fi

log_message "INFO" "Prerequisite directory found"

# List contents of prerequisite directory
log_message "INFO" "Listing prerequisite directory contents..."
ls -la "$PREREQ_PATH" | tee -a "$LOG_FILE"

# Check for Helm chart (directory or packaged .tgz)
log_message "INFO" "Checking for Helm chart..."

# Find .tgz chart package or Chart.yaml
TGZ_CHARTS=($(find "$PREREQ_PATH" -maxdepth 1 -type f -name "*.tgz"))
TGZ_COUNT=${#TGZ_CHARTS[@]}

if [[ -f "$PREREQ_PATH/Chart.yaml" ]] || [[ $TGZ_COUNT -gt 0 ]]; then
    if [[ $TGZ_COUNT -gt 0 ]]; then
        if [[ $TGZ_COUNT -gt 1 ]]; then
            log_message "WARN" "Multiple .tgz files found ($TGZ_COUNT files). Using most recent one."
            # Sort by modification time and pick the newest
            TGZ_CHART=$(ls -t "$PREREQ_PATH"/*.tgz 2>/dev/null | head -1)
        else
            TGZ_CHART="${TGZ_CHARTS[0]}"
        fi
        log_message "INFO" "Packaged Helm chart detected: $(basename "$TGZ_CHART")"
        CHART_PATH="$TGZ_CHART"
    else
        log_message "INFO" "Helm chart directory detected"
        CHART_PATH="."
    fi
    
    # Check for values files
    VALUES_FLAG=""
    if [[ -f "$PREREQ_PATH/custom-values.yaml" ]]; then
        log_message "INFO" "Found custom-values.yaml"
        VALUES_FLAG="-f $PREREQ_PATH/custom-values.yaml"
    fi
    
    if [[ -z "$VALUES_FLAG" ]]; then
        log_message "WARN" "No values files found, using default Helm chart values"
    else
        log_message "INFO" "Using values files:$VALUES_FLAG"
    fi
    
    # Install prerequisites using Helm
    log_message "INFO" "Installing prerequisites with Helm..."
    cd "$PREREQ_PATH"
    
    if helm upgrade --install fndsec-hashicorp-vault-helm-pre-requisite "$CHART_PATH" --namespace "$PREREQ_NAMESPACE" --create-namespace $VALUES_FLAG --timeout "$HELM_TIMEOUT" --wait >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "✓ Prerequisites installed successfully"
    else
        log_message "ERROR" "✗ Prerequisites installation failed"
        exit 1
    fi
    
else
    log_message "WARN" "No Helm chart found. Checking for shell scripts..."
    
    # Look for setup.sh or install.sh
    SETUP_SCRIPT=$(find "$PREREQ_PATH" -maxdepth 2 -type f \( -name 'setup.sh' -o -name 'install.sh' -o -name 'deploy.sh' \) | head -1)
    
    if [[ -n "$SETUP_SCRIPT" ]]; then
        log_message "INFO" "Found setup script: $SETUP_SCRIPT"
        
        # Make executable and run
        chmod +x "$SETUP_SCRIPT"
        if bash "$SETUP_SCRIPT" >> "$LOG_FILE" 2>&1; then
            log_message "INFO" "✓ Setup script executed successfully"
        else
            log_message "ERROR" "✗ Setup script failed"
            exit 1
        fi
    else
        log_message "ERROR" "No Helm chart or setup script found in prerequisite directory"
        exit 1
    fi
fi

# Verify deployment
log_message "INFO" "Verifying prerequisite deployment..."
oc get all -n "$PREREQ_NAMESPACE" >> "$LOG_FILE" 2>&1

write_section_header "PREREQUISITES DEPLOYMENT COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"

exit 0


