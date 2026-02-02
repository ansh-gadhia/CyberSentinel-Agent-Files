# CyberSentinel Agent

## Introduction

CyberSentinel Agent is a comprehensive security monitoring solution designed to protect your systems from cyber threats. This repository contains all the necessary compilation files and resources required to build the CyberSentinel Agent installer.

## Build Requirements

To successfully compile and create the CyberSentinel Agent MSI installer, you will need:

1. **Linux System** - For cross-platform compilation and build preparation
2. **Windows System** - For final MSI package creation and Windows-specific builds

Both systems are essential components of the build pipeline to ensure proper compilation and packaging of the agent across different platforms.
## Linux Environment Setup

### 1. Clone the Wazuh Repository
```bash
git clone https://github.com/wazuh/wazuh
cd wazuh
git checkout v4.14.2
```

### 2. Prepare Installation Files

Navigate to the Windows build directory:
```bash
cd ./src/win32
```

### 3. Update Installer Components

- **Add** `cybersentinel-installer.wxs` from the repository:
  - Source: https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/cybersentinel-installer.wxs

- **Update** the following icon files with `favicon.ico`:
  - `install.ico`
  - `favicon.ico`
  - `uninstall.ico`
  - Source: https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/favicon.ico

- **Remove** `wazuh-installer.wxs` from the folder

> **Note:** All required components are available in the [CyberSentinel-Agent-Files repository](https://github.com/ansh-gadhia/CyberSentinel-Agent-Files).
### 4. Customize Branding and License

In the same `./src/win32` directory:

- **Modify** `version.rc`:
  - Replace the product name with your desired product name
  - Replace the company name with your company name

- **Replace** `license.rtf` with the license file provided in the repository

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
  - Download: https://dotnet.microsoft.com/en-us/download/dotnet-framework/thank-you/net481-web-installer

- **Microsoft Windows SDK**
  - Download: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/

- **PowerShell 5 or higher** (usually pre-installed)

- **cv2pdb.exe V3** (must be accessible via system PATH)

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
