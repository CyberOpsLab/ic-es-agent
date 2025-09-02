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
$CaCertUrl    = 'https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/ca.crt'

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

  # Bail if already installed (avoid clobbering a live agent)
  if (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Elastic Agent' }) {
    Write-Warning 'Elastic Agent already installed. If you intend to re-install, run "elastic-agent uninstall" first.'
    return
  }

  # All work stays under USERPROFILE
  $folderName = "elastic-agent-$AgentVersion-$Arch"
  $zipName    = "$folderName.zip"
  $zipUrl     = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$zipName"

  $userRoot   = $env:USERPROFILE
  $baseDir    = Join-Path $userRoot $folderName
  $zipPath    = Join-Path $userRoot $zipName

  # Clean prior artifacts if present
  if (Test-Path $baseDir) {
    Write-Host ("Removing existing directory: {0}" -f $baseDir)
    Remove-Item -Path $baseDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
  }

  # Download archive to USERPROFILE
  Write-Host ("Downloading Elastic Agent {0}..." -f $AgentVersion)
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

  # Extract directly under USERPROFILE (creates $folderName)
  Write-Host 'Extracting archive...'
  Expand-Archive -Path $zipPath -DestinationPath $userRoot -Force

  # Optionally remove the zip (keeps only the directory under USERPROFILE)
  Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

  # cd into the agent directory
  Set-Location -Path $baseDir

  $agentExe = Join-Path $baseDir 'elastic-agent.exe'
  if (-not (Test-Path $agentExe)) { throw ("elastic-agent.exe not found at {0}" -f $agentExe) }

  # Download CA into the same directory
  $caPath = Join-Path $baseDir 'ca.crt'
  Write-Host ("Downloading CA certificate: {0}" -f $CaCertUrl)
  Invoke-WebRequest -Uri $CaCertUrl -OutFile $caPath
  if (-not (Test-Path $caPath)) { throw 'CA certificate download failed.' }

  # Optional: PEM sanity check
  $firstLine = (Get-Content -Path $caPath -First 1 -ErrorAction SilentlyContinue)
  if ($firstLine -notmatch 'BEGIN CERTIFICATE') {
    Write-Warning 'Downloaded CA does not look like PEM text. Ensure it is a PEM/CRT.'
  }

  # Install with --certificate-authorities
  $args = @(
    'install',
    "--url=$FleetUrl",
    "--enrollment-token=$EnrollmentToken",
    "--certificate-authorities=`"$caPath`""
  )
  Write-Host ('Running: "{0}" {1}' -f $agentExe, ($args -join ' '))
  & $agentExe @args

  # Wait ~20s before checking status
  Start-Sleep -Seconds 20

  # Ensure service is running (best effort)
  $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Elastic Agent' }
  if ($svc) {
    if ($svc.Status -ne 'Running') {
      Start-Service -Name 'Elastic Agent' -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
    Write-Host ('Elastic Agent service state: {0}' -f (Get-Service 'Elastic Agent').Status)
  } else {
    Write-Warning 'Elastic Agent service not found—check logs in C:\Program Files\Elastic\Agent\logs'
  }

  # Persist CA into installed path as well (handy for future troubleshooting)
  $installedDir = 'C:\Program Files\Elastic\Agent'
  if (Test-Path $installedDir) {
    Copy-Item -Path $caPath -Destination (Join-Path $installedDir 'ca.crt') -Force
  }

  # Final status output (after the 20s wait)
  $cli = 'C:\Program Files\Elastic\Agent\elastic-agent.exe'
  if (Test-Path $cli) {
    Write-Host "`n=== elastic-agent status (after 20s) ==="
    & $cli status 2>$null | Out-String | Write-Host
  } else {
    Write-Warning "CLI not found at $cli"
  }

  Write-Host ("`nInstall complete.")
  Write-Host ("Working directory: {0}" -f $baseDir)
  Write-Host ("CA certificate stored at: {0}" -f $caPath)
}
catch {
  Write-Error $_.Exception.Message
  if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage }
  exit 1
}
