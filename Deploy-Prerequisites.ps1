# Deploy-Prerequisites.ps1
# Script to deploy Vault Helm prerequisites

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

Write-SectionHeader "VAULT HELM PREREQUISITES DEPLOYMENT"

$remoteHost = $config.remote.host
$username = $config.remote.username
$password = $config.remote.password
$basePath = $config.remote.basePath
$prereqDir = $config.directories.prerequisite

Write-LogMessage "INFO" "Remote Host: $remoteHost"
Write-LogMessage "INFO" "Username: $username"
Write-LogMessage "INFO" "Base Path: $basePath"
Write-LogMessage "INFO" "Prerequisite Directory: $prereqDir"

# Test SSH connection
Write-LogMessage "INFO" "Testing SSH connection..."
$sshTest = Test-SSHConnection -RemoteHost $remoteHost -Username $username

if (-not $sshTest) {
    Write-LogMessage "ERROR" "SSH connection test failed. Please verify credentials and network connectivity."
    exit 1
}

# Navigate to prerequisite directory
$prereqPath = "$basePath/$prereqDir"
Write-LogMessage "INFO" "Checking prerequisite directory: $prereqPath"

$checkDirCmd = "test -d $prereqPath && echo 'EXISTS' || echo 'NOT_FOUND'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $checkDirCmd

if ($result.Output -notlike "*EXISTS*") {
    Write-LogMessage "ERROR" "Prerequisite directory not found: $prereqPath"
    exit 1
}

Write-LogMessage "INFO" "Prerequisite directory found"

# List contents of prerequisite directory
Write-LogMessage "INFO" "Listing prerequisite directory contents..."
$listCmd = "ls -la $prereqPath"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $listCmd
Write-LogMessage "INFO" $result.Output

# Check for setup script or README
Write-LogMessage "INFO" "Looking for setup scripts..."
$findScriptCmd = "find $prereqPath -type f -name '*.sh' -o -name 'README*' -o -name 'values.yaml'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $findScriptCmd
Write-LogMessage "INFO" "Found files:"
Write-LogMessage "INFO" $result.Output

# Check for Helm chart
Write-LogMessage "INFO" "Checking for Helm chart..."
$chartCheckCmd = "test -f $prereqPath/Chart.yaml && echo 'CHART_FOUND' || echo 'NO_CHART'"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $chartCheckCmd

if ($result.Output -like "*CHART_FOUND*") {
    Write-LogMessage "INFO" "Helm chart detected in prerequisite directory"
    
    # Create namespace if not exists
    Write-LogMessage "INFO" "Creating namespace: $($config.deployment.namespace)"
    $createNsCmd = "kubectl create namespace $($config.deployment.namespace) --dry-run=client -o yaml | kubectl apply -f -"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createNsCmd
    Write-LogMessage "INFO" $result.Output
    
    # Create OpenShift Route for Vault (before prerequisites installation)
    Write-LogMessage "INFO" "Creating OpenShift Route for Vault external access..."
    
    # Create route YAML definition
    $routeYaml = @"
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: vault
  namespace: $($config.deployment.namespace)
  labels:
    app.kubernetes.io/instance: $($config.deployment.releaseName)
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
"@

    # Create route using kubectl
    $createRouteCmd = "echo '$routeYaml' | kubectl apply -f -"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $createRouteCmd
    
    if ($result.Success) {
        Write-LogMessage "INFO" "✓ OpenShift Route created successfully"
        
        # Get route details (may not have hostname yet until service exists)
        $getRouteCmd = "kubectl get route vault -n $($config.deployment.namespace) -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Route created, hostname will be assigned when service is available'"
        $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $getRouteCmd
        $routeInfo = $result.Output.Trim()
        Write-LogMessage "INFO" "Route: $routeInfo"
    }
    else {
        Write-LogMessage "WARN" "Route creation failed or already exists (will retry after service creation)"
        Write-LogMessage "WARN" $result.Output
    }
    
    # Check if values.yaml exists
    $valuesCheckCmd = "test -f $prereqPath/values.yaml && echo 'VALUES_FOUND' || echo 'NO_VALUES'"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $valuesCheckCmd
    
    $valuesFlag = ""
    if ($result.Output -like "*VALUES_FOUND*") {
        Write-LogMessage "INFO" "Using custom values.yaml"
        $valuesFlag = "-f $prereqPath/values.yaml"
    }
    
    # Install prerequisites using Helm
    Write-LogMessage "INFO" "Installing prerequisites with Helm..."
    $helmInstallCmd = "cd $prereqPath && helm upgrade --install vault-prereq . --namespace $($config.deployment.namespace) $valuesFlag --timeout $($config.deployment.helmTimeout) --wait"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $helmInstallCmd
    
    if ($result.Success) {
        Write-LogMessage "INFO" "✓ Prerequisites installed successfully"
        Write-LogMessage "INFO" $result.Output
    }
    else {
        Write-LogMessage "ERROR" "✗ Prerequisites installation failed"
        Write-LogMessage "ERROR" $result.Output
        exit 1
    }
}
else {
    Write-LogMessage "WARN" "No Helm chart found. Checking for shell scripts..."
    
    # Look for setup.sh or install.sh
    $setupScriptCmd = "find $prereqPath -maxdepth 2 -type f \( -name 'setup.sh' -o -name 'install.sh' -o -name 'deploy.sh' \) | head -1"
    $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $setupScriptCmd
    
    if ($result.Output) {
        $setupScript = $result.Output.Trim()
        Write-LogMessage "INFO" "Found setup script: $setupScript"
        
        # Make script executable and run it
        $runScriptCmd = "cd $prereqPath && chmod +x $setupScript && bash $setupScript"
        $result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $runScriptCmd
        
        if ($result.Success) {
            Write-LogMessage "INFO" "✓ Prerequisites script executed successfully"
            Write-LogMessage "INFO" $result.Output
        }
        else {
            Write-LogMessage "ERROR" "✗ Prerequisites script failed"
            Write-LogMessage "ERROR" $result.Output
            exit 1
        }
    }
    else {
        Write-LogMessage "WARN" "No automated setup found. Manual intervention may be required."
    }
}

# Verify prerequisites installation
Write-LogMessage "INFO" "Verifying prerequisites installation..."
$verifyCmd = "kubectl get all -n $($config.deployment.namespace)"
$result = Invoke-RemoteCommand -RemoteHost $remoteHost -Username $username -Password $password -Command $verifyCmd
Write-LogMessage "INFO" $result.Output

Write-SectionHeader "PREREQUISITES DEPLOYMENT COMPLETED"
Write-LogMessage "INFO" "Log file: $(Get-LogFilePath)"
