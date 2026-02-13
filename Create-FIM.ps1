# ================================
# Quarantine Script to EXE Builder
# ================================

# ================================
# GLOBAL SETTINGS
# ================================
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\quarantine-builder-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ================================
# HELPER FUNCTIONS
# ================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    # Also display to console with color
    switch ($Level) {
        "ERROR"   { Write-Host "  ✗ $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  ✓ $Message" -ForegroundColor Green }
        "WARNING" { Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
        default   { Write-Host "  → $Message" -ForegroundColor White }
    }
}

function Read-SecureInput {
    param([string]$Prompt)
    
    Write-Host $Prompt -NoNewline -ForegroundColor Yellow
    
    $input = ""
    
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
            Write-Host "*" -NoNewline -ForegroundColor Gray
        }
    }
    
    # Clean token - remove any control characters
    $input = $input -replace '[\x00-\x1F\x7F]', ''
    
    return $input
}

try {
    # ================================
    # HEADER
    # ================================
    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Quarantine Script to EXE Builder            " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Build process started"
    Write-Log "Log file: $logFile"
    Write-Host ""

    # ================================
    # COLLECT GITHUB TOKEN
    # ================================
    Write-Host "GitHub Configuration" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
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
    Write-Host "Token received: " -NoNewline -ForegroundColor White
    Write-Host ("*" * [Math]::Min($GitHubToken.Length, 30)) -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Proceed with download and build? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Build cancelled by user." -ForegroundColor Yellow
        Write-Log "Build cancelled by user" -Level "WARNING"
        exit 0
    }

    # ================================
    # SETUP PATHS
    # ================================
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Building Executable                          " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $downloadsFolder = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    $scriptPath = Join-Path $downloadsFolder "quarantine_rtgs.py"
    $exePath = Join-Path $downloadsFolder "quarantine_rtgs.exe"
    
    Write-Log "Downloads folder: $downloadsFolder"
    Write-Log "Script path: $scriptPath"
    Write-Log "EXE path: $exePath"

    # ================================
    # STEP 1: CHECK AND INSTALL PYTHON
    # ================================
    Write-Host "[1/5] Checking Python installation..." -ForegroundColor Yellow
    Write-Host ""
    
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    $needPythonInstall = $false
    
    if ($pythonCmd) {
        $pythonPath = $pythonCmd.Source
        Write-Log "Python found at: $pythonPath" -Level "SUCCESS"
        
        $fileInfo = Get-Item $pythonPath
        if ($fileInfo.Length -eq 0) {
            Write-Log "Python executable is corrupted (0 KB). Deleting..." -Level "WARNING"
            Remove-Item -Force $pythonPath
            $needPythonInstall = $true
        } else {
            # Verify Python works
            try {
                $pythonVersion = & python --version 2>&1
                Write-Log "Python version: $pythonVersion" -Level "SUCCESS"
            } catch {
                Write-Log "Python found but not working properly" -Level "WARNING"
                $needPythonInstall = $true
            }
        }
    } else {
        Write-Log "Python is not installed" -Level "WARNING"
        $needPythonInstall = $true
    }
    
    # Install Python if needed
    if ($needPythonInstall) {
        Write-Host ""
        Write-Host "  Python is required but not installed" -ForegroundColor Yellow
        Write-Host "  Installing Python automatically..." -ForegroundColor White
        Write-Host ""
        
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
                Write-Log "Using existing Python installer" -Level "SUCCESS"
                $downloadSuccess = $true
            } else {
                Remove-Item $pythonInstaller -Force
            }
        }
        
        # Try downloading from multiple sources
        if (-not $downloadSuccess) {
            Write-Log "Downloading Python installer..."
            
            foreach ($url in $downloadUrls) {
                Write-Log "Trying: $url"
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $url -OutFile $pythonInstaller -UseBasicParsing -TimeoutSec 120
                    
                    # Verify download
                    if (Test-Path $pythonInstaller) {
                        $fileSize = (Get-Item $pythonInstaller).Length
                        if ($fileSize -gt 10MB) {
                            Write-Log "Download complete ($([math]::Round($fileSize/1MB, 2)) MB)" -Level "SUCCESS"
                            $downloadSuccess = $true
                            break
                        } else {
                            Remove-Item $pythonInstaller -Force
                        }
                    }
                }
                catch {
                    Write-Log "Failed: $($_.Exception.Message)" -Level "WARNING"
                    continue
                }
            }
        }
        
        if (-not $downloadSuccess) {
            Write-Log "Failed to download Python installer" -Level "ERROR"
            Write-Host ""
            Write-Host "  Failed to download Python installer automatically" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Please download Python manually:" -ForegroundColor Yellow
            Write-Host "    1. Visit: https://www.python.org/downloads/" -ForegroundColor White
            Write-Host "    2. Download Python 3.13.1 or newer" -ForegroundColor White
            Write-Host "    3. Install with 'Add Python to PATH' checked" -ForegroundColor White
            Write-Host "    4. Re-run this script" -ForegroundColor White
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
        
        Write-Log "Installing Python silently (this may take 2-3 minutes)..."
        Write-Host "  Installing Python $pythonVersion..." -ForegroundColor White
        Write-Host "  This may take 2-3 minutes, please wait..." -ForegroundColor Gray
        Write-Host ""
        
        # FULLY AUTOMATED SILENT INSTALL
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
            Write-Host ""
            Write-Host "  Python installation failed!" -ForegroundColor Red
            Write-Host "  Please install Python manually from: https://www.python.org/downloads/" -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
        
        Write-Log "Python installed successfully" -Level "SUCCESS"
        
        # Refresh environment variables
        Write-Log "Refreshing environment variables..."
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
                Write-Log "Python found at: $pythonExe" -Level "SUCCESS"
                break
            }
        }
        
        if (-not $pythonExe) {
            Write-Log "Python installed but executable not found" -Level "ERROR"
            Write-Host ""
            Write-Host "  Python installed but not found in PATH" -ForegroundColor Red
            Write-Host "  Please restart PowerShell and try again" -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
        
        # Verify Python works
        $pythonVersion = & $pythonExe --version 2>&1
        Write-Log "Python version: $pythonVersion" -Level "SUCCESS"
        
        # Cleanup installer
        Remove-Item $pythonInstaller -Force -ErrorAction SilentlyContinue
    }

    # ================================
    # STEP 2: DOWNLOAD PYTHON SCRIPT
    # ================================
    Write-Host ""
    Write-Host "[2/5] Downloading Python script from GitHub..." -ForegroundColor Yellow
    Write-Host ""
    
    $scriptUrl = "https://raw.githubusercontent.com/cybersentinel-06/CyberSentinel-SIEM/refs/heads/main/AGENTS/WINDOWS-AGENT/quarantine_rtgs.py"
    
    # Add token to URL
    $authenticatedUrl = "${scriptUrl}?token=${GitHubToken}"
    
    Write-Log "Downloading from GitHub repository"
    Write-Log "URL: $scriptUrl"
    
    try {
        # Download the file
        Invoke-WebRequest -Uri $authenticatedUrl -OutFile $scriptPath -UseBasicParsing -ErrorAction Stop
        
        if (Test-Path $scriptPath) {
            $fileSize = (Get-Item $scriptPath).Length
            Write-Log "Script downloaded successfully ($fileSize bytes)" -Level "SUCCESS"
        } else {
            throw "File not found after download"
        }
    } catch {
        Write-Host ""
        Write-Log "Failed to download script: $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Verify your token has 'repo' scope" -ForegroundColor White
        Write-Host "  2. Check if the repository exists and is accessible" -ForegroundColor White
        Write-Host "  3. Ensure the file path is correct in the repository" -ForegroundColor White
        Write-Host ""
        Write-Host "Repository: https://github.com/cybersentinel-06/CyberSentinel-SIEM" -ForegroundColor White
        Write-Host "File path: /AGENTS/WINDOWS-AGENT/quarantine_rtgs.py" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ================================
    # STEP 3: CHECK PYTHON INSTALLATION
    # ================================
    Write-Host ""
    Write-Host "[3/5] Verifying Python installation..." -ForegroundColor Yellow
    Write-Host ""
    
    # Use py.exe if available (more reliable)
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        $pythonCmd = "py"
        Write-Log "Using py.exe launcher" -Level "SUCCESS"
    } else {
        $pythonCmd = "python"
        Write-Log "Using python.exe" -Level "SUCCESS"
    }
    
    try {
        $pythonVersion = & $pythonCmd --version 2>&1
        Write-Log "Python found: $pythonVersion" -Level "SUCCESS"
    } catch {
        Write-Host ""
        Write-Log "Python is not installed or not in PATH" -Level "ERROR"
        Write-Host ""
        Write-Host "Please install Python from: https://www.python.org/downloads/" -ForegroundColor White
        Write-Host "Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
        Write-Host ""
    }

    # ================================
    # STEP 4: INSTALL/CHECK PYINSTALLER
    # ================================
    Write-Host ""
    Write-Host "[4/5] Checking PyInstaller installation..." -ForegroundColor Yellow
    Write-Host ""
    
    Write-Log "Installing/upgrading pip..."
    & $pythonCmd -m ensurepip --upgrade 2>&1 | Out-File -FilePath $logFile -Append
    & $pythonCmd -m pip install --upgrade pip 2>&1 | Out-File -FilePath $logFile -Append
    
    $pyinstallerCheck = & $pythonCmd -m pip show pyinstaller 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "PyInstaller not found, installing..." -Level "WARNING"
        Write-Host ""
        Write-Host "  Installing PyInstaller (this may take a minute)..." -ForegroundColor White
        Write-Host ""
        
        & $pythonCmd -m pip install pyinstaller 2>&1 | Out-File -FilePath $logFile -Append
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "PyInstaller installed successfully" -Level "SUCCESS"
        } else {
            Write-Log "Failed to install PyInstaller" -Level "ERROR"
            Write-Host ""
            Write-Host "Please install PyInstaller manually:" -ForegroundColor Yellow
            Write-Host "  $pythonCmd -m pip install pyinstaller" -ForegroundColor White
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    } else {
        Write-Log "PyInstaller is already installed" -Level "SUCCESS"
    }
    
    # Get Python Scripts folder (where pyinstaller.exe is installed)
    $pyScriptsPath = & $pythonCmd -c "import sysconfig; print(sysconfig.get_paths()['scripts'])" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "PyInstaller location: $pyScriptsPath"
        
        # Add to current session PATH
        if ($env:Path -notlike "*$pyScriptsPath*") {
            $env:Path += ";$pyScriptsPath"
        }
    }

    # ================================
    # STEP 5: BUILD EXECUTABLE
    # ================================
    Write-Host ""
    Write-Host "[5/5] Building executable with PyInstaller..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This may take a few minutes..." -ForegroundColor White
    Write-Host ""
    
    Write-Log "Starting PyInstaller build process"
    
    # Change to downloads directory
    Push-Location $downloadsFolder
    
    try {
        # Build the executable
        $pyinstallerArgs = @(
            "-m", "PyInstaller",
            "--onefile",
            "--clean",
            "--name", "quarantine_rtgs",
            "--log-level", "ERROR",
            "quarantine_rtgs.py"
        )
        
        Write-Log "PyInstaller command: $pythonCmd $($pyinstallerArgs -join ' ')"
        
        $buildOutput = & $pythonCmd @pyinstallerArgs 2>&1
        $buildOutput | Out-File -FilePath $logFile -Append
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "PyInstaller build completed" -Level "SUCCESS"
        } else {
            throw "PyInstaller build failed with exit code $LASTEXITCODE"
        }
        
        # Move executable from dist folder to downloads folder
        $distExePath = Join-Path $downloadsFolder "dist\quarantine_rtgs.exe"
        
        if (Test-Path $distExePath) {
            Write-Log "Moving executable to Downloads folder"
            Move-Item -Path $distExePath -Destination $exePath -Force
            Write-Log "Executable moved successfully" -Level "SUCCESS"
        } else {
            throw "Executable not found in dist folder"
        }
        
        # Clean up build artifacts
        Write-Log "Cleaning up build artifacts"
        Remove-Item -Path (Join-Path $downloadsFolder "build") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $downloadsFolder "dist") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $downloadsFolder "quarantine_rtgs.spec") -Force -ErrorAction SilentlyContinue
        Write-Log "Build artifacts cleaned up" -Level "SUCCESS"
        
    } catch {
        Write-Log "Build failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    } finally {
        Pop-Location
    }

    # ================================
    # VERIFY EXECUTABLE
    # ================================
    if (Test-Path $exePath) {
        $exeSize = (Get-Item $exePath).Length
        $exeSizeMB = [math]::Round($exeSize / 1MB, 2)
        Write-Log "Executable created successfully ($exeSizeMB MB)" -Level "SUCCESS"
    } else {
        throw "Executable file not found after build"
    }

    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Log "Build process completed successfully" -Level "SUCCESS"
    
    Write-Host ""
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  █     ✓ BUILD SUCCESSFUL                   █" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host ""
    Write-Host ""
    Write-Host "  Build Information:" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Python Script:  $scriptPath" -ForegroundColor White
    Write-Host "    Executable:     $exePath" -ForegroundColor White
    Write-Host "    Size:           $exeSizeMB MB" -ForegroundColor White
    Write-Host ""
    Write-Host "  The executable is ready to use!" -ForegroundColor Green
    Write-Host ""
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █     ✗ BUILD FAILED                       █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log file: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "BUILD ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
