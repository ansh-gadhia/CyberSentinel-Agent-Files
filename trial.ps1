# ================================
# CyberSentinel Agent Installation Script
# ================================

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$logFile = "$env:TEMP\cybersentinel-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ================================
# HELPER: LOGGING
# ================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ================================
# HELPER: SECURE INPUT (masked)
# ================================
function Read-SecureInput {
    param([string]$Prompt)
    Write-Host $Prompt -NoNewline -ForegroundColor Yellow
    $input = ""
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { Write-Host ""; break }
        elseif ($key.VirtualKeyCode -eq 8) {
            if ($input.Length -gt 0) {
                $input = $input.Substring(0, $input.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        } elseif ($key.Character -match '[^\x00-\x1F\x7F]') {
            $input += $key.Character
            Write-Host "*" -NoNewline -ForegroundColor Gray
        }
    }
    return ($input -replace '[\x00-\x1F\x7F]', '')
}

# ================================
# HELPER: SPINNER
#
# Runs while a background job is active.
# Frames produce a smooth left-to-right wave sweep effect.
# ================================
function Show-Spinner {
    param(
        [System.Management.Automation.Job]$Job,
        [string]$Label,
        [ConsoleColor]$Color = "Cyan"
    )

    $frames = @(
        " >--      ",
        "  >--     ",
        "   >--    ",
        "    >--   ",
        "     >--  ",
        "      >-- ",
        "       >--",
        "      --< ",
        "     --<  ",
        "    --<   ",
        "   --<    ",
        "  --<     ",
        " --<      ",
        "--<       "
    )

    $i = 0
    $cursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        while ($Job.State -eq "Running") {
            $frame = $frames[$i % $frames.Count]
            Write-Host "`r  [ $frame ]  $Label" -NoNewline -ForegroundColor $Color
            Start-Sleep -Milliseconds 80
            $i++
        }
    } finally {
        [Console]::CursorVisible = $cursorVisible
        Write-Host ("`r" + (" " * ($Label.Length + 25)) + "`r") -NoNewline
    }

    if ($Job.State -eq "Failed") {
        throw "Task failed: $($Job.ChildJobs[0].JobStateInfo.Reason.Message)"
    }
}

# ================================
# HELPER: STEP HEADER
# ================================
function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host ("  " + ([string][char]0x2500 * 47)) -ForegroundColor DarkGray
    Write-Host ""
}

# ================================
# HELPER: CHECK EXISTING INSTALL
# ================================
function Test-ExistingInstallation {
    $found = @()
    foreach ($svc in @("CyberSentinelSvc","CyberSentinel","WazuhSvc")) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) { $found += "Service: $svc" }
    }
    if (Test-Path "C:\Program Files (x86)\ossec-agent") { $found += "Directory: ossec-agent" }
    return $found
}

# ================================
# HELPER: FULL REMOVAL
# ================================
function Remove-ExistingInstallation {
    param([string]$LogFile)

    Write-Host ""

    foreach ($svc in @("CyberSentinelSvc","CyberSentinel","WazuhSvc")) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            $s = $svc
            $job = Start-Job -ScriptBlock {
                param($svcName)
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                sc.exe delete $svcName | Out-Null
            } -ArgumentList $s
            Show-Spinner -Job $job -Label "Stopping service: $svc" -Color Yellow
            Receive-Job $job -Wait | Out-Null
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) [INFO] Removed service: $svc" | Out-File $LogFile -Append
            Write-Host "  ✓ Removed service: $svc" -ForegroundColor Green
        }
    }

    $job = Start-Job -ScriptBlock {
        $products = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*Wazuh*" -or $_.Name -like "*CyberSentinel*" }
        foreach ($p in $products) { $p.Uninstall() | Out-Null }
    }
    Show-Spinner -Job $job -Label "Uninstalling existing MSI package..." -Color Yellow
    Receive-Job $job -Wait | Out-Null
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ MSI package uninstalled" -ForegroundColor Green

    $agentPath = "C:\Program Files (x86)\ossec-agent"
    if (Test-Path $agentPath) {
        Remove-Item $agentPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed agent directory" -ForegroundColor Green
        "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) [INFO] Removed agent directory" | Out-File $LogFile -Append
    }

    foreach ($item in @(
        "$env:TEMP\wazuh-agent.msi", "$env:TEMP\cybersentinel-agent.msi",
        "$env:TEMP\ca.cer", "$env:TEMP\nssm.zip", "$env:TEMP\nssm", "$env:TEMP\nssm.exe"
    )) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Write-Host ""
    Write-Host "  ✓ Existing installation fully removed." -ForegroundColor Green
    "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) [SUCCESS] Removal complete" | Out-File $LogFile -Append
}

# ================================================================
# MAIN
# ================================================================
try {

    # Admin check
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Host "ERROR: Run this script as Administrator." -ForegroundColor Red
        Read-Host "Press Enter to exit"; exit 1
    }

    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║    CyberSentinel Agent  ·  Installation     ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Installation script started"

    # ─────────────────────────────────────────
    # STEP 1 · GitHub Token + Validation
    # ─────────────────────────────────────────
    Write-Step "Step 1 of 4  ·  GitHub Token Validation"

    $GitHubToken = Read-SecureInput "  Enter GitHub Personal Access Token: "

    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        Write-Host ""
        Write-Host "  ✗ Token cannot be empty." -ForegroundColor Red
        Write-Host "    Generate at: https://github.com/settings/tokens  (scope: repo)" -ForegroundColor DarkGray
        Write-Log "No token provided" -Level "ERROR"
        Read-Host "Press Enter to exit"; exit 1
    }

    $privateRepoOwner = "cybersentinel-06"
    $privateRepoName  = "CyberSentinel-SIEM"
    $headers = @{
        Authorization = "Bearer $GitHubToken"
        "User-Agent"  = "CyberSentinel-Agent-Installer"
        Accept        = "application/vnd.github+json"
    }

    Write-Host ""

    foreach ($file in @(
        "AGENTS/WINDOWS-AGENT/ossec.conf",
        "AGENTS/WINDOWS-AGENT/enrich.ps1",
        "AGENTS/WINDOWS-AGENT/sysmon.ps1"
    )) {
        $vUrl = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$file"
        $vHdr = $headers
        $job = Start-Job -ScriptBlock {
            param($u, $h)
            Invoke-WebRequest -Uri $u -Headers $h -Method GET -UseBasicParsing | Out-Null
        } -ArgumentList $vUrl, $vHdr

        Show-Spinner -Job $job -Label "Validating: $file"

        if ($job.State -eq "Failed") {
            Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Host "  ✗ Access denied: $file" -ForegroundColor Red
            Write-Host "    Check token scope ('repo') and expiry." -ForegroundColor DarkGray
            Write-Log "GitHub validation failed: $file" -Level "ERROR"
            Read-Host "Press Enter to exit"; exit 1
        }

        Receive-Job $job -Wait | Out-Null
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ $file" -ForegroundColor Green
        Write-Log "Validated: $file" -Level "SUCCESS"
    }

    Write-Host ""
    Write-Host "  ✓ GitHub access confirmed." -ForegroundColor Green
    Write-Log "GitHub token validated" -Level "SUCCESS"

    # ─────────────────────────────────────────
    # STEP 2 · Existing Installation Check
    # ─────────────────────────────────────────
    Write-Step "Step 2 of 4  ·  Existing Installation Check"

    $found = Test-ExistingInstallation

    if ($found.Count -gt 0) {
        Write-Host "  ⚠  Existing installation detected:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($item in $found) { Write-Host "     • $item" -ForegroundColor White }
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor DarkGray
        Write-Host "  │  [1]  Remove existing + do a fresh install   │" -ForegroundColor White
        Write-Host "  │  [2]  Exit without making any changes        │" -ForegroundColor White
        Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor DarkGray
        Write-Host ""

        do { $choice = Read-Host "  Your choice (1 or 2)" }
        while ($choice -ne '1' -and $choice -ne '2')

        if ($choice -eq '2') {
            Write-Host ""
            Write-Host "  Exiting. No changes made." -ForegroundColor Yellow
            Write-Log "User exited — no changes made" -Level "WARNING"
            Read-Host "Press Enter to exit"; exit 0
        }

        Write-Log "User chose to remove existing installation"
        Remove-ExistingInstallation -LogFile $logFile
    } else {
        Write-Host "  ✓ No existing installation found." -ForegroundColor Green
        Write-Log "No existing installation detected"
    }

    # ─────────────────────────────────────────
    # STEP 3 · Configuration Input
    # ─────────────────────────────────────────
    Write-Step "Step 3 of 4  ·  Installation Configuration"

    do {
        $managerIP = Read-Host "  Manager IP address"
        if ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
            Write-Host "  ✗ Invalid IP format. Try again." -ForegroundColor Red
        }
    } while ($managerIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$')
    Write-Log "Manager IP: $managerIP"

    do {
        $agentName = Read-Host "  Agent name (e.g. Workstation-01)"
        if ([string]::IsNullOrWhiteSpace($agentName)) {
            Write-Host "  ✗ Name cannot be empty. Try again." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($agentName))
    Write-Log "Agent Name: $agentName"

    $ipPad   = $managerIP.PadRight(29)
    $namePad = $agentName.PadRight(29)
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Manager IP  :  $ipPad│" -ForegroundColor White
    Write-Host "  │  Agent Name  :  $namePad│" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Read-Host "  Proceed with installation? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "  Installation cancelled." -ForegroundColor Yellow
        Write-Log "Cancelled by user" -Level "WARNING"; exit 0
    }

    # ─────────────────────────────────────────
    # STEP 4 · Installation
    # ─────────────────────────────────────────
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║    CyberSentinel Agent  ·  Installing...    ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 4.1 · CA Certificate
    Write-Log "[1/7] CA certificate"
    $lf = $logFile
    $job = Start-Job -ScriptBlock {
        param($lf)
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer" `
            -OutFile "$env:TEMP\ca.cer" -UseBasicParsing 2>&1 | Out-File $lf -Append
        Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root 2>&1 | Out-File $lf -Append
    } -ArgumentList $lf
    Show-Spinner -Job $job -Label "Downloading & importing CA certificate..."
    Receive-Job $job -Wait -ErrorAction Stop | Out-Null; Remove-Job $job -Force
    Write-Host "  ✓ CA certificate imported" -ForegroundColor Green
    Write-Log "CA certificate imported" -Level "SUCCESS"

    # 4.2 · Download MSI
    Write-Log "[2/7] Download MSI"
    $job = Start-Job -ScriptBlock {
        param($lf)
        Invoke-WebRequest -Uri "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi" `
            -OutFile "$env:TEMP\cybersentinel-agent.msi" -UseBasicParsing 2>&1 | Out-File $lf -Append
    } -ArgumentList $lf
    Show-Spinner -Job $job -Label "Downloading agent package..."
    Receive-Job $job -Wait -ErrorAction Stop | Out-Null; Remove-Job $job -Force
    Write-Host "  ✓ Package downloaded" -ForegroundColor Green
    Write-Log "MSI downloaded" -Level "SUCCESS"

    # 4.3 · Install MSI
    Write-Log "[3/7] Install MSI"
    $msiLog = "$env:TEMP\cybersentinel-msi-install.log"
    $mIP    = $managerIP
    $mName  = $agentName
    $job = Start-Job -ScriptBlock {
        param($ip, $name, $msiLog)
        $args = @(
            "/i", "`"$env:TEMP\cybersentinel-agent.msi`"",
            "/qn", "/norestart",
            "WAZUH_MANAGER=`"$ip`"",
            "WAZUH_AGENT_NAME=`"$name`"",
            "/L*v", "`"$msiLog`""
        )
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru
        return $p.ExitCode
    } -ArgumentList $mIP, $mName, $msiLog
    Show-Spinner -Job $job -Label "Installing agent (this may take a minute)..."
    $exitCode = Receive-Job $job -Wait -ErrorAction Stop; Remove-Job $job -Force
    if ($exitCode -ne 0) { throw "MSI installation failed (exit code $exitCode). Log: $msiLog" }
    Write-Host "  ✓ Agent installed" -ForegroundColor Green
    Write-Log "MSI installed" -Level "SUCCESS"
    Start-Sleep -Seconds 2

    $ossecDir = "C:\Program Files (x86)\ossec-agent"
    if (-not (Test-Path $ossecDir)) { throw "Installation directory not found: $ossecDir" }

    # 4.4 · .env file
    $envFilePath = Join-Path $ossecDir ".env"
    @("ManagerIP=$managerIP","AgentName=$agentName") | Set-Content $envFilePath -Encoding UTF8
    Write-Host "  ✓ Environment file created" -ForegroundColor Green
    Write-Log ".env created" -Level "SUCCESS"

    # 4.5 · Download config files from private repo
    Write-Log "[5/7] Config files"
    $ossecConfPath    = Join-Path $ossecDir "ossec.conf"
    $enrichScriptPath = Join-Path $ossecDir "enrich.ps1"
    $sysmonScriptPath = Join-Path $ossecDir "sysmon.ps1"
    Stop-Service -Name "CyberSentinelSvc" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $owner = $privateRepoOwner
    $repo  = $privateRepoName
    $hdrs  = $headers

    $downloads = @(
        @{ rp = "AGENTS/WINDOWS-AGENT/ossec.conf";  dst = $ossecConfPath    },
        @{ rp = "AGENTS/WINDOWS-AGENT/enrich.ps1";  dst = $enrichScriptPath },
        @{ rp = "AGENTS/WINDOWS-AGENT/sysmon.ps1";  dst = $sysmonScriptPath }
    )

    foreach ($dl in $downloads) {
        $rp  = $dl.rp
        $dst = $dl.dst
        $job = Start-Job -ScriptBlock {
            param($owner, $repo, $rp, $dst, $hdrs)
            $url      = "https://api.github.com/repos/$owner/$repo/contents/$rp"
            $response = Invoke-RestMethod -Uri $url -Headers $hdrs -Method GET
            $content  = [System.Text.Encoding]::UTF8.GetString(
                            [System.Convert]::FromBase64String($response.content))
            Set-Content -Path $dst -Value $content -Encoding UTF8
        } -ArgumentList $owner, $repo, $rp, $dst, $hdrs
        Show-Spinner -Job $job -Label "Fetching $rp..."
        Receive-Job $job -Wait -ErrorAction Stop | Out-Null; Remove-Job $job -Force
        Write-Host "  ✓ $rp" -ForegroundColor Green
        Write-Log "Downloaded: $rp" -Level "SUCCESS"
    }

    # 4.6 · Run scripts
    Write-Log "[6/7] Running config scripts"
    foreach ($scriptPath in @($enrichScriptPath, $sysmonScriptPath)) {
        $sName = Split-Path $scriptPath -Leaf
        $sp    = $scriptPath
        $job = Start-Job -ScriptBlock {
            param($s, $lf)
            & powershell.exe -ExecutionPolicy Bypass -File $s 2>&1 | Out-File $lf -Append
        } -ArgumentList $sp, $lf
        Show-Spinner -Job $job -Label "Running $sName..."
        try { Receive-Job $job -Wait -ErrorAction Stop | Out-Null } catch { Write-Log "Warning: $sName - $_" -Level "WARNING" }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ $sName completed" -ForegroundColor Green
        Write-Log "$sName completed" -Level "SUCCESS"
    }

    # 4.6.5 · Active response executables
    Write-Log "[6.5/7] Active response executables"
    $arBinPath = Join-Path $ossecDir "active-response\bin"
    if (-not (Test-Path $arBinPath)) { New-Item -Path $arBinPath -ItemType Directory -Force | Out-Null }

    foreach ($exeName in @("remove-malware.exe","remove-threat.exe")) {
        $eUrl  = "https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/$exeName"
        $ePath = Join-Path $arBinPath $exeName
        $job = Start-Job -ScriptBlock {
            param($u, $p, $lf)
            Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing 2>&1 | Out-File $lf -Append
        } -ArgumentList $eUrl, $ePath, $lf
        Show-Spinner -Job $job -Label "Downloading $exeName..."
        Receive-Job $job -Wait -ErrorAction Stop | Out-Null; Remove-Job $job -Force
        if (-not (Test-Path $ePath)) { throw "Download failed: $exeName" }
        Write-Host "  ✓ $exeName" -ForegroundColor Green
        Write-Log "Downloaded: $exeName" -Level "SUCCESS"
    }

    # 4.7 · Start service
    Write-Log "[7/7] Starting service"
    $job = Start-Job -ScriptBlock {
        param($lf)
        try {
            Start-Service -Name "CyberSentinelSvc" -ErrorAction Stop
            Start-Sleep -Seconds 5
        } catch {
            NET START CyberSentinelSvc 2>&1 | Out-File $lf -Append
            Start-Sleep -Seconds 5
        }
    } -ArgumentList $lf
    Show-Spinner -Job $job -Label "Starting CyberSentinel service..."
    Receive-Job $job -Wait | Out-Null; Remove-Job $job -Force -ErrorAction SilentlyContinue

    $svc = Get-Service -Name "CyberSentinelSvc" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  ✓ Service running" -ForegroundColor Green
        Write-Log "Service running" -Level "SUCCESS"
    } else {
        Write-Host "  ⚠  Service status unclear — check log." -ForegroundColor Yellow
        Write-Log "WARNING: Service status unclear after start" -Level "WARNING"
    }

    # Detect group
    $ossecContent  = Get-Content $ossecConfPath -Raw -ErrorAction SilentlyContinue
    $detectedGroup = "default"
    if ($ossecContent -match '<groups>([^<]+)</groups>') { $detectedGroup = $matches[1].Trim() }

    # Temp cleanup
    Remove-Item "$env:TEMP\ca.cer"                   -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\cybersentinel-agent.msi"   -Force -ErrorAction SilentlyContinue
    Write-Log "Installation completed successfully" -Level "SUCCESS"

    # ─────────────────────────────────────────
    # SUCCESS SCREEN
    # ─────────────────────────────────────────
    Clear-Host
    $ipPad    = $managerIP.PadRight(29)
    $namePad  = $agentName.PadRight(29)
    $grpPad   = $detectedGroup.PadRight(29)
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                              ║" -ForegroundColor Green
    Write-Host "  ║     ✓   INSTALLATION SUCCESSFUL             ║" -ForegroundColor Green
    Write-Host "  ║                                              ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Manager IP  :  $ipPad│" -ForegroundColor White
    Write-Host "  │  Agent Name  :  $namePad│" -ForegroundColor White
    Write-Host "  │  Group       :  $grpPad│" -ForegroundColor White
    Write-Host "  │  Service     :  Running                      │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Log  :  $logFile" -ForegroundColor DarkGray
    Write-Host ""
}
catch {
    [Console]::CursorVisible = $true
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║                                              ║" -ForegroundColor Red
    Write-Host "  ║     ✗   INSTALLATION FAILED                 ║" -ForegroundColor Red
    Write-Host "  ║                                              ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error  :  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Log    :  $logFile"                 -ForegroundColor DarkGray
    Write-Host ""
    Write-Log "FAILED: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack: $($_.ScriptStackTrace)"   -Level "ERROR"
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
