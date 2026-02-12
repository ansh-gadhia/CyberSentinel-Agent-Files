# CyberSentinel Complete Installation Guide

## Overview

This document provides comprehensive information about the CyberSentinel Complete Installation Script (Version 3.0), which automates the deployment of both the CyberSentinel Agent and Active Response components on Windows systems.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation Process Overview](#installation-process-overview)
3. [User Input Requirements](#user-input-requirements)
4. [Phase 1: Agent Installation](#phase-1-agent-installation)
5. [Phase 2: Active Response Setup](#phase-2-active-response-setup)
6. [Internal Processes](#internal-processes)
7. [External Dependencies](#external-dependencies)
8. [Logging and Monitoring](#logging-and-monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Post-Installation](#post-installation)

---

## Prerequisites

### System Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **Architecture**: 64-bit (x64)
- **PowerShell**: Version 5.1 or higher
- **Administrator Privileges**: Required for installation
- **Internet Connection**: Required for downloading components
- **Disk Space**: Minimum 2 GB free space

### Required Information

Before running the installation, gather the following information:

1. **CyberSentinel Manager IP Address** (IPv4 format: xxx.xxx.xxx.xxx)
2. **Agent Name** (e.g., Workstation-01, Server-DC01)
3. **GitHub Personal Access Token** (with `repo` scope)

### GitHub Token Generation

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Add a note (e.g., "CyberSentinel Agent Installation")
4. Select scope: **`repo`** (Full control of private repositories)
5. Click "Generate token"
6. **Copy the token immediately** (you won't see it again)

---

## Installation Process Overview

The installation consists of two phases:

```
┌─────────────────────────────────────────────────┐
│         PHASE 1: Agent Installation             │
│  - Validate GitHub Access                       │
│  - Download and Install Agent                   │
│  - Configure Agent                               │
│  - Deploy Configuration Files                   │
│  - Start Service                                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│      PHASE 2: Active Response Setup             │
│  - Check/Install Python Environment             │
│  - Install PyInstaller                           │
│  - Download Source Scripts                      │
│  - Compile Executables                           │
│  - Deploy to Agent Directory                     │
│  - Cleanup Python Installation                  │
└─────────────────────────────────────────────────┘
```

**Total Installation Time**: 10-20 minutes (depending on network speed)

---

## User Input Requirements

### Step 1: Manager IP Address

**Prompt**: `Enter CyberSentinel Manager IP address`

- **Format**: IPv4 address (e.g., 192.168.1.100)
- **Validation**: Script validates IP format automatically
- **Purpose**: Specifies which CyberSentinel manager the agent will connect to

**Example**:
```
Enter CyberSentinel Manager IP address: 192.168.1.100
```

### Step 2: Agent Name

**Prompt**: `Enter CyberSentinel Agent name - example Workstation-01`

- **Format**: Alphanumeric with hyphens (e.g., Workstation-01, Server-DC01)
- **Validation**: Cannot be empty
- **Purpose**: Unique identifier for this agent in the CyberSentinel system

**Example**:
```
Enter CyberSentinel Agent name: Workstation-01
```

### Step 3: GitHub Personal Access Token

**Prompt**: `Enter GitHub Personal Access Token:`

- **Format**: Secure masked input (displays as asterisks)
- **Validation**: Cannot be empty, minimum length required
- **Purpose**: Authenticates access to private repository containing configuration files
- **Security**: Input is masked and not displayed in logs

**Example**:
```
Enter GitHub Personal Access Token: ******************** (masked)
```

### Step 4: Installation Confirmation

**Prompt**: `Proceed with installation? (Y/N)`

Review the configuration summary before proceeding:
```
Configuration Summary:
  Manager IP: 192.168.1.100
  Agent Name: Workstation-01
  GitHub Token: ********************
```

- Type `Y` or `y` to proceed
- Type `N` or `n` to cancel

---

## Phase 1: Agent Installation

### Step-by-Step Process

#### Step 1/7: GitHub Access Validation

**What Happens**:
- Validates GitHub token has access to private repository
- Checks accessibility of required configuration files:
  - `AGENTS/WINDOWS-AGENT/ossec.conf`
  - `AGENTS/WINDOWS-AGENT/enrich.ps1`
  - `AGENTS/WINDOWS-AGENT/sysmon.ps1`

**Internal Process**:
```powershell
# Authenticates using GitHub API
Authorization: Bearer <your-token>
# Tests file access via API calls
GET https://api.github.com/repos/cybersentinel-06/CyberSentinel-SIEM/contents/...
```

**Possible Issues**:
- Invalid token → Script terminates
- Expired token → Script terminates
- Missing repo access → Script terminates

#### Step 2/7: Download and Install Agent

**What Happens**:
- Downloads SSL certificate (ca.cer)
- Imports certificate to Windows certificate store
- Downloads CyberSentinel agent MSI installer
- Installs agent silently with parameters

**Download Sources**:
```
CA Certificate:
https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer

MSI Installer:
https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi
```

**Internal MSI Installation**:
```batch
msiexec.exe /i "cybersentinel-agent.msi" /qn /norestart 
  WAZUH_MANAGER="192.168.1.100" 
  WAZUH_AGENT_NAME="Workstation-01"
```

**Installation Location**: `C:\Program Files (x86)\ossec-agent`

#### Step 3/7: Verify Installation

**What Happens**:
- Checks if installation directory exists
- Validates core agent files are present

**Verification Check**:
```powershell
Test-Path "C:\Program Files (x86)\ossec-agent"
```

#### Step 4/7: Create Environment File

**What Happens**:
- Creates `.env` file in agent directory
- Stores configuration parameters

**File Created**: `C:\Program Files (x86)\ossec-agent\.env`

**Content**:
```
ManagerIP=192.168.1.100
AgentName=Workstation-01
```

#### Step 5/7: Fetch Configuration Files

**What Happens**:
- Stops CyberSentinel service (if running)
- Downloads configuration files from GitHub private repository
- Overwrites default configurations

**Files Downloaded**:
1. `ossec.conf` - Main agent configuration
2. `enrich.ps1` - Log enrichment script
3. `sysmon.ps1` - Sysmon installation/configuration script

**Download Method**:
```powershell
# Fetches from GitHub API
# Decodes Base64 content
# Writes to agent directory
```

#### Step 6/7: Execute Configuration Scripts

**What Happens**:
- Executes `enrich.ps1` to configure log enrichment
- Executes `sysmon.ps1` to install/configure Sysmon

**Internal Process**:
```powershell
powershell.exe -ExecutionPolicy Bypass -File enrich.ps1
powershell.exe -ExecutionPolicy Bypass -File sysmon.ps1
```

**Note**: Script continues even if these scripts encounter warnings

#### Step 7/7: Start Service

**What Happens**:
- Starts the CyberSentinel service
- Waits 5 seconds for service to initialize
- Verifies service is running

**Service Name**: `CyberSentinelSvc`

**Fallback Method**: If standard service start fails, uses `NET START CyberSentinelSvc`

#### Step 7.5/7: Detect Group Configuration

**What Happens**:
- Reads `ossec.conf` to detect configured group
- Extracts group from XML configuration
- Defaults to "default" if no group specified

**Detection Logic**:
```powershell
# Searches for: <groups>groupname</groups>
# Extracts group name from configuration
```

---

## Phase 2: Active Response Setup

### Step-by-Step Process

#### Python Environment Check

**What Happens**:
- Checks for existing Python installation
- Validates Python version (minimum 3.12.1)
- Verifies PyInstaller is installed
- Checks pip functionality

**Decision Tree**:
```
Python Installed?
├─ Yes → Version >= 3.12.1?
│         ├─ Yes → PyInstaller Installed?
│         │        ├─ Yes → Use Existing ✓
│         │        └─ No → Reinstall Python
│         └─ No → Reinstall Python
└─ No → Install Python
```

#### Python Complete Removal (If Needed)

**What Happens**:
- Stops all Python processes
- Uninstalls via Windows Registry
- Removes Microsoft Store Python
- Deletes installation directories
- Cleans PATH variables
- Removes pip cache
- Cleans registry keys
- Removes file associations

**Directories Cleaned**:
```
%LOCALAPPDATA%\Programs\Python*
%LOCALAPPDATA%\Python*
%APPDATA%\Python
C:\Program Files\Python*
C:\Program Files (x86)\Python*
C:\Python*
```

#### Python 3.13.1 Installation

**What Happens**:
- Downloads Python 3.13.1 installer (64-bit)
- Installs silently with specific parameters
- Adds Python to system PATH
- Enables pip installation

**Download Source**:
```
https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe
```

**Installation Parameters**:
```
/quiet
InstallAllUsers=1        # System-wide installation
PrependPath=1            # Add to PATH
Include_pip=1            # Install pip
Include_test=0           # Skip tests
Include_doc=0            # Skip documentation
Include_launcher=1       # Install py launcher
AssociateFiles=1         # Associate .py files
Shortcuts=0              # No shortcuts
```

**Installation Location**: `C:\Program Files\Python313`

#### Package Installation with SSL Error Handling

**What Happens**:
- Upgrades pip with SSL workarounds
- Installs PyInstaller with retry logic

**Installation Strategies** (tried in order):

1. **Standard Installation**:
   ```bash
   python -m pip install pyinstaller --upgrade
   ```

2. **Trusted Host Method** (if SSL fails):
   ```bash
   python -m pip install pyinstaller 
     --trusted-host pypi.org 
     --trusted-host files.pythonhosted.org 
     --trusted-host pypi.python.org
   ```

3. **HTTP Fallback** (last resort):
   ```bash
   python -m pip install pyinstaller 
     --trusted-host pypi.org 
     --index-url http://pypi.python.org/simple/
   ```

**Retry Logic**: Up to 3 attempts per strategy

#### Download Source Scripts

**What Happens**:
- Downloads Python source scripts for active response
- Saves to temporary build directory

**Download Sources**:
```
remove-threat.py:
https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-threat.py

remove-malware.py:
https://raw.githubusercontent.com/effaaykhan/VirusTotal-Integration-with-Wazuh/refs/heads/main/remove-malware.py
```

**Build Directory**: `%TEMP%\CyberSentinel-Build-<timestamp>`

#### Compile Executables (Without Admin Privileges)

**What Happens**:
- Creates temporary PowerShell script for compilation
- Uses Windows Task Scheduler to run PyInstaller without elevation
- Compiles Python scripts to standalone executables
- Monitors compilation progress with timeout

**Internal Process**:
```powershell
# Creates scheduled task
# Runs as current user with limited privileges
# Executes: python -m PyInstaller -F script.py
# Waits for completion (5-minute timeout)
```

**Why Task Scheduler?**:
PyInstaller has issues when run with administrator privileges. Running compilation as a regular user (via scheduled task) resolves these issues.

**Compilation Command**:
```bash
python -m PyInstaller -F <script.py> 
  --distpath <output> 
  --workpath <build> 
  --clean 
  --log-level ERROR
```

**Output Files**:
- `remove-threat.exe`
- `remove-malware.exe`

#### Deploy Executables

**What Happens**:
- Copies compiled executables to agent directory (with admin privileges)
- Creates active-response directory structure if needed

**Deployment Location**:
```
C:\Program Files (x86)\ossec-agent\active-response\bin\
├── remove-threat.exe
└── remove-malware.exe
```

#### Verify Deployment

**What Happens**:
- Checks each executable exists
- Displays file size for verification
- Validates all required files are present

**Verification Output**:
```
[OK] remove-malware.exe - 12.34 KB
[OK] remove-threat.exe - 13.45 KB
```

#### Python Cleanup

**What Happens**:
- Removes Python installation completely
- Cleans all directories and registry entries
- Removes PATH entries
- Frees up disk space

**Why Remove Python?**:
Python is only needed for compilation. Removing it after deployment:
- Reduces attack surface
- Frees disk space (~150 MB)
- Simplifies maintenance

**Note**: Active response executables are standalone and don't require Python

#### Service Restart

**What Happens**:
- Attempts to start CyberSentinel service
- Validates service is running

---

## Internal Processes

### Logging System

**Log Location**: `%TEMP%\cybersentinel-complete-install-<timestamp>.log`

**Log Levels**:
- `INFO` - Standard operations
- `SUCCESS` - Successful completions
- `WARNING` - Non-critical issues
- `ERROR` - Critical failures

**Log Format**:
```
2024-02-12 14:30:45 [INFO] Starting Phase 1: Agent Installation
2024-02-12 14:30:46 [SUCCESS] GitHub access validated successfully
2024-02-12 14:31:20 [ERROR] MSI installation failed with exit code: 1603
```

### Error Handling

**Global Error Handling**:
```powershell
$ErrorActionPreference = "Stop"  # Stops on any error
$ProgressPreference = "SilentlyContinue"  # Suppresses progress bars
```

**Try-Catch Blocks**:
- Each phase wrapped in try-catch
- Detailed error messages logged
- Stack traces captured for debugging

### Security Features

**Secure Input**:
- GitHub token masked during input
- Token never displayed in console
- Token length limited in logs (not full value)

**Certificate Validation**:
- Imports CA certificate before agent installation
- Ensures trusted communication with manager

---

## External Dependencies

### Internet Resources

**GitHub Repositories**:
1. **Private Repository** (requires token):
   - `https://github.com/cybersentinel-06/CyberSentinel-SIEM`
   - Contains: Agent configurations

2. **Public Repositories**:
   - `https://github.com/ansh-gadhia/CyberSentinel-Agent-Files`
     - Contains: CA certificate, MSI installer
   - `https://github.com/effaaykhan/VirusTotal-Integration-with-Wazuh`
     - Contains: Active response scripts

**Python Resources**:
- `https://www.python.org` - Python installer
- `https://pypi.org` - PyPI package repository

### Network Requirements

**Firewall Rules**:
- Allow HTTPS (443) outbound for downloads
- Allow communication to CyberSentinel manager (port 1514, 1515)

**Proxy Considerations**:
- Script doesn't configure proxy automatically
- May need manual proxy configuration for corporate networks

---

## Logging and Monitoring

### Log File Analysis

**Finding Your Log File**:
```powershell
# Log file path shown at script start
%TEMP%\cybersentinel-complete-install-<timestamp>.log

# Example
C:\Users\Administrator\AppData\Local\Temp\cybersentinel-complete-install-20240212-143045.log
```

**Opening Log File**:
```powershell
# From PowerShell
notepad $env:TEMP\cybersentinel-complete-install-*.log

# Or search in File Explorer
%TEMP%
```

### Key Log Sections

**Phase 1 Markers**:
```
Starting Phase 1: Agent Installation
GitHub access validated successfully
MSI installation completed successfully
Service started successfully
Phase 1: Agent installation completed successfully
```

**Phase 2 Markers**:
```
Starting Phase 2: Active Response Setup
Python installation validated successfully
PyInstaller installed successfully
remove-threat.exe compiled successfully
All executables verified successfully
Phase 2: Active Response setup completed successfully
```

### MSI Installation Log

**Location**: `%TEMP%\cybersentinel-msi-install.log`

**Purpose**: Detailed Windows Installer logs for agent installation

**When to Check**: If Phase 1 fails during agent installation

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: "Script must be run as Administrator"

**Error Message**:
```
ERROR: This script must be run as Administrator!
Please right-click PowerShell and select 'Run as Administrator'
```

**Solution**:
1. Close current PowerShell window
2. Right-click PowerShell icon
3. Select "Run as Administrator"
4. Re-run the script

**Where Error Displayed**: Console only (script exits immediately)

---

#### Issue 2: GitHub Access Validation Failed

**Error Message**:
```
GitHub Access Failed

Could not access: AGENTS/WINDOWS-AGENT/ossec.conf
Error: 401 Unauthorized
```

**Possible Causes**:
- Invalid GitHub token
- Expired token
- Token missing `repo` scope
- Private repository access revoked

**Solution**:
1. Verify token at: https://github.com/settings/tokens
2. Check token has `repo` scope
3. Ensure token hasn't expired
4. Generate new token if necessary
5. Re-run installation with new token

**Where Error Displayed**:
- Console (red text)
- Log file (ERROR level)

**Log Entry**:
```
2024-02-12 14:30:50 [ERROR] Failed to access: AGENTS/WINDOWS-AGENT/ossec.conf - 401 Unauthorized
```

---

#### Issue 3: MSI Installation Failed

**Error Message**:
```
MSI Installation Failed - Exit Code: 1603
```

**Common Exit Codes**:
- **1603**: Fatal error during installation
- **1619**: Installation package could not be opened
- **1625**: Installation forbidden by system policy
- **1638**: Another version already installed

**Solution for 1603 (General Failure)**:
1. Check MSI log file: `%TEMP%\cybersentinel-msi-install.log`
2. Look for specific error near end of file
3. Common causes:
   - Insufficient disk space
   - Corrupted installer
   - Conflicting software
   - Previous installation not cleaned

**Solution Steps**:
```powershell
# 1. Check disk space (need at least 2 GB)
Get-PSDrive C | Select-Object Used,Free

# 2. Clean previous installation
Get-Service -Name "CyberSentinel*" | Stop-Service -Force
Remove-Item "C:\Program Files (x86)\ossec-agent" -Recurse -Force

# 3. Clear temp files
Remove-Item "$env:TEMP\cybersentinel-*" -Force

# 4. Re-run installation
```

**Where Error Displayed**:
- Console (red text)
- Main log file
- MSI log file (detailed)

---

#### Issue 4: Python Installation Failed

**Error Message**:
```
Failed to download Python installer after all attempts
```

**Possible Causes**:
- Internet connectivity issues
- Firewall blocking downloads
- Python.org unavailable
- Corporate proxy blocking

**Solution**:
1. **Check Internet Connection**:
   ```powershell
   Test-NetConnection python.org -Port 443
   ```

2. **Check Firewall**:
   - Allow HTTPS (443) outbound
   - Whitelist python.org

3. **Manual Download** (if automated fails):
   ```powershell
   # Download manually from:
   https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe
   
   # Place in: %TEMP%\python-3.13.1-installer.exe
   # Re-run script (will detect existing file)
   ```

**Where Error Displayed**:
- Console (red text)
- Log file (ERROR level)

---

#### Issue 5: PyInstaller Installation Failed

**Error Message**:
```
CRITICAL: Failed to install PyInstaller after all attempts
```

**Error Context**:
```
Installing PyInstaller...
  Retrying...
  Trying with trusted host...
  Trying without SSL verification (last resort)...
  Failed to install PyInstaller after all attempts
```

**Possible Causes**:
- SSL certificate issues
- PyPI connectivity problems
- Corporate firewall/proxy
- Corrupted pip cache

**Solution Strategy 1 - Clear Pip Cache**:
```powershell
# Run in PowerShell before re-running script
python -m pip cache purge
Remove-Item "$env:LOCALAPPDATA\pip\cache" -Recurse -Force
```

**Solution Strategy 2 - Manual PyInstaller Install**:
```powershell
# Open PowerShell (not as admin)
python -m pip install pyinstaller --trusted-host pypi.org --trusted-host files.pythonhosted.org

# Verify installation
python -m pip show pyinstaller

# Then re-run main script
```

**Solution Strategy 3 - Check Network**:
```powershell
# Test PyPI connectivity
Test-NetConnection pypi.org -Port 443

# If behind corporate proxy, configure:
python -m pip config set global.proxy http://proxy.company.com:8080
```

**Where Error Displayed**:
- Console (red text with retry attempts)
- Log file (WARNING for retries, ERROR for final failure)

**Log Pattern**:
```
2024-02-12 14:35:10 [WARNING] Standard installation failed on attempt 1
2024-02-12 14:35:15 [WARNING] Standard installation failed on attempt 2
2024-02-12 14:35:20 [WARNING] Standard installation failed on attempt 3
2024-02-12 14:35:25 [WARNING] Trusted host installation failed on attempt 1
...
2024-02-12 14:36:00 [ERROR] All installation strategies failed for PyInstaller
```

---

#### Issue 6: PyInstaller Compilation Failed

**Error Message**:
```
remove-threat.py compilation failed
remove-threat.exe was not created
```

**Possible Causes**:
- Task Scheduler failure
- Insufficient permissions
- Antivirus blocking compilation
- Corrupted Python scripts

**Solution Steps**:

1. **Check Task Scheduler**:
   ```powershell
   Get-ScheduledTask -TaskName "CyberSentinel-PyInstaller-*"
   ```

2. **Manual Compilation Test**:
   ```powershell
   # Navigate to build directory
   cd $env:TEMP
   $buildDir = Get-ChildItem -Directory -Filter "CyberSentinel-Build-*" | Select-Object -First 1
   cd $buildDir.FullName
   
   # Try manual compilation (without admin)
   python -m PyInstaller -F remove-threat.py --clean
   
   # Check for errors
   ```

3. **Check Antivirus**:
   - Temporarily disable real-time protection
   - Add exception for build directory
   - Add exception for PyInstaller executable

4. **Verify Source Scripts Downloaded**:
   ```powershell
   $buildDir = "$env:TEMP\CyberSentinel-Build-*"
   Get-ChildItem $buildDir -Filter "*.py"
   ```

**Where Error Displayed**:
- Console (red text)
- Log file (ERROR level)
- Scheduled task history

**Log Entries**:
```
2024-02-12 14:40:15 [INFO] Compiling as regular user: remove-threat.py
2024-02-12 14:40:20 [ERROR] remove-threat.py compilation failed with exit code: 1
2024-02-12 14:40:20 [ERROR] remove-threat.exe was not created
```

---

#### Issue 7: Service Won't Start

**Error Message**:
```
Failed to start service: Service 'CyberSentinelSvc' cannot be started
```

**Possible Causes**:
- Missing configuration files
- Invalid manager IP
- Port conflicts
- Corrupted installation

**Diagnostic Steps**:

1. **Check Service Status**:
   ```powershell
   Get-Service -Name "CyberSentinelSvc"
   ```

2. **Check Service Dependencies**:
   ```powershell
   Get-Service -Name "CyberSentinelSvc" | Select-Object -ExpandProperty RequiredServices
   ```

3. **Check Configuration**:
   ```powershell
   Test-Path "C:\Program Files (x86)\ossec-agent\ossec.conf"
   Get-Content "C:\Program Files (x86)\ossec-agent\.env"
   ```

4. **Check Event Logs**:
   ```powershell
   Get-EventLog -LogName Application -Source "CyberSentinel*" -Newest 10
   ```

**Solution**:
```powershell
# Manual service start
NET START CyberSentinelSvc

# If fails, check agent logs
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 50
```

**Where Error Displayed**:
- Console (yellow/red text)
- Log file (WARNING/ERROR level)
- Windows Event Viewer

---

### Advanced Troubleshooting

#### Enable Verbose Logging

Modify the script to add more detailed logging:

```powershell
# Add at top of script after $ErrorActionPreference
$VerbosePreference = "Continue"
$DebugPreference = "Continue"
```

#### Check All Prerequisites

```powershell
# PowerShell version
$PSVersionTable.PSVersion

# Administrator check
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")

# Internet connectivity
Test-NetConnection github.com -Port 443
Test-NetConnection python.org -Port 443
Test-NetConnection pypi.org -Port 443

# Disk space
Get-PSDrive C | Select-Object Used,Free

# Available memory
Get-WmiObject Win32_OperatingSystem | Select-Object FreePhysicalMemory,TotalVisibleMemorySize
```

#### Manual Cleanup and Retry

```powershell
# Stop all services
Get-Service -Name "*CyberSentinel*" | Stop-Service -Force

# Remove installation
Remove-Item "C:\Program Files (x86)\ossec-agent" -Recurse -Force

# Clean temp files
Remove-Item "$env:TEMP\cybersentinel-*" -Force
Remove-Item "$env:TEMP\python-*" -Force
Remove-Item "$env:TEMP\CyberSentinel-Build-*" -Recurse -Force

# Remove Python
Get-AppxPackage | Where-Object {$_.Name -like "*Python*"} | Remove-AppxPackage
Remove-Item "C:\Program Files\Python*" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\Programs\Python*" -Recurse -Force

# Clear scheduled tasks
Get-ScheduledTask -TaskName "CyberSentinel-*" | Unregister-ScheduledTask -Confirm:$false

# Restart PowerShell as Administrator
# Re-run installation script
```

---

## Post-Installation

### Verification Steps

#### 1. Verify Agent Installation

```powershell
# Check service status
Get-Service -Name "CyberSentinelSvc"

# Should show:
# Status   Name               DisplayName
# ------   ----               -----------
# Running  CyberSentinelSvc   CyberSentinel Agent
```

#### 2. Verify Files Present

```powershell
# Check agent directory
Test-Path "C:\Program Files (x86)\ossec-agent"

# Check active response
Test-Path "C:\Program Files (x86)\ossec-agent\active-response\bin\remove-threat.exe"
Test-Path "C:\Program Files (x86)\ossec-agent\active-response\bin\remove-malware.exe"

# Check configuration
Test-Path "C:\Program Files (x86)\ossec-agent\ossec.conf"
Test-Path "C:\Program Files (x86)\ossec-agent\.env"
```

#### 3. Verify Agent Connection

```powershell
# Check agent logs
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 50

# Look for connection messages:
# "INFO: Connected to the server"
# "INFO: Agent started"
```

#### 4. Verify Active Response

```powershell
# Check executable sizes
Get-ChildItem "C:\Program Files (x86)\ossec-agent\active-response\bin\" -Filter "*.exe" | 
    Select-Object Name, @{Name="Size(KB)";Expression={[math]::Round($_.Length/1KB,2)}}

# Should show both executables with reasonable sizes (10-15 KB)
```

### Manager-Side Verification

On the CyberSentinel Manager, verify agent registration:

```bash
# List all agents
/var/ossec/bin/agent_control -l

# Check specific agent
/var/ossec/bin/agent_control -i <agent-id>

# Should show:
# - Agent ID
# - Agent Name (matches your input)
# - IP Address
# - Status: Active
```

### Important Notes

**Restart Requirement**:
```
⚠️  IMPORTANT: Restart your computer for all changes to take effect!
```

While the service starts immediately, a full restart ensures:
- All system paths updated
- Service dependencies loaded
- Sysmon fully initialized
- Log collection starts properly

**Firewall Configuration**:
If Windows Firewall is enabled, ensure:
```powershell
# Check if rule exists
Get-NetFirewallRule -DisplayName "*CyberSentinel*"

# If not, create rule
New-NetFirewallRule -DisplayName "CyberSentinel Agent" `
    -Direction Outbound `
    -Action Allow `
    -Program "C:\Program Files (x86)\ossec-agent\ossec-agent.exe"
```

---

## File Locations Reference

### Installation Files

| File/Directory | Location | Purpose |
|----------------|----------|---------|
| Agent Directory | `C:\Program Files (x86)\ossec-agent` | Main installation |
| Configuration | `C:\Program Files (x86)\ossec-agent\ossec.conf` | Agent config |
| Environment | `C:\Program Files (x86)\ossec-agent\.env` | Local settings |
| Active Response | `C:\Program Files (x86)\ossec-agent\active-response\bin` | Response executables |
| Agent Logs | `C:\Program Files (x86)\ossec-agent\ossec.log` | Runtime logs |

### Temporary Files (Auto-Cleaned)

| File/Directory | Location | Purpose |
|----------------|----------|---------|
| Installation Log | `%TEMP%\cybersentinel-complete-install-<timestamp>.log` | Main log |
| MSI Log | `%TEMP%\cybersentinel-msi-install.log` | MSI install log |
| Build Directory | `%TEMP%\CyberSentinel-Build-<timestamp>` | Compilation temp |
| CA Certificate | `%TEMP%\ca.cer` | SSL cert (deleted) |
| MSI Installer | `%TEMP%\cybersentinel-agent.msi` | Installer (deleted) |
| Python Installer | `%TEMP%\python-3.13.1-installer.exe` | Python (deleted) |

---

## Security Considerations

### Token Security

- GitHub token is masked during input
- Token never appears in logs (only length is logged)
- Token stored only in memory during execution
- No persistent storage of token

### Elevated Privileges

Script requires administrator privileges for:
- MSI installation
- Service management
- System directory access
- Certificate import

However:
- PyInstaller compilation runs as regular user (security best practice)
- Minimal privilege escalation

### Network Security

- All downloads use HTTPS (except PyPI fallback)
- CA certificate validated before agent installation
- No credentials transmitted over network (except GitHub API)

---

## Support and Contact

### Log File Submission

If issues persist, provide the following for support:

1. **Installation Log**:
   - Location: `%TEMP%\cybersentinel-complete-install-<timestamp>.log`
   - Contains: Complete installation trace

2. **MSI Log** (if Phase 1 failed):
   - Location: `%TEMP%\cybersentinel-msi-install.log`
   - Contains: Detailed Windows Installer logs

3. **System Information**:
   ```powershell
   Get-ComputerInfo | Select-Object WindowsVersion, OsArchitecture, CsName
   ```

4. **Error Screenshot**: Include console output showing error

### Quick Diagnostics Collection

Run this to collect all relevant information:

```powershell
# Create diagnostics directory
$diagPath = "$env:USERPROFILE\Desktop\CyberSentinel-Diagnostics"
New-Item -ItemType Directory -Path $diagPath -Force

# Copy logs
Copy-Item "$env:TEMP\cybersentinel-*.log" $diagPath -ErrorAction SilentlyContinue
Copy-Item "C:\Program Files (x86)\ossec-agent\ossec.log" $diagPath -ErrorAction SilentlyContinue

# System info
Get-ComputerInfo | Out-File "$diagPath\system-info.txt"
Get-Service | Where-Object {$_.Name -like "*CyberSentinel*"} | Out-File "$diagPath\services.txt"

# Create ZIP
Compress-Archive -Path $diagPath -DestinationPath "$env:USERPROFILE\Desktop\CyberSentinel-Diagnostics.zip"

Write-Host "Diagnostics saved to: $env:USERPROFILE\Desktop\CyberSentinel-Diagnostics.zip"
```

---

## Appendix

### Glossary

- **Agent**: Client software that collects and sends logs to manager
- **Manager**: Central server that receives and analyzes logs
- **Active Response**: Automated actions triggered by security events
- **PyInstaller**: Tool that converts Python scripts to executables
- **MSI**: Microsoft Installer package format
- **Sysmon**: System Monitor tool for detailed event logging

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error or user cancellation |

### Version History

- **v3.0** - Current version with PyInstaller admin privilege fix
- **v2.x** - Previous versions (legacy)

---

## Quick Reference Card

### Before You Start
- [ ] PowerShell as Administrator
- [ ] Manager IP ready
- [ ] Agent name decided
- [ ] GitHub token generated
- [ ] Internet connection verified

### During Installation
- [ ] Confirm configuration summary
- [ ] Wait patiently (10-20 minutes)
- [ ] Don't close PowerShell window

### After Installation
- [ ] Check success message
- [ ] Review installation log
- [ ] Verify service running
- [ ] Restart computer
- [ ] Verify on manager

### If Errors Occur
1. Note the error message
2. Check log file
3. Find error in troubleshooting section
4. Follow solution steps
5. Re-run installation if needed

---

**Document Version**: 1.0  
**Last Updated**: February 12, 2026  
**Script Version**: 3.0
