# SSHConnection.psm1
# Module for managing SSH connections to remote Vault cluster

function Test-SSHConnection {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteHost,
        
        [Parameter(Mandatory=$true)]
        [string]$Username
    )
    
    Write-Host "Testing SSH connection to ${Username}@${RemoteHost}..." -ForegroundColor Cyan
    
    try {
        $result = ssh -o ConnectTimeout=5 -o BatchMode=yes "${Username}@${RemoteHost}" "echo 'Connection successful'" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ SSH connection successful" -ForegroundColor Green
            return $true
        }
        return $false
    }
    catch {
        Write-Host "✗ SSH connection failed: $_" -ForegroundColor Red
        return $false
    }
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteHost,
        
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$Password,
        
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [switch]$UseExpect = $false
    )
    
    Write-Host "Executing: $Command" -ForegroundColor Yellow
    
    if ($UseExpect) {
        # Use sshpass or expect-like approach for password authentication
        $sshCommand = "sshpass -p '$Password' ssh -o StrictHostKeyChecking=no ${Username}@${RemoteHost} `"$Command`""
    }
    else {
        # Try to use existing SSH key authentication first
        $sshCommand = "ssh -o StrictHostKeyChecking=no ${Username}@${RemoteHost} `"$Command`""
    }
    
    try {
        $output = Invoke-Expression $sshCommand 2>&1
        $exitCode = $LASTEXITCODE
        
        return @{
            Output = $output
            ExitCode = $exitCode
            Success = ($exitCode -eq 0)
        }
    }
    catch {
        Write-Host "✗ Command execution failed: $_" -ForegroundColor Red
        return @{
            Output = $_.Exception.Message
            ExitCode = 1
            Success = $false
        }
    }
}

function Copy-ToRemote {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteHost,
        
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$LocalPath,
        
        [Parameter(Mandatory=$true)]
        [string]$RemotePath
    )
    
    Write-Host "Copying $LocalPath to ${Username}@${RemoteHost}:${RemotePath}" -ForegroundColor Cyan
    
    try {
        scp -o StrictHostKeyChecking=no -r "$LocalPath" "${Username}@${RemoteHost}:${RemotePath}"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ File transfer successful" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ File transfer failed" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ File transfer error: $_" -ForegroundColor Red
        return $false
    }
}

function Get-RemoteFileContent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteHost,
        
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilePath
    )
    
    $command = "cat $RemoteFilePath"
    $result = Invoke-RemoteCommand -RemoteHost $RemoteHost -Username $Username -Password "" -Command $command
    
    if ($result.Success) {
        return $result.Output
    }
    else {
        return $null
    }
}

Export-ModuleMember -Function Test-SSHConnection, Invoke-RemoteCommand, Copy-ToRemote, Get-RemoteFileContent
