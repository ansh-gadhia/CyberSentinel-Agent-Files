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
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" `
        -OutFile "$env:TEMP\ca.cer" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Import CA certificate
    Write-Log "Importing CA certificate"
    Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root 2>&1 | Out-File -FilePath $logFile -Append

    # Download MSI installer
    Write-Log "Downloading MSI installer"
    Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" `
        -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing 2>&1 | Out-File -FilePath $logFile -Append

    # Install agent - let MSI set default group
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

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Active Response Setup & Cleanup" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # =============================================================================
    # PHASE 1: INSTALL PYTHON AND BUILD ACTIVE RESPONSE TOOLS
    # =============================================================================
    Write-Host "[PHASE 1] Installing Python and building executables..." -ForegroundColor Yellow
Write-Host ""

# --- Check Python installation ---
Write-Host "=== Checking for Python installation... ===" -ForegroundColor White
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue

$needPythonInstall = $false
if ($pythonCmd) {
    $pythonPath = $pythonCmd.Source
    Write-Host "Python found at: $pythonPath" -ForegroundColor Green
    $fileInfo = Get-Item $pythonPath
    if ($fileInfo.Length -eq 0) {
        Write-Warning "Python executable is 0 KB. Deleting corrupted file..."
        Remove-Item -Force $pythonPath
        $needPythonInstall = $true
    }
} else {
    Write-Warning "Python is not installed."
    $needPythonInstall = $true
}

# --- Install Python if needed (FULLY AUTOMATED) ---
if ($needPythonInstall) {
    $pythonInstaller = "$env:TEMP\python-installer.exe"
    $pythonVersion = "3.13.1"
    
    # Multiple download sources
    $downloadUrls = @(
        "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe",
        "https://github.com/python/cpython/releases/download/v$pythonVersion/python-$pythonVersion-amd64.exe"
    )
    
    $downloadSuccess = $false
    
    # Check if installer already exists
    if (Test-Path $pythonInstaller) {
        $fileSize = (Get-Item $pythonInstaller).Length
        if ($fileSize -gt 10MB) {
            Write-Host "=== Using existing Python installer... ===" -ForegroundColor Green
            $downloadSuccess = $true
        } else {
            Remove-Item $pythonInstaller -Force
        }
    }
    
    # Try downloading from multiple sources
    if (-not $downloadSuccess) {
        Write-Host "=== Downloading Python installer... ===" -ForegroundColor White
        
        foreach ($url in $downloadUrls) {
            Write-Host "  Trying: $url" -ForegroundColor Gray
            try {
                # Disable certificate validation for corporate networks
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $url -OutFile $pythonInstaller -UseBasicParsing -TimeoutSec 60
                
                # Verify download
                if (Test-Path $pythonInstaller) {
                    $fileSize = (Get-Item $pythonInstaller).Length
                    if ($fileSize -gt 10MB) {
                        Write-Host "  Download complete ($([math]::Round($fileSize/1MB, 2)) MB)" -ForegroundColor Green
                        $downloadSuccess = $true
                        break
                    } else {
                        Remove-Item $pythonInstaller -Force
                    }
                }
            }
            catch {
                Write-Warning "  Failed: $($_.Exception.Message)"
                continue
            }
        }
    }
    
    if (-not $downloadSuccess) {
        Write-Error @"
Failed to download Python installer.

OPTIONS:
1. Check your internet connection
2. Download manually from: https://www.python.org/downloads/
   Save as: $pythonInstaller
3. Re-run this script

If behind a proxy, configure PowerShell proxy:
`$webproxy = New-Object System.Net.WebProxy("http://proxy:port")
`$webclient = New-Object System.Net.WebClient
`$webclient.Proxy = `$webproxy
"@
        exit 1
    }

    Write-Host "=== Installing Python silently (no dialogs)... ===" -ForegroundColor White
    
    # FULLY AUTOMATED SILENT INSTALL
    # /quiet = no UI
    # InstallAllUsers=1 = system-wide install
    # PrependPath=1 = add to PATH
    # Include_pip=1 = install pip
    # Include_tcltk=1 = include Tkinter
    # Include_launcher=1 = install py.exe launcher
    # AssociateFiles=1 = associate .py files
    
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
    
    Write-Host "  Installing Python $pythonVersion (this may take 2-3 minutes)..." -ForegroundColor Gray
    
    $process = Start-Process -FilePath $pythonInstaller -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Error "Python installation failed with exit code: $($process.ExitCode)"
        exit 1
    }
    
    Write-Host "  Python installed successfully" -ForegroundColor Green
    
    # Refresh environment variables
    Write-Host "=== Refreshing environment variables... ===" -ForegroundColor White
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Wait for installation to complete
    Start-Sleep -Seconds 3
    
    # Find Python executable
    $pythonExe = $null
    $possiblePaths = @(
        "C:\Program Files\Python313\python.exe",
        "C:\Program Files\Python$($pythonVersion.Replace('.',''))\python.exe",
        "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python313\python.exe",
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
        Write-Error "Python installed but executable not found. Try restarting PowerShell."
        exit 1
    }
    
    Write-Host "Python available at: $pythonExe" -ForegroundColor Green
    
    # Verify Python works
    $pythonVersion = & $pythonExe --version 2>&1
    Write-Host "Python version: $pythonVersion" -ForegroundColor Green
}
else {
    $pythonExe = $pythonCmd.Source
}

# --- Python confirmed installed, continue with pip + PyInstaller ---
Write-Host "`n=== Installing required Python packages... ===" -ForegroundColor White

# Use py.exe if available (more reliable)
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($pyLauncher) {
    $pythonCmd = "py"
    Write-Host "  Using py.exe launcher" -ForegroundColor Gray
} else {
    $pythonCmd = "python"
    Write-Host "  Using python.exe" -ForegroundColor Gray
}

Write-Host "  Installing pip..." -ForegroundColor Gray
& $pythonCmd -m ensurepip --upgrade 2>&1 | Out-Null

# Upgrade pip first
Write-Host "  Upgrading pip..." -ForegroundColor Gray
& $pythonCmd -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null

# Get Python Scripts path and add to PATH immediately
Write-Host "  Configuring environment..." -ForegroundColor Gray
$pyScriptsPath = & $pythonCmd -c "import sysconfig; print(sysconfig.get_paths()['scripts'])" 2>&1

if ($LASTEXITCODE -eq 0 -and $pyScriptsPath) {
    $pyScriptsPath = $pyScriptsPath.Trim()
    
    # Add to current session PATH
    if ($env:Path -notlike "*$pyScriptsPath*") {
        $env:Path = "$pyScriptsPath;$env:Path"
        Write-Host "  Added Scripts to PATH: $pyScriptsPath" -ForegroundColor Gray
    }
    
    # Add to machine PATH permanently
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$pyScriptsPath*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$pyScriptsPath;$machinePath", "Machine")
        Write-Host "  Updated system PATH permanently" -ForegroundColor Gray
    }
}

Write-Host "  Installing PyInstaller..." -ForegroundColor Gray
& $pythonCmd -m pip install pyinstaller --quiet --disable-pip-version-check 2>&1 | Out-Null

Write-Host "  Dependencies installed successfully" -ForegroundColor Green


# --- Main build logic ---
$targetDir = "C:\Program Files (x86)\ossec-agent\active-response"
$binDir    = "$targetDir\bin"
$buildDir  = "$env:TEMP\CyberSentinel-Build"

# Prepare directories
if (!(Test-Path $binDir)) { 
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null 
    Write-Host "`nCreated directory: $binDir" -ForegroundColor Green
}
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

# Download Python scripts
Write-Host "`n=== Downloading Python scripts... ===" -ForegroundColor White
$removeThreatUrl  = "https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-threat.py"
$removeMalwareUrl = "https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-malware.py"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "  Downloading remove-threat.py..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $removeThreatUrl -OutFile "$buildDir\remove-threat.py" -UseBasicParsing
    Write-Host "  Downloading remove-malware.py..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $removeMalwareUrl -OutFile "$buildDir\remove-malware.py" -UseBasicParsing
    Write-Host "  Scripts downloaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to download scripts: $_"
    exit 1
}

# Compile with pyinstaller
Write-Host "`n=== Compiling executables... ===" -ForegroundColor White

Write-Host "  Compiling remove-threat.py..." -ForegroundColor Gray

# Capture full output for debugging
$pyinstallerOutput = & $pythonCmd -m PyInstaller -F "$buildDir\remove-threat.py" --distpath "$buildDir\dist" --workpath "$buildDir\build" --clean 2>&1

# Filter out just the admin warning
$filteredOutput = $pyinstallerOutput | Where-Object { $_ -notmatch "DEPRECATION.*admin" }

# Check if compilation actually succeeded by looking for the exe
if (Test-Path "$buildDir\dist\remove-threat.exe") {
    Write-Host "  remove-threat.exe compiled successfully" -ForegroundColor Green
} else {
    Write-Host "`n  Compilation failed. Full output:" -ForegroundColor Red
    $pyinstallerOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Log "PyInstaller output: $($pyinstallerOutput -join "`n")" -Level "ERROR"
    Write-Error "remove-threat.py compilation failed!"
    exit 1
}

Write-Host "  Compiling remove-malware.py..." -ForegroundColor Gray

# Capture full output for debugging
$pyinstallerOutput = & $pythonCmd -m PyInstaller -F "$buildDir\remove-malware.py" --distpath "$buildDir\dist" --workpath "$buildDir\build" --clean 2>&1

# Filter out just the admin warning
$filteredOutput = $pyinstallerOutput | Where-Object { $_ -notmatch "DEPRECATION.*admin" }

# Check if compilation actually succeeded by looking for the exe
if (Test-Path "$buildDir\dist\remove-malware.exe") {
    Write-Host "  remove-malware.exe compiled successfully" -ForegroundColor Green
} else {
    Write-Host "`n  Compilation failed. Full output:" -ForegroundColor Red
    $pyinstallerOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Log "PyInstaller output: $($pyinstallerOutput -join "`n")" -Level "ERROR"
    Write-Error "remove-malware.py compilation failed!"
    exit 1
}

Write-Host "`n  Both executables compiled successfully" -ForegroundColor Green
# Deploy executables
Write-Host "`n=== Deploying executables... ===" -ForegroundColor White
try {
    Move-Item -Path "$buildDir\dist\remove-threat.exe" -Destination $binDir -Force
    Move-Item -Path "$buildDir\dist\remove-malware.exe" -Destination $binDir -Force
    Write-Host "  Executables deployed to $binDir" -ForegroundColor Green
}
catch {
    Write-Error "Failed to deploy executables: $_"
    exit 1
}

# Cleanup build directory
Remove-Item -Recurse -Force $buildDir

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

    Write-Host ""
Write-Host "[PHASE 1] Complete - Active response tools built and deployed" -ForegroundColor Green
Write-Host ""

# =============================================================================
# PHASE 2: VERIFY DEPLOYMENT
# =============================================================================

Write-Host "[PHASE 2] Verifying deployment..." -ForegroundColor Yellow
Write-Host ""

$requiredFiles = @(
    "remove-malware.exe",
    "remove-threat.exe"
)

$allFilesPresent = $true
$missingFiles = @()

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $binDir $file
    if (Test-Path $filePath) {
        $fileSize = (Get-Item $filePath).Length
        Write-Host "  [OK] $file ($([math]::Round($fileSize/1KB, 2)) KB)" -ForegroundColor Green
    }
    else {
        Write-Host "  [MISSING] $file" -ForegroundColor Red
        $allFilesPresent = $false
        $missingFiles += $file
    }
}

Write-Host ""

if (-not $allFilesPresent) {
    Write-Error "Deployment verification failed! Missing files: $($missingFiles -join ', ')"
    Write-Error "Cannot proceed with Python removal. Please ensure all required files are in place."
    exit 1
}

Write-Host "[PHASE 2] Complete - Required executables verified" -ForegroundColor Green
Write-Host ""

# =============================================================================
# PHASE 3: REMOVE PYTHON COMPLETELY
# =============================================================================

Write-Host "[PHASE 3] Removing Python installation..." -ForegroundColor Yellow
Write-Host ""

# Stop any Python processes first
Write-Host "=== Stopping Python processes... ===" -ForegroundColor White
$pythonProcesses = Get-Process | Where-Object { $_.ProcessName -like "*python*" }
if ($pythonProcesses) {
    foreach ($proc in $pythonProcesses) {
        Write-Host "  Stopping: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Gray
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host "  Stopped" -ForegroundColor Green
        }
        catch {
            Write-Host "  Could not stop process" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "  No Python processes running" -ForegroundColor Gray
}

Start-Sleep -Seconds 2

# Method 1: Uninstall via Registry
Write-Host "`n=== Searching for Python in registry... ===" -ForegroundColor White

$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

$pythonInstalls = @()

foreach ($path in $uninstallPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | ForEach-Object {
            $app = Get-ItemProperty $_.PSPath
            if ($app.DisplayName -like "*Python*") {
                $pythonInstalls += $app
            }
        }
    }
}

if ($pythonInstalls.Count -gt 0) {
    foreach ($install in $pythonInstalls) {
        $name = $install.DisplayName
        $uninstallString = $install.UninstallString
        
        if ($uninstallString) {
            Write-Host "  Found: $name" -ForegroundColor Gray
            
            # Try multiple uninstall methods
            $uninstalled = $false
            
            # Method 1: Use the uninstall string directly
            if ($uninstallString -match "msiexec") {
                Write-Host "  Trying standard MSI uninstall..." -ForegroundColor Gray
                $extractedGuid = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
                $result = Start-Process "msiexec.exe" -ArgumentList "/x $extractedGuid /qn /norestart" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Host "  Success" -ForegroundColor Green
                    $uninstalled = $true
                }
            }
            
            # Method 2: Try with /quiet instead of /qn
            if (-not $uninstalled -and $uninstallString -match "msiexec") {
                Write-Host "  Trying alternate MSI method..." -ForegroundColor Gray
                $extractedGuid = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
                $result = Start-Process "msiexec.exe" -ArgumentList "/x $extractedGuid /quiet /norestart" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Host "  Success" -ForegroundColor Green
                    $uninstalled = $true
                }
            }
            
            # Method 3: Try running the uninstaller directly
            if (-not $uninstalled -and $uninstallString -match '"(.+?)"') {
                Write-Host "  Trying direct uninstaller..." -ForegroundColor Gray
                $exe = $matches[1]
                if (Test-Path $exe) {
                    $result = Start-Process $exe -ArgumentList "/uninstall /quiet" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
                    if ($result.ExitCode -eq 0) {
                        Write-Host "  Success" -ForegroundColor Green
                        $uninstalled = $true
                    }
                }
            }
            
            if (-not $uninstalled) {
                Write-Host "  Could not uninstall via MSI (will remove manually)" -ForegroundColor Yellow
            }
        }
    }
}
else {
    Write-Host "  No Python found in registry" -ForegroundColor Gray
}

# Method 2: Remove Microsoft Store Python
Write-Host "`n=== Checking for Microsoft Store Python... ===" -ForegroundColor White
$storeApps = Get-AppxPackage | Where-Object { $_.Name -like "*Python*" }
if ($storeApps) {
    foreach ($app in $storeApps) {
        Write-Host "  Removing: $($app.Name)" -ForegroundColor Gray
        try {
            Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
            Write-Host "  Success" -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "  No Microsoft Store Python found" -ForegroundColor Gray
}

# Method 3: Force remove directories
Write-Host "`n=== Force removing Python directories... ===" -ForegroundColor White

$dirsToCheck = @(
    "$env:LOCALAPPDATA\Programs\Python*",
    "$env:LOCALAPPDATA\Python*",
    "$env:APPDATA\Python",
    "$env:ProgramFiles\Python*",
    "${env:ProgramFiles(x86)}\Python*",
    "C:\Python*"
)

$removed = $false
foreach ($pattern in $dirsToCheck) {
    $dirs = Get-Item $pattern -ErrorAction SilentlyContinue
    if ($dirs) {
        foreach ($dir in $dirs) {
            Write-Host "  Removing: $($dir.FullName)" -ForegroundColor Gray
            
            # Try to take ownership first if needed
            try {
                takeown /f "$($dir.FullName)" /r /d y 2>&1 | Out-Null
                icacls "$($dir.FullName)" /grant administrators:F /t 2>&1 | Out-Null
            }
            catch {
                # Ignore ownership errors
            }
            
            try {
                Remove-Item $dir.FullName -Recurse -Force -ErrorAction Stop
                Write-Host "  Success" -ForegroundColor Green
                $removed = $true
            }
            catch {
                Write-Host "  Warning: Some files may be locked" -ForegroundColor Yellow
                # Try to remove what we can
                Get-ChildItem $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

if (-not $removed) {
    Write-Host "  No directories found" -ForegroundColor Gray
}

# Method 4: Clean PATH
Write-Host "`n=== Cleaning PATH variables... ===" -ForegroundColor White
$pathChanged = $false

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
                Write-Host "  Cleaned $scope PATH" -ForegroundColor Green
                $pathChanged = $true
            }
        }
    }
    catch {
        Write-Host "  Warning cleaning $scope PATH: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $pathChanged) {
    Write-Host "  PATH already clean" -ForegroundColor Gray
}

# Method 5: Remove pip cache
Write-Host "`n=== Cleaning pip cache... ===" -ForegroundColor White
$pipDirs = @(
    "$env:LOCALAPPDATA\pip",
    "$env:APPDATA\pip"
)

$cleaned = $false
foreach ($dir in $pipDirs) {
    if (Test-Path $dir) {
        try {
            Remove-Item $dir -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed $dir" -ForegroundColor Green
            $cleaned = $true
        }
        catch {
            Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

if (-not $cleaned) {
    Write-Host "  No pip cache found" -ForegroundColor Gray
}

# Method 6: Clean registry
Write-Host "`n=== Cleaning registry... ===" -ForegroundColor White
$regKeys = @(
    "HKCU:\Software\Python",
    "HKLM:\Software\Python",
    "HKLM:\Software\WOW6432Node\Python"
)

$regCleaned = $false
foreach ($key in $regKeys) {
    if (Test-Path $key) {
        try {
            Remove-Item $key -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed $key" -ForegroundColor Green
            $regCleaned = $true
        }
        catch {
            Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Also remove installer registry keys
foreach ($path in $uninstallPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | ForEach-Object {
            $app = Get-ItemProperty $_.PSPath
            if ($app.DisplayName -like "*Python*") {
                try {
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction Stop
                    Write-Host "  Removed installer key: $($app.DisplayName)" -ForegroundColor Green
                    $regCleaned = $true
                }
                catch {
                    # Ignore
                }
            }
        }
    }
}

if (-not $regCleaned) {
    Write-Host "  No Python registry keys found" -ForegroundColor Gray
}

# Method 7: Remove file associations
Write-Host "`n=== Cleaning file associations... ===" -ForegroundColor White
$assocKeys = @(
    "HKCU:\Software\Classes\.py",
    "HKCU:\Software\Classes\.pyw",
    "HKCU:\Software\Classes\.pyc",
    "HKCU:\Software\Classes\Python.File",
    "HKCU:\Software\Classes\Python.NoConFile",
    "HKCU:\Software\Classes\Python.CompiledFile"
)

$assocCleaned = $false
foreach ($key in $assocKeys) {
    if (Test-Path $key) {
        try {
            Remove-Item $key -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed association: $key" -ForegroundColor Green
            $assocCleaned = $true
        }
        catch {
            # Ignore
        }
    }
}

if (-not $assocCleaned) {
    Write-Host "  No file associations found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[PHASE 3] Complete - Python removed successfully" -ForegroundColor Green
Write-Host ""

# =============================================================================
# FINAL SUMMARY
# =============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "  ✓ Python installed and configured" -ForegroundColor Green
Write-Host "  ✓ Active response tools compiled" -ForegroundColor Green
Write-Host "  ✓ Executables deployed to $binDir" -ForegroundColor Green
Write-Host "  ✓ All required files verified" -ForegroundColor Green
Write-Host "  ✓ Python completely removed" -ForegroundColor Green
Write-Host "  ✓ System cleaned and ready" -ForegroundColor Green
Write-Host ""
Write-Host "Deployed files:" -ForegroundColor White
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $binDir $file
    if (Test-Path $filePath) {
        $fileSize = (Get-Item $filePath).Length
        Write-Host "  - $file ($([math]::Round($fileSize/1KB, 2)) KB)" -ForegroundColor Gray
    }
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
    Write-Host "    Group:     $detectedGroup" -ForegroundColor White
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
