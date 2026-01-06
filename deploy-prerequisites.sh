#!/bin/bash
# deploy-prerequisites.sh
# Script to deploy Vault Helm prerequisites

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
PREREQ_DIR=$(jq -r '.directories.prerequisite' "$CONFIG_FILE")
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
HELM_TIMEOUT=$(jq -r '.deployment.helmTimeout // "10m"' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

write_section_header "VAULT HELM PREREQUISITES DEPLOYMENT"

log_message "INFO" "Base Path: $BASE_PATH"
log_message "INFO" "Prerequisite Directory: $PREREQ_DIR"
log_message "INFO" "Namespace: $NAMESPACE"

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

# Check for Helm chart
log_message "INFO" "Checking for Helm chart..."
if [[ -f "$PREREQ_PATH/Chart.yaml" ]]; then
    log_message "INFO" "Helm chart detected in prerequisite directory"
    
    # Create namespace if not exists
    log_message "INFO" "Creating namespace: $NAMESPACE"
    oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - 2>&1 | tee -a "$LOG_FILE"
    
    # Create OpenShift Route for Vault (before prerequisites installation)
    log_message "INFO" "Creating OpenShift Route for Vault external access..."
    
    # Get route configuration from config file
    ROUTE_NAME=$(jq -r '.deployment.routeName // "vault"' "$CONFIG_FILE")
    ROUTE_URL=$(jq -r '.deployment.routeUrl // ""' "$CONFIG_FILE")
    
    log_message "INFO" "Route name: $ROUTE_NAME"
    if [[ -n "$ROUTE_URL" ]]; then
        log_message "INFO" "Route URL: $ROUTE_URL"
    fi
    
    # Create route YAML and apply
    if [[ -n "$ROUTE_URL" ]]; then
        # Create route with custom host
        oc apply -f - 2>&1 | tee -a "$LOG_FILE" <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $ROUTE_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/instance: $RELEASE_NAME
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: vault
spec:
  host: $ROUTE_URL
  to:
    kind: Service
    name: vault-active
    weight: 100
  port:
    targetPort: 8200
  tls:
    termination: passthrough
  wildcardPolicy: None
EOF
    else
        # Create route without custom host (OpenShift will assign)
        oc apply -f - 2>&1 | tee -a "$LOG_FILE" <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $ROUTE_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/instance: $RELEASE_NAME
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: vault
spec:
  to:
    kind: Service
    name: vault-active
    weight: 100
  port:
    targetPort: 8200
  tls:
    termination: passthrough
  wildcardPolicy: None
EOF
    fi
    
    if [[ $? -eq 0 ]]; then
        log_message "INFO" "✓ OpenShift Route created successfully"
        
        # Get route details (may not have hostname yet until service exists)
        ROUTE_HOST=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route created, hostname will be assigned when service is available")
        log_message "INFO" "Route: $ROUTE_HOST"
    else
        log_message "WARN" "Route creation failed or already exists (will retry after service creation)"
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
    
    if helm upgrade --install fndsec-hashicorp-vault-helm-pre-requisite . --namespace "ms360-platform-crd" $VALUES_FLAG --timeout "$HELM_TIMEOUT" --wait 2>&1 | tee -a "$LOG_FILE"; then
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
        if bash "$SETUP_SCRIPT" 2>&1 | tee -a "$LOG_FILE"; then
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
oc get all -n "$NAMESPACE" 2>&1 | tee -a "$LOG_FILE"

write_section_header "PREREQUISITES DEPLOYMENT COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"

exit 0

