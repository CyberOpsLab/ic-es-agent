# PowerShell Script to Install iCompaas-EDR Agent in Current Directory on Windows

# Variables
$elasticAgentVersion = "9.1.3"
$caCrtUrl = "https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/ca.crt"
$elasticAgentUrl = "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$elasticAgentVersion-windows-x86_64.zip"
$downloadPath = ".\elastic-agent-$elasticAgentVersion-windows-x86_64.zip"
$extractDir = ".\elastic-agent-$elasticAgentVersion"
$installPath = "C:\Program Files\Elastic\Agent"
$currentDir = Get-Location
$certPath = Join-Path -Path $installPath -ChildPath "ca.crt"
$scriptUrl = "https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/windows-x86_64.ps1"
$scriptPath = ".\windows-x86_64.ps1"

# Trap errors and perform rollback with detailed error reporting
trap {
    Write-Host "Error occurred: $_"
    Write-Host "Rolling back changes..."

    # Stop Elastic Agent service if running
    $service = Get-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "Stopping Elastic Agent service..."
        Stop-Service -Name "elastic-agent" -Force -ErrorAction Stop
    }

    # Remove downloaded files and directories with error reporting
    if (Test-Path $downloadPath) {
        Write-Host "Removing $downloadPath..."
        Remove-Item -Path $downloadPath -Force -ErrorAction Continue
    }
    if (Test-Path $extractDir) {
        Write-Host "Removing $extractDir..."
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction Continue
    }
    if (Test-Path $scriptPath) {
        Write-Host "Removing $scriptPath..."
        Remove-Item -Path $scriptPath -Force -ErrorAction Continue
    }
    if (Test-Path $installPath) {
        Write-Host "Removing $installPath..."
        Remove-Item -Path $installPath -Recurse -Force -ErrorAction Continue
    }

    # Revert execution policy if changed
    if ($originalExecutionPolicy -and $originalExecutionPolicy -ne "Bypass") {
        Write-Host "Reverting execution policy to $originalExecutionPolicy..."
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $originalExecutionPolicy -Force -ErrorAction Continue
    }

    exit 1
}

# Ensure the script runs with PowerShell by forcing execution policy
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "Error: PowerShell version 3.0 or higher is required."
    exit 1
}
$originalExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
if ($originalExecutionPolicy -ne "Bypass") {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to set execution policy. Run with administrative privileges or manually set to Bypass."
        exit 1
    }
}

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script requires administrative privileges. Please run as Administrator."
    exit 1
}

# Define parameters
param (
    [Parameter(Mandatory=$true)][string]$url,
    [Parameter(Mandatory=$true)][string]$token
)

# Suppress download progress
$ProgressPreference = 'SilentlyContinue'

# Ensure TLS 1.2 for secure downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Stop Elastic Agent service if running
$service = Get-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Write-Host "Stopping Elastic Agent service..."
    Stop-Service -Name "elastic-agent" -Force -ErrorAction Stop
}

# Check if directories exist and delete if they do
if (Test-Path $extractDir) {
    Write-Host "Removing existing $extractDir..."
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction Stop
}
if (Test-Path $installPath) {
    Write-Host "Removing existing $installPath..."
    Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
}

# Check if script exists and delete if it does
if (Test-Path $scriptPath) {
    Remove-Item -Path $scriptPath -Force
}

# Download the script
Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath

# Download Elastic Agent
Write-Host "Downloading iCompaas-EDR Agent $elasticAgentVersion to $downloadPath..."
Invoke-WebRequest -Uri $elasticAgentUrl -OutFile $downloadPath
if (-not (Test-Path $downloadPath)) {
    Write-Host "Error: Failed to download iCompaas-EDR Agent."
    exit 1
}

# Extract the downloaded zip
Write-Host "Extracting iCompaas-EDR Agent to $extractDir..."
Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force

# Download CA certificate
Write-Host "Downloading CA certificate to $certPath..."
Invoke-WebRequest -Uri $caCrtUrl -OutFile (Join-Path -Path $extractDir -ChildPath "ca.crt")
if (-not (Test-Path (Join-Path -Path $extractDir -ChildPath "ca.crt"))) {
    Write-Host "Error: Failed to download CA certificate."
    exit 1
}

# Create installation directory if it doesn't exist
if (-not (Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force
}

# Move files to installation directory
Write-Host "Moving files to $installPath..."
Move-Item -Path "$extractDir\elastic-agent-$elasticAgentVersion-windows-x86_64\*" -Destination $installPath -Force
Move-Item -Path (Join-Path -Path $extractDir -ChildPath "ca.crt") -Destination $certPath -Force

# Change to the installation directory
Set-Location -Path $installPath

# Install iCompaas-EDR Agent
Write-Host "Installing iCompaas-EDR Agent..."
$installArgs = "install --url=$url --token=$token --certificate-authorities=$certPath"
$installResult = Start-Process -FilePath ".\elastic-agent.exe" -ArgumentList $installArgs -Wait -PassThru
if ($installResult.ExitCode -ne 0) {
    Write-Host "Error: iCompaas-EDR Agent installation failed with exit code $($installResult.ExitCode)."
    exit 1
}

# Cleanup only the downloaded zip file
Write-Host "Cleaning up downloaded zip file..."
Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue

# Start Elastic Agent service if it was running
if ($service -and $service.Status -ne "Running") {
    Write-Host "Starting Elastic Agent service..."
    Start-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
}

# Revert execution policy to original setting
if ($originalExecutionPolicy -and $originalExecutionPolicy -ne "Bypass") {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $originalExecutionPolicy -Force -ErrorAction SilentlyContinue
}

Write-Host "iCompaas-EDR Agent installation completed in $installPath."
Write-Host "Extracted files remain in $extractDir."
