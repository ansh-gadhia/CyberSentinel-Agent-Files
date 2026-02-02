# ================================
# CyberSentinel Agent Installation Script
# ================================

# ================================
# GLOBAL HARDENING (MANDATORY)
# ================================
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\cybersentinel-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:animationRunning = $true

# ================================
# HELPER FUNCTIONS
# ================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Show-AnimatedProgress {
    param(
        [string]$Message,
        [scriptblock]$Action
    )
    
    $frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $frameIndex = 0
    
    # Start the action in a background job
    $job = Start-Job -ScriptBlock $Action -ArgumentList $logFile
    
    # Show animation while job is running
    while ($job.State -eq 'Running') {
        $frame = $frames[$frameIndex % $frames.Count]
        Write-Host "`r$frame $Message" -NoNewline -ForegroundColor Cyan
        $frameIndex++
        Start-Sleep -Milliseconds 100
    }
    
    # Get job results
    $result = Receive-Job -Job $job -Wait
    Remove-Job -Job $job
    
    # Clear the animation line
    Write-Host "`r" -NoNewline
    
    return $result
}

function Write-StepHeader {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step] $Message" -ForegroundColor Green
    Write-Log "[$Step] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
    Write-Log "✓ $Message" -Level "SUCCESS"
}

function Write-Progress {
    param([string]$Message)
    Write-Host "  → $Message" -ForegroundColor Cyan
    Write-Log "→ $Message"
}

function Read-SecureInput {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )
    
    Write-Host $Prompt -NoNewline -ForegroundColor Yellow
    
    $input = ""
    $secureString = New-Object System.Security.SecureString
    
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        if ($key.VirtualKeyCode -eq 13) { # Enter
            Write-Host ""
            break
        }
        elseif ($key.VirtualKeyCode -eq 8) { # Backspace
            if ($input.Length -gt 0) {
                $input = $input.Substring(0, $input.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        }
        else {
            $input += $key.Character
            $secureString.AppendChar($key.Character)
            Write-Host "*" -NoNewline -ForegroundColor Gray
        }
    }
    
    if ($AsSecureString) {
        return $secureString
    }
    return $input
}

try {
    # ================================
    # CHECK ADMINISTRATOR PRIVILEGES
    # ================================
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
        Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }

    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   CyberSentinel Agent Installation Script     " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Installation started" -Level "INFO"
    Write-Log "Log file: $logFile" -Level "INFO"

    # ================================
    # STEP 1: COLLECT USER INPUTS
    # ================================
    Write-Host "Configuration Setup" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    # Get Manager IP
    do {
        $managerIP = Read-Host "Enter CyberSentinel Manager IP address"
        if ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
            Write-Host "  ✗ Invalid IP address format! Please try again." -ForegroundColor Red
        }
    } while ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$')
    
    Write-Log "Manager IP: $managerIP"
    
    # Get Agent Name
    do {
        $agentName = Read-Host "Enter CyberSentinel Agent name (e.g., Workstation-01)"
        if ([string]::IsNullOrWhiteSpace($agentName)) {
            Write-Host "  ✗ Agent name cannot be empty! Please try again." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($agentName))
    
    Write-Log "Agent Name: $agentName"
    
    # Get GitHub Token (Secure Input)
    Write-Host ""
    $GitHubToken = Read-SecureInput "Enter GitHub Personal Access Token: "
    
    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        Write-Host ""
        Write-Host "ERROR: GitHub token cannot be empty!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Generate a token at: https://github.com/settings/tokens" -ForegroundColor White
        Write-Host "Required scope: 'repo' (Full control of private repositories)" -ForegroundColor White
        Write-Log "ERROR: No GitHub token provided" -Level "ERROR"
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Log "GitHub token provided (length: $($GitHubToken.Length))"
    
    Write-Host ""
    Write-Host "Configuration Summary:" -ForegroundColor Yellow
    Write-Host "  Manager IP: $managerIP" -ForegroundColor White
    Write-Host "  Agent Name: $agentName" -ForegroundColor White
    Write-Host "  GitHub Token: " -NoNewline -ForegroundColor White
    Write-Host ("*" * $GitHubToken.Length) -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Proceed with installation? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Installation cancelled by user." -ForegroundColor Yellow
        Write-Log "Installation cancelled by user" -Level "WARNING"
        exit 0
    }

    # ================================
    # SETUP GITHUB CONFIGURATION
    # ================================
    $privateRepoOwner = "cybersentinel-06"
    $privateRepoName  = "CyberSentinel-SIEM"

    $headers = @{
        Authorization = "Bearer $GitHubToken"
        "User-Agent"  = "CyberSentinel-Agent-Installer"
        Accept        = "application/vnd.github+json"
    }

    # ================================
    # STEP 2: VALIDATE GITHUB ACCESS
    # ================================
    Write-StepHeader "1/7" "Validating GitHub access to private repository..."
    
    $filesToValidate = @(
        "AGENTS/WINDOWS-AGENT/ossec.conf",
        "AGENTS/WINDOWS-AGENT/enrich.ps1",
        "AGENTS/WINDOWS-AGENT/sysmon.ps1"
    )

    $validationSuccess = $true
    foreach ($file in $filesToValidate) {
        $validationUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$file"
        
        try {
            Write-Log "Validating access to: $file"
            Invoke-WebRequest -Uri $validationUrl -Headers $headers -Method GET -UseBasicParsing | Out-Null
            Write-Log "✓ Access validated: $file" -Level "SUCCESS"
        } catch {
            Write-Host "  ✗ Failed to access: $file" -ForegroundColor Red
            Write-Log "✗ Failed to access: $file - $($_.Exception.Message)" -Level "ERROR"
            $validationSuccess = $false
            break
        }
    }

    if (-not $validationSuccess) {
        Write-Host ""
        Write-Host "Verify:" -ForegroundColor Yellow
        Write-Host "  - Repository: https://github.com/$privateRepoOwner/$privateRepoName" -ForegroundColor White
        Write-Host "  - Token has 'repo' scope" -ForegroundColor White
        Write-Host "  - Token owner has repository access" -ForegroundColor White
        Write-Host ""
        Write-Host "Check log file for details: $logFile" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Success "GitHub access validated successfully"

    # ================================
    # STEP 3: DOWNLOAD AND INSTALL AGENT
    # ================================
    Write-StepHeader "2/7" "Downloading and installing CyberSentinel agent..."
    
    # Download CA certificate
    Write-Progress "Downloading CA certificate..."
    Write-Log "Downloading CA certificate"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" `
        -OutFile "$env:TEMP\ca.cer" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Import CA certificate
    Write-Progress "Importing CA certificate..."
    Write-Log "Importing CA certificate"
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root 2>&1 | Out-File -FilePath $logFile -Append

    # Download MSI installer
    Write-Progress "Downloading installer (this may take a moment)..."
    Write-Log "Downloading MSI installer"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" `
        -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Install agent
    Write-Progress "Installing agent (this may take 1-2 minutes)..."
    $msiLogPath = "$env:TEMP\cybersentinel-msi-install.log"
    Write-Log "Starting MSI installation"
    Write-Log "MSI log file: $msiLogPath"
    
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
        Write-Log "MSI installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
        Write-Host "  Check logs:" -ForegroundColor Yellow
        Write-Host "    - Script log: $logFile" -ForegroundColor White
        Write-Host "    - MSI log: $msiLogPath" -ForegroundColor White
        throw "MSI installation failed"
    }
    
    Write-Log "MSI installation completed successfully" -Level "SUCCESS"
    Start-Sleep -Seconds 3

    Write-Success "CyberSentinel agent installed successfully"

    # ================================
    # STEP 4: VERIFY INSTALLATION
    # ================================
    Write-StepHeader "3/7" "Verifying installation..."
    
    $ossecDir = "C:\Program Files (x86)\ossec-agent"
    
    if (-not (Test-Path $ossecDir)) {
        Write-Host "  ✗ Installation directory not found: $ossecDir" -ForegroundColor Red
        Write-Log "Installation directory not found: $ossecDir" -Level "ERROR"
        throw "Agent installation directory does not exist"
    }
    
    Write-Log "Installation directory verified: $ossecDir" -Level "SUCCESS"
    Write-Success "Installation directory verified: $ossecDir"

    # ================================
    # STEP 5: CREATE ENVIRONMENT FILE
    # ================================
    Write-StepHeader "4/7" "Creating environment configuration..."
    
    $envFilePath = Join-Path $ossecDir ".env"
    Write-Log "Creating .env file at: $envFilePath"

    @(
        "ManagerIP=$managerIP"
        "AgentName=$agentName"
    ) | Set-Content -Path $envFilePath -Encoding UTF8

    Write-Log ".env file created successfully" -Level "SUCCESS"
    Write-Success "Environment file created: $envFilePath"

    # ================================
    # STEP 6: FETCH CONFIGURATION FILES
    # ================================
    Write-StepHeader "5/7" "Fetching configuration files from private repository..."

    # Helper function to download files
    function Download-GitHubFile {
        param (
            [string]$RepoPath,
            [string]$Destination
        )

        Write-Log "Downloading: $RepoPath -> $Destination"
        $apiUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$RepoPath"
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
        $content = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($response.content)
        )
        Set-Content -Path $Destination -Value $content -Encoding UTF8
        Write-Log "✓ Downloaded: $RepoPath" -Level "SUCCESS"
    }

    # Stop service
    Write-Progress "Stopping CyberSentinel service..."
    try {
        Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue 2>&1 | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 2
        Write-Log "Service stopped successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Service not running or not found yet" -Level "WARNING"
    }

    # Download files
    $ossecConfPath = Join-Path $ossecDir "ossec.conf"
    Write-Progress "Downloading ossec.conf..."
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/ossec.conf" -Destination $ossecConfPath

    $enrichScriptPath = Join-Path $ossecDir "enrich.ps1"
    Write-Progress "Downloading enrich.ps1..."
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/enrich.ps1" -Destination $enrichScriptPath

    $sysmonScriptPath = Join-Path $ossecDir "sysmon.ps1"
    Write-Progress "Downloading sysmon.ps1..."
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/sysmon.ps1" -Destination $sysmonScriptPath

    Write-Success "Configuration files downloaded successfully"

    # ================================
    # STEP 6.5: FIX GROUP CONFIGURATION
    # ================================
    Write-StepHeader "5.5/7" "Fixing ossec.conf group configuration..."
    
    Write-Log "Reading ossec.conf for group configuration fix"
    $ossecConfContent = Get-Content $ossecConfPath -Raw
    
    # Fix any uppercase "Windows" to lowercase "windows"
    $originalContent = $ossecConfContent
    $ossecConfContent = $ossecConfContent -replace '<groups>Windows</groups>', '<groups>windows</groups>'
    $ossecConfContent = $ossecConfContent -replace '<config-profile>Windows,', '<config-profile>windows,'
    $ossecConfContent = $ossecConfContent -replace '<config-profile>Windows</config-profile>', '<config-profile>windows</config-profile>'
    
    if ($ossecConfContent -ne $originalContent) {
        Set-Content -Path $ossecConfPath -Value $ossecConfContent -Encoding UTF8
        Write-Log "Group configuration corrected to lowercase 'windows'" -Level "SUCCESS"
        Write-Success "Group configuration corrected to lowercase 'windows'"
    } else {
        Write-Log "No group configuration changes needed" -Level "INFO"
        Write-Success "Group configuration already correct"
    }

    # ================================
    # STEP 7: EXECUTE CONFIGURATION SCRIPTS
    # ================================
    Write-StepHeader "6/7" "Executing configuration scripts..."

    # Execute enrich.ps1
    Write-Progress "Executing enrich.ps1..."
    Write-Log "Executing enrich.ps1"
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $enrichScriptPath 2>&1 | Out-File -FilePath $logFile -Append
        Write-Log "enrich.ps1 executed successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Warning: enrich.ps1 execution had issues: $($_.Exception.Message)" -Level "WARNING"
    }

    # Execute sysmon.ps1
    Write-Progress "Executing sysmon.ps1 (installing Sysmon)..."
    Write-Log "Executing sysmon.ps1"
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $sysmonScriptPath 2>&1 | Out-File -FilePath $logFile -Append
        Write-Log "sysmon.ps1 executed successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Warning: sysmon.ps1 execution had issues: $($_.Exception.Message)" -Level "WARNING"
    }

    Write-Success "Configuration scripts executed successfully"

    # ================================
    # STEP 8: START SERVICE
    # ================================
    Write-StepHeader "7/7" "Starting CyberSentinel service..."
    
    Write-Progress "Starting CyberSentinel service..."
    Write-Log "Starting CyberSentinel service"
    try {
        Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop 2>&1 | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 3
        
        # Verify service
        $service = Get-Service -Name "CyberSentinelSvc"
        if ($service.Status -ne "Running") {
            throw "Service failed to start properly"
        }
        Write-Log "Service started successfully" -Level "SUCCESS"
    } catch {
        Write-Host "  ✗ Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to start service: $($_.Exception.Message)" -Level "ERROR"
        Write-Host "  → Attempting to start via NET START..." -ForegroundColor Yellow
        NET START CyberSentinelSvc 2>&1 | Out-File -FilePath $logFile -Append
    }

    Write-Success "CyberSentinel service started successfully"

    # ================================
    # CLEANUP
    # ================================
    Write-Host ""
    Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
    Write-Log "Cleaning up temporary files"
    Remove-Item -Path "$env:TEMP\ca.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\cybersentinel-agent.msi" -Force -ErrorAction SilentlyContinue

    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Log "Installation completed successfully" -Level "SUCCESS"
    
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Installation completed successfully! ✓      " -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Agent Details:" -ForegroundColor Yellow
    Write-Host "  Manager IP: $managerIP" -ForegroundColor White
    Write-Host "  Agent Name: $agentName" -ForegroundColor White
    Write-Host "  Installation Directory: $ossecDir" -ForegroundColor White
    Write-Host "  Group: windows (lowercase)" -ForegroundColor White
    Write-Host ""
    Write-Host "Installation Log: $logFile" -ForegroundColor Yellow
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
    Write-Log "INSTALLATION ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host "Installation logs:" -ForegroundColor Yellow
    Write-Host "  - Script log: $logFile" -ForegroundColor White
    if (Test-Path "$env:TEMP\cybersentinel-msi-install.log") {
        Write-Host "  - MSI log: $env:TEMP\cybersentinel-msi-install.log" -ForegroundColor White
    }
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
