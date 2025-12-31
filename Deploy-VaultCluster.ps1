# Deploy-VaultCluster.ps1
# Script to deploy HashiCorp Vault Cluster

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

Write-SectionHeader "VAULT CLUSTER DEPLOYMENT"

$remoteHost = $config.remote.host
$username = $config.remote.username
$password = $config.remote.password
$basePath = $config.remote.basePath
$clusterDir = $config.directories.cluster

Write-LogMessage "INFO" "Remote Host: $remoteHost"
Write-LogMessage "INFO" "Cluster Directory: $clusterDir"

# Navigate to cluster directory
$clusterPath = "$basePath/$clusterDir"
Write-LogMessage "INFO" "Checking cluster directory: $clusterPath"

$checkDirCmd = "test -d $clusterPath && echo 'EXISTS' || echo 'NOT_FOUND'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $checkDirCmd

if ($result.Output -notlike "*EXISTS*") {
    Write-LogMessage "ERROR" "Cluster directory not found: $clusterPath"
    exit 1
}

Write-LogMessage "INFO" "Cluster directory found"

# List contents
Write-LogMessage "INFO" "Listing cluster directory contents..."
$listCmd = "ls -la $clusterPath"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $listCmd
Write-LogMessage "INFO" $result.Output

# Check for Helm chart
Write-LogMessage "INFO" "Checking for Helm chart..."
$chartCheckCmd = "test -f $clusterPath/Chart.yaml && echo 'CHART_FOUND' || echo 'NO_CHART'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $chartCheckCmd

if ($result.Output -like "*CHART_FOUND*") {
    Write-LogMessage "INFO" "Helm chart detected"
    
    # Ensure namespace exists
    Write-LogMessage "INFO" "Ensuring namespace exists: $($config.deployment.namespace)"
    $createNsCmd = "kubectl create namespace $($config.deployment.namespace) --dry-run=client -o yaml | kubectl apply -f -"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createNsCmd
    
    # Check for certificates
    Write-LogMessage "INFO" "Checking for certificates..."
    $certsCheckCmd = "find $clusterPath -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.key' \)"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $certsCheckCmd
    
    if ($result.Output) {
        Write-LogMessage "INFO" "Certificates found:"
        Write-LogMessage "INFO" $result.Output
        
        # Create TLS secret if certificates exist
        $certDir = "$clusterPath/certs"
        $createSecretCmd = "if [ -d $certDir ]; then kubectl create secret generic vault-tls -n $($config.deployment.namespace) --from-file=$certDir --dry-run=client -o yaml | kubectl apply -f -; fi"
        $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createSecretCmd
        Write-LogMessage "INFO" "TLS secret created"
    }
    
    # Check for values.yaml
    $valuesCheckCmd = "test -f $clusterPath/values.yaml && echo 'VALUES_FOUND' || echo 'NO_VALUES'"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $valuesCheckCmd
    
    $valuesFlag = ""
    if ($result.Output -like "*VALUES_FOUND*") {
        Write-LogMessage "INFO" "Using custom values.yaml"
        $valuesFlag = "-f $clusterPath/values.yaml"
    }
    
    # Deploy Vault cluster
    Write-LogMessage "INFO" "Deploying Vault cluster with Helm..."
    $helmInstallCmd = "cd $clusterPath && helm upgrade --install $($config.deployment.releaseName) . --namespace $($config.deployment.namespace) $valuesFlag --timeout $($config.deployment.helmTimeout) --wait"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $helmInstallCmd
    
    if ($result.Success) {
        Write-LogMessage "INFO" "✓ Vault cluster deployed successfully"
        Write-LogMessage "INFO" $result.Output
    }
    else {
        Write-LogMessage "ERROR" "✗ Vault cluster deployment failed"
        Write-LogMessage "ERROR" $result.Output
        exit 1
    }
}
else {
    Write-LogMessage "WARN" "No Helm chart found. Checking for deployment scripts..."
    
    $deployScriptCmd = "find $clusterPath -maxdepth 2 -type f \( -name 'deploy.sh' -o -name 'install.sh' \) | head -1"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $deployScriptCmd
    
    if ($result.Output) {
        $deployScript = $result.Output.Trim()
        Write-LogMessage "INFO" "Found deploy script: $deployScript"
        
        $runScriptCmd = "cd $clusterPath && chmod +x $deployScript && bash $deployScript"
        $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $runScriptCmd
        
        if ($result.Success) {
            Write-LogMessage "INFO" "✓ Deploy script executed successfully"
            Write-LogMessage "INFO" $result.Output
        }
        else {
            Write-LogMessage "ERROR" "✗ Deploy script failed"
            Write-LogMessage "ERROR" $result.Output
            exit 1
        }
    }
}

# Wait for pods to be ready
Write-LogMessage "INFO" "Waiting for Vault pods to be ready..."
$waitCmd = "kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault -n $($config.deployment.namespace) --timeout=300s"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $waitCmd
Write-LogMessage "INFO" $result.Output

# Get pod status
Write-LogMessage "INFO" "Vault pod status:"
$statusCmd = "kubectl get pods -n $($config.deployment.namespace) -l app.kubernetes.io/name=vault"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $statusCmd
Write-LogMessage "INFO" $result.Output

# Get services
Write-LogMessage "INFO" "Vault services:"
$svcCmd = "kubectl get svc -n $($config.deployment.namespace)"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $svcCmd
Write-LogMessage "INFO" $result.Output

Write-SectionHeader "VAULT CLUSTER DEPLOYMENT COMPLETED"
Write-LogMessage "INFO" "Log file: $(Get-LogFilePath)"
