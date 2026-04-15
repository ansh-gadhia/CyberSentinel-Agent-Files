# CyberSentinel Agent — macOS Intel Build Guide

> Build a signed CyberSentinel Agent `.pkg` installer for Intel-based macOS systems, compiled natively on a Mac Mini running macOS Catalina (10.15).  
> Based on Wazuh v4.14.2, rebranded for Virtual Galaxy Infotech Ltd.

---

## Table of Contents

- [Requirements](#requirements)
- [Repository Setup](#repository-setup)
- [Source-Level Rebranding](#source-level-rebranding)
  - [1. etc/preloaded-vars.conf](#1-etcpreloaded-varsconf)
  - [2. packages/macos/generate_wazuh_packages.sh](#2-packagesmacosgenerate_wazuh_packagessh)
  - [3. packages/macos/package_files/build.sh](#3-packagesmacospackage_filesbuildsh)
  - [4. packages/macos/package_files/introduction.txt](#4-packagesmacospackage_filesintroductiontxt)
  - [5. packages/macos/package_files/postinstall.sh](#5-packagesmacospackage_filespostinstallsh)
  - [6. packages/macos/package_files/preinstall.sh](#6-packagesmacospackage_filespreinstallsh)
  - [7. packages/macos/specs/build-info.json](#7-packagesmacosspecsbuild-infojson)
  - [8. packages/macos/uninstall.sh](#8-packagesmacosuninstallsh)
  - [9. src/Makefile](#9-srcmakefile)
  - [10. src/client-agent/main.c](#10-srcclient-agentmainc)
  - [11. src/client-agent/agentd.c](#11-srcclient-agentagentdc)
  - [12. src/client-agent/notify.c](#12-srcclient-agentnotifyc)
  - [13. src/client-agent/buffer.c](#13-srcclient-agentbufferc)
  - [14. src/client-agent/receiver.c](#14-srcclient-agentreceiverc)
  - [15. src/client-agent/reload_agent.c](#15-srcclient-agentreload_agentc)
  - [16. src/client-agent/start_agent.c](#16-srcclient-agentstart_agentc)
  - [17. src/headers/defs.h](#17-srcheadersdefsh)
  - [18. src/init/darwin-init.sh](#18-srcinitdarwin-initsh)
  - [19. src/init/inst-functions.sh](#19-srcinitinat-functionssh)
  - [20. src/init/init.sh](#20-srcinitinitsh)
  - [21. src/os_execd/wcom.c](#21-srcos_execdwcomc)
  - [22. src/shared_modules/content_manager/include/sharedDefs.hpp](#22-srcshared_modulescontent_managerincludeshareddefinitionshpp)
  - [23. src/syscheckd/CMakeLists.txt](#23-srcsyscheckdcmakeliststxt)
  - [24. src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp](#24-srcwazuh_modulesvulnerability_scannerincludevulnerabilityscannerdefinitionshpp)
  - [25. src/wazuh_modules/wmodules_def.h](#25-srcwazuh_moduleswmodules_defh)
  - [26. Create src/init/cybersentinel-client.sh](#26-create-srcinitinitcybersentinel-clientsh)
- [Compile the Agent](#compile-the-agent)
- [Generate Self-Signed Certificate and Sign the Package](#generate-self-signed-certificate-and-sign-the-package)
- [Deployment](#deployment)
- [Support](#support)
- [License](#license)

---

## Requirements

### Hardware

- Intel-based Mac (Mac Mini Late 2012 or newer)
- macOS Catalina 10.15 or newer
- Minimum 8 GB RAM, 20 GB free disk space

### Software Prerequisites

**1. Xcode Command Line Tools**

```bash
xcode-select --install
```

Click **Install** in the popup and wait for completion. Verify:

```bash
clang --version
# Should show: Apple clang version 12.x.x
```

**2. Homebrew**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**3. Build dependencies**

```bash
brew install cmake automake autoconf libtool openssl@1.1 gnu-make munkipkg
```

> **Note:** `gmake` is the GNU make binary installed by Homebrew. The build script uses `gmake` explicitly — verify it is available:
> ```bash
> which gmake
> # Should return: /usr/local/bin/gmake
> ```

**4. Verify munkipkg**

```bash
which munkipkg
# Should return: /usr/local/bin/munkipkg
```

---

## Repository Setup

### Clone the Wazuh Repository

```bash
git clone https://github.com/wazuh/wazuh
cd wazuh
git checkout v4.14.2
```

---

## Source-Level Rebranding

All changes below must be made inside the cloned `wazuh/` directory **before** compilation. The changes replace all Wazuh branding with CyberSentinel and rename all agent daemon binaries accordingly.

> **Already-present files:** `packages/macos/generate_cybersentinel_packages.sh` and `src/init/cybersentinel-client.sh` are untracked files already present in your working tree. Steps 2 and 26 below reference them directly.

---

### 1. `etc/preloaded-vars.conf`

Replace the entire file contents with:

```
USER_LANGUAGE=en
USER_NO_STOP=y
USER_INSTALL_TYPE=agent
USER_DIR=/Library/Ossec
USER_DELETE_DIR=y
USER_CLEANINSTALL=y
USER_BINARYINSTALL=y
USER_AGENT_SERVER_IP=MANAGER_IP
USER_ENABLE_SYSCHECK=y
USER_ENABLE_ROOTCHECK=y
USER_ENABLE_OPENSCAP=n
USER_ENABLE_CISCAT=n
USER_ENABLE_ACTIVE_RESPONSE=y
USER_CA_STORE=n
```

---

### 2. `packages/macos/generate_wazuh_packages.sh`

The pre-modified version already exists in the repo as `packages/macos/generate_cybersentinel_packages.sh`. Copy it over the original:

```bash
cp packages/macos/generate_cybersentinel_packages.sh packages/macos/generate_wazuh_packages.sh
chmod +x packages/macos/generate_wazuh_packages.sh
```

Key changes this file applies compared to the upstream original:

- Copyright header updated to `Virtual Galaxy Infotech Ltd.`
- `SERVICE_PATH` → `com.cybersentinel.agent.plist`
- `LAUNCHER_SCRIPT_PATH` → `CYBERSENTINEL/CyberSentinel-launcher`
- Working build directory: `wazuh-agent/` → `cybersentinel-agent/`
- Package names: `wazuh-agent_*` → `cybersentinel-agent_*`
- All user-facing log messages updated to reference CyberSentinel

---

### 3. `packages/macos/package_files/build.sh`

Find this block:

```bash
if [ "${MAKE_COMPILATION}" == "yes" ]; then
    make -C ${SOURCES_PATH}/src deps TARGET=agent

    echo "Generating Wazuh executables"
    make -j $BUILD_JOBS -C ${SOURCES_PATH}/src DYLD_FORCE_FLAT_NAMESPACE=1 DEBUG=$DEBUG TARGET=agent build
fi
```

Change to:

```bash
if [ "${MAKE_COMPILATION}" == "yes" ]; then
gmake -C ${SOURCES_PATH}/src deps TARGET=agent

    echo "Generating CyberSentinel executables"
gmake -j $BUILD_JOBS -C ${SOURCES_PATH}/src DYLD_FORCE_FLAT_NAMESPACE=1 DEBUG=$DEBUG TARGET=agent WAZUH_GROUP=cybersentinel WAZUH_USER=cybersentinel build
fi
```

> `gmake` (GNU make from Homebrew) is used instead of the system `make`. The `WAZUH_GROUP` and `WAZUH_USER` variables are passed as `cybersentinel` so compiled binaries reference the correct system user/group at runtime.

---

### 4. `packages/macos/package_files/introduction.txt`

Replace the entire file contents with:

```
Welcome to the CyberSentinel Agent Installer.

CyberSentinel is an enterprise-ready security monitoring solution for threat detection, integrity monitoring, incident response and compliance.

This package will install the CyberSentinel agent in your system.

Check out our documentation to learn more about CyberSentinel, and join our community where our team and other users can help you.

To continue, click Next.
```

---

### 5. `packages/macos/package_files/postinstall.sh`

**Change 1** — user and group names (lines 11–12):

```bash
# Change from:
GROUP="wazuh"
USER="wazuh"

# Change to:
GROUP="cybersentinel"
USER="cybersentinel"
```

**Change 2** — configuration message and file ownership (around line 92):

```bash
# Change from:
echo "Generating Wazuh configuration for a fresh installation."
...
chown root:wazuh ${DIR}/etc/ossec.conf

# Change to:
echo "Generating CyberSentinel configuration for a fresh installation."
...
chown root:cybersentinel ${DIR}/etc/ossec.conf
```

**Change 3** — ossec group/user migration messages (around line 160):

```bash
# Change from:
echo "Changing group from Ossec to Wazuh"
find ${DIR}/ -group ossec -user root -exec chown root:wazuh {} \ > /dev/null 2>&1 || true
...
echo "Changing user from Ossec to Wazuh"
find ${DIR}/ -group ossec -user ossec -exec chown wazuh:wazuh {} \ > /dev/null 2>&1 || true

# Change to:
echo "Changing group from Ossec to CyberSentinel"
find ${DIR}/ -group ossec -user root -exec chown root:cybersentinel {} \ > /dev/null 2>&1 || true
...
echo "Changing user from Ossec to CyberSentinel"
find ${DIR}/ -group ossec -user ossec -exec chown cybersentinel:cybersentinel {} \ > /dev/null 2>&1 || true
```

**Change 4** — restart message and LaunchDaemon plist name (last block):

```bash
# Change from:
echo "Restarting Wazuh..."
launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist

# Change to:
echo "Restarting CyberSentinel..."
launchctl bootstrap system /Library/LaunchDaemons/com.cybersentinel.agent.plist
```

---

### 6. `packages/macos/package_files/preinstall.sh`

**Change 1** — upgrade detection message (around line 39):

```bash
# Change from:
echo "A Wazuh agent installation was found in ${DIR}. Will perform an upgrade."

# Change to:
echo "A CyberSentinel agent installation was found in ${DIR}. Will perform an upgrade."
```

**Change 2** — control binary references (around line 48):

```bash
# Change from:
if ${DIR}/bin/wazuh-control status | grep "is running" > /dev/null 2>&1; then
    touch "${DIR}/WAZUH_RESTART"
    ${DIR}/bin/wazuh-control stop

# Change to:
if ${DIR}/bin/cybersentinel-control status | grep "is running" > /dev/null 2>&1; then
    touch "${DIR}/WAZUH_RESTART"
    ${DIR}/bin/cybersentinel-control stop
```

**Change 3** — log directory rename message (around line 63):

```bash
# Change from:
echo "Renaming ${DIR}/logs/ossec to ${DIR}/logs/wazuh"
mv ${DIR}/logs/ossec ${DIR}/logs/wazuh

# Change to:
echo "Renaming ${DIR}/logs/ossec to ${DIR}/logs/cybersentinel"
mv ${DIR}/logs/ossec ${DIR}/logs/cybersentinel
```

**Change 4** — package receipt removal (around line 72):

```bash
# Change from:
if pkgutil --pkgs | grep -i wazuh-agent-etc > /dev/null 2>&1 ; then
    echo "Removing previous package receipt for wazuh-agent-etc"
    pkgutil --forget com.wazuh.pkg.wazuh-agent-etc

# Change to:
if pkgutil --pkgs | grep -i cybersentinel-agent-etc > /dev/null 2>&1 ; then
    echo "Removing previous package receipt for cybersentinel-agent-etc"
    pkgutil --forget com.cybersentinel.pkg.cybersentinel-agent-etc
```

**Change 5** — UID message (around line 101):

```bash
# Change from:
echo "UID available for wazuh user is:";

# Change to:
echo "UID available for cybersentinel user is:";
```

**Change 6** — group creation block (around line 118):

```bash
# Change from:
if [[ $(dscl . -read /Groups/wazuh) ]]
    then
    echo "wazuh group already exists.";
else
    sudo ${DSCL} localhost -create /Local/Default/Groups/wazuh
    check_errm "Error creating group wazuh" "67"
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/wazuh PrimaryGroupID ${new_gid}
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/wazuh RealName wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/wazuh RecordName wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/wazuh RecordType: dsRecTypeStandard:Groups
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/wazuh Password "*"
fi

# Change to:
if [[ $(dscl . -read /Groups/cybersentinel) ]]
    then
    echo "cybersentinel group already exists.";
else
    sudo ${DSCL} localhost -create /Local/Default/Groups/cybersentinel
    check_errm "Error creating group cybersentinel" "67"
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/cybersentinel PrimaryGroupID ${new_gid}
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/cybersentinel RealName cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/cybersentinel RecordName cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/cybersentinel RecordType: dsRecTypeStandard:Groups
    sudo ${DSCL} localhost -createprop /Local/Default/Groups/cybersentinel Password "*"
fi
```

**Change 7** — user creation block (around line 130):

```bash
# Change from:
if [[ $(dscl . -read /Users/wazuh) ]]
    then
    echo "wazuh user already exists.";
else
    sudo ${DSCL} localhost -create /Local/Default/Users/wazuh
    check_errm "Error creating user wazuh" "77"
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh RecordName wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh RealName wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh UserShell /usr/bin/false
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh NFSHomeDirectory /var/wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh UniqueID ${new_uid}
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh PrimaryGroupID ${new_gid}
    sudo ${DSCL} localhost -append /Local/Default/Groups/wazuh GroupMembership wazuh
    sudo ${DSCL} localhost -createprop /Local/Default/Users/wazuh Password "*"
fi
echo "Hiding the fixed wazuh user"
dscl . create /Users/wazuh IsHidden 1

# Change to:
if [[ $(dscl . -read /Users/cybersentinel) ]]
    then
    echo "cybersentinel user already exists.";
else
    sudo ${DSCL} localhost -create /Local/Default/Users/cybersentinel
    check_errm "Error creating user cybersentinel" "77"
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel RecordName cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel RealName cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel UserShell /usr/bin/false
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel NFSHomeDirectory /var/cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel UniqueID ${new_uid}
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel PrimaryGroupID ${new_gid}
    sudo ${DSCL} localhost -append /Local/Default/Groups/cybersentinel GroupMembership cybersentinel
    sudo ${DSCL} localhost -createprop /Local/Default/Users/cybersentinel Password "*"
fi
echo "Hiding the fixed cybersentinel user"
dscl . create /Users/cybersentinel IsHidden 1
```

---

### 7. `packages/macos/specs/build-info.json`

Find:

```json
"identifier": "com.wazuh.pkg.wazuh-agent",
```

Change to:

```json
"identifier": "com.cybersentinel.pkg.cybersentinel-agent",
```

---

### 8. `packages/macos/uninstall.sh`

Replace the entire file contents with:

```bash
#!/bin/sh

## Stop and remove application
sudo /Library/Ossec/bin/cybersentinel-control stop
sudo /bin/rm -r /Library/Ossec*

# remove launchdaemons
/bin/rm -f /Library/LaunchDaemons/com.cybersentinel.agent.plist

## remove StartupItems
/bin/rm -rf /Library/StartupItems/CYBERSENTINEL

## Remove User and Groups
/usr/bin/dscl . -delete "/Users/cybersentinel"
/usr/bin/dscl . -delete "/Groups/cybersentinel"

/usr/sbin/pkgutil --forget com.cybersentinel.pkg.cybersentinel-agent
/usr/sbin/pkgutil --forget com.cybersentinel.pkg.cybersentinel-agent-etc

# In case it was installed via Puppet pkgdmg provider
if [ -e /var/db/.puppet_pkgdmg_installed_cybersentinel-agent ]; then
    rm -f /var/db/.puppet_pkgdmg_installed_cybersentinel-agent
fi

echo
echo "CyberSentinel agent correctly removed from the system."
echo

exit 0
```

---

### 9. `src/Makefile`

**Change 1** — `BUILD_AGENT` target names (around line 803):

```makefile
# Change from:
BUILD_AGENT+=wazuh-agentd
BUILD_AGENT+=wazuh-logcollector
BUILD_AGENT+=wazuh-syscheckd
BUILD_AGENT+=wazuh-execd
BUILD_AGENT+=wazuh-modulesd

# Change to:
BUILD_AGENT+=cybersentinel-agentd
BUILD_AGENT+=cybersentinel-logcollector
BUILD_AGENT+=cybersentinel-syscheckd
BUILD_AGENT+=cybersentinel-execd
BUILD_AGENT+=cybersentinel-modulesd
```

**Change 2** — agentlessd compiler flag (around line 2086):

```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-agentlessd\" -c $^ -o $@

# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-agentlessd\" -c $^ -o $@
```

**Change 3** — execd compiler flag and target (around line 2094):

```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-execd\" -c $^ -o $@
wazuh-execd: ${os_execd_o} active-response/active_responses.o

# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-execd\" -c $^ -o $@
cybersentinel-execd: ${os_execd_o} active-response/active_responses.o
```

**Change 4** — logcollector compiler flags and target (around line 2107):

```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-logcollector\" -c $^ -o $@
...
${OSSEC_CC} ${OSSEC_CFLAGS} -DEVENTCHANNEL_SUPPORT -DARGV0=\"wazuh-logcollector\" -c $^ -o $@
wazuh-logcollector: ${os_logcollector_o}

# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-logcollector\" -c $^ -o $@
...
${OSSEC_CC} ${OSSEC_CFLAGS} -DEVENTCHANNEL_SUPPORT -DARGV0=\"cybersentinel-logcollector\" -c $^ -o $@
cybersentinel-logcollector: ${os_logcollector_o}
```

**Change 5** — agentd compiler flag and target (around line 2132):

```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"wazuh-agentd\" -c $^ -o $@
wazuh-agentd: ${client_agent_o} monitord/rotate_log.o monitord/compress_log.o

# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"cybersentinel-agentd\" -c $^ -o $@
cybersentinel-agentd: ${client_agent_o} monitord/rotate_log.o monitord/compress_log.o
```

**Change 6** — syscheckd target (around line 2306):

```makefile
# Change from:
wazuh-syscheckd: librootcheck.a libwazuh.a ${WAZUHEXT_LIB} build_shared_modules

# Change to:
cybersentinel-syscheckd: librootcheck.a libwazuh.a ${WAZUHEXT_LIB} build_shared_modules
```

**Change 7** — modulesd target (around line 2467):

```makefile
# Change from:
wazuh-modulesd: ${wmodulesd_o}

# Change to:
cybersentinel-modulesd: ${wmodulesd_o}
```

---

### 10. `src/client-agent/main.c`

```c
// Change from:
#define ARGV0 "wazuh-agentd"

// Change to:
#define ARGV0 "cybersentinel-agentd"
```

---

### 11. `src/client-agent/agentd.c`

```c
// Change from:
minfo("Using force reconnect interval, Wazuh Agent will reconnect every %ld %s", ...);

// Change to:
minfo("Using force reconnect interval, CyberSentinel Agent will reconnect every %ld %s", ...);
```

---

### 12. `src/client-agent/notify.c`

```c
// Change from:
minfo("Wazuh Agent will be reconnected because of force reconnect interval");

// Change to:
minfo("CyberSentinel Agent will be reconnected because of force reconnect interval");
```

---

### 13. `src/client-agent/buffer.c`

Change all four `"wazuh-agent"` string literals to `"cybersentinel-agent"` (lines 209, 217, 225, 233):

```c
// Change from:
snprintf(warn_msg,   OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", warn_str);
snprintf(full_msg,   OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", OS_FULL_BUFFER);
snprintf(flood_msg,  OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", OS_FLOOD_BUFFER);
snprintf(normal_msg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", OS_NORMAL_BUFFER);

// Change to:
snprintf(warn_msg,   OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", warn_str);
snprintf(full_msg,   OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", OS_FULL_BUFFER);
snprintf(flood_msg,  OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", OS_FLOOD_BUFFER);
snprintf(normal_msg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", OS_NORMAL_BUFFER);
```

---

### 14. `src/client-agent/receiver.c`

```c
// Change from:
minfo("Wazuh Agent will be reconnected because a reconnect message was received");
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", AG_IN_UNMERGE);

// Change to:
minfo("CyberSentinel Agent will be reconnected because a reconnect message was received");
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", AG_IN_UNMERGE);
```

---

### 15. `src/client-agent/reload_agent.c`

**Change 1** — static constant (line 22):

```c
// Change from:
static const char AG_IN_RCON[] = "wazuh: Invalid remote configuration";

// Change to:
static const char AG_IN_RCON[] = "cybersentinel: Invalid remote configuration";
```

**Change 2** — all seven `"wazuh-agent"` literals inside `verifyRemoteConf()` (around line 70). Change every occurrence:

```c
// Change from (each of the 7 lines):
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s: '%s'. ", LOCALFILE_MQ, "wazuh-agent", AG_IN_RCON, "<module>");

// Change to:
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s: '%s'. ", LOCALFILE_MQ, "cybersentinel-agent", AG_IN_RCON, "<module>");
```

The affected modules are: `syscheck`, `rootcheck`, `localfile`, `client`, `client_buffer`, `wodle`, `labels`.

---

### 16. `src/client-agent/start_agent.c`

```c
// Change from:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", msg);

// Change to:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", msg);
```

---

### 17. `src/headers/defs.h`

```c
// Change from:
#define __ossec_name    "Wazuh"
#define __author        "Wazuh Inc."
#define __contact       "info@wazuh.com"
#define __site          "http://www.wazuh.com"

// Change to:
#define __ossec_name    "CyberSentinel"
#define __author        "Virtual Galaxy Infotech Ltd."
#define __contact       "socass@vgipl.in"
#define __site          "http://www.vgipl.com"
```

---

### 18. `src/init/darwin-init.sh`

The pre-modified version already exists in the repository at `packages/macos/darwin-init.sh`. Copy it into place:

```bash
cp packages/macos/darwin-init.sh src/init/darwin-init.sh
chmod +x src/init/darwin-init.sh
```

Key changes this file contains compared to the upstream original:

- Copyright updated to `Virtual Galaxy Infotech Ltd.`
- `SERVICE` path: `com.wazuh.agent.plist` → `com.cybersentinel.agent.plist`
- `STARTUP` / `LAUNCHER_SCRIPT` / `STARTUP_SCRIPT` paths: `WAZUH/` → `CYBERSENTINEL/`
- LaunchDaemon `Label` key: `com.wazuh.agent` → `com.cybersentinel.agent`
- All `wazuh-control` binary calls → `cybersentinel-control`
- `StartupParameters.plist` description / messages updated to `CyberSentinel`
- `Provides` key: `WAZUH` → `CYBERSENTINEL`

---

### 19. `src/init/inst-functions.sh`

**Change 1** — control script source reference (around line 757):

```bash
# Change from:
OSSEC_CONTROL_SRC='./init/wazuh-client.sh'

# Change to:
OSSEC_CONTROL_SRC='./init/cybersentinel-client.sh'
```

**Change 2** — binary installation paths (around line 968):

```bash
# Change from:
${INSTALL} -m 0750 -o root -g 0 wazuh-logcollector ${INSTALLDIR}/bin
${INSTALL} -m 0750 -o root -g 0 syscheckd/build/bin/wazuh-syscheckd ${INSTALLDIR}/bin
${INSTALL} -m 0750 -o root -g 0 wazuh-execd ${INSTALLDIR}/bin
${INSTALL} -m 0750 -o root -g 0 ${OSSEC_CONTROL_SRC} ${INSTALLDIR}/bin/wazuh-control
${INSTALL} -m 0750 -o root -g 0 wazuh-modulesd ${INSTALLDIR}/bin/

# Change to:
${INSTALL} -m 0750 -o root -g 0 cybersentinel-logcollector ${INSTALLDIR}/bin
${INSTALL} -m 0750 -o root -g 0 syscheckd/build/bin/cybersentinel-syscheckd ${INSTALLDIR}/bin/cybersentinel-syscheckd
${INSTALL} -m 0750 -o root -g 0 cybersentinel-execd ${INSTALLDIR}/bin
${INSTALL} -m 0750 -o root -g 0 ${OSSEC_CONTROL_SRC} ${INSTALLDIR}/bin/cybersentinel-control
${INSTALL} -m 0750 -o root -g 0 cybersentinel-modulesd ${INSTALLDIR}/bin/
```

**Change 3** — agentd binary installation (around line 1419):

```bash
# Change from:
${INSTALL} -m 0750 -o root -g 0 wazuh-agentd ${INSTALLDIR}/bin

# Change to:
${INSTALL} -m 0750 -o root -g 0 cybersentinel-agentd ${INSTALLDIR}/bin
```

---

### 20. `src/init/init.sh`

**Change 1** (around line 173) — BSD/FreeBSD rc.local:

```bash
# Change from:
grep wazuh-control /etc/rc.local > /dev/null 2>&1
...
echo "${INSTALLDIR}/bin/wazuh-control start" >> /etc/rc.local

# Change to:
grep cybersentinel-control /etc/rc.local > /dev/null 2>&1
...
echo "${INSTALLDIR}/bin/cybersentinel-control start" >> /etc/rc.local
```

**Change 2** (around line 187) — Linux rc.d:

```bash
# Change from:
grep wazuh-control /etc/rc.d/rc.local > /dev/null 2>&1
...
echo "${INSTALLDIR}/bin/wazuh-control start" >> /etc/rc.d/rc.local

# Change to:
grep cybersentinel-control /etc/rc.d/rc.local > /dev/null 2>&1
...
echo "${INSTALLDIR}/bin/cybersentinel-control start" >> /etc/rc.d/rc.local
```

---

### 21. `src/os_execd/wcom.c`

Find (around line 382):

```c
"bin/wazuh-integratord", "bin/wazuh-syscheckd", "bin/wazuh-maild",
```

Change to:

```c
"bin/wazuh-integratord", "bin/cybersentinel-syscheckd", "bin/wazuh-maild",
```

---

### 22. `src/shared_modules/content_manager/include/sharedDefs.hpp`

```cpp
// Change from:
#define WM_CONTENTUPDATER "wazuh-modulesd:content-updater"

// Change to:
#define WM_CONTENTUPDATER "cybersentinel-modulesd:content-updater"
```

---

### 23. `src/syscheckd/CMakeLists.txt`

**Change 1** — project name (line 4):

```cmake
# Change from:
project(wazuh-syscheckd)

# Change to:
project(cybersentinel-syscheckd)
```

**Change 2** — ARGV0 definition (around line 37):

```cmake
# Change from:
add_definitions(-DARGV0="wazuh-syscheckd")

# Change to:
add_definitions(-DARGV0="cybersentinel-syscheckd")
```

**Change 3** — all executable target names throughout the file. Replace every occurrence of `wazuh-syscheckd` with `cybersentinel-syscheckd` in `add_executable`, `target_link_libraries`, and `target_compile_definitions` calls. There are 12 occurrences — change all of them. These appear across the non-Windows build path, unit test linkage, and sanitizer linkage sections.

---

### 24. `src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp`

```cpp
// Change from:
#define WM_VULNSCAN_LOGTAG "wazuh-modulesd:" VS_WM_NAME

// Change to:
#define WM_VULNSCAN_LOGTAG "cybersentinel-modulesd:" VS_WM_NAME
```

---

### 25. `src/wazuh_modules/wmodules_def.h`

```c
// Change from:
#define ARGV0 "wazuh-modulesd"

// Change to:
#define ARGV0 "cybersentinel-modulesd"
```

---

### 26. Create `src/init/cybersentinel-client.sh`

This file is already present in the repo as an untracked file at `src/init/cybersentinel-client.sh`. Ensure it is executable:

```bash
chmod +x src/init/cybersentinel-client.sh
```

The file is the CyberSentinel replacement for `wazuh-client.sh` and defines the following daemon list:

```bash
DAEMONS="cybersentinel-modulesd cybersentinel-logcollector cybersentinel-syscheckd cybersentinel-agentd cybersentinel-execd"
```

It implements the standard `start`, `stop`, `restart`, `reload`, `status`, and `info` commands. The `reload` subcommand restarts all daemons except `cybersentinel-agentd`, then sends `SIGUSR1` to the running agentd PID to trigger a reconnect.

---

## Compile the Agent

Navigate to the macOS packages directory and run the build script:

```bash
cd packages/macos

sudo ./generate_wazuh_packages.sh \
  -a intel64 \
  -j $(sysctl -n hw.logicalcpu) \
  -s ./cyb-output
```

| Flag | Description |
|------|-------------|
| `-a intel64` | Target Intel x86_64 architecture |
| `-j $(sysctl -n hw.logicalcpu)` | Use all available CPU cores |
| `-s ./cyb-output` | Output directory for the built package |

> **Note:** First-run compilation takes **20–40 minutes**. On completion, the unsigned package will be at:
> ```
> packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_custom.pkg
> ```

---

## Generate Self-Signed Certificate and Sign the Package

Since a paid Apple Developer account is not being used, a self-signed certificate is created locally. This is suitable for internal/corporate deployment.

### 1. Create the Certificate Authority and Signing Certificate

```bash
mkdir ~/certs && cd ~/certs

# Root CA key and certificate
openssl genrsa -out macca.key 2048
openssl req -x509 -new -nodes -key macca.key \
  -sha256 -days 1095 \
  -subj "/CN=VGIPLRootCA/O=Virtual Galaxy Infotech Ltd." \
  -out macca.crt

# Signing key and certificate
openssl genrsa -out signing.key 2048
openssl req -new -key signing.key \
  -subj "/CN=CyberSentinel Installer/O=Virtual Galaxy Infotech Ltd." \
  -out signing.csr
openssl x509 -req -in signing.csr \
  -CA macca.crt -CAkey macca.key \
  -CAcreateserial -out signing.crt \
  -days 1095 -sha256

# Bundle into .p12
openssl pkcs12 -export \
  -inkey signing.key -in signing.crt \
  -certfile macca.crt \
  -out signing.p12 -passout pass:Virtual09
```

### 2. Import into Keychain

```bash
security import ~/certs/signing.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P Virtual09 \
  -T /usr/bin/productsign

# Verify it imported successfully
security find-identity -v -p basic | grep "CyberSentinel"
```

### 3. Sign the Package

```bash
productsign \
  --sign "CyberSentinel Installer" \
  --keychain ~/Library/Keychains/login.keychain-db \
  packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_custom.pkg \
  packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_signed.pkg
```

The signed package will be at:

```
packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_signed.pkg
```

---

## Deployment

### 1. Create a Release

- Upload `cybersentinel-agent_4.14.2-1_intel64_signed.pkg` to your GitHub repository releases.
- Include `macca.crt` (the CA certificate) in the release assets so client machines can trust it.

### 2. Distribute the CA Certificate to Client Macs

On each client Mac, run this **once** to trust your CA before installing the package:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/macca.crt
```

Or push it via script:

```bash
curl -o /tmp/macca.crt \
  https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/macOS/macca.crt

sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/macca.crt
```

### 3. Client Installation

On the target Mac, run the following in Terminal:

```bash
# Set manager IP
echo "WAZUH_MANAGER='YOUR_MANAGER_IP'" > /tmp/wazuh_envs

# Install silently
sudo installer -pkg /path/to/cybersentinel-agent_4.14.2-1_intel64_signed.pkg -target /

# Start the agent
sudo /Library/Ossec/bin/cybersentinel-control start
```

### 4. Verify Installation

```bash
# Check agent status
sudo /Library/Ossec/bin/cybersentinel-control status

# Check logs — should reference cybersentinel-agentd, not wazuh-agentd
tail -f /Library/Ossec/logs/ossec.log

# Verify the LaunchDaemon loaded under the correct identifier
launchctl list | grep cybersentinel
```

---

## Support

For issues or questions, please open an issue in this repository.

---

## License

See `license.rtf` for license information.
