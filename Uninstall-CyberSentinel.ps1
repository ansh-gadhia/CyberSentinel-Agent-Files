# ================================
# CyberSentinel Agent Uninstallation Script
# ================================

# ================================
# GLOBAL SETTINGS
# ================================
$ErrorActionPreference = "Continue"  # Continue on errors to clean up as much as possible
$ProgressPreference   = "SilentlyContinue"

# Setup logging
$logFile = "$env:TEMP\cybersentinel-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ================================
# HELPER FUNCTIONS
# ================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    # Also display to console with color
    switch ($Level) {
        "SUCCESS" { Write-Host "  ✓ $Message" -ForegroundColor Green }
        "ERROR"   { Write-Host "  ✗ $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
        default   { Write-Host "  • $Message" -ForegroundColor Gray }
    }
}

function Remove-ItemSafely {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$Recurse
    )
    
    if (Test-Path $Path) {
        try {
            if ($Recurse) {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -Path $Path -Force -ErrorAction Stop
            }
            Write-Log "Removed: $Description" -Level "SUCCESS"
            return $true
        } catch {
            Write-Log "Failed to remove: $Description - $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    } else {
        Write-Log "Not found (skipping): $Description" -Level "WARNING"
        return $true
    }
}

# ================================
# MAIN UNINSTALLATION
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

    Clear-Host
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   CyberSentinel Agent Uninstallation Script   " -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: This will completely remove CyberSentinel Agent" -ForegroundColor Yellow
    Write-Host "         and ALL associated files and configurations!" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Log "Uninstallation started"
    Write-Log "Log file: $logFile"
    
    # Confirmation
    $confirm = Read-Host "Are you sure you want to continue? (Type 'YES' to confirm)"
    if ($confirm -ne 'YES') {
        Write-Host ""
        Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
        Write-Log "Uninstallation cancelled by user" -Level "WARNING"
        exit 0
    }

    Write-Host ""
    Write-Host "Starting uninstallation..." -ForegroundColor Cyan
    Write-Host ""

    # ================================
    # STEP 1: STOP SERVICES
    # ================================
    Write-Host "[1/8] Stopping CyberSentinel services..." -ForegroundColor Cyan
    Write-Log "[1/8] Stopping services"
    
    $services = @("CyberSentinelSvc", "Sysmon", "Sysmon64")
    
    foreach ($serviceName in $services) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -eq "Running") {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Stopped service: $serviceName" -Level "SUCCESS"
                } else {
                    Write-Log "Service already stopped: $serviceName" -Level "SUCCESS"
                }
            } else {
                Write-Log "Service not found: $serviceName" -Level "WARNING"
            }
        } catch {
            Write-Log "Error stopping service $serviceName : $($_.Exception.Message)" -Level "ERROR"
        }
    }

    Start-Sleep -Seconds 2

    # ================================
    # STEP 2: UNINSTALL SYSMON
    # ================================
    Write-Host ""
    Write-Host "[2/8] Uninstalling Sysmon..." -ForegroundColor Cyan
    Write-Log "[2/8] Uninstalling Sysmon"
    
    $sysmonPaths = @(
        "C:\Program Files (x86)\ossec-agent\Sysmon64.exe",
        "C:\Program Files (x86)\ossec-agent\Sysmon.exe",
        "C:\Windows\Sysmon64.exe",
        "C:\Windows\Sysmon.exe"
    )
    
    foreach ($sysmonPath in $sysmonPaths) {
        if (Test-Path $sysmonPath) {
            try {
                Write-Log "Found Sysmon at: $sysmonPath"
                & $sysmonPath -u force 2>&1 | Out-File -FilePath $logFile -Append
                Write-Log "Uninstalled Sysmon from: $sysmonPath" -Level "SUCCESS"
                Start-Sleep -Seconds 1
            } catch {
                Write-Log "Error uninstalling Sysmon from $sysmonPath : $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }

    # ================================
    # STEP 3: UNINSTALL MSI PACKAGE
    # ================================
    Write-Host ""
    Write-Host "[3/8] Uninstalling CyberSentinel MSI package..." -ForegroundColor Cyan
    Write-Log "[3/8] Uninstalling MSI package"
    
    # Find installed product
    $productName = "CyberSentinel Agent"
    $products = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*CyberSentinel*" -or $_.Name -like "*Wazuh*" -or $_.Name -like "*OSSEC*" }
    
    if ($products) {
        foreach ($product in $products) {
            try {
                Write-Log "Found product: $($product.Name) (Version: $($product.Version))"
                Write-Log "Uninstalling: $($product.Name)"
                
                $msiLogPath = "$env:TEMP\cybersentinel-msi-uninstall.log"
                $uninstallResult = $product.Uninstall()
                
                if ($uninstallResult.ReturnValue -eq 0) {
                    Write-Log "Successfully uninstalled: $($product.Name)" -Level "SUCCESS"
                } else {
                    Write-Log "Uninstall returned code: $($uninstallResult.ReturnValue)" -Level "WARNING"
                }
                
                Start-Sleep -Seconds 3
            } catch {
                Write-Log "Error uninstalling MSI: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    } else {
        Write-Log "No MSI package found" -Level "WARNING"
        
        # Try alternative method using registry
        Write-Log "Attempting registry-based uninstall"
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($key in $uninstallKeys) {
            Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -like "*CyberSentinel*" -or 
                $_.DisplayName -like "*Wazuh*" -or 
                $_.DisplayName -like "*OSSEC*" 
            } | ForEach-Object {
                try {
                    Write-Log "Found in registry: $($_.DisplayName)"
                    if ($_.UninstallString) {
                        $uninstallCmd = $_.UninstallString -replace "msiexec.exe", "" -replace "/I", "/X"
                        Write-Log "Executing: msiexec.exe $uninstallCmd /qn /norestart"
                        Start-Process "msiexec.exe" -ArgumentList "$uninstallCmd /qn /norestart" -Wait
                        Write-Log "Uninstalled via registry method" -Level "SUCCESS"
                    }
                } catch {
                    Write-Log "Registry uninstall failed: $($_.Exception.Message)" -Level "ERROR"
                }
            }
        }
    }

    # ================================
    # STEP 4: REMOVE INSTALLATION DIRECTORY
    # ================================
    Write-Host ""
    Write-Host "[4/8] Removing installation directories..." -ForegroundColor Cyan
    Write-Log "[4/8] Removing installation directories"
    
    $installDirs = @(
        "C:\Program Files (x86)\ossec-agent",
        "C:\Program Files\ossec-agent",
        "C:\ossec-agent"
    )
    
    foreach ($dir in $installDirs) {
        Remove-ItemSafely -Path $dir -Description "Installation directory: $dir" -Recurse
    }

    # ================================
    # STEP 5: REMOVE SYSMON FILES
    # ================================
    Write-Host ""
    Write-Host "[5/8] Removing Sysmon files..." -ForegroundColor Cyan
    Write-Log "[5/8] Removing Sysmon files"
    
    $sysmonFiles = @(
        "C:\Windows\Sysmon64.exe",
        "C:\Windows\Sysmon.exe",
        "C:\Windows\SysmonDrv.sys"
    )
    
    foreach ($file in $sysmonFiles) {
        Remove-ItemSafely -Path $file -Description "Sysmon file: $file"
    }

    # ================================
    # STEP 6: REMOVE REGISTRY ENTRIES
    # ================================
    Write-Host ""
    Write-Host "[6/8] Cleaning registry entries..." -ForegroundColor Cyan
    Write-Log "[6/8] Cleaning registry entries"
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\CyberSentinel",
        "HKLM:\SOFTWARE\Wazuh",
        "HKLM:\SOFTWARE\OSSEC",
        "HKLM:\SYSTEM\CurrentControlSet\Services\CyberSentinelSvc",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Sysmon",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Sysmon64",
        "HKLM:\SYSTEM\CurrentControlSet\Services\SysmonDrv"
    )
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $regPath" -Level "SUCCESS"
            } catch {
                Write-Log "Failed to remove registry key: $regPath - $($_.Exception.Message)" -Level "ERROR"
            }
        } else {
            Write-Log "Registry key not found: $regPath" -Level "WARNING"
        }
    }

    # ================================
    # STEP 7: REMOVE FIREWALL RULES
    # ================================
    Write-Host ""
    Write-Host "[7/8] Removing firewall rules..." -ForegroundColor Cyan
    Write-Log "[7/8] Removing firewall rules"
    
    $firewallRules = @("CyberSentinel*", "Wazuh*", "OSSEC*")
    
    foreach ($ruleName in $firewallRules) {
        try {
            $rules = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if ($rules) {
                foreach ($rule in $rules) {
                    Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                    Write-Log "Removed firewall rule: $($rule.DisplayName)" -Level "SUCCESS"
                }
            } else {
                Write-Log "No firewall rules found matching: $ruleName" -Level "WARNING"
            }
        } catch {
            Write-Log "Error removing firewall rules: $($_.Exception.Message)" -Level "ERROR"
        }
    }

    # ================================
    # STEP 8: REMOVE CERTIFICATES
    # ================================
    Write-Host ""
    Write-Host "[8/8] Removing certificates..." -ForegroundColor Cyan
    Write-Log "[8/8] Removing certificates"
    
    try {
        $certs = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { 
            $_.Subject -like "*CyberSentinel*" -or 
            $_.Subject -like "*Wazuh*" -or 
            $_.Issuer -like "*CyberSentinel*" -or 
            $_.Issuer -like "*Wazuh*"
        }
        
        if ($certs) {
            foreach ($cert in $certs) {
                try {
                    Remove-Item -Path "Cert:\LocalMachine\Root\$($cert.Thumbprint)" -Force
                    Write-Log "Removed certificate: $($cert.Subject) (Thumbprint: $($cert.Thumbprint))" -Level "SUCCESS"
                } catch {
                    Write-Log "Failed to remove certificate: $($cert.Subject) - $($_.Exception.Message)" -Level "ERROR"
                }
            }
        } else {
            Write-Log "No CyberSentinel certificates found" -Level "WARNING"
        }
    } catch {
        Write-Log "Error scanning certificates: $($_.Exception.Message)" -Level "ERROR"
    }

    # ================================
    # CLEANUP TEMPORARY FILES
    # ================================
    Write-Host ""
    Write-Log "Cleaning up temporary installation files"
    
    $tempFiles = @(
        "$env:TEMP\ca.cer",
        "$env:TEMP\cybersentinel-agent.msi",
        "$env:TEMP\cybersentinel-msi-*.log"
    )
    
    foreach ($tempFile in $tempFiles) {
        if ($tempFile -like "*`**") {
            # Handle wildcards
            Get-ChildItem -Path $tempFile -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ItemSafely -Path $_.FullName -Description "Temp file: $($_.Name)"
            }
        } else {
            Remove-ItemSafely -Path $tempFile -Description "Temp file: $tempFile"
        }
    }

    # ================================
    # FINAL VERIFICATION
    # ================================
    Write-Host ""
    Write-Host "Verification:" -ForegroundColor Cyan
    Write-Log "Performing final verification"
    
    $installDir = "C:\Program Files (x86)\ossec-agent"
    $serviceExists = Get-Service -Name "CyberSentinelSvc" -ErrorAction SilentlyContinue
    
    $fullyRemoved = $true
    
    if (Test-Path $installDir) {
        Write-Log "WARNING: Installation directory still exists: $installDir" -Level "WARNING"
        $fullyRemoved = $false
    }
    
    if ($serviceExists) {
        Write-Log "WARNING: Service still exists: CyberSentinelSvc" -Level "WARNING"
        $fullyRemoved = $false
    }
    
    # ================================
    # SUCCESS MESSAGE
    # ================================
    Write-Log "Uninstallation completed"
    
    Clear-Host
    
    Write-Host ""
    if ($fullyRemoved) {
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
        Write-Host "  █                                          █" -ForegroundColor Green
        Write-Host "  █     ✓ UNINSTALLATION COMPLETE            █" -ForegroundColor Green
        Write-Host "  █                                          █" -ForegroundColor Green
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Green
        Write-Host ""
        Write-Host ""
        Write-Host "  CyberSentinel Agent has been completely removed." -ForegroundColor White
    } else {
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Yellow
        Write-Host "  █                                          █" -ForegroundColor Yellow
        Write-Host "  █     ⚠ UNINSTALLATION COMPLETE            █" -ForegroundColor Yellow
        Write-Host "  █         (with warnings)                  █" -ForegroundColor Yellow
        Write-Host "  █                                          █" -ForegroundColor Yellow
        Write-Host "  ████████████████████████████████████████████" -ForegroundColor Yellow
        Write-Host ""
        Write-Host ""
        Write-Host "  Some components may remain. Please check the log file." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "  Log file: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  NOTE: A system reboot is recommended to ensure" -ForegroundColor Yellow
    Write-Host "        all components are fully removed." -ForegroundColor Yellow
    Write-Host ""
    
    $reboot = Read-Host "Would you like to reboot now? (Y/N)"
    if ($reboot -eq 'Y' -or $reboot -eq 'y') {
        Write-Host ""
        Write-Host "System will reboot in 10 seconds..." -ForegroundColor Yellow
        Write-Log "User initiated system reboot" -Level "SUCCESS"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    
}
catch {
    Write-Host ""
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  █     ✗ UNINSTALLATION ERROR               █" -ForegroundColor Red
    Write-Host "  █                                          █" -ForegroundColor Red
    Write-Host "  ████████████████████████████████████████████" -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Log "UNINSTALLATION ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
}

Write-Host ""
Read-Host "Press Enter to exit"
