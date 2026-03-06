# ================================
# Active Response EXE Deployment Script
# Deploys: remove-malware.exe & remove-threat.exe
# ================================

# ================================
# GLOBAL SETTINGS
# ================================
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\active-response-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ================================
# HELPER FUNCTIONS
# ================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    switch ($Level) {
        "ERROR"   { Write-Host "  ✗ $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  ✓ $Message" -ForegroundColor Green }
        "WARNING" { Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
        default   { Write-Host "  → $Message" -ForegroundColor White }
    }
}

function Deploy-Exe {
    param(
        [string]$ExeName,
        [string]$DownloadUrl,
        [string]$TargetDir
    )

    $tempExePath  = "$env:TEMP\$ExeName"
    $finalExePath = Join-Path $TargetDir $ExeName

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Deploying: $ExeName" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # --- Download ---
    Write-Log "Downloading $ExeName from: $DownloadUrl"
    Write-Host "  Downloading... (this may take a moment)" -ForegroundColor White
    Write-Host ""

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempExePath -UseBasicParsing -ErrorAction Stop

        if (Test-Path $tempExePath) {
            $fileSizeMB = [math]::Round((Get-Item $tempExePath).Length / 1MB, 2)
            Write-Log "Download complete: $ExeName ($fileSizeMB MB)" -Level "SUCCESS"
        } else {
            throw "File not found after download attempt."
        }
    } catch {
        Write-Log "Download failed for $ExeName : $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "  Troubleshooting:" -ForegroundColor Yellow
        Write-Host "    1. Check your internet connection" -ForegroundColor White
        Write-Host "    2. Verify the GitHub release exists" -ForegroundColor White
        Write-Host "    3. Try downloading manually: $DownloadUrl" -ForegroundColor Gray
        Write-Host ""
        return $false
    }

    # --- Deploy ---
    Write-Log "Copying $ExeName to $finalExePath ..."

    try {
        if (Test-Path $finalExePath) {
            $backupPath = "$finalExePath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Log "Existing file found, backing up to: $backupPath" -Level "WARNING"
            Copy-Item -Path $finalExePath -Destination $backupPath -Force
            Write-Log "Backup created" -Level "SUCCESS"
        }

        Copy-Item -Path $tempExePath -Destination $finalExePath -Force

        if (Test-Path $finalExePath) {
            $deployedSizeMB = [math]::Round((Get-Item $finalExePath).Length / 1MB, 2)
            Write-Log "$ExeName deployed successfully ($deployedSizeMB MB)" -Level "SUCCESS"
        } else {
            throw "File not found at destination after copy."
        }
    } catch {
        Write-Log "Deployment failed for $ExeName : $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "  Possible causes:" -ForegroundColor Yellow
        Write-Host "    1. Insufficient permissions (run as Administrator)" -ForegroundColor White
        Write-Host "    2. File is in use by another process" -ForegroundColor White
        Write-Host "    3. Disk is full or write-protected" -ForegroundColor White
        Write-Host ""
        Remove-Item -Path $tempExePath -Force -ErrorAction SilentlyContinue
        return $false
    }

    # --- Cleanup ---
    Remove-Item -Path $tempExePath -Force -ErrorAction SilentlyContinue
    Write-Log "Temp file cleaned up for $ExeName"

    return $true
}

# ================================
# MAIN SCRIPT
# ================================

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
    Write-Host "   Active Response EXE Deployment Script       " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Deployment started"
    Write-Log "Log file: $logFile"
    Write-Host ""

    # ================================
    # CONFIGURATION
    # ================================
    $targetDir = "C:\Program Files (x86)\ossec-agent\active-response\bin"
    $baseUrl   = "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0"

    # Define the EXEs to deploy: Name -> Download URL
    $exeList = [ordered]@{
        "remove-malware.exe" = "$baseUrl/remove-malware.exe"
        "remove-threat.exe"  = "$baseUrl/remove-threat.exe"
    }

    Write-Log "Target directory : $targetDir"
    Write-Log "Files to deploy  : $($exeList.Keys -join ', ')"

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
            Write-Host "  Could not create target directory." -ForegroundColor Red
            Write-Host "  Please ensure the CyberSentinel agent is installed." -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    } else {
        Write-Log "Target directory exists: $targetDir" -Level "SUCCESS"
    }

    # ================================
    # STEP 2 & 3: DOWNLOAD & DEPLOY EACH EXE
    # ================================
    Write-Host ""
    Write-Host "[2/4] Downloading and deploying executables..." -ForegroundColor Yellow

    $results = @{}

    foreach ($entry in $exeList.GetEnumerator()) {
        $success = Deploy-Exe -ExeName $entry.Key -DownloadUrl $entry.Value -TargetDir $targetDir
        $results[$entry.Key] = $success
    }

    # ================================
    # STEP 3: SUMMARY
    # ================================
    Write-Host ""
    Write-Host "[3/4] Deployment Summary" -ForegroundColor Yellow
    Write-Host ""

    $allSuccess = $true
    foreach ($entry in $results.GetEnumerator()) {
        if ($entry.Value) {
            Write-Host "  ✓ $($entry.Key)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $($entry.Key)  — FAILED" -ForegroundColor Red
            $allSuccess = $false
        }
    }

    Write-Host ""

    if ($allSuccess) {
        Write-Log "All executables deployed successfully" -Level "SUCCESS"
        Write-Host ""
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
        Write-Host "  █                                          █" -ForegroundColor Green
        Write-Host "  █     ✓ DEPLOYMENT SUCCESSFUL              █" -ForegroundColor Green
        Write-Host "  █                                          █" -ForegroundColor Green
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Deployment Information:" -ForegroundColor Yellow
        Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($exeName in $exeList.Keys) {
            $finalPath = Join-Path $targetDir $exeName
            if (Test-Path $finalPath) {
                $sizeMB = [math]::Round((Get-Item $finalPath).Length / 1MB, 2)
                Write-Host "    File:     $exeName" -ForegroundColor White
                Write-Host "    Location: $finalPath" -ForegroundColor White
                Write-Host "    Size:     $sizeMB MB" -ForegroundColor White
                Write-Host ""
            }
        }
        Write-Host "  Both executables are ready to use!" -ForegroundColor Green
        Write-Host ""

        # ================================
        # RESTART CyberSentinelSvc SERVICE
        # ================================
        Write-Host ""
        Write-Host "[4/4] Restarting CyberSentinelSvc service..." -ForegroundColor Yellow
        Write-Host ""

        $serviceName = "CyberSentinelSvc"

        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop

            Write-Log "Stopping $serviceName ..."
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-Log "$serviceName stopped" -Level "SUCCESS"

            Start-Sleep -Seconds 2

            Write-Log "Starting $serviceName ..."
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-Log "$serviceName started" -Level "SUCCESS"

            $svcStatus = (Get-Service -Name $serviceName).Status
            Write-Host "  ✓ $serviceName restarted successfully (Status: $svcStatus)" -ForegroundColor Green
            Write-Host ""
        } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            Write-Log "Service '$serviceName' not found on this machine" -Level "WARNING"
            Write-Host "  ⚠ Service '$serviceName' was not found — skipping restart." -ForegroundColor Yellow
            Write-Host "    Verify the CyberSentinel agent is installed correctly." -ForegroundColor Gray
            Write-Host ""
        } catch {
            Write-Log "Failed to restart $serviceName : $($_.Exception.Message)" -Level "ERROR"
            Write-Host "  ✗ Could not restart $serviceName" -ForegroundColor Red
            Write-Host "    You may need to restart it manually:" -ForegroundColor Yellow
            Write-Host "    Restart-Service -Name $serviceName -Force" -ForegroundColor Gray
            Write-Host ""
        }

    } else {
        Write-Log "One or more executables failed to deploy" -Level "ERROR"
        Write-Host ""
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
        Write-Host "  █                                          █" -ForegroundColor Red
        Write-Host "  █     ✗ DEPLOYMENT PARTIALLY FAILED        █" -ForegroundColor Red
        Write-Host "  █                                          █" -ForegroundColor Red
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Check the log for details: $logFile" -ForegroundColor Gray
        Write-Host ""
    }
}
catch {
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █     ✗ DEPLOYMENT FAILED                  █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
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
