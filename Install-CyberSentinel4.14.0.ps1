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

# ================================
# HELPER FUNCTIONS
# ================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
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
        elseif ($key.Character -match '[^\x00-\x1F\x7F]') { # Only printable characters
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
    
    Write-Log "Installation started"
    Write-Log "Log file: $logFile"

    # ================================
    # COLLECT USER INPUTS
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
    
    # Clean token - remove any control characters
    $GitHubToken = $GitHubToken -replace '[\x00-\x1F\x7F]', ''
    
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
    Write-Host ("*" * [Math]::Min($GitHubToken.Length, 20)) -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Proceed with installation? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Installation cancelled by user." -ForegroundColor Yellow
        Write-Log "Installation cancelled by user" -Level "WARNING"
        exit 0
    }

    # Clear screen for installation
    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   CyberSentinel Agent Installation            " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installing CyberSentinel Agent..." -ForegroundColor Yellow
    Write-Host "Please wait, this may take a few minutes..." -ForegroundColor White
    Write-Host ""

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
    # STEP 1: VALIDATE GITHUB ACCESS
    # ================================
    Write-Log "[1/7] Validating GitHub access to private repository..."
    
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
            Write-Log "✗ Failed to access: $file - $($_.Exception.Message)" -Level "ERROR"
            $validationSuccess = $false
            
            # Show error
            Write-Host ""
            Write-Host "  ✗ GitHub Access Failed" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Could not access: $file" -ForegroundColor Yellow
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Verify:" -ForegroundColor Yellow
            Write-Host "    - Repository: https://github.com/$privateRepoOwner/$privateRepoName" -ForegroundColor White
            Write-Host "    - Token has 'repo' scope and is not expired" -ForegroundColor White
            Write-Host ""
            Write-Host "  Log: $logFile" -ForegroundColor Gray
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    Write-Log "✓ GitHub access validated successfully" -Level "SUCCESS"

    # ================================
    # STEP 2: DOWNLOAD AND INSTALL AGENT
    # ================================
    Write-Log "[2/7] Downloading and installing CyberSentinel agent..."
    
    # Download CA certificate
    Write-Log "Downloading CA certificate"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca4.14.0.cer" `
        -OutFile "$env:TEMP\ca.cer" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Import CA certificate
    Write-Log "Importing CA certificate"
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root 2>&1 | Out-File -FilePath $logFile -Append

    # Download MSI installer
    Write-Log "Downloading MSI installer"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent4.14.0.msi" `
        -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Install agent WITHOUT group to avoid MSI setting uppercase
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
        Write-Host ""
        Write-Host "  ✗ MSI Installation Failed (Exit Code: $($process.ExitCode))" -ForegroundColor Red
        Write-Log "MSI installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
        Write-Host ""
        Write-Host "  Logs: $logFile" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Log "MSI installation completed successfully" -Level "SUCCESS"
    Start-Sleep -Seconds 3

    # ================================
    # STEP 3: VERIFY INSTALLATION
    # ================================
    Write-Log "[3/7] Verifying installation..."
    
    $ossecDir = "C:\Program Files (x86)\ossec-agent"
    
    if (-not (Test-Path $ossecDir)) {
        Write-Host ""
        Write-Host "  ✗ Installation directory not found: $ossecDir" -ForegroundColor Red
        Write-Log "Installation directory not found: $ossecDir" -Level "ERROR"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Log "Installation directory verified: $ossecDir" -Level "SUCCESS"

    # ================================
    # STEP 4: CREATE ENVIRONMENT FILE
    # ================================
    Write-Log "[4/7] Creating environment configuration..."
    
    $envFilePath = Join-Path $ossecDir ".env"
    Write-Log "Creating .env file at: $envFilePath"

    @(
        "ManagerIP=$managerIP"
        "AgentName=$agentName"
    ) | Set-Content -Path $envFilePath -Encoding UTF8

    Write-Log ".env file created successfully" -Level "SUCCESS"

    # ================================
    # STEP 5: FETCH CONFIGURATION FILES
    # ================================
    Write-Log "[5/7] Fetching configuration files from private repository..."

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

    # Stop service before making changes
    Write-Log "Stopping CyberSentinel service"
    try {
        Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue 2>&1 | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 2
        Write-Log "Service stopped successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Service not running or not found yet" -Level "WARNING"
    }

    # Download files
    $ossecConfPath = Join-Path $ossecDir "ossec.conf"
    Write-Log "Downloading ossec.conf"
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/ossec.conf" -Destination $ossecConfPath

    $enrichScriptPath = Join-Path $ossecDir "enrich.ps1"
    Write-Log "Downloading enrich.ps1"
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/enrich.ps1" -Destination $enrichScriptPath

    $sysmonScriptPath = Join-Path $ossecDir "sysmon.ps1"
    Write-Log "Downloading sysmon.ps1"
    Download-GitHubFile -RepoPath "AGENTS/WINDOWS-AGENT/sysmon.ps1" -Destination $sysmonScriptPath

    Write-Log "Configuration files downloaded successfully" -Level "SUCCESS"

    # ================================
    # STEP 5.5: EXTRACT GROUP FROM DOWNLOADED CONFIG
    # ================================
    Write-Log "[5.5/7] Extracting group configuration from downloaded ossec.conf..."
    
    Write-Log "Reading downloaded ossec.conf to detect group casing"
    $ossecConfContent = Get-Content $ossecConfPath -Raw
    
    # Extract the group value (preserve exact casing)
    $detectedGroup = "windows"  # Default fallback
    if ($ossecConfContent -match '<groups>([^<]+)</groups>') {
        $detectedGroup = $matches[1]
        Write-Log "Detected group from ossec.conf: '$detectedGroup'" -Level "SUCCESS"
    } elseif ($ossecConfContent -match '<config-profile>([^<,]+)') {
        $detectedGroup = $matches[1]
        Write-Log "Detected group from config-profile: '$detectedGroup'" -Level "SUCCESS"
    } else {
        Write-Log "No group found in ossec.conf, using default: '$detectedGroup'" -Level "WARNING"
    }
    
    # Store the detected group for later use
    $scriptGroupCasing = $detectedGroup
    Write-Log "Group casing preserved from imported config: '$scriptGroupCasing'" -Level "SUCCESS"

    # ================================
    # STEP 6: EXECUTE CONFIGURATION SCRIPTS
    # ================================
    Write-Log "[6/7] Executing configuration scripts..."

    # Execute enrich.ps1
    Write-Log "Executing enrich.ps1"
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $enrichScriptPath 2>&1 | Out-File -FilePath $logFile -Append
        Write-Log "enrich.ps1 executed successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Warning: enrich.ps1 execution had issues: $($_.Exception.Message)" -Level "WARNING"
    }

    # Execute sysmon.ps1
    Write-Log "Executing sysmon.ps1"
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $sysmonScriptPath 2>&1 | Out-File -FilePath $logFile -Append
        Write-Log "sysmon.ps1 executed successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Warning: sysmon.ps1 execution had issues: $($_.Exception.Message)" -Level "WARNING"
    }

    Write-Log "Configuration scripts executed successfully" -Level "SUCCESS"

    # ================================
    # STEP 7: START SERVICE
    # ================================
    Write-Log "[7/7] Starting CyberSentinel service..."
    
    Write-Log "Starting CyberSentinel service"
    try {
        Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop 2>&1 | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 5
        
        # Verify service
        $service = Get-Service -Name "CyberSentinelSvc"
        if ($service.Status -ne "Running") {
            throw "Service failed to start properly"
        }
        Write-Log "Service started successfully" -Level "SUCCESS"
    } catch {
        Write-Log "Failed to start service: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Attempting to start via NET START" -Level "WARNING"
        NET START CyberSentinelSvc 2>&1 | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 5
    }

    # ================================
    # STEP 7.5: RESTORE GROUP CONFIGURATION IF CHANGED
    # ================================
    Write-Log "[7.5/7] Verifying group configuration matches imported script..."
    
    # Stop service to safely check/modify config
    Write-Log "Stopping service to verify configuration"
    Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue 2>&1 | Out-File -FilePath $logFile -Append
    Start-Sleep -Seconds 3
    
    # Read the current ossec.conf (might have been modified by agent startup)
    Write-Log "Checking if group configuration was altered during service startup"
    $currentOssecContent = Get-Content $ossecConfPath -Raw
    
    # Extract current group
    $currentGroup = "unknown"
    if ($currentOssecContent -match '<groups>([^<]+)</groups>') {
        $currentGroup = $matches[1]
    }
    
    Write-Log "Current group in ossec.conf: '$currentGroup'"
    Write-Log "Expected group from script: '$scriptGroupCasing'"
    
    # Only modify if the casing changed
    if ($currentGroup -cne $scriptGroupCasing) {
        Write-Log "Group casing mismatch detected! Restoring original casing..." -Level "WARNING"
        
        # Replace with the correct casing from the imported script
        $currentOssecContent = $currentOssecContent -creplace "<groups>$currentGroup</groups>", "<groups>$scriptGroupCasing</groups>"
        $currentOssecContent = $currentOssecContent -creplace "<config-profile>$currentGroup,", "<config-profile>$scriptGroupCasing,"
        $currentOssecContent = $currentOssecContent -creplace "<config-profile>$currentGroup</config-profile>", "<config-profile>$scriptGroupCasing</config-profile>"
        
        Set-Content -Path $ossecConfPath -Value $currentOssecContent -Encoding UTF8
        Write-Log "Group configuration restored to: '$scriptGroupCasing'" -Level "SUCCESS"
    } else {
        Write-Log "Group configuration unchanged, matches imported script: '$scriptGroupCasing'" -Level "SUCCESS"
    }
    
    # Restart service with verified config
    Write-Log "Restarting service with verified configuration"
    Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop 2>&1 | Out-File -FilePath $logFile -Append
    Start-Sleep -Seconds 5
    
    Write-Log "CyberSentinel service restarted successfully" -Level "SUCCESS"

    # ================================
    # CLEANUP
    # ================================
    Write-Log "Cleaning up temporary files"
    Remove-Item -Path "$env:TEMP\ca.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\cybersentinel-agent.msi" -Force -ErrorAction SilentlyContinue

    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Log "Installation completed successfully" -Level "SUCCESS"
    
    # Clear screen
    Clear-Host
    
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  █     ✓ INSTALLATION SUCCESSFUL            █" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host ""
    Write-Host ""
    Write-Host "  Agent Information:" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Manager:   $managerIP" -ForegroundColor White
    Write-Host "    Name:      $agentName" -ForegroundColor White
    Write-Host "    Group:     $scriptGroupCasing" -ForegroundColor White
    Write-Host ""
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █     ✗ INSTALLATION FAILED                █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "INSTALLATION ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
