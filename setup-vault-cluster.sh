#!/bin/bash
# setup-vault-cluster.sh
# Main orchestration script for complete Vault cluster setup

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger module
source "$SCRIPT_DIR/modules/logger.sh"

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated HashiCorp Vault Cluster Setup on Kubernetes/OpenShift

OPTIONS:
    -c, --config FILE       Configuration file (default: config.json)
    -s, --skip-certs        Skip TLS certificate generation
    -p, --skip-prereq       Skip prerequisites installation
    -d, --skip-deploy       Skip Vault cluster deployment
    -i, --skip-postinstall  Skip post-installation tasks
    -t, --test-connection   Only test connection (oc cluster-info)
    -h, --help              Display this help message

EXAMPLES:
    $0                              # Run complete setup
    $0 -t                           # Test cluster connectivity
    $0 -s                           # Skip certificate generation
    $0 -c custom-config.json        # Use custom config file
    $0 -p -d                        # Skip prerequisites and deployment

EOF
    exit 0
}

# Default parameters
CONFIG_FILE="config.json"
SKIP_CERTS=false
SKIP_PREREQ=false
SKIP_DEPLOY=false
SKIP_POSTINSTALL=false
TEST_CONNECTION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--skip-certs)
            SKIP_CERTS=true
            shift
            ;;
        -p|--skip-prereq)
            SKIP_PREREQ=true
            shift
            ;;
        -d|--skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        -i|--skip-postinstall)
            SKIP_POSTINSTALL=true
            shift
            ;;
        -t|--test-connection)
            TEST_CONNECTION=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check for required commands
for cmd in oc helm jq openssl; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: Required command '$cmd' is not installed"
        exit 1
    fi
done

# Parse configuration
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
BASE_PATH=$(jq -r '.directories.basePath // "/jenkins_home/vault-cluster-setup"' "$CONFIG_FILE" 2>/dev/null || echo "/jenkins_home/vault-cluster-setup")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

echo ""
write_section_header "HASHICORP VAULT CLUSTER SETUP"
log_message "INFO" "Starting Vault cluster setup automation"
log_message "INFO" "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
log_message "INFO" "Configuration: $CONFIG_FILE"
echo ""

# Display configuration
log_message "INFO" "Configuration Details:"
log_message "INFO" "  Base Path: $BASE_PATH"
log_message "INFO" "  Namespace: $NAMESPACE"
log_message "INFO" "  Release Name: $RELEASE_NAME"
echo ""

# Test Kubernetes connectivity
log_message "INFO" "Testing Kubernetes cluster connectivity..."
if oc cluster-info >> "$LOG_FILE" 2>&1 | head -5; then
    log_message "INFO" "✓ Kubernetes cluster accessible"
else
    log_message "ERROR" "✗ Cannot access Kubernetes cluster"
    log_message "ERROR" "Please verify:"
    log_message "ERROR" "  1. oc is configured correctly"
    log_message "ERROR" "  2. You have access to the target cluster"
    log_message "ERROR" "  3. Cluster is running and accessible"
    exit 1
fi
echo ""

# If test connection flag is set, exit here
if [[ "$TEST_CONNECTION" == true ]]; then
    log_message "INFO" "Connection test completed successfully"
    exit 0
fi

# Track deployment steps
DEPLOYMENT_STEPS=()

# Step 0: Create Namespace and Route
write_section_header "STEP 0: CREATING NAMESPACE AND ROUTE"

if [[ -x "$SCRIPT_DIR/create-namespace-route.sh" ]]; then
    if bash "$SCRIPT_DIR/create-namespace-route.sh" "config-unsealer-vault.json" "config-vault-1.json"; then
        log_message "INFO" "✓ Namespace and route created successfully"
        DEPLOYMENT_STEPS+=("Namespace & Route: SUCCESS")
    else
        log_message "ERROR" "✗ Namespace and route creation failed"
        DEPLOYMENT_STEPS+=("Namespace & Route: FAILED")
        log_message "ERROR" "Stopping deployment due to namespace/route creation failure"
        exit 1
    fi
else
    log_message "ERROR" "Namespace/route script not found: $SCRIPT_DIR/create-namespace-route.sh"
    exit 1
fi
echo ""

# Step 1: Generate Certificates
if [[ "$SKIP_CERTS" == false ]]; then
    write_section_header "STEP 1: GENERATING TLS CERTIFICATES"
    
    if [[ -x "$SCRIPT_DIR/generate-certificates.sh" ]]; then
        if bash "$SCRIPT_DIR/generate-certificates.sh" "$CONFIG_FILE"; then
            log_message "INFO" "✓ TLS certificates generated successfully"
            DEPLOYMENT_STEPS+=("Certificates: SUCCESS")
        else
            log_message "ERROR" "✗ Certificate generation failed"
            DEPLOYMENT_STEPS+=("Certificates: FAILED")
            log_message "ERROR" "Stopping deployment due to certificate generation failure"
            exit 1
        fi
    else
        log_message "WARN" "Certificate generation script not found, skipping..."
        DEPLOYMENT_STEPS+=("Certificates: SKIPPED")
    fi
    echo ""
else
    log_message "INFO" "Skipping certificate generation (as requested)"
    DEPLOYMENT_STEPS+=("Certificates: SKIPPED")
fi

# Step 2: Deploy Prerequisites
if [[ "$SKIP_PREREQ" == false ]]; then
    write_section_header "STEP 2: DEPLOYING PREREQUISITES"
    
    if [[ -x "$SCRIPT_DIR/deploy-prerequisites.sh" ]]; then
        if bash "$SCRIPT_DIR/deploy-prerequisites.sh" "$CONFIG_FILE"; then
            log_message "INFO" "✓ Prerequisites deployment completed"
            DEPLOYMENT_STEPS+=("Prerequisites: SUCCESS")
        else
            log_message "ERROR" "✗ Prerequisites deployment failed"
            DEPLOYMENT_STEPS+=("Prerequisites: FAILED")
            log_message "ERROR" "Stopping deployment due to prerequisite failure"
            exit 1
        fi
    else
        log_message "ERROR" "Prerequisites script not found: $SCRIPT_DIR/deploy-prerequisites.sh"
        exit 1
    fi
    echo ""
else
    log_message "INFO" "Skipping prerequisites (as requested)"
    DEPLOYMENT_STEPS+=("Prerequisites: SKIPPED")
fi

# Step 3: Deploy Vault Cluster
if [[ "$SKIP_DEPLOY" == false ]]; then
    write_section_header "STEP 3: DEPLOYING VAULT CLUSTER"
    
    if [[ -x "$SCRIPT_DIR/deploy-vault-cluster.sh" ]]; then
        if bash "$SCRIPT_DIR/deploy-vault-cluster.sh" "$CONFIG_FILE"; then
            log_message "INFO" "✓ Vault cluster deployment completed"
            DEPLOYMENT_STEPS+=("Vault Cluster: SUCCESS")
        else
            log_message "ERROR" "✗ Vault cluster deployment failed"
            DEPLOYMENT_STEPS+=("Vault Cluster: FAILED")
            log_message "ERROR" "Stopping deployment due to cluster failure"
            exit 1
        fi
    else
        log_message "ERROR" "Cluster script not found: $SCRIPT_DIR/deploy-vault-cluster.sh"
        exit 1
    fi
    echo ""
else
    log_message "INFO" "Skipping Vault cluster deployment (as requested)"
    DEPLOYMENT_STEPS+=("Vault Cluster: SKIPPED")
fi

# Step 4: Post-Installation
if [[ "$SKIP_POSTINSTALL" == false ]]; then
    write_section_header "STEP 4: POST-INSTALLATION CONFIGURATION"
    
    if [[ -x "$SCRIPT_DIR/deploy-post-install.sh" ]]; then
        if bash "$SCRIPT_DIR/deploy-post-install.sh" "$CONFIG_FILE"; then
            log_message "INFO" "✓ Post-installation completed"
            DEPLOYMENT_STEPS+=("Post-Install: SUCCESS")
        else
            log_message "WARN" "Post-installation completed with warnings"
            DEPLOYMENT_STEPS+=("Post-Install: COMPLETED WITH WARNINGS")
        fi
    else
        log_message "WARN" "Post-install script not found: $SCRIPT_DIR/deploy-post-install.sh"
        DEPLOYMENT_STEPS+=("Post-Install: SCRIPT NOT FOUND")
    fi
    echo ""
else
    log_message "INFO" "Skipping post-installation (as requested)"
    DEPLOYMENT_STEPS+=("Post-Install: SKIPPED")
fi

# Final Summary
write_section_header "DEPLOYMENT SUMMARY"
log_message "INFO" "Deployment Steps Completed:"
for step in "${DEPLOYMENT_STEPS[@]}"; do
    log_message "INFO" "  $step"
done
echo ""

# Get final cluster status
log_message "INFO" "Final Cluster Status:"
kubectl get all -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
echo ""

# Check Vault pods specifically
log_message "INFO" "Vault Pods Status:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide >> "$LOG_FILE" 2>&1
echo ""

# Get Vault service endpoints
log_message "INFO" "Vault Service Endpoints:"
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=vault >> "$LOG_FILE" 2>&1
echo ""

# Get Route information
log_message "INFO" "Vault Route Information:"
if kubectl get route vault -n "$NAMESPACE" &> /dev/null; then
    ROUTE_HOST=$(kubectl get route vault -n "$NAMESPACE" -o jsonpath='{.spec.host}')
    log_message "INFO" "External URL: https://$ROUTE_HOST"
else
    log_message "INFO" "No route configured (use port-forward or create route manually)"
fi
echo ""

write_section_header "SETUP COMPLETED SUCCESSFULLY"
log_message "INFO" "Vault cluster setup completed!"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next Steps:"
log_message "INFO" "  1. Initialize Vault: oc exec -n $NAMESPACE vault-0 -- vault operator init"
log_message "INFO" "  2. Unseal Vault nodes with the unseal keys"
log_message "INFO" "  3. Configure authentication methods and policies"
log_message "INFO" "  4. Test Vault connectivity"
echo ""

exit 0

