# setup-vault-cluster.ps1
# Main orchestration script for complete Vault cluster setup

<#
.SYNOPSIS
    Automated HashiCorp Vault Cluster Setup on remote Kubernetes cluster

.DESCRIPTION
    This script orchestrates the complete deployment of a Vault cluster including:
    - Prerequisites installation
    - Vault cluster deployment
    - Post-installation configuration
    All operations are performed on remote machine jenkins@ilceatm137

.PARAMETER ConfigFile
    Path to the configuration JSON file (default: config.json)

.PARAMETER SkipPrerequisites
    Skip prerequisites installation

.PARAMETER SkipClusterDeploy
    Skip Vault cluster deployment

.PARAMETER SkipPostInstall
    Skip post-installation tasks

.PARAMETER TestConnection
    Only test SSH connection without deploying

.EXAMPLE
    .\setup-vault-cluster.ps1
    Run complete setup with default configuration

.EXAMPLE
    .\setup-vault-cluster.ps1 -TestConnection
    Test connection to remote machine only

.EXAMPLE
    .\setup-vault-cluster.ps1 -SkipPrerequisites
    Skip prerequisites and deploy cluster only
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "config.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPrerequisites,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipClusterDeploy,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPostInstall,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestConnection
)

# Set error action preference
$ErrorActionPreference = "Continue"

# Import modules
$modulePath = Join-Path $PSScriptRoot "modules"
Import-Module (Join-Path $modulePath "SSHConnection.psm1") -Force
Import-Module (Join-Path $modulePath "Logger.psm1") -Force

# Verify config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Host "ERROR: Configuration file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

# Load configuration
$config = Get-Content $ConfigFile | ConvertFrom-Json

# Initialize logger
$logDir = Join-Path $PSScriptRoot $config.logging.logDir
Initialize-Logger -LogDirectory $logDir -Level $config.logging.logLevel

Write-Host ""
Write-SectionHeader "HASHICORP VAULT CLUSTER SETUP"
Write-LogMessage "INFO" "Starting Vault cluster setup automation"
Write-LogMessage "INFO" "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-LogMessage "INFO" "Configuration: $ConfigFile"
Write-Host ""

# Display configuration
Write-LogMessage "INFO" "Configuration Details:"
Write-LogMessage "INFO" "  Remote Host: $($config.remote.host)"
Write-LogMessage "INFO" "  Username: $($config.remote.username)"
Write-LogMessage "INFO" "  Base Path: $($config.remote.basePath)"
Write-LogMessage "INFO" "  Namespace: $($config.deployment.namespace)"
Write-LogMessage "INFO" "  Release Name: $($config.deployment.releaseName)"
Write-Host ""

# Test SSH connection
Write-LogMessage "INFO" "Testing SSH connection to $($config.remote.username)@$($config.remote.host)..."
$connectionTest = Test-SSHConnection -RemoteHost $config.remote.host -Username $config.remote.username

if (-not $connectionTest) {
    Write-LogMessage "ERROR" "Cannot establish SSH connection to remote machine"
    Write-LogMessage "ERROR" "Please verify:"
    Write-LogMessage "ERROR" "  1. SSH service is running on remote machine"
    Write-LogMessage "ERROR" "  2. Network connectivity is available"
    Write-LogMessage "ERROR" "  3. SSH keys are configured or password is correct"
    Write-LogMessage "ERROR" "  4. Host '$($config.remote.host)' is resolvable"
    exit 1
}

Write-LogMessage "INFO" "✓ SSH connection successful"
Write-Host ""

# If TestConnection flag is set, exit here
if ($TestConnection) {
    Write-LogMessage "INFO" "Connection test completed successfully"
    exit 0
}

# Verify remote directories exist
Write-LogMessage "INFO" "Verifying remote directories..."
$basePath = $config.remote.basePath
$checkCmd = "test -d $basePath && ls -la $basePath"
$result = Invoke-RemoteCommand -RemoteHost $config.remote.host -Username $config.remote.username -Password $config.remote.password -Command $checkCmd

if (-not $result.Success) {
    Write-LogMessage "ERROR" "Base path not found: $basePath"
    exit 1
}

Write-LogMessage "INFO" "Remote directory structure:"
Write-LogMessage "INFO" $result.Output
Write-Host ""

# Check Kubernetes connectivity
Write-LogMessage "INFO" "Verifying Kubernetes cluster access..."
$k8sCheckCmd = "kubectl cluster-info"
$result = Invoke-RemoteCommand -RemoteHost $config.remote.host -Username $config.remote.username -Password $config.remote.password -Command $k8sCheckCmd

if ($result.Success) {
    Write-LogMessage "INFO" "✓ Kubernetes cluster accessible"
    Write-LogMessage "INFO" $result.Output
}
else {
    Write-LogMessage "WARN" "Kubernetes cluster check failed. Proceeding anyway..."
    Write-LogMessage "WARN" $result.Output
}
Write-Host ""

# Track deployment steps
$deploymentSteps = @()

# Step 1: Deploy Prerequisites
if (-not $SkipPrerequisites) {
    Write-SectionHeader "STEP 1: DEPLOYING PREREQUISITES"
    
    $prereqScript = Join-Path $PSScriptRoot "Deploy-Prerequisites.ps1"
    if (Test-Path $prereqScript) {
        try {
            & $prereqScript -ConfigFile $ConfigFile
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "INFO" "✓ Prerequisites deployment completed"
                $deploymentSteps += "Prerequisites: SUCCESS"
            }
            else {
                Write-LogMessage "ERROR" "✗ Prerequisites deployment failed"
                $deploymentSteps += "Prerequisites: FAILED"
                Write-LogMessage "ERROR" "Stopping deployment due to prerequisite failure"
                exit 1
            }
        }
        catch {
            Write-LogMessage "ERROR" "Error executing prerequisites script: $_"
            $deploymentSteps += "Prerequisites: ERROR"
            exit 1
        }
    }
    else {
        Write-LogMessage "ERROR" "Prerequisites script not found: $prereqScript"
        exit 1
    }
    Write-Host ""
}
else {
    Write-LogMessage "INFO" "Skipping prerequisites (as requested)"
    $deploymentSteps += "Prerequisites: SKIPPED"
}

# Step 2: Deploy Vault Cluster
if (-not $SkipClusterDeploy) {
    Write-SectionHeader "STEP 2: DEPLOYING VAULT CLUSTER"
    
    $clusterScript = Join-Path $PSScriptRoot "Deploy-VaultCluster.ps1"
    if (Test-Path $clusterScript) {
        try {
            & $clusterScript -ConfigFile $ConfigFile
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "INFO" "✓ Vault cluster deployment completed"
                $deploymentSteps += "Vault Cluster: SUCCESS"
            }
            else {
                Write-LogMessage "ERROR" "✗ Vault cluster deployment failed"
                $deploymentSteps += "Vault Cluster: FAILED"
                Write-LogMessage "ERROR" "Stopping deployment due to cluster failure"
                exit 1
            }
        }
        catch {
            Write-LogMessage "ERROR" "Error executing cluster script: $_"
            $deploymentSteps += "Vault Cluster: ERROR"
            exit 1
        }
    }
    else {
        Write-LogMessage "ERROR" "Cluster script not found: $clusterScript"
        exit 1
    }
    Write-Host ""
}
else {
    Write-LogMessage "INFO" "Skipping Vault cluster deployment (as requested)"
    $deploymentSteps += "Vault Cluster: SKIPPED"
}

# Step 3: Post-Installation
if (-not $SkipPostInstall) {
    Write-SectionHeader "STEP 3: POST-INSTALLATION CONFIGURATION"
    
    $postInstallScript = Join-Path $PSScriptRoot "Deploy-PostInstall.ps1"
    if (Test-Path $postInstallScript) {
        try {
            & $postInstallScript -ConfigFile $ConfigFile
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "INFO" "✓ Post-installation completed"
                $deploymentSteps += "Post-Install: SUCCESS"
            }
            else {
                Write-LogMessage "WARN" "Post-installation completed with warnings"
                $deploymentSteps += "Post-Install: COMPLETED WITH WARNINGS"
            }
        }
        catch {
            Write-LogMessage "WARN" "Error in post-installation (non-critical): $_"
            $deploymentSteps += "Post-Install: ERROR (NON-CRITICAL)"
        }
    }
    else {
        Write-LogMessage "WARN" "Post-install script not found: $postInstallScript"
        $deploymentSteps += "Post-Install: SCRIPT NOT FOUND"
    }
    Write-Host ""
}
else {
    Write-LogMessage "INFO" "Skipping post-installation (as requested)"
    $deploymentSteps += "Post-Install: SKIPPED"
}

# Final Summary
Write-SectionHeader "DEPLOYMENT SUMMARY"
Write-LogMessage "INFO" "Deployment Steps Completed:"
foreach ($step in $deploymentSteps) {
    Write-LogMessage "INFO" "  $step"
}
Write-Host ""

# Get final cluster status
Write-LogMessage "INFO" "Final Cluster Status:"
$statusCmd = "kubectl get all -n $($config.deployment.namespace)"
$result = Invoke-RemoteCommand -RemoteHost $config.remote.host -Username $config.remote.username -Password $config.remote.password -Command $statusCmd
Write-LogMessage "INFO" $result.Output
Write-Host ""

# Check Vault pods specifically
Write-LogMessage "INFO" "Vault Pods Status:"
$vaultPodsCmd = "kubectl get pods -n $($config.deployment.namespace) -l app.kubernetes.io/name=vault -o wide"
$result = Invoke-RemoteCommand -RemoteHost $config.remote.host -Username $config.remote.username -Password $config.remote.password -Command $vaultPodsCmd
Write-LogMessage "INFO" $result.Output
Write-Host ""

# Get Vault service endpoints
Write-LogMessage "INFO" "Vault Service Endpoints:"
$vaultSvcCmd = "kubectl get svc -n $($config.deployment.namespace) -l app.kubernetes.io/name=vault"
$result = Invoke-RemoteCommand -RemoteHost $config.remote.host -Username $config.remote.username -Password $config.remote.password -Command $vaultSvcCmd
Write-LogMessage "INFO" $result.Output
Write-Host ""

Write-SectionHeader "SETUP COMPLETED SUCCESSFULLY"
Write-LogMessage "INFO" "Vault cluster setup completed!"
Write-LogMessage "INFO" "Log file: $(Get-LogFilePath)"
Write-LogMessage "INFO" ""
Write-LogMessage "INFO" "Next Steps:"
Write-LogMessage "INFO" "  1. Initialize Vault: kubectl exec -n $($config.deployment.namespace) vault-0 -- vault operator init"
Write-LogMessage "INFO" "  2. Unseal Vault nodes with the unseal keys"
Write-LogMessage "INFO" "  3. Configure authentication methods and policies"
Write-LogMessage "INFO" "  4. Test Vault connectivity"
Write-Host ""

exit 0
