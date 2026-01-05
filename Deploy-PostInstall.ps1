# Deploy-PostInstall.ps1
# Script to run post-installation tasks

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

Write-SectionHeader "VAULT POST-INSTALLATION"

$remoteHost = $config.remote.host
$username = $config.remote.username
$password = $config.remote.password
$basePath = $config.remote.basePath
$postInstallDir = $config.directories.postInstall

Write-LogMessage "INFO" "Remote Host: $remoteHost"
Write-LogMessage "INFO" "Post-Install Directory: $postInstallDir"

# Navigate to post-install directory
$postInstallPath = "$basePath/$postInstallDir"
Write-LogMessage "INFO" "Checking post-install directory: $postInstallPath"

$checkDirCmd = "test -d $postInstallPath && echo 'EXISTS' || echo 'NOT_FOUND'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $checkDirCmd

if ($result.Output -notlike "*EXISTS*") {
    Write-LogMessage "ERROR" "Post-install directory not found: $postInstallPath"
    exit 1
}

Write-LogMessage "INFO" "Post-install directory found"

# List contents
Write-LogMessage "INFO" "Listing post-install directory contents..."
$listCmd = "ls -la $postInstallPath"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $listCmd
Write-LogMessage "INFO" $result.Output

# Check for Helm chart
Write-LogMessage "INFO" "Checking for Helm chart..."
$chartCheckCmd = "test -f $postInstallPath/Chart.yaml && echo 'CHART_FOUND' || echo 'NO_CHART'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $chartCheckCmd

if ($result.Output -like "*CHART_FOUND*") {
    Write-LogMessage "INFO" "Helm chart detected for post-installation"
    
    # Check for values.yaml
    $valuesCheckCmd = "test -f $postInstallPath/values.yaml && echo 'VALUES_FOUND' || echo 'NO_VALUES'"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $valuesCheckCmd
    
    $valuesFlag = ""
    if ($result.Output -like "*VALUES_FOUND*") {
        Write-LogMessage "INFO" "Using custom values.yaml"
        $valuesFlag = "-f $postInstallPath/values.yaml"
    }
    
    # Install post-install chart
    Write-LogMessage "INFO" "Running post-installation with Helm..."
    $helmInstallCmd = "cd $postInstallPath && helm upgrade --install vault-post-install . --namespace $($config.deployment.namespace) $valuesFlag --timeout $($config.deployment.helmTimeout) --wait"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $helmInstallCmd
    
    if ($result.Success) {
        Write-LogMessage "INFO" "✓ Post-installation completed successfully"
        Write-LogMessage "INFO" $result.Output
    }
    else {
        Write-LogMessage "ERROR" "✗ Post-installation failed"
        Write-LogMessage "ERROR" $result.Output
        exit 1
    }
}
else {
    Write-LogMessage "WARN" "No Helm chart found. Checking for post-install scripts..."
    
    # Look for post-install script
    $scriptCheckCmd = "find $postInstallPath -maxdepth 2 -type f \( -name 'post-install.sh' -o -name 'configure.sh' -o -name 'setup.sh' \) | head -1"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $scriptCheckCmd
    
    if ($result.Output) {
        $postInstallScript = $result.Output.Trim()
        Write-LogMessage "INFO" "Found post-install script: $postInstallScript"
        
        # Run post-install script
        $runScriptCmd = "cd $postInstallPath && chmod +x $postInstallScript && bash $postInstallScript"
        $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $runScriptCmd
        
        if ($result.Success) {
            Write-LogMessage "INFO" "✓ Post-install script executed successfully"
            Write-LogMessage "INFO" $result.Output
        }
        else {
            Write-LogMessage "ERROR" "✗ Post-install script failed"
            Write-LogMessage "ERROR" $result.Output
            exit 1
        }
    }
    else {
        Write-LogMessage "WARN" "No automated post-install found."
    }
}

# Verify OpenShift Route and display access information
Write-LogMessage "INFO" "Verifying OpenShift Route for external access..."

$getRouteCmd = "kubectl get route vault -n $($config.deployment.namespace) -o jsonpath='{.spec.host}' 2>/dev/null"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $getRouteCmd

if ($result.Success -and $result.Output) {
    $routeHost = $result.Output.Trim()
    Write-LogMessage "INFO" "✓ Vault Route is active"
    Write-LogMessage "INFO" "Vault External URL: https://$routeHost"
    Write-LogMessage "INFO" "Use this URL to access Vault UI and API from outside the cluster"
}
else {
    Write-LogMessage "WARN" "Route not found or not accessible yet"
    Write-LogMessage "INFO" "Route should have been created during prerequisites phase"
}

# Check Vault initialization status
Write-LogMessage "INFO" "Checking Vault initialization status..."
$vaultPod = "kubectl get pods -n $($config.deployment.namespace) -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $vaultPod
$podName = $result.Output.Trim()

if ($podName) {
    Write-LogMessage "INFO" "Vault pod: $podName"
    
    $initStatusCmd = "kubectl exec -n $($config.deployment.namespace) $podName -- vault status"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $initStatusCmd
    Write-LogMessage "INFO" "Vault status:"
    Write-LogMessage "INFO" $result.Output
}

# Final verification
Write-LogMessage "INFO" "Final cluster verification..."
$allResourcesCmd = "kubectl get all -n $($config.deployment.namespace)"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $allResourcesCmd
Write-LogMessage "INFO" $result.Output

Write-SectionHeader "POST-INSTALLATION COMPLETED"
Write-LogMessage "INFO" "Log file: $(Get-LogFilePath)"
