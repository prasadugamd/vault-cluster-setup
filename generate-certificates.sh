#!/bin/bash
# generate-certificates.sh
# Script to generate TLS certificates for Vault cluster

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
NAMESPACE=$(jq -r '.deployment.namespace' "$CONFIG_FILE")
RELEASE_NAME=$(jq -r '.deployment.releaseName' "$CONFIG_FILE")
LOG_DIR=$(jq -r '.logging.logDir' "$CONFIG_FILE")
LOG_LEVEL=$(jq -r '.logging.logLevel // "INFO"' "$CONFIG_FILE")
CLUSTER_DIR=$(jq -r '.directories.cluster' "$CONFIG_FILE")

# Initialize logger
initialize_logger "$LOG_DIR" "$LOG_LEVEL"

write_section_header "VAULT TLS CERTIFICATE GENERATION"

log_message "INFO" "Generating TLS certificates for Vault cluster"
log_message "INFO" "Namespace: $NAMESPACE"
log_message "INFO" "Release Name: $RELEASE_NAME"

# Certificate parameters
CERT_DIR="$BASE_PATH/vault-certs"
VALIDITY_DAYS=3650  # 10 years
COUNTRY="US"
STATE="California"
LOCALITY="San Francisco"
ORGANIZATION="HashiCorp"
OU="Vault"

# Create certificate directory
log_message "INFO" "Creating certificate directory: $CERT_DIR"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Generate SANs (Subject Alternative Names)
SERVICE_NAME="$RELEASE_NAME"
SANS=(
    "DNS:$SERVICE_NAME"
    "DNS:$SERVICE_NAME.$NAMESPACE"
    "DNS:$SERVICE_NAME.$NAMESPACE.svc"
    "DNS:$SERVICE_NAME.$NAMESPACE.svc.cluster.local"
    "DNS:$SERVICE_NAME-0.$SERVICE_NAME-internal"
    "DNS:$SERVICE_NAME-0.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local"
    "DNS:$SERVICE_NAME-1.$SERVICE_NAME-internal"
    "DNS:$SERVICE_NAME-1.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local"
    "DNS:$SERVICE_NAME-2.$SERVICE_NAME-internal"
    "DNS:$SERVICE_NAME-2.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local"
    "DNS:localhost"
    "IP:127.0.0.1"
)

log_message "INFO" "Certificate SANs: ${SANS[*]}"

# Check if OpenSSL is available
if ! command -v openssl &> /dev/null; then
    log_message "ERROR" "OpenSSL is not installed. Please install openssl."
    exit 1
fi

log_message "INFO" "OpenSSL version: $(openssl version)"

# Step 1: Generate CA private key and certificate
log_message "INFO" "Step 1/4: Generating CA private key and certificate..."
openssl genrsa -out ca.key 4096 2>&1 | tee -a "$LOG_FILE"
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$VALIDITY_DAYS" \
  -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$OU/CN=Vault CA" \
  -out ca.crt 2>&1 | tee -a "$LOG_FILE"

if [[ -f ca.crt && -f ca.key ]]; then
    log_message "INFO" "✓ CA certificate generated successfully"
else
    log_message "ERROR" "✗ Failed to generate CA certificate"
    exit 1
fi

# Step 2: Generate server private key
log_message "INFO" "Step 2/4: Generating server private key..."
openssl genrsa -out vault.key 4096 2>&1 | tee -a "$LOG_FILE"

if [[ -f vault.key ]]; then
    log_message "INFO" "✓ Server private key generated"
else
    log_message "ERROR" "✗ Failed to generate server key"
    exit 1
fi

# Step 3: Create OpenSSL config for SANs
log_message "INFO" "Step 3/4: Creating certificate signing request with SANs..."

cat > openssl.cnf << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = $COUNTRY
ST = $STATE
L = $LOCALITY
O = $ORGANIZATION
OU = $OU
CN = $SERVICE_NAME.$NAMESPACE.svc.cluster.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $SERVICE_NAME
DNS.2 = $SERVICE_NAME.$NAMESPACE
DNS.3 = $SERVICE_NAME.$NAMESPACE.svc
DNS.4 = $SERVICE_NAME.$NAMESPACE.svc.cluster.local
DNS.5 = $SERVICE_NAME-0.$SERVICE_NAME-internal
DNS.6 = $SERVICE_NAME-0.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local
DNS.7 = $SERVICE_NAME-1.$SERVICE_NAME-internal
DNS.8 = $SERVICE_NAME-1.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local
DNS.9 = $SERVICE_NAME-2.$SERVICE_NAME-internal
DNS.10 = $SERVICE_NAME-2.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local
DNS.11 = localhost
IP.1 = 127.0.0.1

[v3_ext]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment,digitalSignature
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

# Generate CSR
openssl req -new -key vault.key -out vault.csr -config openssl.cnf 2>&1 | tee -a "$LOG_FILE"

if [[ -f vault.csr ]]; then
    log_message "INFO" "✓ Certificate signing request created"
else
    log_message "ERROR" "✗ Failed to create CSR"
    exit 1
fi

# Step 4: Sign the certificate with CA
log_message "INFO" "Step 4/4: Signing server certificate with CA..."
openssl x509 -req -in vault.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out vault.crt -days "$VALIDITY_DAYS" -sha256 -extensions v3_ext -extfile openssl.cnf \
  2>&1 | tee -a "$LOG_FILE"

if [[ -f vault.crt ]]; then
    log_message "INFO" "✓ Server certificate signed successfully"
else
    log_message "ERROR" "✗ Failed to sign certificate"
    exit 1
fi

# Verify certificate
log_message "INFO" "Verifying certificate..."
if openssl verify -CAfile ca.crt vault.crt 2>&1 | grep -q "OK"; then
    log_message "INFO" "✓ Certificate verification passed"
    openssl verify -CAfile ca.crt vault.crt 2>&1 | tee -a "$LOG_FILE"
else
    log_message "WARN" "Certificate verification warning"
    openssl verify -CAfile ca.crt vault.crt 2>&1 | tee -a "$LOG_FILE"
fi

# Display certificate details
log_message "INFO" "Certificate details:"
openssl x509 -in vault.crt -text -noout | grep -A 1 "Subject:" | tee -a "$LOG_FILE"

# List generated files
log_message "INFO" "Generated certificate files:"
ls -lh "$CERT_DIR" | tee -a "$LOG_FILE"

# Create Kubernetes TLS secret
log_message "INFO" "Creating Kubernetes TLS secret..."

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"

# Delete existing secret if present
kubectl delete secret vault-tls -n "$NAMESPACE" --ignore-not-found 2>&1 | tee -a "$LOG_FILE"

# Create new secret
kubectl create secret generic vault-tls -n "$NAMESPACE" \
  --from-file=ca.crt="$CERT_DIR/ca.crt" \
  --from-file=tls.crt="$CERT_DIR/vault.crt" \
  --from-file=tls.key="$CERT_DIR/vault.key" \
  --from-file=vault.crt="$CERT_DIR/vault.crt" \
  --from-file=vault.key="$CERT_DIR/vault.key" \
  2>&1 | tee -a "$LOG_FILE"

if [[ $? -eq 0 ]]; then
    log_message "INFO" "✓ Kubernetes TLS secret created"
else
    log_message "ERROR" "✗ Failed to create Kubernetes secret"
    exit 1
fi

# Verify secret
log_message "INFO" "Verifying Kubernetes secret..."
kubectl get secret vault-tls -n "$NAMESPACE" -o jsonpath='{.metadata.name}' 2>&1 | tee -a "$LOG_FILE"
log_message "INFO" "Secret created successfully"

# Copy certificates to Vault cluster directory
CLUSTER_PATH="$BASE_PATH/$CLUSTER_DIR"
log_message "INFO" "Copying certificates to cluster directory..."
mkdir -p "$CLUSTER_PATH/certs"
cp "$CERT_DIR"/*.crt "$CERT_DIR"/*.key "$CLUSTER_PATH/certs/" 2>&1 | tee -a "$LOG_FILE"

if [[ $? -eq 0 ]]; then
    log_message "INFO" "✓ Certificates copied to cluster directory"
else
    log_message "WARN" "Could not copy to cluster directory (may not exist yet)"
fi

# Summary
log_message "INFO" "Certificate files are available at: $CERT_DIR"
log_message "INFO" "  - CA Certificate: $CERT_DIR/ca.crt"
log_message "INFO" "  - Server Certificate: $CERT_DIR/vault.crt"
log_message "INFO" "  - Server Key: $CERT_DIR/vault.key"

write_section_header "CERTIFICATE GENERATION COMPLETED"
log_message "INFO" "TLS certificates generated successfully!"
log_message "INFO" "Kubernetes secret 'vault-tls' created in namespace '$NAMESPACE'"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next: Run deploy-prerequisites.sh to continue setup"

exit 0
