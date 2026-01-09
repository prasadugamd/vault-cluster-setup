#!/bin/bash
# create-namespace-route.sh
# Script to create namespace and OpenShift route for Vault

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Default config files
if [[ $# -eq 0 ]]; then
    CONFIG_FILES=("config-unsealer-vault.json" "config-vault-1.json")
else
    CONFIG_FILES=("$@")
fi

# Validate all config files exist
for config in "${CONFIG_FILES[@]}"; do
    if [[ ! -f "$config" ]]; then
        echo "ERROR: Configuration file not found: $config"
        exit 1
    fi
done

# Validate all config files exist
for config in "${CONFIG_FILES[@]}"; do
    if [[ ! -f "$config" ]]; then
        echo "ERROR: Configuration file not found: $config"
        exit 1
    fi
done

# Initialize logger (use first config for log settings)
FIRST_CONFIG="${CONFIG_FILES[0]}"
LOG_DIR=$(jq -r '.logging.logDir' "$FIRST_CONFIG")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$FIRST_CONFIG")
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

write_section_header "NAMESPACE AND ROUTE CREATION"

log_message "INFO" "Processing ${#CONFIG_FILES[@]} configuration file(s)"

# Process each config file
for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    log_message "INFO" "Processing configuration: $CONFIG_FILE"
    echo ""
    
    # Parse configuration using jq
    NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
    RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
    ROUTE_NAME=$(jq -r '.deployment.routeName // "vault"' "$CONFIG_FILE")
    ROUTE_URL=$(jq -r '.deployment.routeUrl // ""' "$CONFIG_FILE")
    
    log_message "INFO" "  Namespace: $NAMESPACE"
    log_message "INFO" "  Route Name: $ROUTE_NAME (will be created by Helm chart)"
    
    # Create namespace if not exists
    log_message "INFO" "  Creating namespace: $NAMESPACE"
    if oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "  ✓ Namespace created/verified: $NAMESPACE"
    else
        log_message "ERROR" "  ✗ Failed to create namespace: $NAMESPACE"
        exit 1
    fi
    
    # Route creation is disabled - routes will be created by Helm chart in deploy-vault-cluster.sh
    log_message "INFO" "  ⓘ Route creation skipped - will be created by Helm chart deployment"
    if [[ -n "$ROUTE_URL" ]]; then
        log_message "INFO" "  Route URL configured: $ROUTE_URL (will be applied during Helm install)"
    fi
    
    # Commenting out route creation - now handled by Helm chart
    # # Create OpenShift Route for Vault
    # log_message "INFO" "  Creating OpenShift Route for Vault external access..."
    # 
    # if [[ -n "$ROUTE_URL" ]]; then
    #     log_message "INFO" "  Route URL: $ROUTE_URL"
    # fi
    # 
    # # Create route YAML and apply
    # if [[ -n "$ROUTE_URL" ]]; then
    #     # Create route with custom host
    #     oc apply -f - >> "$LOG_FILE" 2>&1 <<EOF
    # apiVersion: route.openshift.io/v1
    # kind: Route
    # metadata:
    #   name: $ROUTE_NAME
    #   namespace: $NAMESPACE
    #   labels:
    #     app.kubernetes.io/instance: $RELEASE_NAME
    #     app.kubernetes.io/managed-by: Helm
    #     app.kubernetes.io/name: vault
    # spec:
    #   host: $ROUTE_URL
    #   to:
    #     kind: Service
    #     name: vault-active
    #     weight: 100
    #   port:
    #     targetPort: 8200
    #   tls:
    #     termination: passthrough
    #   wildcardPolicy: None
    # EOF
    # else
    #     # Create route without custom host (OpenShift will assign)
    #     oc apply -f - >> "$LOG_FILE" 2>&1 <<EOF
    # apiVersion: route.openshift.io/v1
    # kind: Route
    # metadata:
    #   name: $ROUTE_NAME
    #   namespace: $NAMESPACE
    #   labels:
    #     app.kubernetes.io/instance: $RELEASE_NAME
    #     app.kubernetes.io/managed-by: Helm
    #     app.kubernetes.io/name: vault
    # spec:
    #   to:
    #     kind: Service
    #     name: vault-active
    #     weight: 100
    #   port:
    #     targetPort: 8200
    #   tls:
    #     termination: passthrough
    #   wildcardPolicy: None
    # EOF
    # fi
    # 
    # if [[ $? -eq 0 ]]; then
    #     log_message "INFO" "  ✓ OpenShift Route created successfully"
    #     
    #     # Get route details (may not have hostname yet until service exists)
    #     ROUTE_HOST=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route created, hostname will be assigned when service is available")
    #     log_message "INFO" "  Route: $ROUTE_HOST"
    # else
    #     log_message "WARN" "  Route creation failed or already exists"
    # fi
    
    echo ""
done

write_section_header "NAMESPACE AND ROUTE CREATION COMPLETED"
log_message "INFO" "Log file: $(get_log_file_path)"

exit 0
