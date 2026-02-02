# ================================
# CyberSentinel Agent Installation Script
# ================================

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken
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
    Write-Host "[1/7] Validating GitHub access to private repository..." -ForegroundColor Green

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
    Write-Host "[2/7] Downloading and installing CyberSentinel agent..." -ForegroundColor Green

    # Download CA certificate
    Write-Host "  → Downloading CA certificate..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" -OutFile "$env:TEMP\ca.cer" -UseBasicParsing

    # Import CA certificate
    Write-Host "  → Importing CA certificate..." -ForegroundColor Cyan
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

    # Download MSI installer
    Write-Host "  → Downloading installer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing

    # Install agent WITHOUT group assignment to avoid uppercase issue
    Write-Host "  → Installing agent..." -ForegroundColor Cyan
    $msiLogPath = "$env:TEMP\cybersentinel-install.log"
    
    # Use Start-Process with -Wait to ensure installation completes
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
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    
    if ($process.ExitCode -ne 0) {
        Write-Host "  ✗ Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        Write-Host "  Check log: $msiLogPath" -ForegroundColor Yellow
        throw "MSI installation failed"
    }
    
    # Wait for service to be registered
    Start-Sleep -Seconds 3

    Write-Host "  ✓ CyberSentinel agent installed successfully" -ForegroundColor Green

    # ================================
    # STEP 4.5: VERIFY INSTALLATION DIRECTORY EXISTS
    # ================================
    Write-Host ""
    Write-Host "[3/7] Verifying installation..." -ForegroundColor Green
    
    $ossecDir = "C:\Program Files (x86)\ossec-agent"
    
    if (-not (Test-Path $ossecDir)) {
        Write-Host "  ✗ Installation directory not found: $ossecDir" -ForegroundColor Red
        throw "Agent installation directory does not exist"
    }
    
    Write-Host "  ✓ Installation directory verified: $ossecDir" -ForegroundColor Green

    # ================================
    # STEP 5: WRITE .ENV FILE
    # ================================
    Write-Host ""
    Write-Host "[4/7] Creating environment configuration..." -ForegroundColor Green

    $envFilePath = Join-Path $ossecDir ".env"

    @(
        "ManagerIP=$managerIP"
        "AgentName=$agentName"
    ) | Set-Content -Path $envFilePath -Encoding UTF8

    Write-Host "  ✓ Environment file created: $envFilePath" -ForegroundColor Green

    # ================================
    # STEP 6: FETCH CONFIG/SCRIPTS FROM GITHUB
    # ================================
    Write-Host ""
    Write-Host "[5/7] Fetching configuration files from private repository..." -ForegroundColor Green

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
    Write-Host "  → Stopping CyberSentinel service..." -ForegroundColor Cyan
    try {
        Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  → Service not running or not found yet" -ForegroundColor Yellow
    }

    # Download ossec.conf
    $ossecConfPath = Join-Path $ossecDir "ossec.conf"
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
    # STEP 6.5: FIX OSSEC.CONF GROUP CONFIGURATION
    # ================================
    Write-Host ""
    Write-Host "[5.5/7] Fixing ossec.conf group configuration..." -ForegroundColor Green
    
    # Read the downloaded ossec.conf
    $ossecConfContent = Get-Content $ossecConfPath -Raw
    
    # Replace any uppercase "Windows" with lowercase "windows" in the groups tag
    $ossecConfContent = $ossecConfContent -replace '<groups>Windows</groups>', '<groups>windows</groups>'
    
    # Also ensure config-profile uses lowercase
    $ossecConfContent = $ossecConfContent -replace '<config-profile>Windows,', '<config-profile>windows,'
    $ossecConfContent = $ossecConfContent -replace '<config-profile>Windows</config-profile>', '<config-profile>windows</config-profile>'
    
    # Save the corrected configuration
    Set-Content -Path $ossecConfPath -Value $ossecConfContent -Encoding UTF8
    
    Write-Host "  ✓ Group configuration corrected to lowercase 'windows'" -ForegroundColor Green

    # ================================
    # STEP 7: EXECUTE DOWNLOADED SCRIPTS
    # ================================
    Write-Host ""
    Write-Host "[6/7] Executing configuration scripts..." -ForegroundColor Green

    # Execute enrich.ps1
    Write-Host "  → Executing enrich.ps1..." -ForegroundColor Cyan
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $enrichScriptPath
    } catch {
        Write-Host "  → Warning: enrich.ps1 execution had issues: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Execute sysmon.ps1
    Write-Host "  → Executing sysmon.ps1..." -ForegroundColor Cyan
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $sysmonScriptPath
    } catch {
        Write-Host "  → Warning: sysmon.ps1 execution had issues: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "  ✓ Configuration scripts executed successfully" -ForegroundColor Green

    # ================================
    # STEP 8: START SERVICE
    # ================================
    Write-Host ""
    Write-Host "[7/7] Starting CyberSentinel service..." -ForegroundColor Green
    
    # Start the service
    Write-Host "  → Starting CyberSentinel service..." -ForegroundColor Cyan
    try {
        Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop
        Start-Sleep -Seconds 3
        
        # Verify service is running
        $service = Get-Service -Name "CyberSentinelSvc"
        if ($service.Status -ne "Running") {
            throw "Service failed to start properly"
        }
    } catch {
        Write-Host "  ✗ Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  → Attempting to start via NET START..." -ForegroundColor Yellow
        NET START CyberSentinelSvc
    }

    Write-Host "  ✓ CyberSentinel service started successfully" -ForegroundColor Green

    # ================================
    # CLEANUP
    # ================================
    Write-Host ""
    Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\ca.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\cybersentinel-agent.msi" -Force -ErrorAction SilentlyContinue

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
    Write-Host "  Installation Directory: $ossecDir" -ForegroundColor White
    Write-Host "  Group: windows (lowercase)" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. On the manager ($managerIP), ensure the 'windows' group exists:" -ForegroundColor White
    Write-Host "     sudo mkdir -p /var/ossec/etc/shared/windows" -ForegroundColor Cyan
    Write-Host "     sudo chown -R wazuh:wazuh /var/ossec/etc/shared/windows" -ForegroundColor Cyan
    Write-Host "     sudo systemctl restart wazuh-manager" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Check agent logs for connection status:" -ForegroundColor White
    Write-Host "     Get-Content '$ossecDir\ossec.log' -Tail 20" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3. Verify agent is connected on manager:" -ForegroundColor White
    Write-Host "     /var/ossec/bin/agent_control -l" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: The group name is 'windows' (lowercase) - ensure your" -ForegroundColor Yellow
    Write-Host "           manager configuration matches this exactly." -ForegroundColor Yellow
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   [INSTALLATION ERROR]                        " -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Installation log (if available): $env:TEMP\cybersentinel-install.log" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
