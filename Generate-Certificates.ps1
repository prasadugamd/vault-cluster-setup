# Generate-Certificates.ps1
# Script to generate TLS certificates for Vault cluster

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "config.json"
)

# Import modules
Import-Module (Join-Path $PSScriptRoot "modules\SSHConnection.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\Logger.psm1") -Force

# Load configuration
$config = Get-Content $ConfigFile | ConvertFrom-Json

# Initialize logger
Initialize-Logger -LogDirectory $config.logging.logDir -Level $config.logging.logLevel

Write-SectionHeader "VAULT TLS CERTIFICATE GENERATION"

$remoteHost = $config.remote.host
$username = $config.remote.username
$password = $config.remote.password
$basePath = $config.remote.basePath
$namespace = $config.deployment.namespace
$releaseName = $config.deployment.releaseName

Write-LogMessage "INFO" "Generating TLS certificates for Vault cluster"
Write-LogMessage "INFO" "Namespace: $namespace"
Write-LogMessage "INFO" "Release Name: $releaseName"

# Certificate parameters
$certDir = Join-Path $PSScriptRoot "certs"
$validityDays = 3650  # 10 years
$country = "US"
$state = "California"
$locality = "San Francisco"
$organization = "HashiCorp"
$organizationalUnit = "Vault"

# Create local certs directory
if (-not (Test-Path $certDir)) {
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null
    Write-LogMessage "INFO" "Created local certificates directory: $certDir"
}

# Generate SANs (Subject Alternative Names) for Vault service
$serviceName = "$releaseName"
$sans = @(
    "DNS:$serviceName",
    "DNS:$serviceName.$namespace",
    "DNS:$serviceName.$namespace.svc",
    "DNS:$serviceName.$namespace.svc.cluster.local",
    "DNS:$serviceName-0.$serviceName-internal",
    "DNS:$serviceName-0.$serviceName-internal.$namespace.svc.cluster.local",
    "DNS:$serviceName-1.$serviceName-internal",
    "DNS:$serviceName-1.$serviceName-internal.$namespace.svc.cluster.local",
    "DNS:$serviceName-2.$serviceName-internal",
    "DNS:$serviceName-2.$serviceName-internal.$namespace.svc.cluster.local",
    "DNS:localhost",
    "IP:127.0.0.1"
)

$sanString = $sans -join ","

Write-LogMessage "INFO" "Certificate SANs: $sanString"

# Check if OpenSSL is available locally
$opensslAvailable = $false
try {
    $null = openssl version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $opensslAvailable = $true
        Write-LogMessage "INFO" "OpenSSL found on local machine"
    }
} catch {
    Write-LogMessage "WARN" "OpenSSL not found locally, will generate on remote machine"
}

# Generate certificates on remote machine (more reliable)
Write-LogMessage "INFO" "Generating certificates on remote machine..."

# Create remote certs directory
$remoteCertDir = "$basePath/vault-certs"
$createDirCmd = "mkdir -p $remoteCertDir && cd $remoteCertDir"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createDirCmd

if (-not $result.Success) {
    Write-LogMessage "ERROR" "Failed to create remote certificate directory"
    exit 1
}

Write-LogMessage "INFO" "Created remote certificate directory: $remoteCertDir"

# Generate CA private key and certificate
Write-LogMessage "INFO" "Step 1/4: Generating CA private key and certificate..."
$genCACmd = @"
cd $remoteCertDir && \
openssl genrsa -out ca.key 4096 && \
openssl req -x509 -new -nodes -key ca.key -sha256 -days $validityDays \
  -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalUnit/CN=Vault CA" \
  -out ca.crt
"@

$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $genCACmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ CA certificate generated successfully"
} else {
    Write-LogMessage "ERROR" "✗ Failed to generate CA certificate"
    Write-LogMessage "ERROR" $result.Output
    exit 1
}

# Generate server private key
Write-LogMessage "INFO" "Step 2/4: Generating server private key..."
$genKeyCmd = "cd $remoteCertDir && openssl genrsa -out vault.key 4096"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $genKeyCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Server private key generated"
} else {
    Write-LogMessage "ERROR" "✗ Failed to generate server key"
    exit 1
}

# Create OpenSSL config for SANs
Write-LogMessage "INFO" "Step 3/4: Creating certificate signing request with SANs..."
$opensslConfig = @"
[req]
default_bits = 4096
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = $country
ST = $state
L = $locality
O = $organization
OU = $organizationalUnit
CN = $serviceName.$namespace.svc.cluster.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $serviceName
DNS.2 = $serviceName.$namespace
DNS.3 = $serviceName.$namespace.svc
DNS.4 = $serviceName.$namespace.svc.cluster.local
DNS.5 = $serviceName-0.$serviceName-internal
DNS.6 = $serviceName-0.$serviceName-internal.$namespace.svc.cluster.local
DNS.7 = $serviceName-1.$serviceName-internal
DNS.8 = $serviceName-1.$serviceName-internal.$namespace.svc.cluster.local
DNS.9 = $serviceName-2.$serviceName-internal
DNS.10 = $serviceName-2.$serviceName-internal.$namespace.svc.cluster.local
DNS.11 = localhost
IP.1 = 127.0.0.1

[v3_ext]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment,digitalSignature
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
"@

# Write config to remote machine
$writeConfigCmd = @"
cat > $remoteCertDir/openssl.cnf << 'EOFCONFIG'
$opensslConfig
EOFCONFIG
"@

$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $writeConfigCmd

# Generate CSR
$genCSRCmd = "cd $remoteCertDir && openssl req -new -key vault.key -out vault.csr -config openssl.cnf"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $genCSRCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Certificate signing request created"
} else {
    Write-LogMessage "ERROR" "✗ Failed to create CSR"
    exit 1
}

# Sign the certificate with CA
Write-LogMessage "INFO" "Step 4/4: Signing server certificate with CA..."
$signCertCmd = @"
cd $remoteCertDir && \
openssl x509 -req -in vault.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out vault.crt -days $validityDays -sha256 -extensions v3_ext -extfile openssl.cnf
"@

$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $signCertCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Server certificate signed successfully"
} else {
    Write-LogMessage "ERROR" "✗ Failed to sign certificate"
    Write-LogMessage "ERROR" $result.Output
    exit 1
}

# Verify certificate
Write-LogMessage "INFO" "Verifying certificate..."
$verifyCertCmd = "cd $remoteCertDir && openssl verify -CAfile ca.crt vault.crt"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $verifyCertCmd

if ($result.Output -like "*OK*") {
    Write-LogMessage "INFO" "✓ Certificate verification passed"
    Write-LogMessage "INFO" $result.Output
} else {
    Write-LogMessage "WARN" "Certificate verification warning"
    Write-LogMessage "WARN" $result.Output
}

# Display certificate details
Write-LogMessage "INFO" "Certificate details:"
$certDetailsCmd = "cd $remoteCertDir && openssl x509 -in vault.crt -text -noout | grep -A 1 'Subject:'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $certDetailsCmd
Write-LogMessage "INFO" $result.Output

# List generated files
Write-LogMessage "INFO" "Generated certificate files:"
$listFilesCmd = "ls -lh $remoteCertDir"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $listFilesCmd
Write-LogMessage "INFO" $result.Output

# Create Kubernetes TLS secret
Write-LogMessage "INFO" "Creating Kubernetes TLS secret..."
$createSecretCmd = @"
kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f - && \
kubectl delete secret vault-tls -n $namespace --ignore-not-found && \
kubectl create secret generic vault-tls -n $namespace \
  --from-file=ca.crt=$remoteCertDir/ca.crt \
  --from-file=tls.crt=$remoteCertDir/vault.crt \
  --from-file=tls.key=$remoteCertDir/vault.key \
  --from-file=vault.crt=$remoteCertDir/vault.crt \
  --from-file=vault.key=$remoteCertDir/vault.key
"@

$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createSecretCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Kubernetes TLS secret created"
    Write-LogMessage "INFO" $result.Output
} else {
    Write-LogMessage "ERROR" "✗ Failed to create Kubernetes secret"
    Write-LogMessage "ERROR" $result.Output
    exit 1
}

# Verify secret
Write-LogMessage "INFO" "Verifying Kubernetes secret..."
$verifySecretCmd = "kubectl get secret vault-tls -n $namespace -o yaml"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $verifySecretCmd
Write-LogMessage "INFO" "Secret created successfully"

# Copy certificates to Vault cluster directory
$clusterDir = "$basePath/$($config.directories.cluster)"
Write-LogMessage "INFO" "Copying certificates to cluster directory..."
$copyCertsCmd = "mkdir -p $clusterDir/certs && cp $remoteCertDir/*.crt $remoteCertDir/*.key $clusterDir/certs/"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $copyCertsCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Certificates copied to cluster directory"
} else {
    Write-LogMessage "WARN" "Could not copy to cluster directory (may not exist yet)"
}

# Download certificates locally (optional)
Write-LogMessage "INFO" "Certificate files are available at: $remoteCertDir"
Write-LogMessage "INFO" "  - CA Certificate: $remoteCertDir/ca.crt"
Write-LogMessage "INFO" "  - Server Certificate: $remoteCertDir/vault.crt"
Write-LogMessage "INFO" "  - Server Key: $remoteCertDir/vault.key"

Write-SectionHeader "CERTIFICATE GENERATION COMPLETED"
Write-LogMessage "INFO" "TLS certificates generated successfully!"
Write-LogMessage "INFO" "Kubernetes secret 'vault-tls' created in namespace '$namespace'"
Write-LogMessage "INFO" "Log file: $(Get-LogFilePath)"
Write-LogMessage "INFO" ""
Write-LogMessage "INFO" "Next: Run Deploy-Prerequisites.ps1 to continue setup"

exit 0
