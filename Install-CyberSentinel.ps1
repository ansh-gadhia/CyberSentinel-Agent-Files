# ================================
# CyberSentinel Agent Installation Script
# Fixed Version - Handles Group Registration Properly
# ================================

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [switch]$ManualRegistration
)

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
    Write-Host "   Version 2.0 - Fixed Group Registration      " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # ================================
    # STEP 1: ASK FOR MANAGER IP AND AGENT NAME
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

    # Ask about registration method
    if (-not $ManualRegistration) {
        Write-Host "Registration Method:" -ForegroundColor Yellow
        Write-Host "  [1] Auto-registration (requires 'windows' group on manager)" -ForegroundColor White
        Write-Host "  [2] Manual registration (you'll register agent manually later)" -ForegroundColor White
        $regChoice = Read-Host "Choose registration method (1 or 2)"
        
        if ($regChoice -eq "2") {
            $ManualRegistration = $true
        }
    }
    Write-Host ""

    # ================================
    # STEP 2: VERIFY TOKEN
    # ================================
    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        Write-Host "ERROR: GitHub token not provided!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host '  iex "& { $(irm https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/Install-CyberSentinel.ps1) } -GitHubToken ''YOUR_TOKEN''"' -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Generate a token at: https://github.com/settings/tokens (needs 'repo' scope)" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Private repo configuration
    $privateRepoOwner = "cybersentinel-06"
    $privateRepoName  = "CyberSentinel-SIEM"

    # GitHub API headers
    $headers = @{
        Authorization = "Bearer $GitHubToken"
        "User-Agent"  = "CyberSentinel-Agent-Installer"
        Accept        = "application/vnd.github+json"
    }

    # ================================
    # STEP 3: VALIDATE ACCESS
    # ================================
    Write-Host "[1/8] Validating GitHub access to private repository..." -ForegroundColor Green

    $filesToValidate = @(
        "AGENTS/WINDOWS-AGENT/ossec.conf",
        "AGENTS/WINDOWS-AGENT/enrich.ps1",
        "AGENTS/WINDOWS-AGENT/sysmon.ps1"
    )

    foreach ($file in $filesToValidate) {
        $validationUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$file"
        
        try {
            Invoke-WebRequest -Uri $validationUrl -Headers $headers -Method GET -UseBasicParsing | Out-Null
        } catch {
            Write-Host "  ✗ Failed to access: $file" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Verify:" -ForegroundColor Yellow
            Write-Host "  - Repository: https://github.com/$privateRepoOwner/$privateRepoName" -ForegroundColor White
            Write-Host "  - Token has 'repo' scope" -ForegroundColor White
            Write-Host "  - Token owner has repository access" -ForegroundColor White
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    Write-Host "  ✓ GitHub access validated successfully" -ForegroundColor Green

    # ================================
    # STEP 4: DOWNLOAD AND INSTALL CYBERSENTINEL AGENT
    # ================================
    Write-Host ""
    Write-Host "[2/8] Downloading and installing CyberSentinel agent..." -ForegroundColor Green

    # Download CA certificate
    Write-Host "  → Downloading CA certificate..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" -OutFile "$env:TEMP\ca.cer" -UseBasicParsing

    # Import CA certificate
    Write-Host "  → Importing CA certificate..." -ForegroundColor Cyan
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

    # Download MSI installer
    Write-Host "  → Downloading installer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing

    # Install agent WITHOUT group assignment
    Write-Host "  → Installing agent..." -ForegroundColor Cyan
    $msiLogPath = "$env:TEMP\cybersentinel-install.log"
    
    # Build installation arguments
    $installArgs = @(
        "/i"
        "`"$env:TEMP\cybersentinel-agent.msi`""
        "/qn"
        "/norestart"
        "WAZUH_MANAGER=`"$managerIP`""
        "WAZUH_AGENT_NAME=`"$agentName`""
        "/L*v"
        "`"$msiLogPath`""
    )
    
    # Execute installation and wait for completion
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Host "  ✗ Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        Write-Host "  Check log: $msiLogPath" -ForegroundColor Yellow
        throw "MSI installation failed"
    }
    
    # Wait for service registration
    Start-Sleep -Seconds 3

    Write-Host "  ✓ CyberSentinel agent installed successfully" -ForegroundColor Green

    # ================================
    # STEP 5: VERIFY INSTALLATION DIRECTORY EXISTS
    # ================================
    Write-Host ""
    Write-Host "[3/8] Verifying installation..." -ForegroundColor Green
    
    $ossecDir = "C:\Program Files (x86)\ossec-agent"
    
    if (-not (Test-Path $ossecDir)) {
        Write-Host "  ✗ Installation directory not found: $ossecDir" -ForegroundColor Red
        throw "Agent installation directory does not exist"
    }
    
    # Verify critical files exist
    $criticalFiles = @(
        "ossec-agent.exe",
        "manage_agents.exe",
        "agent-auth.exe"
    )
    
    foreach ($file in $criticalFiles) {
        $filePath = Join-Path $ossecDir $file
        if (-not (Test-Path $filePath)) {
            Write-Host "  ✗ Critical file missing: $file" -ForegroundColor Red
            throw "Installation incomplete"
        }
    }
    
    Write-Host "  ✓ Installation directory verified: $ossecDir" -ForegroundColor Green

    # ================================
    # STEP 6: WRITE .ENV FILE
    # ================================
    Write-Host ""
    Write-Host "[4/8] Creating environment configuration..." -ForegroundColor Green

    $envFilePath = Join-Path $ossecDir ".env"

    @(
        "ManagerIP=$managerIP"
        "AgentName=$agentName"
        "InstallDate=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path $envFilePath -Encoding UTF8

    Write-Host "  ✓ Environment file created: $envFilePath" -ForegroundColor Green

    # ================================
    # STEP 7: FETCH CONFIG/SCRIPTS FROM GITHUB
    # ================================
    Write-Host ""
    Write-Host "[5/8] Fetching configuration files from private repository..." -ForegroundColor Green

    # Helper function to download files from GitHub API
    function Download-GitHubFile {
        param (
            [string]$RepoPath,
            [string]$Destination
        )

        $apiUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$RepoPath"
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
        $content = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($response.content)
        )
        Set-Content -Path $Destination -Value $content -Encoding UTF8
    }

    # Stop service before modifying configuration files
    Write-Host "  → Stopping CyberSentinel service (if running)..." -ForegroundColor Cyan
    try {
        Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  → Service not running" -ForegroundColor Yellow
    }

    # Backup original ossec.conf
    $ossecConfPath = Join-Path $ossecDir "ossec.conf"
    if (Test-Path $ossecConfPath) {
        $backupPath = Join-Path $ossecDir "ossec.conf.backup"
        Copy-Item -Path $ossecConfPath -Destination $backupPath -Force
        Write-Host "  → Original configuration backed up" -ForegroundColor Cyan
    }

    # Download ossec.conf
    Write-Host "  → Downloading ossec.conf..." -ForegroundColor Cyan
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/ossec.conf" -Destination $ossecConfPath

    # Download enrich.ps1
    $enrichScriptPath = Join-Path $ossecDir "enrich.ps1"
    Write-Host "  → Downloading enrich.ps1..." -ForegroundColor Cyan
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/enrich.ps1" -Destination $enrichScriptPath

    # Download sysmon.ps1
    $sysmonScriptPath = Join-Path $ossecDir "sysmon.ps1"
    Write-Host "  → Downloading sysmon.ps1..." -ForegroundColor Cyan
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/sysmon.ps1" -Destination $sysmonScriptPath

    Write-Host "  ✓ Configuration files downloaded successfully" -ForegroundColor Green

    # ================================
    # STEP 8: MODIFY OSSEC.CONF FOR GROUP SETTINGS
    # ================================
    Write-Host ""
    Write-Host "[6/8] Configuring agent registration settings..." -ForegroundColor Green

    try {
        [xml]$ossecXml = Get-Content $ossecConfPath

        # Find or create client node
        $clientNode = $ossecXml.SelectSingleNode("//ossec_config/client")
        if (-not $clientNode) {
            $clientNode = $ossecXml.CreateElement("client")
            $ossecXml.ossec_config.AppendChild($clientNode) | Out-Null
        }

        # Configure based on registration method
        if ($ManualRegistration) {
            Write-Host "  → Configuring for manual registration..." -ForegroundColor Cyan
            
            # Remove config-profile if exists
            $configProfile = $clientNode.SelectSingleNode("config-profile")
            if ($configProfile) {
                $clientNode.RemoveChild($configProfile) | Out-Null
            }

            # Disable enrollment
            $enrollment = $clientNode.SelectSingleNode("enrollment")
            if (-not $enrollment) {
                $enrollment = $ossecXml.CreateElement("enrollment")
                $clientNode.AppendChild($enrollment) | Out-Null
            }

            $enabled = $enrollment.SelectSingleNode("enabled")
            if (-not $enabled) {
                $enabled = $ossecXml.CreateElement("enabled")
                $enrollment.AppendChild($enabled) | Out-Null
            }
            $enabled.InnerText = "no"

            Write-Host "  ✓ Configured for manual registration" -ForegroundColor Green
        } else {
            Write-Host "  → Configuring for auto-registration with 'windows' group..." -ForegroundColor Cyan
            
            # Set config-profile to lowercase 'windows'
            $configProfile = $clientNode.SelectSingleNode("config-profile")
            if (-not $configProfile) {
                $configProfile = $ossecXml.CreateElement("config-profile")
                $clientNode.AppendChild($configProfile) | Out-Null
            }
            $configProfile.InnerText = "windows"

            # Enable enrollment
            $enrollment = $clientNode.SelectSingleNode("enrollment")
            if (-not $enrollment) {
                $enrollment = $ossecXml.CreateElement("enrollment")
                $clientNode.AppendChild($enrollment) | Out-Null
            }

            $enabled = $enrollment.SelectSingleNode("enabled")
            if (-not $enabled) {
                $enabled = $ossecXml.CreateElement("enabled")
                $enrollment.AppendChild($enabled) | Out-Null
            }
            $enabled.InnerText = "yes"

            Write-Host "  ✓ Configured for auto-registration" -ForegroundColor Green
        }

        # Ensure server address is set
        $server = $clientNode.SelectSingleNode("server")
        if (-not $server) {
            $server = $ossecXml.CreateElement("server")
            $clientNode.AppendChild($server) | Out-Null
        }

        $address = $server.SelectSingleNode("address")
        if (-not $address) {
            $address = $ossecXml.CreateElement("address")
            $server.AppendChild($address) | Out-Null
        }
        $address.InnerText = $managerIP

        # Save modified config
        $ossecXml.Save($ossecConfPath)
        Write-Host "  ✓ Configuration file updated" -ForegroundColor Green

    } catch {
        Write-Host "  ✗ Failed to modify ossec.conf: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  → Continuing with default configuration..." -ForegroundColor Yellow
    }

    # ================================
    # STEP 9: EXECUTE DOWNLOADED SCRIPTS
    # ================================
    Write-Host ""
    Write-Host "[7/8] Executing configuration scripts..." -ForegroundColor Green

    # Execute enrich.ps1
    Write-Host "  → Executing enrich.ps1..." -ForegroundColor Cyan
    try {
        $enrichOutput = & powershell.exe -ExecutionPolicy Bypass -File $enrichScriptPath 2>&1
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Host "  → Warning: enrich.ps1 returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  → Warning: enrich.ps1 execution had issues: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Execute sysmon.ps1
    Write-Host "  → Executing sysmon.ps1..." -ForegroundColor Cyan
    try {
        $sysmonOutput = & powershell.exe -ExecutionPolicy Bypass -File $sysmonScriptPath 2>&1
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Host "  → Warning: sysmon.ps1 returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  → Warning: sysmon.ps1 execution had issues: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "  ✓ Configuration scripts executed" -ForegroundColor Green

    # ================================
    # STEP 10: START SERVICE
    # ================================
    Write-Host ""
    Write-Host "[8/8] Starting CyberSentinel service..." -ForegroundColor Green

    try {
        Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop
        Start-Sleep -Seconds 3
        
        # Verify service is running
        $service = Get-Service -Name "CyberSentinelSvc"
        if ($service.Status -eq "Running") {
            Write-Host "  ✓ CyberSentinel service started successfully" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Service status: $($service.Status)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ✗ Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  → Attempting alternative method..." -ForegroundColor Yellow
        try {
            NET START CyberSentinelSvc
            Write-Host "  ✓ Service started via NET START" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Could not start service. Manual start may be required." -ForegroundColor Red
        }
    }

    # ================================
    # CLEANUP
    # ================================
    Write-Host ""
    Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\ca.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\cybersentinel-agent.msi" -Force -ErrorAction SilentlyContinue

    # ================================
    # SUCCESS MESSAGE & NEXT STEPS
    # ================================
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Installation completed successfully!        " -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Agent Details:" -ForegroundColor Yellow
    Write-Host "  Manager IP: $managerIP" -ForegroundColor White
    Write-Host "  Agent Name: $agentName" -ForegroundColor White
    Write-Host "  Installation Directory: $ossecDir" -ForegroundColor White
    Write-Host "  Registration Method: $(if ($ManualRegistration) { 'Manual' } else { 'Auto' })" -ForegroundColor White
    Write-Host ""

    if ($ManualRegistration) {
        Write-Host "================================================" -ForegroundColor Yellow
        Write-Host "   MANUAL REGISTRATION REQUIRED                " -ForegroundColor Yellow
        Write-Host "================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Complete these steps to register the agent:" -ForegroundColor White
        Write-Host ""
        Write-Host "1. On the manager ($managerIP), run:" -ForegroundColor Cyan
        Write-Host "   sudo /var/ossec/bin/manage_agents" -ForegroundColor White
        Write-Host ""
        Write-Host "2. Select 'A' to add a new agent" -ForegroundColor Cyan
        Write-Host "   - Agent name: $agentName" -ForegroundColor White
        Write-Host "   - Agent IP: any" -ForegroundColor White
        Write-Host ""
        Write-Host "3. Select 'E' to extract the key" -ForegroundColor Cyan
        Write-Host "   - Enter the agent ID shown" -ForegroundColor White
        Write-Host "   - Copy the entire key string" -ForegroundColor White
        Write-Host ""
        Write-Host "4. On this Windows machine, import the key:" -ForegroundColor Cyan
        Write-Host "   & '$ossecDir\manage_agents.exe' -i 'PASTE_KEY_HERE'" -ForegroundColor White
        Write-Host ""
        Write-Host "5. Restart the agent service:" -ForegroundColor Cyan
        Write-Host "   Restart-Service CyberSentinelSvc" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1. Ensure the 'windows' group exists on manager:" -ForegroundColor Cyan
        Write-Host "   SSH to $managerIP and run:" -ForegroundColor White
        Write-Host "   sudo mkdir -p /var/ossec/etc/shared/windows" -ForegroundColor White
        Write-Host "   sudo chown -R wazuh:wazuh /var/ossec/etc/shared/windows" -ForegroundColor White
        Write-Host "   sudo chmod 750 /var/ossec/etc/shared/windows" -ForegroundColor White
        Write-Host "   sudo systemctl restart wazuh-manager" -ForegroundColor White
        Write-Host ""
        Write-Host "2. Check agent logs for connection status:" -ForegroundColor Cyan
        Write-Host "   Get-Content '$ossecDir\ossec.log' -Tail 20" -ForegroundColor White
        Write-Host ""
        Write-Host "3. If you see 'Invalid group: Windows' error:" -ForegroundColor Cyan
        Write-Host "   The MSI may be using uppercase 'Windows'. Create that group:" -ForegroundColor White
        Write-Host "   sudo mkdir -p /var/ossec/etc/shared/Windows" -ForegroundColor White
        Write-Host "   sudo chown -R wazuh:wazuh /var/ossec/etc/shared/Windows" -ForegroundColor White
        Write-Host "   sudo systemctl restart wazuh-manager" -ForegroundColor White
        Write-Host "   Restart-Service CyberSentinelSvc" -ForegroundColor White
        Write-Host ""
    }

    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  - View logs: Get-Content '$ossecDir\ossec.log' -Tail 50" -ForegroundColor White
    Write-Host "  - Check service: Get-Service CyberSentinelSvc" -ForegroundColor White
    Write-Host "  - Test connectivity: Test-NetConnection $managerIP -Port 1514" -ForegroundColor White
    Write-Host "  - Installation log: $msiLogPath" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   [INSTALLATION ERROR]                        " -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Error Details:" -ForegroundColor Yellow
    Write-Host $_.Exception.GetType().FullName -ForegroundColor Red
    Write-Host "At line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path "$env:TEMP\cybersentinel-install.log") {
        Write-Host "Installation log available at: $env:TEMP\cybersentinel-install.log" -ForegroundColor Yellow
    }
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
