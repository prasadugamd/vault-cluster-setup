#!/bin/bash
# deploy-post-install.sh
# Script to run post-installation tasks

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
POST_INSTALL_DIR=$(jq -r '.directories.postInstall' "$CONFIG_FILE")
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

write_section_header "VAULT POST-INSTALLATION"

log_message "INFO" "Post-Install Directory: $POST_INSTALL_DIR"
log_message "INFO" "Namespace: $NAMESPACE"

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

# Check for Helm chart
log_message "INFO" "Checking for Helm chart..."
if [[ -f "$POST_INSTALL_PATH/Chart.yaml" ]]; then
    log_message "INFO" "Helm chart detected for post-installation"
    
    # Check if values.yaml exists
    VALUES_FLAG=""
    if [[ -f "$POST_INSTALL_PATH/values.yaml" ]]; then
        log_message "INFO" "Using custom values.yaml"
        VALUES_FLAG="-f $POST_INSTALL_PATH/values.yaml"
    fi
    
    # Install post-install chart
    log_message "INFO" "Running post-installation with Helm..."
    cd "$POST_INSTALL_PATH"
    
    if helm upgrade --install vault-post-install . --namespace "$NAMESPACE" $VALUES_FLAG --timeout "$HELM_TIMEOUT" --wait >> "$LOG_FILE" 2>&1; then
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
log_message "INFO" "  1. Initialize Vault: oc exec -n $NAMESPACE $POD_NAME -- vault operator init"
log_message "INFO" "  2. Save unseal keys and root token securely"
log_message "INFO" "  3. Unseal Vault: oc exec -n $NAMESPACE $POD_NAME -- vault operator unseal <key>"
log_message "INFO" "  4. Access Vault UI: https://$ROUTE_HOST (if route is configured)"

exit 0


