# Logger.psm1
# Module for logging deployment activities

$script:LogFile = ""
$script:LogLevel = "INFO"

function Initialize-Logger {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )
    
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $LogDirectory "vault_setup_$timestamp.log"
    $script:LogLevel = $Level
    
    Write-LogMessage "INFO" "Logger initialized. Log file: $script:LogFile"
}

function Write-LogMessage {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level,
        
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logEntry
    }
    
    # Write to console with colors
    $color = switch ($Level) {
        "DEBUG" { "Gray" }
        "INFO"  { "White" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

function Write-SectionHeader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )
    
    $separator = "=" * 80
    Write-LogMessage "INFO" $separator
    Write-LogMessage "INFO" "  $Title"
    Write-LogMessage "INFO" $separator
}

function Get-LogFilePath {
    return $script:LogFile
}

Export-ModuleMember -Function Initialize-Logger, Write-LogMessage, Write-SectionHeader, Get-LogFilePath
