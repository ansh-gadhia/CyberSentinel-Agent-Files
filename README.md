# CyberSentinel Agent

## Introduction

CyberSentinel Agent is a comprehensive security monitoring solution designed to protect your systems from cyber threats. This repository contains all the necessary compilation files and resources required to build the CyberSentinel Agent installer.

## Build Requirements

To successfully compile and create the CyberSentinel Agent MSI installer, you will need:

1. **Linux System** - For source modification, cross-compilation and build preparation
2. **Windows System** - For final MSI package creation and Windows-specific builds

Both systems are essential components of the build pipeline to ensure proper compilation and packaging of the agent across different platforms.

---

## Linux Environment Setup

### 1. Clone the Wazuh Repository
```bash
git clone https://github.com/wazuh/wazuh
cd wazuh
git checkout v4.14.2
```

### 2. Source-Level Rebranding

All changes below are made inside the cloned `wazuh/` directory before compilation.

---

#### 2.1 — `src/Makefile`

Make the following changes:

**Line 882** — rename Windows binary targets:
```makefile
# Change from:
WINDOWS_BINS:=win32/wazuh-agent.exe win32/wazuh-agent-eventchannel.exe ...
# Change to:
WINDOWS_BINS:=win32/cybersentinel-agent.exe win32/cybersentinel-agent-eventchannel.exe ...
```

**Line 2086** — agentlessd compiler flag:
```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-agentlessd\" -c $^ -o $@
# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-agentlessd\" -c $^ -o $@
```

**Line 2135** — agentd compiler flag:
```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"wazuh-agentd\" -c $^ -o $@
# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"cybersentinel-agentd\" -c $^ -o $@
```

**Lines 2663 and 2678** — resource file references:
```makefile
# Change from:
win32/wazuh_agent_resource.o: win32/wazuh-agent.rc
win32/wazuh_agent_eventchannel_resource.o: win32/wazuh-agent-eventchannel.rc
# Change to:
win32/wazuh_agent_resource.o: win32/cybersentinel-agent.rc
win32/wazuh_agent_eventchannel_resource.o: win32/cybersentinel-agent-eventchannel.rc
```

**Lines 2691 and 2694** — win32 compiler flags:
```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-agent\" -c $^ -o $@
${OSSEC_CC} ${OSSEC_CFLAGS} -UOSSECHIDS -DARGV0=\"wazuh-agent\" -c $^ -o $@
# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-agent\" -c $^ -o $@
${OSSEC_CC} ${OSSEC_CFLAGS} -UOSSECHIDS -DARGV0=\"cybersentinel-agent\" -c $^ -o $@
```

**Lines 2702–2706** — build targets and linker flags:
```makefile
# Change from:
win32/wazuh-agent.exe: ...
    ${OSSEC_CCBIN} -DARGV0=\"wazuh-agent\" -DOSSECHIDS ...
win32/wazuh-agent-eventchannel.exe: ...
    ${OSSEC_CCBIN} -DARGV0=\"wazuh-agent\" -DOSSECHIDS -DEVENTCHANNEL_SUPPORT ...
# Change to:
win32/cybersentinel-agent.exe: ...
    ${OSSEC_CCBIN} -DARGV0=\"cybersentinel-agent\" -DOSSECHIDS ...
win32/cybersentinel-agent-eventchannel.exe: ...
    ${OSSEC_CCBIN} -DARGV0=\"cybersentinel-agent\" -DOSSECHIDS -DEVENTCHANNEL_SUPPORT ...
```

**Line 2922** — clean target:
```makefile
# Change from:
rm -f win32/wazuh-agent-*.exe
# Change to:
rm -f win32/cybersentinel-agent-*.exe
```

---

#### 2.2 — `src/headers/defs.h`

Find and update the global name definitions:
```c
// Change from:
#define __ossec_name    "Wazuh"
#define __author        "Wazuh Inc."
#define __contact       "info@wazuh.com"
#define __site          "http://www.wazuh.com"

// Change to:
#define __ossec_name    "CyberSentinel"
#define __author        "Virtual Galaxy Infotech Ltd."
#define __contact       "SOCasS@vgipl.in"
#define __site          "https://vgipl.in"
```

---

#### 2.3 — `src/client-agent/main.c`
```c
// Change from:
#define ARGV0 "wazuh-agentd"
// Change to:
#define ARGV0 "cybersentinel-agentd"
```

---

#### 2.4 — `src/client-agent/agentd.c`
```c
// Change from:
minfo("Using force reconnect interval, Wazuh Agent will reconnect every %ld %s", ...);
// Change to:
minfo("Using force reconnect interval, CyberSentinel Agent will reconnect every %ld %s", ...);
```

---

#### 2.5 — `src/client-agent/notify.c`
```c
// Change from:
minfo("Wazuh Agent will be reconnected because of force reconnect interval");
// Change to:
minfo("CyberSentinel Agent will be reconnected because of force reconnect interval");
```

---

#### 2.6 — `src/client-agent/buffer.c`

Change all four `"wazuh-agent"` string literals to `"CyberSentinel-agent"`:
```c
// Lines 209, 217, 225, 233 — change from:
snprintf(..., LOCALFILE_MQ, "wazuh-agent", ...);
// Change to:
snprintf(..., LOCALFILE_MQ, "CyberSentinel-agent", ...);
```

---

#### 2.7 — `src/client-agent/receiver.c`
```c
// Change from:
minfo("Wazuh Agent will be reconnected because a reconnect message was received");
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", AG_IN_UNMERGE);
// Change to:
minfo("CyberSentinel Agent will be reconnected because a reconnect message was received");
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "CyberSentinel-agent", AG_IN_UNMERGE);
```

---

#### 2.8 — `src/client-agent/reload_agent.c`
```c
// Change from:
static const char AG_IN_RCON[] = "wazuh: Invalid remote configuration";
// Change to:
static const char AG_IN_RCON[] = "CyberSentinel: Invalid remote configuration";
```

Also change all seven `"wazuh-agent"` string literals in the `verifyRemoteConf()` function to `"CyberSentinel-agent"`.

---

#### 2.9 — `src/client-agent/start_agent.c`
```c
// Change from:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", msg);
// Change to:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "CyberSentinel-agent", msg);
```

---

#### 2.10 — `src/wazuh_modules/wmodules_def.h`
```c
// Change from:
#define ARGV0 "wazuh-modulesd"
// Change to:
#define ARGV0 "CyberSentinel-modulesd"
```

---

#### 2.11 — `src/shared_modules/content_manager/include/sharedDefs.hpp`
```cpp
// Change from:
#define WM_CONTENTUPDATER "wazuh-modulesd:content-updater"
// Change to:
#define WM_CONTENTUPDATER "CyberSentinel-modulesd:content-updater"
```

---

#### 2.12 — `src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp`
```cpp
// Change from:
#define WM_VULNSCAN_LOGTAG "wazuh-modulesd:" VS_WM_NAME
// Change to:
#define WM_VULNSCAN_LOGTAG "CyberSentinel-modulesd:" VS_WM_NAME
```

---

#### 2.13 — `src/win32/win_agent.c`
```c
// Change from:
#define ARGV0 "wazuh-agent"
// Change to:
#define ARGV0 "cybersentinel-agent"
```

---

#### 2.14 — `src/win32/win_service.c`
```c
// Change from:
#define ARGV0 "wazuh-agent"
static LPTSTR g_lpszServiceName        = "WazuhSvc";
static LPTSTR g_lpszServiceDisplayName = "Wazuh";
static LPTSTR g_lpszServiceDescription = "Wazuh Windows Agent";

// Change to:
#define ARGV0 "cybersentinel-agent"
static LPTSTR g_lpszServiceName        = "CyberSentinelSvc";
static LPTSTR g_lpszServiceDisplayName = "CyberSentinel";
static LPTSTR g_lpszServiceDescription = "CyberSentinel Windows Agent";
```

---

#### 2.15 — `src/win32/win_utils.c`
```c
// Change from:
minfo("Using force reconnect interval, Wazuh Agent will reconnect every %ld %s", ...);
// Change to:
minfo("Using force reconnect interval, CyberSentinel Agent will reconnect every %ld %s", ...);
```

---

#### 2.16 — `src/win32/ui/common.c`
```c
// Change from:
SendMessage(hStatus, SB_SETTEXT, 0, (LPARAM)"https://wazuh.com");
snprintf(buffer, sizeof(buffer), "Wazuh %s", prefixed_version);
snprintf(buffer, sizeof(buffer), "Wazuh %s", tmp_str);

// Change to:
SendMessage(hStatus, SB_SETTEXT, 0, (LPARAM)"https://vgipl.in");
snprintf(buffer, sizeof(buffer), "CyberSentinel %s", prefixed_version);
snprintf(buffer, sizeof(buffer), "CyberSentinel %s", tmp_str);
```

---

#### 2.17 — `src/win32/ui/os_win32ui.c`
```c
// Change from:
SendMessage(hStatus, SB_SETTEXT, 0, (LPARAM)"https://wazuh.com");
// Change to:
SendMessage(hStatus, SB_SETTEXT, 0, (LPARAM)"https://vgipl.in");
```

---

#### 2.18 — `src/win32/ui/win32ui.rc`
```rc
// Change from:
CAPTION "About Wazuh"
GROUPBOX " Copyright (C) 2023, Wazuh Inc."
"This program is a free software; you can redistribute it..."
"For more information, visit us online at https://wazuh.com/"
CAPTION "Wazuh Agent"

// Change to:
CAPTION "About CyberSentinel"
GROUPBOX " Copyright (C) 2026, Virtual Galaxy Infotech Ltd."
"This program is a paid software; you cannot redistribute it..."
"For more information, visit us online at https://vgipl.in/"
CAPTION "CyberSentinel Agent"
```

---

#### 2.19 — `src/win32/InstallerScripts.vbs`
```vb
' Change from:
SERVICE = "WazuhSvc"
StartSvc = "NET START WazuhSvc"
strKeyPath = "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\wazuh-agent.exe"

' Change to:
SERVICE = "CyberSentinelSvc"
StartSvc = "NET START CyberSentinelSvc"
strKeyPath = "SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\cybersentinel-agent.exe"
```

---

#### 2.20 — `src/win32/wazuh-installer.nsi`
```nsi
; Change from:
!define NAME "Wazuh"
!define SERVICE "WazuhSvc"
!define OutFile "wazuh-agent-${VERSION}.exe"
BrandingText "Copyright (C) 2015, Wazuh Inc."
VIAddVersionKey CompanyName "Wazuh Inc."
VIAddVersionKey LegalCopyright "2023 - Wazuh Inc."
VIAddVersionKey FileDescription "Wazuh Agent installer"
VIAddVersionKey InternalName "Wazuh Agent"
File wazuh-agent.exe
File wazuh-agent-eventchannel.exe

; Change to:
!define NAME "CyberSentinel"
!define SERVICE "CyberSentinelSvc"
!define OutFile "cybersentinel-agent-${VERSION}.exe"
BrandingText "Copyright (C) 2026, Virtual Galaxy Infotech Ltd."
VIAddVersionKey CompanyName "Virtual Galaxy Infotech Ltd."
VIAddVersionKey LegalCopyright "2026 Virtual Galaxy Infotech Ltd"
VIAddVersionKey FileDescription "CyberSentinel Agent installer"
VIAddVersionKey InternalName "CyberSentinel Agent"
File cybersentinel-agent.exe
File cybersentinel-agent-eventchannel.exe
```

Also update all references to `wazuh-agent.exe` → `cybersentinel-agent.exe` in the install, rename, uninstall, and service sections.

---

#### 2.21 — Rename and update `.rc` and `.manifest` files

Delete the original Wazuh files:
```bash
rm src/win32/wazuh-agent.rc
rm src/win32/wazuh-agent.exe.manifest
rm src/win32/wazuh-agent-eventchannel.rc
rm src/win32/wazuh-agent-eventchannel.exe.manifest
rm src/win32/wazuh-installer.wxs
```

Create `src/win32/cybersentinel-agent.rc`:
```rc
#define ID_MANIFEST 1
#define RT_MANIFEST 24
ID_MANIFEST RT_MANIFEST "cybersentinel-agent.exe.manifest"
```

Create `src/win32/cybersentinel-agent-eventchannel.rc`:
```rc
#define ID_MANIFEST 1
#define RT_MANIFEST 24
ID_MANIFEST RT_MANIFEST "cybersentinel-agent-eventchannel.exe.manifest"
```

Create `src/win32/cybersentinel-agent.exe.manifest` — same as the original `wazuh-agent.exe.manifest` with description updated:
```xml
<description>CyberSentinel Agent</description>
```

Create `src/win32/cybersentinel-agent-eventchannel.exe.manifest` — same as original with:
```xml
<description>CyberSentinel Agent Eventchannel</description>
```

---

### 3. Prepare Installation Files

Navigate to the Windows build directory:
```bash
cd ./src/win32
```

- **Add** `cybersentinel-installer.wxs` from the repository:
  - Source: https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/cybersentinel-installer.wxs

- **Update** the following icon files with `favicon.ico`:
  - `install.ico`
  - `favicon.ico`
  - `uninstall.ico`
  - Source: https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/favicon.ico

- **Update** UI images:
  - `src/win32/ui/bannrbmp.jpg`
  - `src/win32/ui/dlgbmp.jpg`
  - `src/win32/ui/favicon.ico`

> **Note:** All required components are available in the [CyberSentinel-Agent-Files repository](https://github.com/ansh-gadhia/CyberSentinel-Agent-Files).

---

### 4. Customize Branding and License

In the same `./src/win32` directory:

- **Modify** `version.rc`:
  - Replace the product name with your desired product name
  - Replace the company name with your company name

- **Replace** `license.rtf` with the license file provided in the repository

---

### 5. Compile the Agent

Navigate to the packages directory:
```bash
cd ../../packages/windows
```

Run the compilation script:
```bash
./generate_compiled_windows_agent.sh -o cybersentinel-agent -s ./cybersentinel-build
```

This will create a `cybersentinel-build` directory containing `cybersentinel-agent.zip`.

---


## Windows Environment Setup

### 1. Transfer and Extract Files

- Move `cybersentinel-agent.zip` to your Windows system
- Extract all files from the zip archive

### 2. Install Prerequisites

Install the following required components:

- **WiX Toolset v3.14**
  - Download: https://github.com/wixtoolset/wix3/releases/tag/wix3141rtm

- **.NET Framework 4.8.1**
  - Download: https://dotnet.microsoft.com/en-us/download/dotnet-framework/thank-you/net481-offline-installer

- **Microsoft Windows SDK**
  - Download: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/

- **PowerShell 5 or higher** (usually pre-installed)

- **cv2pdb.exe V3** (must be accessible via system PATH)
  - Download: https://github.com/rainers/cv2pdb/releases

### 3. Generate Self-Signed Certificate

Run the following commands in **PowerShell as Administrator**:
```powershell
# Create self-signed certificate
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject "CN=YourCompanyName" `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(3)

# Export to PFX with password
$password = ConvertTo-SecureString -String "YourPassword123" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\cybersentinel-signing.pfx" -Password $password
```

This will generate a `.pfx` certificate file.

### 4. Generate the MSI Installer

- Copy `generate_cybersentinel_msi.ps1` from the repository to:
```
  cybersentinel-agent\wazuh-local-src\src\win32
```

- Run the following command:
```powershell
.\generate_cybersentinel_msi.ps1 `
-MSI_NAME cybersentinel-agent.msi `
-SIGN yes `
-WIX_TOOLS_PATH "C:\Program Files (x86)\WiX Toolset v3.14\bin" `
-CERTIFICATE_PATH "C:\cybersentinel-signing.pfx" `
-CERTIFICATE_PASSWORD "YourPassword123"
```

This will generate a signed MSI file for the CyberSentinel Agent.

---

## Output

Upon successful completion, you will have a signed `cybersentinel-agent.msi` installer ready for deployment.

---

## Deployment

### 1. Create a Release

- Upload the signed `cybersentinel-agent.msi` to your GitHub repository releases
- Include the certificate file (`ca.cer`) in the release assets

### 2. Client Installation

On the client device, run the following command in **PowerShell as Administrator**:
```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/ca.cer -OutFile "$env:TEMP\ca.cer"; Import-Certificate -FilePath "$env:TEMP\ca.cer" -CertStoreLocation Cert:\LocalMachine\Root; Invoke-WebRequest -Uri https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/releases/download/1.0.0/cybersentinel-agent-1.0.0.msi -OutFile "$env:TEMP\cybersentinel-agent.msi"; msiexec.exe /i "$env:TEMP\cybersentinel-agent.msi" /q WAZUH_MANAGER="{Your_IP}" WAZUH_AGENT_GROUP="windows" WAZUH_AGENT_NAME="{Client_Agent_Name}"
```

**Parameters to customize:**
- `{Your_IP}` - Replace with your CyberSentinel Manager server IP address
- `{Client_Agent_Name}` - Replace with a unique name for the client agent

This command will:
1. Download and install the CA certificate
2. Download the CyberSentinel Agent MSI
3. Silently install the agent with the specified manager and agent configuration

---

## Support

For issues or questions, please open an issue in this repository.

## License

See `license.rtf` for license information.
