<# 
Install Elastic Agent on Windows with a bundled CA certificate.
- Params: Fleet URL, Enrollment Token
- CA cert URL + Agent version are fixed in this script.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FleetUrl,

  [Parameter(Mandatory = $true)]
  [string]$EnrollmentToken
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ======= FIXED VALUES =======
$AgentVersion = "9.1.3"
$Arch         = "windows-x86_64"
$CaCertUrl    = "https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/ca.crt"
# ============================

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script in an elevated (Administrator) PowerShell."
  }
}

try {
  Assert-Admin
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  # Prevent overwrite if already installed
  if (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Elastic Agent" }) {
    Write-Warning "Elastic Agent already installed. If you intend to re-install, run 'elastic-agent uninstall' first."
    return
  }

  $zipName = "elastic-agent-$AgentVersion-$Arch.zip"
  $zipUrl  = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$zipName"
  $workDir = Join-Path $env:TEMP ("elastic-agent-install-" + [Guid]::NewGuid().ToString("N"))
  New-Item -Path $workDir -ItemType Directory | Out-Null

  $zipPath = Join-Path $workDir $zipName
  Write-Host "Downloading Elastic Agent $AgentVersion..."
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

  Write-Host "Extracting archive..."
  Expand-Archive -Path $zipPath -DestinationPath $workDir -Force

  $agentDir = Join-Path $workDir "elastic-agent-$AgentVersion-$Arch"
  $agentExe = Join-Path $agentDir "elastic-agent.exe"
  if (-not (Test-Path $agentExe)) { throw "elastic-agent.exe not found at $agentExe" }

  # Download CA cert into agent directory
  $caPath = Join-Path $agentDir "ca.crt"
  Write-Host "Downloading CA certificate: $CaCertUrl"
  Invoke-WebRequest -Uri $CaCertUrl -OutFile $caPath
  if (-not (Test-Path $caPath)) { throw "CA certificate download failed." }

  # Optional: sanity check PEM header
  $firstLine = (Get-Content -Path $caPath -First 1 -ErrorAction SilentlyContinue)
  if ($firstLine -notmatch "BEGIN CERTIFICATE") {
    Write-Warning "Downloaded CA does not look like PEM text. Ensure it's a PEM/CRT trusted by Elastic."
  }

  # Install with --certificate-authorities (quote the path safely)
  $args = @(
    "install",
    "--url=$FleetUrl",
    "--enrollment-token=$EnrollmentToken",
    "--certificate-authorities=`"$caPath`""
  )
  Write-Host "Running: `"$agentExe`" $($args -join ' ')"
  & $agentExe @args

  Start-Sleep -Seconds 3

  # Ensure service is running
  $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Elastic Agent" }
  if ($svc) {
    if ($svc.Status -ne "Running") {
      Start-Service -Name "Elastic Agent" -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
    Write-Host ("Elastic Agent service state: " + (Get-Service 'Elastic Agent').Status)
  } else {
    Write-Warning "Elastic Agent service not found—check logs in C:\Program Files\Elastic\Agent\logs"
  }

  # Copy CA into installed directory for persistence
  $installedDir = "C:\Program Files\Elastic\Agent"
  if (Test-Path $installedDir) {
    Copy-Item -Path $caPath -Destination (Join-Path $installedDir "ca.crt") -Force
  }

  # Status
  $cli = "C:\Program Files\Elastic\Agent\elastic-agent.exe"
  if (Test-Path $cli) {
    Write-Host "`n=== elastic-agent status ==="
    & $cli status 2>$null | Out-String | Write-Host
  }

  Write-Host "`nInstall complete. CA certificate stored at: $caPath"
}
catch {
  Write-Error $_.Exception.Message
  if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage }
  exit 1
}
