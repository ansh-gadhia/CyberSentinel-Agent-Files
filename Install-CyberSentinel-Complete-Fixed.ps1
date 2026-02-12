# ================================
# CyberSentinel Complete Installation Script
# Agent + Active Response
# ================================

# ================================
# GLOBAL HARDENING (MANDATORY)
# ================================
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\cybersentinel-complete-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
        
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            break
        }
        elseif ($key.VirtualKeyCode -eq 8) {
            if ($input.Length -gt 0) {
                $input = $input.Substring(0, $input.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        }
        elseif ($key.Character -match '[^\x00-\x1F\x7F]') {
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

function Remove-PythonCompletely {
    Write-Host "`n=== Completely removing existing Python installations... ===" -ForegroundColor White
    Write-Log "Starting complete Python removal"
    
    # Stop all Python processes
    Write-Host "  Stopping Python processes..." -ForegroundColor Gray
    $pythonProcesses = Get-Process | Where-Object { $_.ProcessName -like "*python*" }
    if ($pythonProcesses) {
        foreach ($proc in $pythonProcesses) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Log "Stopped Python process: $($proc.ProcessName) - PID: $($proc.Id)"
            }
            catch {
                Write-Log "Could not stop process $($proc.Id): $($_.Exception.Message)" -Level "WARNING"
            }
        }
    }
    Start-Sleep -Seconds 2

    # Uninstall via Registry
    Write-Host "  Uninstalling via registry..." -ForegroundColor Gray
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            Get-ChildItem $path | ForEach-Object {
                $app = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($app.DisplayName -like "*Python*") {
                    $uninstallString = $app.UninstallString
                    if ($uninstallString -match "msiexec") {
                        $guid = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
                        Write-Log "Uninstalling: $($app.DisplayName)"
                        Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow -PassThru | Out-Null
                    }
                }
            }
        }
    }

    # Remove Microsoft Store Python
    Write-Host "  Removing Microsoft Store Python..." -ForegroundColor Gray
    $storeApps = Get-AppxPackage | Where-Object { $_.Name -like "*Python*" }
    foreach ($app in $storeApps) {
        try {
            Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
            Write-Log "Removed Store Python: $($app.Name)"
        } catch { }
    }

    # Force remove directories
    Write-Host "  Removing Python directories..." -ForegroundColor Gray
    $dirsToCheck = @(
        "$env:LOCALAPPDATA\Programs\Python*",
        "$env:LOCALAPPDATA\Python*",
        "$env:APPDATA\Python",
        "$env:ProgramFiles\Python*",
        "${env:ProgramFiles(x86)}\Python*",
        "C:\Python*"
    )

    foreach ($pattern in $dirsToCheck) {
        $dirs = Get-Item $pattern -ErrorAction SilentlyContinue
        if ($dirs) {
            foreach ($dir in $dirs) {
                Write-Log "Removing directory: $($dir.FullName)"
                try {
                    takeown /f "$($dir.FullName)" /r /d y 2>&1 | Out-Null
                    icacls "$($dir.FullName)" /grant administrators:F /t 2>&1 | Out-Null
                    Remove-Item $dir.FullName -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Get-ChildItem $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                    try { Remove-Item $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { }
                }
            }
        }
    }

    # Clean PATH
    Write-Host "  Cleaning PATH variables..." -ForegroundColor Gray
    foreach ($scope in @("User", "Machine")) {
        try {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", $scope)
            if ($currentPath) {
                $pathArray = $currentPath -split ';'
                $newPathArray = @()
                foreach ($p in $pathArray) {
                    if ($p -notlike "*Python*" -and $p -notlike "*\Scripts" -and $p -ne "") {
                        $newPathArray += $p
                    }
                }
                if ($pathArray.Count -ne $newPathArray.Count) {
                    $newPath = $newPathArray -join ';'
                    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
                    Write-Log "Cleaned $scope PATH"
                }
            }
        } catch { }
    }

    # Remove pip cache
    Write-Host "  Cleaning pip cache..." -ForegroundColor Gray
    $pipDirs = @("$env:LOCALAPPDATA\pip", "$env:APPDATA\pip")
    foreach ($dir in $pipDirs) {
        if (Test-Path $dir) {
            try {
                Remove-Item $dir -Recurse -Force -ErrorAction Stop
                Write-Log "Removed pip cache: $dir"
            } catch { }
        }
    }

    # Clean registry
    Write-Host "  Cleaning registry..." -ForegroundColor Gray
    $regKeys = @(
        "HKCU:\Software\Python",
        "HKLM:\Software\Python",
        "HKLM:\Software\WOW6432Node\Python"
    )
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item $key -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $key"
            } catch { }
        }
    }

    # Remove file associations
    $assocKeys = @(
        "HKCU:\Software\Classes\.py",
        "HKCU:\Software\Classes\.pyw",
        "HKCU:\Software\Classes\.pyc",
        "HKCU:\Software\Classes\Python.File",
        "HKCU:\Software\Classes\Python.NoConFile",
        "HKCU:\Software\Classes\Python.CompiledFile"
    )
    foreach ($key in $assocKeys) {
        if (Test-Path $key) {
            try { Remove-Item $key -Recurse -Force -ErrorAction Stop } catch { }
        }
    }

    Write-Host "  Python removal complete" -ForegroundColor Green
    Write-Log "Python completely removed"
}

function Test-PythonInstallation {
    param([string]$MinVersion = "3.12.1")
    
    Write-Host "`n=== Checking existing Python installation... ===" -ForegroundColor White
    
    # Try multiple Python commands
    $pythonCommands = @("python", "py", "python3")
    $pythonExe = $null
    
    foreach ($cmd in $pythonCommands) {
        try {
            $cmdPath = (Get-Command $cmd -ErrorAction SilentlyContinue).Source
            if ($cmdPath -and (Test-Path $cmdPath)) {
                $pythonExe = $cmdPath
                break
            }
        } catch { }
    }
    
    if (-not $pythonExe) {
        Write-Host "  No Python found" -ForegroundColor Yellow
        Write-Log "No Python installation detected"
        return @{
            Installed = $false
            NeedsReinstall = $true
            Reason = "Not installed"
        }
    }
    
    Write-Host "  Python found at: $pythonExe" -ForegroundColor Green
    Write-Log "Python found: $pythonExe"
    
    # Check version
    try {
        $versionOutput = & $pythonExe --version 2>&1
        if ($versionOutput -match 'Python (\d+\.\d+\.\d+)') {
            $currentVersion = [version]$matches[1]
            $minVer = [version]$MinVersion
            
            Write-Host "  Current version: $currentVersion" -ForegroundColor Cyan
            Write-Log "Python version: $currentVersion"
            
            if ($currentVersion -lt $minVer) {
                Write-Host "  Version too old - minimum required: $MinVersion" -ForegroundColor Red
                Write-Log "Python version $currentVersion is below minimum $MinVersion"
                return @{
                    Installed = $true
                    NeedsReinstall = $true
                    Reason = "Version $currentVersion < $MinVersion"
                }
            }
        }
    } catch {
        Write-Host "  Could not determine version" -ForegroundColor Red
        Write-Log "Failed to get Python version: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Installed = $true
            NeedsReinstall = $true
            Reason = "Version check failed"
        }
    }
    
    # Check for PyInstaller
    try {
        $pyinstallerCheck = & $pythonExe -m pip show pyinstaller 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  PyInstaller not found" -ForegroundColor Red
            Write-Log "PyInstaller not installed"
            return @{
                Installed = $true
                NeedsReinstall = $true
                Reason = "PyInstaller missing"
            }
        }
        Write-Host "  PyInstaller found" -ForegroundColor Green
        Write-Log "PyInstaller is installed"
    } catch {
        Write-Host "  PyInstaller check failed" -ForegroundColor Red
        Write-Log "PyInstaller check failed: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Installed = $true
            NeedsReinstall = $true
            Reason = "PyInstaller check failed"
        }
    }
    
    # Validate pip is working
    try {
        $pipCheck = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -ne 0 -or $pipCheck -like "*WARNING*invalid*") {
            Write-Host "  Pip installation corrupted" -ForegroundColor Red
            Write-Log "Pip validation failed: $pipCheck" -Level "ERROR"
            return @{
                Installed = $true
                NeedsReinstall = $true
                Reason = "Pip corrupted"
            }
        }
        Write-Host "  Pip working correctly" -ForegroundColor Green
    } catch {
        Write-Host "  Pip validation failed" -ForegroundColor Red
        return @{
            Installed = $true
            NeedsReinstall = $true
            Reason = "Pip validation failed"
        }
    }
    
    Write-Host "  Python installation is valid" -ForegroundColor Green
    Write-Log "Python installation validated successfully"
    return @{
        Installed = $true
        NeedsReinstall = $false
        Reason = "Valid installation"
    }
}

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
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   CyberSentinel Complete Installation  " -ForegroundColor Cyan
Write-Host "   Agent + Active Response Setup        " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Complete installation started"
Write-Log "Log file: $logFile"

# ================================
# PHASE 1: AGENT INSTALLATION
# ================================

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   PHASE 1: Agent Installation" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Starting Phase 1: Agent Installation"

    # ================================
    # COLLECT USER INPUTS
    # ================================
    Write-Host "Configuration Setup" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    
    # Get Manager IP
    do {
        $managerIP = Read-Host "Enter CyberSentinel Manager IP address"
        if ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
            Write-Host "  Invalid IP address format! Please try again." -ForegroundColor Red
        }
    } while ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$')
    
    Write-Log "Manager IP: $managerIP"
    
    # Get Agent Name
    do {
        $agentName = Read-Host "Enter CyberSentinel Agent name - example Workstation-01"
        if ([string]::IsNullOrWhiteSpace($agentName)) {
            Write-Host "  Agent name cannot be empty! Please try again." -ForegroundColor Red
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
        Write-Host "Required scope: repo - Full control of private repositories" -ForegroundColor White
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
            Write-Log "Access validated: $file" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to access: $file - $($_.Exception.Message)" -Level "ERROR"
            $validationSuccess = $false
            
            # Show error
            Write-Host ""
            Write-Host "  GitHub Access Failed" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Could not access: $file" -ForegroundColor Yellow
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Verify:" -ForegroundColor Yellow
            Write-Host "    - Repository: https://github.com/$privateRepoOwner/$privateRepoName" -ForegroundColor White
            Write-Host "    - Token has repo scope and is not expired" -ForegroundColor White
            Write-Host ""
            Write-Host "  Log: $logFile" -ForegroundColor Gray
            Write-Host ""
            throw "GitHub access validation failed"
        }
    }

    Write-Log "GitHub access validated successfully" -Level "SUCCESS"

    # ================================
    # STEP 2: DOWNLOAD AND INSTALL AGENT
    # ================================
    Write-Log "[2/7] Downloading and installing CyberSentinel agent..."
    
    # Download CA certificate
    Write-Log "Downloading CA certificate"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" `
        -OutFile "$env:TEMP\ca.cer" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Import CA certificate
    Write-Log "Importing CA certificate"
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root 2>&1 | Out-File -FilePath $logFile -Append

    # Download MSI installer
    Write-Log "Downloading MSI installer"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" `
        -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Install agent
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
        Write-Host "  MSI Installation Failed - Exit Code: $($process.ExitCode)" -ForegroundColor Red
        Write-Log "MSI installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
        throw "MSI installation failed"
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
        Write-Host "  Installation directory not found: $ossecDir" -ForegroundColor Red
        Write-Log "Installation directory not found: $ossecDir" -Level "ERROR"
        throw "Installation directory not found"
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
        Write-Log "Downloaded: $RepoPath" -Level "SUCCESS"
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
    # STEP 7.5: DETECT ACTUAL GROUP FROM CONFIG
    # ================================
    Write-Log "[7.5/7] Detecting configured group..."
    
    # Read the ossec.conf to detect what group was actually set
    $ossecConfContent = Get-Content $ossecConfPath -Raw
    
    # Extract group from config
    $detectedGroup = "default"
    if ($ossecConfContent -match '<groups>([^<]+)</groups>') {
        $detectedGroup = $matches[1]
        Write-Log "Detected group from configuration: $detectedGroup" -Level "SUCCESS"
    } else {
        Write-Log "No group tag found in configuration, using default" -Level "WARNING"
    }

    # ================================
    # CLEANUP
    # ================================
    Write-Log "Cleaning up temporary files"
    Remove-Item -Path "$env:TEMP\ca.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\cybersentinel-agent.msi" -Force -ErrorAction SilentlyContinue

    # ================================
    # PHASE 1 SUCCESS MESSAGE
    # ================================
    Write-Log "Phase 1: Agent installation completed successfully" -Level "SUCCESS"
    
    # Clear screen
    Clear-Host
    
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  █   CYBERSENTINEL AGENT INSTALLED          █" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host ""
    Write-Host ""
    Write-Host "  Agent Information:" -ForegroundColor Yellow
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Manager:   $managerIP" -ForegroundColor White
    Write-Host "    Name:      $agentName" -ForegroundColor White
    Write-Host "    Group:     $detectedGroup" -ForegroundColor White
    Write-Host ""
    Write-Host ""
    Write-Host "  CyberSentinel-agent is installed completely!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Press Enter to continue with Active Response installation..." -ForegroundColor Yellow
    Read-Host

}
catch {
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █   AGENT INSTALLATION FAILED              █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  The CyberSentinel-agent installation is failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "PHASE 1 ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host ""
    Write-Host "  Cannot proceed with Active Response installation." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ================================
# PHASE 2: ACTIVE RESPONSE SETUP
# ================================

try {
    # Change to C: drive
    Write-Log "Changing to C: drive"
    Set-Location C:\
    
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   PHASE 2: Active Response Setup" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Starting Phase 2: Active Response Setup"

    # ================================
    # CHECK AND VALIDATE PYTHON
    # ================================
    
    $pythonCheck = Test-PythonInstallation -MinVersion "3.12.1"
    
    if ($pythonCheck.NeedsReinstall) {
        Write-Host ""
        Write-Host "  Python needs reinstallation" -ForegroundColor Yellow
        Write-Host "  Reason: $($pythonCheck.Reason)" -ForegroundColor Yellow
        Write-Host ""
        
        if ($pythonCheck.Installed) {
            Remove-PythonCompletely
        }
        
        $needPythonInstall = $true
    } else {
        Write-Host ""
        Write-Host "  Using existing Python installation" -ForegroundColor Green
        Write-Host ""
        $needPythonInstall = $false
    }

    # ================================
    # INSTALL PYTHON 3.14.0 IF NEEDED
    # ================================
    
    if ($needPythonInstall) {
        Write-Host "=== Installing Python 3.14.0... ===" -ForegroundColor White
        Write-Log "Starting Python 3.14.0 installation"
        
        $pythonVersion = "3.14.0"
        $pythonInstaller = "$env:TEMP\python-$pythonVersion-installer.exe"
        
        # Download URLs
        $downloadUrls = @(
            "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe"
        )
        
        $downloadSuccess = $false
        
        # Check if installer already exists
        if (Test-Path $pythonInstaller) {
            $fileSize = (Get-Item $pythonInstaller).Length
            if ($fileSize -gt 10MB) {
                Write-Host "  Using existing Python installer" -ForegroundColor Green
                $downloadSuccess = $true
            } else {
                Remove-Item $pythonInstaller -Force
            }
        }
        
        # Download Python installer
        if (-not $downloadSuccess) {
            Write-Host "  Downloading Python $pythonVersion installer..." -ForegroundColor Gray
            
            foreach ($url in $downloadUrls) {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Write-Log "Downloading from: $url"
                    Invoke-WebRequest -Uri $url -OutFile $pythonInstaller -UseBasicParsing -TimeoutSec 120
                    
                    if (Test-Path $pythonInstaller) {
                        $fileSize = (Get-Item $pythonInstaller).Length
                        if ($fileSize -gt 10MB) {
                            Write-Host "  Download complete - $([math]::Round($fileSize/1MB, 2)) MB" -ForegroundColor Green
                            Write-Log "Python installer downloaded successfully"
                            $downloadSuccess = $true
                            break
                        } else {
                            Remove-Item $pythonInstaller -Force
                        }
                    }
                }
                catch {
                    Write-Log "Download failed from $url : $($_.Exception.Message)" -Level "ERROR"
                    continue
                }
            }
        }
        
        if (-not $downloadSuccess) {
            Write-Host ""
            Write-Host "  Failed to download Python installer!" -ForegroundColor Red
            Write-Host ""
            Write-Log "Failed to download Python installer" -Level "ERROR"
            throw "Python installer download failed - Cannot proceed"
        }

        # Install Python silently
        Write-Host "  Installing Python $pythonVersion..." -ForegroundColor Gray
        Write-Log "Starting Python installation"
        
        $installArgs = @(
            "/quiet",
            "InstallAllUsers=1",
            "PrependPath=1",
            "Include_pip=1",
            "Include_test=0",
            "Include_doc=0",
            "Include_launcher=1",
            "AssociateFiles=1",
            "Shortcuts=0"
        )
        
        $process = Start-Process -FilePath $pythonInstaller -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            Write-Log "Python installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
            throw "Python installation failed with exit code: $($process.ExitCode)"
        }
        
        Write-Host "  Python installed successfully" -ForegroundColor Green
        Write-Log "Python $pythonVersion installed successfully"
        
        # Cleanup installer
        Remove-Item $pythonInstaller -Force -ErrorAction SilentlyContinue
        
        # Refresh environment
        Write-Host "  Refreshing environment..." -ForegroundColor Gray
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        Start-Sleep -Seconds 5
        
        # Find Python executable
        $pythonExe = $null
        $possiblePaths = @(
            "C:\Program Files\Python314\python.exe",
            "C:\Program Files\Python$($pythonVersion.Replace('.',''))\python.exe",
            (Get-Command python -ErrorAction SilentlyContinue).Source,
            (Get-Command py -ErrorAction SilentlyContinue).Source
        )
        
        foreach ($path in $possiblePaths) {
            if ($path -and (Test-Path $path)) {
                $pythonExe = $path
                break
            }
        }
        
        if (-not $pythonExe) {
            Write-Log "Python installed but executable not found" -Level "ERROR"
            throw "Python installed but executable not found - Try restarting PowerShell"
        }
        
        Write-Host "  Python executable: $pythonExe" -ForegroundColor Green
        Write-Log "Python executable found: $pythonExe"
        
        # Verify installation
        $versionCheck = & $pythonExe --version 2>&1
        Write-Host "  Verified: $versionCheck" -ForegroundColor Green
        Write-Log "Python version verified: $versionCheck"
    } else {
        # Use existing Python
        $pythonCommands = @("python", "py")
        $pythonExe = $null
        
        foreach ($cmd in $pythonCommands) {
            try {
                $cmdPath = (Get-Command $cmd -ErrorAction SilentlyContinue).Source
                if ($cmdPath -and (Test-Path $cmdPath)) {
                    $pythonExe = $cmdPath
                    break
                }
            } catch { }
        }
    }

    # ================================
    # INSTALL PIP AND PYINSTALLER
    # ================================
    
    Write-Host "`n=== Installing Python packages... ===" -ForegroundColor White
    Write-Log "Installing pip and PyInstaller"
    
    # Determine Python command
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        $pythonCmd = "py"
    } else {
        $pythonCmd = "python"
    }
    
    Write-Host "  Using: $pythonCmd" -ForegroundColor Gray
    
    # Upgrade pip first
    Write-Host "  Upgrading pip..." -ForegroundColor Gray
    & $pythonCmd -m ensurepip --upgrade 2>&1 | Out-Null
    & $pythonCmd -m pip install --upgrade pip --no-warn-script-location 2>&1 | Out-Null
    
    # Install PyInstaller
    Write-Host "  Installing PyInstaller..." -ForegroundColor Gray
    $pyinstallerOutput = & $pythonCmd -m pip install pyinstaller --no-warn-script-location 2>&1
    
    # Check for errors
    if ($LASTEXITCODE -ne 0) {
        Write-Log "PyInstaller installation failed" -Level "ERROR"
        Write-Log "Output: $pyinstallerOutput" -Level "ERROR"
        throw "PyInstaller installation failed"
    }
    
    Write-Host "  Packages installed successfully" -ForegroundColor Green
    Write-Log "pip and PyInstaller installed successfully"
    
    # Get Scripts path
    $pyScriptsPath = & $pythonCmd -c "import sysconfig; print(sysconfig.get_paths()['scripts'])" 2>&1
    if ($LASTEXITCODE -eq 0 -and $pyScriptsPath) {
        Write-Host "  Scripts directory: $pyScriptsPath" -ForegroundColor Gray
        if ($env:Path -notlike "*$pyScriptsPath*") {
            $env:Path += ";$pyScriptsPath"
        }
    }

    # ================================
    # BUILD ACTIVE RESPONSE EXECUTABLES
    # ================================
    
    $targetDir = "C:\Program Files (x86)\ossec-agent\active-response"
    $binDir    = "$targetDir\bin"
    $buildDir  = "$env:TEMP\CyberSentinel-Build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    Write-Host "`n=== Building Active Response executables... ===" -ForegroundColor White
    Write-Log "Starting executable build process"
    
    # Create directories
    if (!(Test-Path $binDir)) { 
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null 
        Write-Log "Created bin directory: $binDir"
    }
    
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    Write-Log "Created build directory: $buildDir"

    # Download Python scripts
    Write-Host "  Downloading source scripts..." -ForegroundColor Gray
    $removeThreatUrl  = "https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-threat.py"
    $removeMalwareUrl = "https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-malware.py"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $removeThreatUrl -OutFile "$buildDir\remove-threat.py" -UseBasicParsing
        Invoke-WebRequest -Uri $removeMalwareUrl -OutFile "$buildDir\remove-malware.py" -UseBasicParsing
        Write-Host "  Scripts downloaded" -ForegroundColor Green
        Write-Log "Source scripts downloaded successfully"
    }
    catch {
        Write-Log "Failed to download scripts: $($_.Exception.Message)" -Level "ERROR"
        throw "Failed to download Active Response scripts"
    }

    # Compile executables
    Write-Host "  Compiling remove-threat.exe..." -ForegroundColor Gray
    $compileOutput = & $pythonCmd -m PyInstaller -F "$buildDir\remove-threat.py" --distpath "$buildDir\dist" --workpath "$buildDir\build" --clean --log-level ERROR 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "remove-threat.py compilation failed" -Level "ERROR"
        Write-Log "Output: $compileOutput" -Level "ERROR"
        throw "remove-threat.py compilation failed"
    }
    Write-Host "  remove-threat.exe compiled" -ForegroundColor Green
    Write-Log "remove-threat.exe compiled successfully"

    Write-Host "  Compiling remove-malware.exe..." -ForegroundColor Gray
    $compileOutput = & $pythonCmd -m PyInstaller -F "$buildDir\remove-malware.py" --distpath "$buildDir\dist" --workpath "$buildDir\build" --clean --log-level ERROR 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "remove-malware.py compilation failed" -Level "ERROR"
        Write-Log "Output: $compileOutput" -Level "ERROR"
        throw "remove-malware.py compilation failed"
    }
    Write-Host "  remove-malware.exe compiled" -ForegroundColor Green
    Write-Log "remove-malware.exe compiled successfully"

    # Deploy executables
    Write-Host "  Deploying executables..." -ForegroundColor Gray
    try {
        Move-Item -Path "$buildDir\dist\remove-threat.exe" -Destination $binDir -Force
        Move-Item -Path "$buildDir\dist\remove-malware.exe" -Destination $binDir -Force
        Write-Host "  Executables deployed to $binDir" -ForegroundColor Green
        Write-Log "Executables deployed successfully"
    }
    catch {
        Write-Log "Failed to deploy executables: $($_.Exception.Message)" -Level "ERROR"
        throw "Failed to deploy executables"
    }

    # Cleanup build directory
    Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
    Write-Log "Build directory cleaned up"

    # ================================
    # VERIFY DEPLOYMENT
    # ================================
    
    Write-Host "`n=== Verifying deployment... ===" -ForegroundColor White
    
    $requiredFiles = @("remove-malware.exe", "remove-threat.exe")
    $allFilesPresent = $true
    $missingFiles = @()

    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $binDir $file
        if (Test-Path $filePath) {
            $fileSize = (Get-Item $filePath).Length
            Write-Host "  [OK] $file - $([math]::Round($fileSize/1KB, 2)) KB" -ForegroundColor Green
            Write-Log "Verified: $file - $([math]::Round($fileSize/1KB, 2)) KB"
        }
        else {
            Write-Host "  [MISSING] $file" -ForegroundColor Red
            Write-Log "Missing file: $file" -Level "ERROR"
            $allFilesPresent = $false
            $missingFiles += $file
        }
    }

    if (-not $allFilesPresent) {
        throw "Deployment verification failed - Missing: $($missingFiles -join ', ')"
    }

    Write-Host "  All executables verified" -ForegroundColor Green
    Write-Log "All executables verified successfully"

    # ================================
    # CLEANUP PYTHON (OPTIONAL)
    # ================================
    
    Write-Host "`n=== Cleaning up Python installation... ===" -ForegroundColor White
    Write-Log "Starting Python cleanup"
    
    Remove-PythonCompletely
    
    Write-Host "  Python cleanup complete" -ForegroundColor Green
    Write-Log "Python cleanup completed"

    # ================================
    # START SERVICE
    # ================================
    
    Write-Host "`n=== Starting CyberSentinel service... ===" -ForegroundColor White
    try {
        Start-Service -Name "CyberSentinel" -ErrorAction Stop
        Write-Host "  Service started" -ForegroundColor Green
        Write-Log "CyberSentinel service started"
    }
    catch {
        Write-Host "  Service not found or already running" -ForegroundColor Yellow
        Write-Log "CyberSentinel service start: $($_.Exception.Message)" -Level "WARNING"
    }

    Write-Log "Phase 2: Active Response setup completed successfully" -Level "SUCCESS"

}
catch {
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █   ACTIVE RESPONSE SETUP FAILED           █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "PHASE 2 ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ================================
# FINAL SUCCESS SUMMARY
# ================================

Clear-Host
Write-Host ""
Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
Write-Host "  █                                          █" -ForegroundColor Green
Write-Host "  █   INSTALLATION COMPLETE                  █" -ForegroundColor Green
Write-Host "  █                                          █" -ForegroundColor Green
Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
Write-Host ""
Write-Host ""
Write-Host "  Summary:" -ForegroundColor Yellow
Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    CyberSentinel-agent successfully installed" -ForegroundColor Green
Write-Host "    Active-Response successfully installed" -ForegroundColor Green
Write-Host ""
Write-Host ""
Write-Host "  Installation Details:" -ForegroundColor White
Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    Agent Directory:" -ForegroundColor Gray
Write-Host "      C:\Program Files (x86)\ossec-agent" -ForegroundColor White
Write-Host ""
Write-Host "    Active Response Directory:" -ForegroundColor Gray
Write-Host "      C:\Program Files (x86)\ossec-agent\active-response\bin" -ForegroundColor White
Write-Host ""
Write-Host "    Deployed Files:" -ForegroundColor Gray
foreach ($file in @("remove-malware.exe", "remove-threat.exe")) {
    $filePath = "C:\Program Files (x86)\ossec-agent\active-response\bin\$file"
    if (Test-Path $filePath) {
        $fileSize = (Get-Item $filePath).Length
        Write-Host "      - $file - $([math]::Round($fileSize/1KB, 2)) KB" -ForegroundColor White
    }
}
Write-Host ""
Write-Host "    Log File:" -ForegroundColor Gray
Write-Host "      $logFile" -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  IMPORTANT: Please restart your computer for all changes to take effect!" -ForegroundColor Yellow
Write-Host ""
Write-Host ""

Write-Log "Complete installation finished successfully" -Level "SUCCESS"

Read-Host "Press Enter to exit"
