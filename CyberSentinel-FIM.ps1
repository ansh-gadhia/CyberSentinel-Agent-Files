# ================================
# Quarantine EXE Deployment Script
# ================================

# ================================
# GLOBAL SETTINGS
# ================================
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\quarantine-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

try {
    # ================================
    # CHECK ADMINISTRATOR PRIVILEGES
    # ================================
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host ""
        Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
        Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ================================
    # HEADER
    # ================================
    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Quarantine EXE Deployment Script            " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Deployment started"
    Write-Log "Log file: $logFile"
    Write-Host ""

    # ================================
    # CONFIGURATION
    # ================================
    $targetDir = "C:\Program Files (x86)\ossec-agent\active-response\bin"
    $exeUrl = "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/quarantine_rtgs.exe"
    $exeName = "quarantine_rtgs.exe"
    $tempExePath = "$env:TEMP\$exeName"
    $finalExePath = Join-Path $targetDir $exeName

    Write-Log "Target directory: $targetDir"
    Write-Log "Download URL: $exeUrl"
    Write-Log "Final path: $finalExePath"

    # ================================
    # STEP 1: VERIFY TARGET DIRECTORY
    # ================================
    Write-Host "[1/3] Verifying target directory..." -ForegroundColor Yellow
    Write-Host ""
    
    if (-not (Test-Path $targetDir)) {
        Write-Log "Target directory does not exist, creating..." -Level "WARNING"
        try {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Write-Log "Directory created: $targetDir" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to create directory: $($_.Exception.Message)" -Level "ERROR"
            Write-Host ""
            Write-Host "Could not create target directory." -ForegroundColor Red
            Write-Host "Please ensure CyberSentinel agent is installed." -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    } else {
        Write-Log "Target directory exists" -Level "SUCCESS"
    }

    # ================================
    # STEP 2: DOWNLOAD EXECUTABLE
    # ================================
    Write-Host ""
    Write-Host "[2/3] Downloading quarantine_rtgs.exe..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This may take a moment..." -ForegroundColor White
    Write-Host ""
    
    Write-Log "Downloading from GitHub releases..."
    
    try {
        # Enable TLS 1.2 for GitHub
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Download the file
        Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath -UseBasicParsing -ErrorAction Stop
        
        if (Test-Path $tempExePath) {
            $fileSize = (Get-Item $tempExePath).Length
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
            Write-Log "Download complete ($fileSizeMB MB)" -Level "SUCCESS"
        } else {
            throw "File not found after download"
        }
    } catch {
        Write-Host ""
        Write-Log "Failed to download executable: $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Check your internet connection" -ForegroundColor White
        Write-Host "  2. Verify the GitHub release exists" -ForegroundColor White
        Write-Host "  3. Try downloading manually from:" -ForegroundColor White
        Write-Host "     $exeUrl" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Log file: $logFile" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ================================
    # STEP 3: DEPLOY EXECUTABLE
    # ================================
    Write-Host ""
    Write-Host "[3/3] Deploying executable..." -ForegroundColor Yellow
    Write-Host ""
    
    Write-Log "Copying executable to target directory..."
    
    try {
        # Check if file already exists and backup if needed
        if (Test-Path $finalExePath) {
            $backupPath = "$finalExePath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Log "Existing file found, creating backup: $backupPath" -Level "WARNING"
            Copy-Item -Path $finalExePath -Destination $backupPath -Force
            Write-Log "Backup created" -Level "SUCCESS"
        }
        
        # Copy the file
        Copy-Item -Path $tempExePath -Destination $finalExePath -Force
        
        # Verify deployment
        if (Test-Path $finalExePath) {
            $deployedSize = (Get-Item $finalExePath).Length
            $deployedSizeMB = [math]::Round($deployedSize / 1MB, 2)
            Write-Log "Executable deployed successfully ($deployedSizeMB MB)" -Level "SUCCESS"
        } else {
            throw "File not found at destination after copy"
        }
        
    } catch {
        Write-Log "Failed to deploy executable: $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "Could not copy file to target directory." -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  1. Insufficient permissions (run as Administrator)" -ForegroundColor White
        Write-Host "  2. File is in use by another process" -ForegroundColor White
        Write-Host "  3. Disk is full or write-protected" -ForegroundColor White
        Write-Host ""
        Write-Host "Log file: $logFile" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ================================
    # CLEANUP
    # ================================
    Write-Log "Cleaning up temporary files..."
    Remove-Item -Path $tempExePath -Force -ErrorAction SilentlyContinue

    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Log "Deployment completed successfully" -Level "SUCCESS"
    
    Write-Host ""
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  █     ✓ DEPLOYMENT SUCCESSFUL              █" -ForegroundColor Green
    Write-Host "  █                                          █" -ForegroundColor Green
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
    Write-Host ""
    Write-Host ""
    Write-Host "  Deployment Information:" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    File:      $exeName" -ForegroundColor White
    Write-Host "    Location:  $finalExePath" -ForegroundColor White
    Write-Host "    Size:      $deployedSizeMB MB" -ForegroundColor White
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
    Write-Host "  █     ✗ DEPLOYMENT FAILED                  █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log file: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "DEPLOYMENT ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
