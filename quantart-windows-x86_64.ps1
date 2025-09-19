[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$FleetUrl,
  [Parameter(Mandatory = $true)][string]$EnrollmentToken
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Fixed values
$AgentVersion = '9.1.3'
$Arch         = 'windows-x86_64'
$CaCertUrl    = 'https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/quant-ca.crt'

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated (Administrator) PowerShell.'
  }
}

try {
  Assert-Admin
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  # Work entirely under USERPROFILE
  $userRoot   = $env:USERPROFILE
  $folderName = "elastic-agent-$AgentVersion-$Arch"
  $zipName    = "$folderName.zip"
  $zipUrl     = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$zipName"
  $baseDir    = Join-Path $userRoot $folderName
  $zipPath    = Join-Path $userRoot $zipName

  # Clean any prior artifacts in USERPROFILE
  if (Test-Path $baseDir) {
    Write-Host ("Removing existing directory: {0}" -f $baseDir)
    Remove-Item -Path $baseDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
  }

  # Download archive to USERPROFILE
  Write-Host ("Downloading iCompaas-EDR Agent {0}..." -f $AgentVersion)
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

  # Extract directly under USERPROFILE (creates $folderName)
  Write-Host 'Extracting archive...'
  Expand-Archive -Path $zipPath -DestinationPath $userRoot -Force

  # Remove the zip (keep only the directory)
  Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

  # cd into the agent directory
  Set-Location -Path $baseDir

  $agentExe = Join-Path $baseDir 'elastic-agent.exe'
  if (-not (Test-Path $agentExe)) { throw ("elastic-agent.exe not found at {0}" -f $agentExe) }

  # Download CA into the same directory
  $caPath = Join-Path $baseDir 'quant-ca.crt'
  Write-Host ("Downloading your Organization CA certificate: {0}" -f $CaCertUrl)
  Invoke-WebRequest -Uri $CaCertUrl -OutFile $caPath
  if (-not (Test-Path $caPath)) { throw 'CA certificate download failed.' }

  # Optional: PEM sanity check (does not affect install)
  $firstLine = (Get-Content -Path $caPath -First 1 -ErrorAction SilentlyContinue)
  if ($firstLine -notmatch 'BEGIN CERTIFICATE') {
    Write-Warning 'Downloaded CA does not look like PEM text. Ensure it is a PEM/CRT.'
  }

  # Install with --certificate-authorities pointing to ca.crt we just downloaded
  $args = @(
    'install',
    "--url=$FleetUrl",
    "--enrollment-token=$EnrollmentToken",
    "--certificate-authorities=`"$caPath`""
  )
  Write-Host ('Running: "{0}" {1}' -f $agentExe, ($args -join ' '))
  & $agentExe @args

  # Persist a copy of the CA into the installed path (helpful for later troubleshooting)
  $installedDir = 'C:\Program Files\Elastic\Agent'
  if (Test-Path $installedDir) {
    Copy-Item -Path $caPath -Destination (Join-Path $installedDir 'quant-ca.crt') -Force
  }

  Write-Host ("`nInstall step invoked. Working directory: {0}" -f $baseDir)
  Write-Host ("CA certificate stored at: {0}" -f $caPath)
}
catch {
  Write-Error $_.Exception.Message
  if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage }
  exit 1
}
