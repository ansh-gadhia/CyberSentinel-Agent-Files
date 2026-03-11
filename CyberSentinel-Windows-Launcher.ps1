# ================================================================
# CyberSentinel — Windows Public Launcher
# ================================================================
# This is the ONLY script that lives on the public repo.
# It validates the GitHub token, then fetches the private
# installer script into a string in memory and executes it
# via Invoke-Expression — the script is NEVER written to disk.
# ================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ================================================================
# Helpers
# ================================================================
function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host ("  " + ([string][char]0x2500 * 47)) -ForegroundColor DarkGray
    Write-Host ""
}

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

function Show-Spinner {
    param(
        [System.Management.Automation.Job]$Job,
        [string]$Label,
        [ConsoleColor]$Color = "Cyan"
    )
    $frames = @(
        " >--      ","  >--     ","   >--    ","    >--   ",
        "     >--  ","      >-- ","       >--","      --< ",
        "     --<  ","    --<   ","   --<    ","  --<     ",
        " --<      ","--<       "
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

# ================================================================
# Cleanup — guaranteed on success, failure, or Ctrl+C
# ================================================================
$script:RawToken = $null

try {

    # Admin check
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Host "ERROR: Run this script as Administrator." -ForegroundColor Red
        Read-Host "Press Enter to exit"; exit 1
    }

    $privateRepoOwner  = "cybersentinel-06"
    $privateRepoName   = "CyberSentinel-SIEM"
    $privateScriptPath = "AGENTS/INSTALLATION-SCRIPTS/CyberSentinel-Windows-Install.ps1"

    # ────────────────────────────────────────────────────────────
    # Banner — printed here so the main script doesn't repeat it
    # ────────────────────────────────────────────────────────────
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║    CyberSentinel Agent  ·  Installation      ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # ────────────────────────────────────────────────────────────
    # GitHub Token — collect, validate, 3 attempts
    # ────────────────────────────────────────────────────────────
    Write-Step "GitHub Token"

    $MAX_ATTEMPTS = 3
    $attempt      = 0
    $validated    = $false

    while ($attempt -lt $MAX_ATTEMPTS -and -not $validated) {
        $attempt++

        $script:RawToken = Read-SecureInput "  Enter GitHub Personal Access Token: "

        if ([string]::IsNullOrWhiteSpace($script:RawToken)) {
            Write-Host ""
            Write-Host "  ✗ Token cannot be empty (attempt $attempt/$MAX_ATTEMPTS)." -ForegroundColor Red
            Write-Host "    Generate at: https://github.com/settings/tokens  (scope: repo)" -ForegroundColor DarkGray
            if ($attempt -eq $MAX_ATTEMPTS) { Read-Host "Press Enter to exit"; exit 1 }
            continue
        }

        # Masked confirmation
        $t = $script:RawToken
        $masked = if ($t.Length -gt 8) {
            $t.Substring(0,4) + ("*" * ($t.Length - 8)) + $t.Substring($t.Length - 4)
        } else { "****" }
        Write-Host ""

        # Validate by checking the 3 private files directly — same approach as the original script
        $vOwner = $privateRepoOwner
        $vRepo  = $privateRepoName
        $vToken = $script:RawToken

        $hdrsForValidation = @{
            Authorization = "Bearer $vToken"
            "User-Agent"  = "CyberSentinel-Agent-Installer"
            Accept        = "application/vnd.github+json"
        }

        $vHdrs = $hdrsForValidation
        $job = Start-Job -ScriptBlock {
            param($owner, $repo, $hdrs)
            $files = @(
                "AGENTS/WINDOWS-AGENT/ossec.conf",
                "AGENTS/WINDOWS-AGENT/enrich.ps1",
                "AGENTS/WINDOWS-AGENT/sysmon.ps1"
            )
            foreach ($f in $files) {
                $url = "https://api.github.com/repos/$owner/$repo/contents/$f"
                Invoke-WebRequest -Uri $url -Headers $hdrs -Method GET -UseBasicParsing | Out-Null
            }
        } -ArgumentList $vOwner, $vRepo, $vHdrs
        Remove-Variable vToken, vHdrs, hdrsForValidation

        Show-Spinner -Job $job -Label "Validating GitHub access..."

        if ($job.State -eq "Failed") {
            Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Host "  ✗ GitHub access failed (attempt $attempt/$MAX_ATTEMPTS)." -ForegroundColor Red
            Write-Host "    Check token scope ('repo') and expiry." -ForegroundColor DarkGray
            if ($attempt -eq $MAX_ATTEMPTS) { Read-Host "Press Enter to exit"; exit 1 }
            Write-Host "  Please try again." -ForegroundColor Yellow
        } else {
            Receive-Job $job -Wait | Out-Null
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Host "  ✓ GitHub access confirmed." -ForegroundColor Green
            $validated = $true
        }
    }

    # ────────────────────────────────────────────────────────────
    # Fetch private installer into memory + execute
    #
    # The script is downloaded via GitHub API (returns base64),
    # decoded into a string in RAM, and run with Invoke-Expression.
    # It is NEVER written to disk.
    #
    # CS_TOKEN_PREVALIDATED and CS_GITHUB_TOKEN are set as env vars
    # so the main script skips its own banner + token step entirely,
    # producing one seamless unbroken flow for the user.
    # ────────────────────────────────────────────────────────────
    $fetchUrl   = "https://api.github.com/repos/$privateRepoOwner/$privateRepoName/contents/$privateScriptPath"
    $fetchToken = $script:RawToken
    $fetchHdrs  = @{
        Authorization = "Bearer $fetchToken"
        "User-Agent"  = "CyberSentinel-Agent-Installer"
        Accept        = "application/vnd.github+json"
    }

    $job = Start-Job -ScriptBlock {
        param($url, $hdrs)
        $response = Invoke-RestMethod -Uri $url -Headers $hdrs -Method GET -ErrorAction Stop
        return [System.Text.Encoding]::UTF8.GetString(
                   [System.Convert]::FromBase64String($response.content))
    } -ArgumentList $fetchUrl, $fetchHdrs
    Remove-Variable fetchToken, fetchHdrs

    Show-Spinner -Job $job -Label "Loading installer..."

    $installerScript = Receive-Job $job -Wait -ErrorAction Stop
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    # Pass token + flag to main script via env vars.
    # Main script reads these, wipes them immediately, and skips
    # its own banner + token step — user sees one continuous flow.
    $env:CS_TOKEN_PREVALIDATED = "1"
    $env:CS_GITHUB_TOKEN       = $script:RawToken

    # Wipe our local copy now — env var is the only reference left
    $script:RawToken = $null
    [System.GC]::Collect()

    # Run installer from memory — no file on disk at any point
    Invoke-Expression $installerScript

} finally {
    # Guaranteed wipe on any exit path including Ctrl+C
    $script:RawToken           = $null
    $env:CS_TOKEN_PREVALIDATED = $null
    $env:CS_GITHUB_TOKEN       = $null
    [System.GC]::Collect()
}
