<#
.SYNOPSIS
    Removes all Python installations from Windows
.DESCRIPTION
    This script uninstalls Python from Windows by:
    - Finding all Python installations via Windows Installer
    - Uninstalling via official uninstallers
    - Removing Python from PATH
    - Cleaning up residual files and registry entries
.NOTES
    Run as Administrator for complete removal
#>

# Require Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    Exit
}

Write-Host "Starting Python removal process..." -ForegroundColor Cyan

# Function to remove from PATH
function Remove-FromPath {
    param([string]$pathToRemove)
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    if ($userPath -match [regex]::Escape($pathToRemove)) {
        $newUserPath = ($userPath.Split(';') | Where-Object { $_ -notlike "*Python*" }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Host "Removed from User PATH" -ForegroundColor Green
    }
    
    if ($machinePath -match [regex]::Escape($pathToRemove)) {
        $newMachinePath = ($machinePath.Split(';') | Where-Object { $_ -notlike "*Python*" }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
        Write-Host "Removed from System PATH" -ForegroundColor Green
    }
}

# Uninstall Python via Windows Installer
Write-Host "`nSearching for Python installations..." -ForegroundColor Yellow
$pythonApps = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Python*" }

if ($pythonApps) {
    foreach ($app in $pythonApps) {
        Write-Host "Uninstalling: $($app.Name)" -ForegroundColor Yellow
        try {
            $app.Uninstall() | Out-Null
            Write-Host "Successfully uninstalled: $($app.Name)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to uninstall $($app.Name): $_"
        }
    }
}
else {
    Write-Host "No Python installations found via Windows Installer" -ForegroundColor Gray
}

# Remove from PATH
Write-Host "`nCleaning PATH variables..." -ForegroundColor Yellow
Remove-FromPath ""

# Remove common Python directories
$pythonDirs = @(
    "$env:LOCALAPPDATA\Programs\Python",
    "$env:APPDATA\Python",
    "$env:ProgramFiles\Python*",
    "${env:ProgramFiles(x86)}\Python*"
)

Write-Host "`nRemoving Python directories..." -ForegroundColor Yellow
foreach ($dir in $pythonDirs) {
    $matchedDirs = Get-Item $dir -ErrorAction SilentlyContinue
    foreach ($matchedDir in $matchedDirs) {
        if (Test-Path $matchedDir) {
            Write-Host "Removing: $matchedDir" -ForegroundColor Yellow
            try {
                Remove-Item -Path $matchedDir -Recurse -Force -ErrorAction Stop
                Write-Host "Removed: $matchedDir" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to remove $matchedDir : $_"
            }
        }
    }
}

# Remove pip cache
if (Test-Path "$env:LOCALAPPDATA\pip") {
    Write-Host "Removing pip cache..." -ForegroundColor Yellow
    Remove-Item -Path "$env:LOCALAPPDATA\pip" -Recurse -Force -ErrorAction SilentlyContinue
}

# Clean registry entries
Write-Host "`nCleaning registry entries..." -ForegroundColor Yellow
$regPaths = @(
    "HKCU:\Software\Python",
    "HKLM:\Software\Python",
    "HKLM:\Software\WOW6432Node\Python"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        Write-Host "Removing registry key: $regPath" -ForegroundColor Yellow
        try {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $regPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to remove $regPath : $_"
        }
    }
}

Write-Host "`nPython removal process completed!" -ForegroundColor Cyan
Write-Host "Please restart your computer for all changes to take effect." -ForegroundColor Yellow
