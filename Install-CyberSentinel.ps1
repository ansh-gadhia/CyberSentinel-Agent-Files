# ================================
# CyberSentinel Agent Installation Script
# ================================

try {
    # ================================
    # GLOBAL HARDENING (MANDATORY)
    # ================================
    $ErrorActionPreference = "Stop"
    $ProgressPreference   = "SilentlyContinue"

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

    # ================================
    # STEP 1: USER INPUT
    # ================================
    $managerIP = Read-Host "Enter the CyberSentinel Manager IP address"

    # Validate IP address format
    if ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
        Write-Host "ERROR: Invalid IP address format!" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    $agentName = Read-Host "Enter the CyberSentinel Agent name (e.g., Workstation-01)"

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

    # ================================
    # STEP 2: GITHUB TOKEN CONFIG (for private repo)
    # ================================
    # IMPORTANT: Replace this with your valid GitHub Personal Access Token
    # This is needed to access the PRIVATE config files repository
    # Generate token at: https://github.com/settings/tokens (needs 'repo' scope)
    
    $githubToken = "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"
    
    if ($githubToken -eq "YOUR_GITHUB_TOKEN_HERE" -or [string]::IsNullOrWhiteSpace($githubToken)) {
        Write-Host "ERROR: GitHub token not configured!" -ForegroundColor Red
        Write-Host "This token is required to access private configuration files." -ForegroundColor Yellow
        Write-Host "Please edit the script and replace 'YOUR_GITHUB_TOKEN_HERE' with your token." -ForegroundColor Yellow
        Write-Host "Generate a token at: https://github.com/settings/tokens" -ForegroundColor Cyan
        Read-Host "Press Enter to exit"
        exit 1
    }

    # GitHub API headers for private repo access
    $headers = @{
        Authorization = "Bearer $githubToken"
        "User-Agent"  = "CyberSentinel-Agent-Installer"
        Accept        = "application/vnd.github+json"
    }

    # Private repo configuration
    $privateRepoOwner = "cybersentinel-06"
    $privateRepoName  = "CyberSentinel-SIEM"

    # ================================
    # STEP 3: VALIDATE GITHUB ACCESS
    # ================================
    Write-Host ""
    Write-Host "[1/8] Validating GitHub access to private repository..." -ForegroundColor Green

    $filesToValidate = @(
        "AGENTS/WINDOWS-AGENT/ossec.conf",
        "AGENTS/WINDOWS-AGENT/enrich.ps1",
        "AGENTS/WINDOWS-AGENT/sysmon.ps1"
    )

    foreach ($file in $filesToValidate) {
        $validationUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$file"
        
        try {
            $response = Invoke-WebRequest -Uri $validationUrl -Headers $headers -Method GET -UseBasicParsing
            Write-Host "  ✓ Access verified for: $file" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to access: $file" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Troubleshooting:" -ForegroundColor Yellow
            Write-Host "  1. Verify repository exists: https://github.com/$privateRepoOwner/$privateRepoName" -ForegroundColor White
            Write-Host "  2. Check file path: $file" -ForegroundColor White
            Write-Host "  3. Ensure token has 'repo' scope" -ForegroundColor White
            Write-Host "  4. Verify token owner has repository access" -ForegroundColor White
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    Write-Host "  ✓ Private repository access validated successfully" -ForegroundColor Green

    # ================================
    # STEP 4: DOWNLOAD CA CERTIFICATE (public repo)
    # ================================
    Write-Host ""
    Write-Host "[2/8] Downloading CA certificate..." -ForegroundColor Green

    $caCertPath = "$env:TEMP\ca.cer"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" -OutFile $caCertPath -UseBasicParsing
    Write-Host "  ✓ CA certificate downloaded successfully" -ForegroundColor Green

    # ================================
    # STEP 5: IMPORT CA CERTIFICATE
    # ================================
    Write-Host ""
    Write-Host "[3/8] Importing CA certificate to Root store..." -ForegroundColor Green

    Import-Certificate -FilePath $caCertPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "  ✓ CA certificate imported successfully" -ForegroundColor Green

    # ================================
    # STEP 6: DOWNLOAD INSTALLER (public repo)
    # ================================
    Write-Host ""
    Write-Host "[4/8] Downloading CyberSentinel agent installer..." -ForegroundColor Green

    $installerPath = "$env:TEMP\cybersentinel-agent.msi"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" -OutFile $installerPath -UseBasicParsing
    Write-Host "  ✓ Installer downloaded successfully" -ForegroundColor Green

    # ================================
    # STEP 7: INSTALL AGENT
    # ================================
    Write-Host ""
    Write-Host "[5/8] Installing CyberSentinel agent..." -ForegroundColor Green

    $arguments = @(
        "/i",
        "`"$installerPath`"",
        "/q",
        "WAZUH_MANAGER=$managerIP",
        "WAZUH_AGENT_GROUP=windows",
        "WAZUH_AGENT_NAME=$agentName"
    )

    Start-Process msiexec.exe -ArgumentList $arguments -Wait
    Write-Host "  ✓ Installation completed successfully" -ForegroundColor Green

    # ================================
    # STEP 8: ENV + CONFIG SETUP
    # ================================
    Write-Host ""
    Write-Host "[6/8] Configuring environment..." -ForegroundColor Green

    $ossecConfPath = "C:\Program Files (x86)\ossec-agent\ossec.conf"
    $ossecDir      = Split-Path $ossecConfPath
    $envFilePath   = Join-Path $ossecDir ".env"

    @(
        "ManagerIP=$managerIP"
        "AgentName=$agentName"
    ) | Set-Content -Path $envFilePath -Encoding UTF8

    Write-Host "  ✓ Environment configured successfully" -ForegroundColor Green

    # ================================
    # STEP 9: DOWNLOAD SECRET CONFIG FILES (private repo with token)
    # ================================
    Write-Host ""
    Write-Host "[7/8] Fetching secret configuration files from private repository..." -ForegroundColor Green

    function Download-GitHubFile {
        param (
            [string]$RepoPath,
            [string]$Destination
        )

        $apiUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$RepoPath"
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
        $content  = [System.Text.Encoding]::UTF8.GetString(
                        [System.Convert]::FromBase64String($response.content)
                    )
        Set-Content -Path $Destination -Value $content -Encoding UTF8
    }

    # Download ossec.conf
    Write-Host "  → Downloading ossec.conf..." -ForegroundColor Cyan
    Download-GitHubFile `
        -RepoPath "AGENTS/WINDOWS-AGENT/ossec.conf" `
        -Destination $ossecConfPath

    # Download and execute enrich.ps1
    $enrichScriptPath = Join-Path $ossecDir "enrich.ps1"
    Write-Host "  → Downloading enrich.ps1..." -ForegroundColor Cyan
    Download-GitHubFile `
        -RepoPath "AGENTS/WINDOWS-AGENT/enrich.ps1" `
        -Destination $enrichScriptPath

    Write-Host "  → Executing enrich.ps1..." -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File $enrichScriptPath

    # Download and execute sysmon.ps1
    $sysmonScriptPath = Join-Path $ossecDir "sysmon.ps1"
    Write-Host "  → Downloading sysmon.ps1..." -ForegroundColor Cyan
    Download-GitHubFile `
        -RepoPath "AGENTS/WINDOWS-AGENT/sysmon.ps1" `
        -Destination $sysmonScriptPath

    Write-Host "  → Executing sysmon.ps1..." -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File $sysmonScriptPath

    Write-Host "  ✓ Secret configuration files downloaded and executed successfully" -ForegroundColor Green

    # ================================
    # STEP 10: START SERVICE
    # ================================
    Write-Host ""
    Write-Host "[8/8] Starting CyberSentinel service..." -ForegroundColor Green

    NET START CyberSentinelSvc
    Write-Host "  ✓ CyberSentinel service started successfully" -ForegroundColor Green

    # ================================
    # CLEANUP
    # ================================
    Write-Host ""
    Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
    Remove-Item -Path $caCertPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Installation completed successfully!        " -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Agent Details:" -ForegroundColor Yellow
    Write-Host "  Manager IP: $managerIP" -ForegroundColor White
    Write-Host "  Agent Name: $agentName" -ForegroundColor White
    Write-Host "  Agent Group: windows" -ForegroundColor White
    Write-Host "  Service Status: Running" -ForegroundColor Green
    Write-Host ""
    Write-Host "CyberSentinel Agent Installed Successfully!" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   [INSTALLATION ERROR]                        " -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
