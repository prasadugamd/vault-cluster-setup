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

# Get absolute path of log file to use after directory changes
LOG_FILE="$(cd "$(dirname "$LOG_FILE")" && pwd)/$(basename "$LOG_FILE")"

write_section_header "VAULT TLS CERTIFICATE GENERATION"

log_message "INFO" "Generating TLS certificates for Vault cluster"
log_message "INFO" "Namespace: $NAMESPACE"
log_message "INFO" "Release Name: $RELEASE_NAME"

# Certificate directories
CA_DIR="$BASE_PATH/CA-certs"
VAULT_CERT_DIR="$BASE_PATH/$NAMESPACE-certs"
VALIDITY_DAYS=3650  # 10 years
COUNTRY="US"
STATE="California"
LOCALITY="San Francisco"
ORGANIZATION="HashiCorp"
OU="Vault"

# Create CA directory if it doesn't exist
log_message "INFO" "CA directory: $CA_DIR"
mkdir -p "$CA_DIR"

# Create namespace-specific vault certificate directory
log_message "INFO" "Creating vault certificate directory: $VAULT_CERT_DIR"
mkdir -p "$VAULT_CERT_DIR"

# Generate SANs (Subject Alternative Names)
SERVICE_NAME="$RELEASE_NAME"

# Get Vault OCP route URL from config or environment
VAULT_ROUTE_URL=$(jq -r '.deployment.routeUrl // "vault-'"$NAMESPACE"'.apps.cluster.domain.com"' "$CONFIG_FILE")

SANS=(
    "DNS:$SERVICE_NAME"
    "DNS:$SERVICE_NAME.$NAMESPACE.svc.cluster.local"
    "DNS:$SERVICE_NAME-active"
    "DNS:$SERVICE_NAME-active.$NAMESPACE.svc.cluster.local"
    "DNS:*.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local"
    "DNS:$VAULT_ROUTE_URL"
    "IP:127.0.0.1"
)

log_message "INFO" "Certificate SANs: ${SANS[*]}"

# Check if OpenSSL is available
if ! command -v openssl &> /dev/null; then
    log_message "ERROR" "OpenSSL is not installed. Please install openssl."
    exit 1
fi

log_message "INFO" "OpenSSL version: $(openssl version)"

# Step 1: Generate or use existing CA private key and certificate
log_message "INFO" "Step 1/7: Checking CA certificate..."
if [[ -f "$CA_DIR/ca.crt" && -f "$CA_DIR/ca.key" ]]; then
    log_message "INFO" "✓ Using existing CA certificate from $CA_DIR"
else
    log_message "INFO" "Generating new CA private key and certificate..."
    cd "$CA_DIR"
    openssl req -x509 -sha256 -days 3650 -newkey rsa:2048 -keyout ca.key -out ca.crt -nodes \
      -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$OU/CN=Vault CA" \
      >> "$LOG_FILE" 2>&1
    
    if [[ -f ca.crt && -f ca.key ]]; then
        log_message "INFO" "✓ CA certificate generated successfully at $CA_DIR"
    else
        log_message "ERROR" "✗ Failed to generate CA certificate"
        exit 1
    fi
fi

# Step 2: Generate namespace-specific RSA private key
log_message "INFO" "Step 2/7: Creating RSA key for namespace $NAMESPACE..."
cd "$VAULT_CERT_DIR"
openssl genrsa -out "$NAMESPACE-rsa.key" 2048 >> "$LOG_FILE" 2>&1

if [[ -f "$NAMESPACE-rsa.key" ]]; then
    log_message "INFO" "✓ RSA private key generated"
else
    log_message "ERROR" "✗ Failed to generate RSA key"
    exit 1
fi

# Step 3: Create the CSR
log_message "INFO" "Step 3/7: Creating certificate signing request..."
openssl req -out "$NAMESPACE.csr" -key "$NAMESPACE-rsa.key" -new -sha256 \
  -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$OU/CN=$SERVICE_NAME.$NAMESPACE.svc.cluster.local" \
  >> "$LOG_FILE" 2>&1

if [[ -f "$NAMESPACE.csr" ]]; then
    log_message "INFO" "✓ Certificate signing request created"
else
    log_message "ERROR" "✗ Failed to create CSR"
    exit 1
fi

# Step 4: Create the extension file for SANs
log_message "INFO" "Step 4/7: Creating certificate extension file with SANs..."

cat > "$NAMESPACE.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints = CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = $SERVICE_NAME
DNS.2 = $SERVICE_NAME.$NAMESPACE.svc.cluster.local
DNS.3 = $SERVICE_NAME-active
DNS.4 = $SERVICE_NAME-active.$NAMESPACE.svc.cluster.local
DNS.5 = *.$SERVICE_NAME-internal.$NAMESPACE.svc.cluster.local
DNS.6 = $VAULT_ROUTE_URL
IP.1 = 127.0.0.1
EOF

log_message "INFO" "✓ Extension file created"

# Step 5: Sign the certificate with CA
log_message "INFO" "Step 5/7: Signing certificate with CA..."
openssl x509 -req -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -in "$NAMESPACE.csr" -out "$NAMESPACE.crt" \
  -days 3650 -CAcreateserial -extfile "$NAMESPACE.ext" -sha256 \
  >> "$LOG_FILE" 2>&1

if [[ -f "$NAMESPACE.crt" ]]; then
    log_message "INFO" "✓ Certificate signed successfully"
else
    log_message "ERROR" "✗ Failed to sign certificate"
    exit 1
fi

# Step 6: Convert certificate to P12 format
log_message "INFO" "Step 6/7: Converting certificate to P12 format..."
openssl pkcs12 -inkey "$NAMESPACE-rsa.key" -in "$NAMESPACE.crt" -export -out "$NAMESPACE.p12" -passout pass: \
  >> "$LOG_FILE" 2>&1

if [[ -f "$NAMESPACE.p12" ]]; then
    log_message "INFO" "✓ Certificate converted to P12 format"
else
    log_message "ERROR" "✗ Failed to convert to P12"
    exit 1
fi

# Step 7: Extract private key from P12
log_message "INFO" "Step 7/7: Extracting private key from P12..."
openssl pkcs12 -info -in "$NAMESPACE.p12" -nodes -nocerts -passin pass: -out "$NAMESPACE.key" \
  >> "$LOG_FILE" 2>&1

if [[ -f "$NAMESPACE.key" ]]; then
    log_message "INFO" "✓ Private key extracted successfully"
else
    log_message "ERROR" "✗ Failed to extract private key"
    exit 1
fi

# Verify certificate
log_message "INFO" "Verifying certificate..."
if openssl verify -CAfile "$CA_DIR/ca.crt" "$NAMESPACE.crt" 2>&1 | grep -q "OK"; then
    log_message "INFO" "✓ Certificate verification passed"
    openssl verify -CAfile "$CA_DIR/ca.crt" "$NAMESPACE.crt" >> "$LOG_FILE" 2>&1
else
    log_message "WARN" "Certificate verification warning"
    openssl verify -CAfile "$CA_DIR/ca.crt" "$NAMESPACE.crt" >> "$LOG_FILE" 2>&1
fi

# Display certificate details
log_message "INFO" "Certificate details:"
openssl x509 -in "$NAMESPACE.crt" -text -noout | grep -A 1 "Subject:" | tee -a "$LOG_FILE"

# List generated files
log_message "INFO" "Generated vault certificate files:"
ls -lh "$VAULT_CERT_DIR" | tee -a "$LOG_FILE"

# Create Kubernetes TLS secret
log_message "INFO" "Creating Kubernetes TLS secret..."

# Create namespace if it doesn't exist
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - >> "$LOG_FILE" 2>&1

# Delete existing secret if present
oc delete secret vault-server-tls -n "$NAMESPACE" --ignore-not-found >> "$LOG_FILE" 2>&1

# Prepare certificate files for vault-1 namespace
if [[ "$NAMESPACE" == "vault-1" ]]; then
    log_message "INFO" "Preparing certificate files for vault-1 namespace..."
    cd "$VAULT_CERT_DIR"
    cp "$NAMESPACE.key" vault.key
    cp "$NAMESPACE.crt" vault.crt
    log_message "INFO" "✓ Certificate files copied for vault-1"
    
    # Create new secret for vault-1
    oc create secret generic vault-server-tls -n "$NAMESPACE" \
      --from-file=vault.key="$VAULT_CERT_DIR/vault.key" \
      --from-file=vault.crt="$VAULT_CERT_DIR/vault.crt" \
      --from-file=vault.ca="$CA_DIR/ca.crt" \
      >> "$LOG_FILE" 2>&1
else
    # Create new secret for other namespaces using namespace-specific files
    oc create secret generic vault-server-tls -n "$NAMESPACE" \
      --from-file=vault.key="$VAULT_CERT_DIR/$NAMESPACE.key" \
      --from-file=vault.crt="$VAULT_CERT_DIR/$NAMESPACE.crt" \
      --from-file=vault.ca="$CA_DIR/ca.crt" \
      >> "$LOG_FILE" 2>&1
fi

if [[ $? -eq 0 ]]; then
    log_message "INFO" "✓ Kubernetes TLS secret created"
else
    log_message "ERROR" "✗ Failed to create Kubernetes secret"
    exit 1
fi

# Verify secret
log_message "INFO" "Verifying Kubernetes secret..."
oc get secret vault-server-tls -n "$NAMESPACE" -o jsonpath='{.metadata.name}' >> "$LOG_FILE" 2>&1
log_message "INFO" "Secret created successfully"

# Summary
log_message "INFO" "CA certificate files are available at: $CA_DIR"
log_message "INFO" "  - CA Certificate: $CA_DIR/ca.crt"
log_message "INFO" "  - CA Key: $CA_DIR/ca.key"
log_message "INFO" "Vault certificate files are available at: $VAULT_CERT_DIR"
log_message "INFO" "  - RSA Key: $VAULT_CERT_DIR/$NAMESPACE-rsa.key"
log_message "INFO" "  - CSR: $VAULT_CERT_DIR/$NAMESPACE.csr"
log_message "INFO" "  - Certificate: $VAULT_CERT_DIR/$NAMESPACE.crt"
log_message "INFO" "  - Private Key: $VAULT_CERT_DIR/$NAMESPACE.key"
log_message "INFO" "  - P12: $VAULT_CERT_DIR/$NAMESPACE.p12"

write_section_header "CERTIFICATE GENERATION COMPLETED"
log_message "INFO" "TLS certificates generated successfully!"
log_message "INFO" "Kubernetes secret 'vault-server-tls' created in namespace '$NAMESPACE'"
log_message "INFO" "Log file: $(get_log_file_path)"
log_message "INFO" ""
log_message "INFO" "Next: Run deploy-prerequisites.sh to continue setup"

exit 0

