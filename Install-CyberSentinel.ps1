# CyberSentinel Agent Installation Script
# This script automates the installation of CyberSentinel agent on Windows systems

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   CyberSentinel Agent Installation Script     " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for Manager IP
$managerIP = Read-Host "Enter the Wazuh Manager IP address"

# Validate IP address format
if ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
    Write-Host "ERROR: Invalid IP address format!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Prompt for Agent Name
$agentName = Read-Host "Enter the Agent Name (e.g., Workstation-01)"

# Validate Agent Name (not empty)
if ([string]::IsNullOrWhiteSpace($agentName)) {
    Write-Host "ERROR: Agent name cannot be empty!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Yellow
Write-Host "  Manager IP: $managerIP" -ForegroundColor White
Write-Host "  Agent Name: $agentName" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Proceed with installation? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Host "Installation cancelled by user." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "[1/4] Downloading CA certificate..." -ForegroundColor Green

try {
    $caCertPath = "$env:TEMP\ca.cer"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" -OutFile $caCertPath -ErrorAction Stop
    Write-Host "  ✓ CA certificate downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to download CA certificate: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "[2/4] Importing CA certificate to Root store..." -ForegroundColor Green

try {
    Import-Certificate -FilePath $caCertPath -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop | Out-Null
    Write-Host "  ✓ CA certificate imported successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to import CA certificate: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "[3/4] Downloading CyberSentinel agent installer..." -ForegroundColor Green

try {
    $installerPath = "$env:TEMP\cybersentinel-agent.msi"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" -OutFile $installerPath -ErrorAction Stop
    Write-Host "  ✓ Installer downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to download installer: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "[4/5] Installing CyberSentinel agent..." -ForegroundColor Green

try {
    $msiArgs = "/i `"$installerPath`" /q WAZUH_MANAGER=`"$managerIP`" WAZUH_AGENT_GROUP=`"windows`" WAZUH_AGENT_NAME=`"$agentName`""
    Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -ErrorAction Stop
    Write-Host "  ✓ Installation completed successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Installation failed: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Installation completed successfully!        " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agent Details:" -ForegroundColor Yellow
Write-Host "  Manager IP: $managerIP" -ForegroundColor White
Write-Host "  Agent Name: $agentName" -ForegroundColor White
Write-Host "  Agent Group: windows" -ForegroundColor White
Write-Host ""

# Cleanup temporary files
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Path $caCertPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[5/5] Starting CyberSentinel service..." -ForegroundColor Green

try {
    NET START CyberSentinelSvc
    Write-Host "  ✓ CyberSentinel service started successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to start service: $_" -ForegroundColor Red
    Write-Host "  You may need to start it manually using: NET START CyberSentinelSvc" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"
