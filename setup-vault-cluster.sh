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
Usage: $0 [OPTIONS] [CONFIG_FILES...]

Automated HashiCorp Vault Cluster Setup on Kubernetes/OpenShift

ARGUMENTS:
    CONFIG_FILES            One or more configuration files (default: config.json)

OPTIONS:
    -n, --skip-namespace    Skip namespace and route creation
    -s, --skip-certs        Skip TLS certificate generation
    -p, --skip-prereq       Skip prerequisites installation
    -d, --skip-deploy       Skip Vault cluster deployment
    -i, --skip-postinstall  Skip post-installation tasks
    -t, --test-connection   Only test connection (oc cluster-info)
    -h, --help              Display this help message

EXAMPLES:
    $0 config-unsealer-vault.json config-vault-1.json    # Deploy both vaults
    $0 config-unsealer-vault.json                        # Deploy unsealer only
    $0 -t                                                 # Test cluster connectivity
    $0 -s config-unsealer-vault.json config-vault-1.json # Skip certificate generation
    $0 -p config-vault-1.json                            # Skip prerequisites

EOF
    exit 0
}

# Default parameters
CONFIG_FILES=()
SKIP_NAMESPACE=false
SKIP_CERTS=false
SKIP_PREREQ=false
SKIP_DEPLOY=false
SKIP_POSTINSTALL=false
TEST_CONNECTION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--skip-namespace)
            SKIP_NAMESPACE=true
            shift
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
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            # Positional argument - config file
            CONFIG_FILES+=("$1")
            shift
            ;;
    esac
done

# Check if config files were provided
if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No configuration files specified"
    echo ""
    usage
fi

# Validate config files exist
for config_file in "${CONFIG_FILES[@]}"; do
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file not found: $config_file"
        exit 1
    fi
done

# Check for required commands
for cmd in oc helm jq openssl; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: Required command '$cmd' is not installed"
        exit 1
    fi
done

# Initialize logger using first config file
FIRST_CONFIG="${CONFIG_FILES[0]}"
LOG_DIR=$(jq -r '.logging.logDir' "$FIRST_CONFIG")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$FIRST_CONFIG")
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

echo ""
write_section_header "HASHICORP VAULT CLUSTER SETUP"
log_message "INFO" "Starting Vault cluster setup automation"
log_message "INFO" "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
log_message "INFO" "Configuration Files: ${CONFIG_FILES[*]}"
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
if [[ "$SKIP_NAMESPACE" == false ]]; then
    write_section_header "STEP 0: CREATING NAMESPACE AND ROUTE"

    if [[ -x "$SCRIPT_DIR/create-namespace-route.sh" ]]; then
        if bash "$SCRIPT_DIR/create-namespace-route.sh" "${CONFIG_FILES[@]}"; then
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
else
    log_message "INFO" "Skipping namespace and route creation (as requested)"
    DEPLOYMENT_STEPS+=("Namespace & Route: SKIPPED")
fi

# Step 1: Generate Certificates
if [[ "$SKIP_CERTS" == false ]]; then
    write_section_header "STEP 1: GENERATING TLS CERTIFICATES"
    
    if [[ -x "$SCRIPT_DIR/generate-certificates.sh" ]]; then
        CERT_SUCCESS=true
        for config_file in "${CONFIG_FILES[@]}"; do
            NAMESPACE=$(jq -r '.deployment.namespace' "$config_file")
            log_message "INFO" "Generating certificates for namespace: $NAMESPACE"
            if bash "$SCRIPT_DIR/generate-certificates.sh" "$config_file"; then
                log_message "INFO" "✓ TLS certificates generated for $NAMESPACE"
            else
                log_message "ERROR" "✗ Certificate generation failed for $NAMESPACE"
                CERT_SUCCESS=false
                break
            fi
        done
        
        if [[ "$CERT_SUCCESS" == true ]]; then
            DEPLOYMENT_STEPS+=("Certificates: SUCCESS")
        else
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
        # Prerequisites are cluster-wide, only need to deploy once
        if bash "$SCRIPT_DIR/deploy-prerequisites.sh"; then
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
        DEPLOY_SUCCESS=true
        for config_file in "${CONFIG_FILES[@]}"; do
            NAMESPACE=$(jq -r '.deployment.namespace' "$config_file")
            log_message "INFO" "Deploying vault cluster for namespace: $NAMESPACE"
            if bash "$SCRIPT_DIR/deploy-vault-cluster.sh" "$config_file"; then
                log_message "INFO" "✓ Vault cluster deployment completed for $NAMESPACE"
            else
                log_message "ERROR" "✗ Vault cluster deployment failed for $NAMESPACE"
                DEPLOY_SUCCESS=false
                break
            fi
        done
        
        if [[ "$DEPLOY_SUCCESS" == true ]]; then
            DEPLOYMENT_STEPS+=("Vault Cluster: SUCCESS")
        else
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
        POSTINSTALL_SUCCESS=true
        for config_file in "${CONFIG_FILES[@]}"; do
            NAMESPACE=$(jq -r '.deployment.namespace' "$config_file")
            log_message "INFO" "Running post-installation for namespace: $NAMESPACE"
            if bash "$SCRIPT_DIR/deploy-post-install.sh" "$config_file"; then
                log_message "INFO" "✓ Post-installation completed for $NAMESPACE"
            else
                log_message "WARN" "Post-installation completed with warnings for $NAMESPACE"
                POSTINSTALL_SUCCESS=false
            fi
        done
        
        if [[ "$POSTINSTALL_SUCCESS" == true ]]; then
            DEPLOYMENT_STEPS+=("Post-Install: SUCCESS")
        else
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

# Get final cluster status for all deployed vaults
log_message "INFO" "Final Cluster Status:"
for config_file in "${CONFIG_FILES[@]}"; do
    NAMESPACE=$(jq -r '.deployment.namespace' "$config_file")
    log_message "INFO" "Status for namespace: $NAMESPACE"
    kubectl get all -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide >> "$LOG_FILE" 2>&1
    
    # Get Route information
    if kubectl get route vault -n "$NAMESPACE" &> /dev/null; then
        ROUTE_HOST=$(kubectl get route vault -n "$NAMESPACE" -o jsonpath='{.spec.host}')
        log_message "INFO" "  External URL: https://$ROUTE_HOST"
    fi
    echo ""
done

write_section_header "SETUP COMPLETED SUCCESSFULLY"
log_message "INFO" "Vault cluster setup completed!"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Deployed Vaults:"
for config_file in "${CONFIG_FILES[@]}"; do
    NAMESPACE=$(jq -r '.deployment.namespace' "$config_file")
    log_message "INFO" "  - $NAMESPACE"
done
log_message "INFO" ""
log_message "INFO" "Next Steps:"
log_message "INFO" "  1. Initialize Vault: oc exec -n <namespace> vault-0 -- vault operator init"
log_message "INFO" "  2. Unseal Vault nodes with the unseal keys"
log_message "INFO" "  3. Configure authentication methods and policies"
log_message "INFO" "  4. Test Vault connectivity"
echo ""

exit 0

