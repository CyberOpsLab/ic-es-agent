# PowerShell Script to Install iCompaas-EDR Agent in Current User's Folder on Windows

# Variables
$elasticAgentVersion = "9.1.3"
$caCrtUrl = "https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/ca.crt"
$elasticAgentUrl = "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$elasticAgentVersion-windows-x86_64.zip"
$currentDir = Get-Location
$installPath = Join-Path -Path $env:USERPROFILE -ChildPath "iCompaas-EDR\Agent"
$downloadPath = Join-Path -Path $currentDir -ChildPath "elastic-agent-$elasticAgentVersion-windows-x86_64.zip"
$extractDir = Join-Path -Path $currentDir -ChildPath "elastic-agent-$elasticAgentVersion"
$certPath = Join-Path -Path $installPath -ChildPath "ca.crt"
$scriptUrl = "https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/windows-x86_64.ps1"
$scriptPath = Join-Path -Path $currentDir -ChildPath "windows-x86_64.ps1"

# Trap errors and perform rollback
trap {
    Write-Host "Error occurred: $_"
    Write-Host "Rolling back changes..."

    # Stop Elastic Agent service if running
    $service = Get-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Stop-Service -Name "elastic-agent" -Force -ErrorAction Continue
    }

    # Remove downloaded files and directories
    if (Test-Path $downloadPath) { Remove-Item -Path $downloadPath -Force -ErrorAction Continue }
    if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction Continue }
    if (Test-Path $scriptPath) { Remove-Item -Path $scriptPath -Force -ErrorAction Continue }
    if (Test-Path $installPath) { Remove-Item -Path $installPath -Recurse -Force -ErrorAction Continue }

    # Revert execution policy if changed
    if ($originalExecutionPolicy -and $originalExecutionPolicy -ne "Bypass") {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $originalExecutionPolicy -Force -ErrorAction Continue
    }

    exit 1
}

# Ensure TLS 1.2 for secure downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Suppress download progress
$ProgressPreference = 'SilentlyContinue'

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script requires administrative privileges. Please run as Administrator."
    exit 1
}

# Store original execution policy and set to Bypass if necessary
$originalExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
if ($originalExecutionPolicy -ne "Bypass") {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
}

# Define parameters
param (
    [Parameter(Mandatory=$true)][string]$url,
    [Parameter(Mandatory=$true)][string]$enrollment_token
)

# Stop Elastic Agent service if running
$service = Get-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Stop-Service -Name "elastic-agent" -Force -ErrorAction Stop
}

# Check if directories exist and delete if they do
if (Test-Path $extractDir) {
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction Stop
}
if (Test-Path $installPath) {
    Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
}

# Check if script exists and delete if it does
if (Test-Path $scriptPath) {
    Remove-Item -Path $scriptPath -Force
}

# Download the script
Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath

# Download Elastic Agent
Invoke-WebRequest -Uri $elasticAgentUrl -OutFile $downloadPath
if (-not (Test-Path $downloadPath)) {
    throw "Failed to download Elastic Agent."
}

# Extract the downloaded zip
Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force

# Download CA certificate to extract directory
$tempCertPath = Join-Path -Path $extractDir -ChildPath "ca.crt"
Invoke-WebRequest -Uri $caCrtUrl -OutFile $tempCertPath
if (-not (Test-Path $tempCertPath)) {
    throw "Failed to download CA certificate."
}

# Create installation directory
New-Item -Path $installPath -ItemType Directory -Force

# Move files to installation directory
Move-Item -Path (Join-Path -Path $extractDir -ChildPath "elastic-agent-$elasticAgentVersion-windows-x86_64\*") -Destination $installPath -Force
Move-Item -Path $tempCertPath -Destination $certPath -Force

# Change to the installation directory
Set-Location -Path $installPath

# Install iCompaas-EDR Agent
$installResult = Start-Process -FilePath ".\elastic-agent.exe" -ArgumentList "install --url=$url --enrollment-token=$enrollment_token --certificate-authorities=$certPath" -Wait -PassThru
if ($installResult.ExitCode -ne 0) {
    throw "Elastic Agent installation failed with exit code $($installResult.ExitCode)."
}

# Silent cleanup of downloaded zip file
Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue

# Start Elastic Agent service if it was running
if ($service -and $service.Status -ne "Running") {
    Start-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
}

# Revert execution policy to original setting
if ($originalExecutionPolicy -and $originalExecutionPolicy -ne "Bypass") {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $originalExecutionPolicy -Force -ErrorAction SilentlyContinue
}
