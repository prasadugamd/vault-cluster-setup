#!/bin/bash
# fix-unsealer-vault.sh
# Quick script to initialize and unseal unsealer-vault pods

set -e

NAMESPACE="unsealer-vault"
INIT_FILE="/tmp/unsealer-vault-init-keys.json"

echo "=========================================="
echo "Initializing and Unsealing Unsealer Vault"
echo "=========================================="
echo ""

# Check if vault is already initialized
echo "Checking if Vault is already initialized..."
if oc exec vault-0 -n "$NAMESPACE" -- vault status 2>&1 | grep -q "Initialized.*true"; then
    echo "✓ Vault is already initialized"
    
    if [[ -f "$INIT_FILE" ]]; then
        echo "✓ Found existing init file: $INIT_FILE"
    else
        echo "✗ ERROR: Vault is initialized but init file not found: $INIT_FILE"
        echo "  Please provide the unseal keys manually or re-deploy the vault."
        exit 1
    fi
else
    # Initialize vault
    echo "Initializing Vault with 5 key shares, threshold 3..."
    oc exec vault-0 -n "$NAMESPACE" -- vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > "$INIT_FILE"
    
    echo "✓ Vault initialized successfully"
    echo "✓ Init keys saved to: $INIT_FILE"
    echo ""
fi

# Extract keys
echo "Extracting unseal keys..."
KEY1=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
KEY2=$(jq -r '.unseal_keys_b64[1]' "$INIT_FILE")
KEY3=$(jq -r '.unseal_keys_b64[2]' "$INIT_FILE")
ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

echo "Root Token: $ROOT_TOKEN"
echo ""

# Unseal all pods
echo "Unsealing all Vault pods..."
for POD in vault-0 vault-1 vault-2; do
    echo "Unsealing $POD..."
    
    # Check if pod exists and is running
    if ! oc get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
        echo "  ⚠ Pod $POD not found, skipping..."
        continue
    fi
    
    # Unseal with 3 keys
    oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY1" > /dev/null 2>&1 || true
    oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY2" > /dev/null 2>&1 || true
    oc exec "$POD" -n "$NAMESPACE" -- vault operator unseal "$KEY3" > /dev/null 2>&1 || true
    
    # Check status
    if oc exec "$POD" -n "$NAMESPACE" -- vault status 2>&1 | grep -q "Sealed.*false"; then
        echo "  ✓ $POD unsealed successfully"
    else
        echo "  ⚠ $POD may not be unsealed, check status"
    fi
done

echo ""
echo "Verifying cluster status..."
oc get pods -n "$NAMESPACE"

echo ""
echo "Checking Vault status on vault-0..."
oc exec vault-0 -n "$NAMESPACE" -- vault status

echo ""
echo "=========================================="
echo "✓ Unsealer Vault initialization complete"
echo "=========================================="
echo ""
echo "IMPORTANT: Save the init keys file securely!"
echo "Location: $INIT_FILE"
echo ""
echo "Root Token: $ROOT_TOKEN"
echo ""
