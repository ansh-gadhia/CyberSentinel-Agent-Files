# Python Removal Script for Windows - Enhanced Version
# Run as Administrator

# Check for admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run as Administrator!"
    Read-Host "Press Enter to exit"
    Exit
}

Write-Host "=== Python Removal Tool (Enhanced) ===" -ForegroundColor Cyan
Write-Host ""

# Stop any Python processes first
Write-Host "[0/7] Stopping Python processes..." -ForegroundColor Yellow
$pythonProcesses = Get-Process | Where-Object { $_.ProcessName -like "*python*" }
if ($pythonProcesses) {
    foreach ($proc in $pythonProcesses) {
        Write-Host "  Stopping: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
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

# Method 1: Manual MSI uninstall with repair attempt
Write-Host "`n[1/7] Attempting MSI uninstall..." -ForegroundColor Yellow

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
        $guid = $install.PSChildName
        
        if ($uninstallString) {
            Write-Host "  Found: $name" -ForegroundColor Gray
            
            # Try multiple uninstall methods
            $uninstalled = $false
            
            # Method 1: Use the uninstall string directly
            if ($uninstallString -match "msiexec") {
                Write-Host "  Trying standard MSI uninstall..." -ForegroundColor Yellow
                $extractedGuid = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
                $result = Start-Process "msiexec.exe" -ArgumentList "/x $extractedGuid /qn /norestart" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Host "  Success" -ForegroundColor Green
                    $uninstalled = $true
                }
            }
            
            # Method 2: Try with /quiet instead of /qn
            if (-not $uninstalled -and $uninstallString -match "msiexec") {
                Write-Host "  Trying alternate MSI method..." -ForegroundColor Yellow
                $extractedGuid = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
                $result = Start-Process "msiexec.exe" -ArgumentList "/x $extractedGuid /quiet /norestart" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Host "  Success" -ForegroundColor Green
                    $uninstalled = $true
                }
            }
            
            # Method 3: Try running the uninstaller directly
            if (-not $uninstalled -and $uninstallString -match '"(.+?)"') {
                Write-Host "  Trying direct uninstaller..." -ForegroundColor Yellow
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
Write-Host "`n[2/7] Checking for Microsoft Store Python..." -ForegroundColor Yellow
$storeApps = Get-AppxPackage | Where-Object { $_.Name -like "*Python*" }
if ($storeApps) {
    foreach ($app in $storeApps) {
        Write-Host "  Removing: $($app.Name)" -ForegroundColor Yellow
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

# Method 3: Force remove directories (even if uninstall failed)
Write-Host "`n[3/7] Force removing Python directories..." -ForegroundColor Yellow

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
            Write-Host "  Removing: $($dir.FullName)" -ForegroundColor Yellow
            
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
Write-Host "`n[4/7] Cleaning PATH variables..." -ForegroundColor Yellow
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
Write-Host "`n[5/7] Cleaning pip cache..." -ForegroundColor Yellow
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

# Method 6: Clean registry (including install keys)
Write-Host "`n[6/7] Cleaning registry..." -ForegroundColor Yellow
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

# Method 7: Remove .py file associations
Write-Host "`n[7/7] Cleaning file associations..." -ForegroundColor Yellow
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

Write-Host "`n=== Removal Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "- Python processes stopped" -ForegroundColor Gray
Write-Host "- Installers removed (or attempted)" -ForegroundColor Gray
Write-Host "- Directories cleaned" -ForegroundColor Gray
Write-Host "- PATH variables cleaned" -ForegroundColor Gray
Write-Host "- Registry entries removed" -ForegroundColor Gray
Write-Host ""
Write-Host "IMPORTANT: Please restart your computer now!" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"
