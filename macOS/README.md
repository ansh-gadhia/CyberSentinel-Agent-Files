# CyberSentinel Agent — macOS Intel x64 Build Guide

> Rebranding, compilation, signing, and deployment of a CyberSentinel `.pkg` agent for macOS Intel x64, based on **Wazuh v4.14.2**.
>
> Maintained by **Virtual Galaxy Infotech Ltd.** — [socass@vgipl.in](mailto:socass@vgipl.in)

---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Clone the Repository](#2-clone-the-repository)
3. [Source-Level Rebranding](#3-source-level-rebranding)
   - [3.1 src/headers/defs.h](#31--srcheadersdefs.h)
   - [3.2 src/Makefile](#32--srcmakefile)
   - [3.3 src/client-agent/main.c](#33--srcclient-agentmainc)
   - [3.4 src/client-agent/agentd.c](#34--srcclient-agentagentdc)
   - [3.5 src/client-agent/notify.c](#35--srcclient-agentnotifyc)
   - [3.6 src/client-agent/buffer.c](#36--srcclient-agentbufferc)
   - [3.7 src/client-agent/receiver.c](#37--srcclient-agentreceiverc)
   - [3.8 src/client-agent/reload_agent.c](#38--srcclient-agentreload_agentc)
   - [3.9 src/client-agent/start_agent.c](#39--srcclient-agentstart_agentc)
   - [3.10 src/wazuh_modules/wmodules_def.h](#310--srcwazuh_moduleswmodules_defh)
   - [3.11 src/shared_modules/content_manager/include/sharedDefs.hpp](#311--srcshared_modulescontent_managerincludeshareddefshpp)
   - [3.12 src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp](#312--srcwazuh_modulesvulnerability_scannerincludevulnerabilityscannerdefs.hpp)
   - [3.13 src/os_execd/wcom.c](#313--srcos_execdwcomc)
   - [3.14 src/syscheckd/CMakeLists.txt](#314--srcsyscheckdcmakeliststxt)
   - [3.15 src/init/inst-functions.sh](#315--srcinitin-functions.sh)
   - [3.16 src/init/init.sh](#316--srcinitinit.sh)
   - [3.17 src/init/cybersentinel-client.sh (new file)](#317--srcinitcybersentinel-clientsh-new-file)
   - [3.18 etc/preloaded-vars.conf](#318--etcpreloaded-varsconf)
4. [Package Files Changes](#4-package-files-changes)
   - [4.1 packages/macos/package_files/introduction.txt](#41--packagesmacospackage_filesintroductiontxt)
   - [4.2 packages/macos/package_files/build.sh](#42--packagesmacospackage_filesbuildsh)
   - [4.3 packages/macos/package_files/postinstall.sh](#43--packagesmacospackage_filespostinstallsh)
   - [4.4 packages/macos/package_files/preinstall.sh](#44--packagesmacospackage_filespreinstallsh)
   - [4.5 packages/macos/specs/build-info.json](#45--packagesmacosspecsbuild-infojson)
   - [4.6 packages/macos/uninstall.sh](#46--packagesmacosuninstallsh)
5. [Pre-built Files](#5-pre-built-files)
6. [Install Build Dependencies on Intel Mac](#6-install-build-dependencies-on-intel-mac)
7. [Transfer Source to Intel Mac](#7-transfer-source-to-intel-mac)
8. [Build the .pkg](#8-build-the-pkg)
9. [Self-Signed Certificate and Signing](#9-self-signed-certificate-and-signing)
10. [Deployment Bundle](#10-deployment-bundle)
11. [Managing the Agent](#11-managing-the-agent)
12. [Uninstall](#12-uninstall)
13. [Troubleshooting](#13-troubleshooting)
14. [Complete File Change Summary](#14-complete-file-change-summary)

---

## 1. System Requirements

### Linux Machine (for source edits)
- Any Linux distro (Parrot OS, Ubuntu, Debian, etc.)
- Git, text editor

### Intel Mac (for compilation and packaging)
- macOS Catalina (10.15) or later — Intel CPU only
- Xcode Command Line Tools
- Homebrew
- GNU make (`gmake`) v4.x — the system `make` 3.81 is **not** supported
- `munkipkg`
- `cmake`
- OpenSSL

---

## 2. Clone the Repository

Do this on **Linux** where all source edits will be made.

```bash
git clone https://github.com/wazuh/wazuh
cd wazuh
git checkout v4.14.2
```

---

## 3. Source-Level Rebranding

All changes below are made inside the cloned `wazuh/` directory on Linux before building.

---

### 3.1 — `src/headers/defs.h`

**Lines 71–74**

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

### 3.2 — `src/Makefile`

**Lines 807–814** — BUILD_AGENT list

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

**Line 2086** — agentlessd ARGV0

```makefile
# Change from:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-agentlessd\" -c $^ -o $@

# Change to:
${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-agentlessd\" -c $^ -o $@
```

**Lines 2094–2100** — execd section

```makefile
# Change from:
os_execd/%.o: os_execd/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-execd\" -c $^ -o $@

wazuh-execd: ${os_execd_o} active-response/active_responses.o

# Change to:
os_execd/%.o: os_execd/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-execd\" -c $^ -o $@

cybersentinel-execd: ${os_execd_o} active-response/active_responses.o
```

**Lines 2107–2116** — logcollector section

```makefile
# Change from:
logcollector/%.o: logcollector/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"wazuh-logcollector\" -c $^ -o $@

logcollector/%-event.o: logcollector/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DEVENTCHANNEL_SUPPORT -DARGV0=\"wazuh-logcollector\" -c $^ -o $@

wazuh-logcollector: ${os_logcollector_o}

# Change to:
logcollector/%.o: logcollector/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DARGV0=\"cybersentinel-logcollector\" -c $^ -o $@

logcollector/%-event.o: logcollector/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -DEVENTCHANNEL_SUPPORT -DARGV0=\"cybersentinel-logcollector\" -c $^ -o $@

cybersentinel-logcollector: ${os_logcollector_o}
```

**Lines 2132–2138** — agentd section

```makefile
# Change from:
client-agent/%.o: client-agent/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"wazuh-agentd\" -c $^ -o $@

wazuh-agentd: ${client_agent_o} monitord/rotate_log.o monitord/compress_log.o

# Change to:
client-agent/%.o: client-agent/%.c
    ${OSSEC_CC} ${OSSEC_CFLAGS} -I./client-agent -DARGV0=\"cybersentinel-agentd\" -c $^ -o $@

cybersentinel-agentd: ${client_agent_o} monitord/rotate_log.o monitord/compress_log.o
```

**Line 2309** — syscheckd target

```makefile
# Change from:
wazuh-syscheckd: librootcheck.a libwazuh.a ${WAZUHEXT_LIB} build_shared_modules

# Change to:
cybersentinel-syscheckd: librootcheck.a libwazuh.a ${WAZUHEXT_LIB} build_shared_modules
```

**Line 2470** — modulesd target

```makefile
# Change from:
wazuh-modulesd: ${wmodulesd_o}

# Change to:
cybersentinel-modulesd: ${wmodulesd_o}
```

> **⚠️ Important:** The Makefile uses hard tabs for recipe indentation. If you copy-paste, ensure lines inside build targets start with a real TAB character, not spaces. A wrong indent causes `missing separator` errors.

> **⚠️ Note:** There is also a broken line around line 796 in the original source where `wazuh-reportd` appears on its own line after `BUILD_SERVER+=`. Join them into one line: `BUILD_SERVER+=wazuh-reportd`

---

### 3.3 — `src/client-agent/main.c`

**Line 21**

```c
// Change from:
#define ARGV0 "wazuh-agentd"

// Change to:
#define ARGV0 "cybersentinel-agentd"
```

---

### 3.4 — `src/client-agent/agentd.c`

**Line 70**

```c
// Change from:
minfo("Using force reconnect interval, Wazuh Agent will reconnect every %ld %s", ...);

// Change to:
minfo("Using force reconnect interval, CyberSentinel Agent will reconnect every %ld %s", ...);
```

---

### 3.5 — `src/client-agent/notify.c`

**Line 113**

```c
// Change from:
minfo("Wazuh Agent will be reconnected because of force reconnect interval");

// Change to:
minfo("CyberSentinel Agent will be reconnected because of force reconnect interval");
```

---

### 3.6 — `src/client-agent/buffer.c`

**Lines 209, 217, 225, 233** — all four occurrences

```c
// Change from:
snprintf(..., LOCALFILE_MQ, "wazuh-agent", ...);

// Change to:
snprintf(..., LOCALFILE_MQ, "cybersentinel-agent", ...);
```

---

### 3.7 — `src/client-agent/receiver.c`

**Line 125**

```c
// Change from:
minfo("Wazuh Agent will be reconnected because a reconnect message was received");

// Change to:
minfo("CyberSentinel Agent will be reconnected because a reconnect message was received");
```

**Line 288**

```c
// Change from:
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", AG_IN_UNMERGE);

// Change to:
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", AG_IN_UNMERGE);
```

---

### 3.8 — `src/client-agent/reload_agent.c`

**Line 22**

```c
// Change from:
static const char AG_IN_RCON[] = "wazuh: Invalid remote configuration";

// Change to:
static const char AG_IN_RCON[] = "cybersentinel: Invalid remote configuration";
```

**Lines 73, 75, 77, 79, 81, 83, 85** — all seven occurrences in `verifyRemoteConf()`

```c
// Change from (all 7 occurrences):
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s: '%s'. ", LOCALFILE_MQ, "wazuh-agent", AG_IN_RCON, "...");

// Change to:
snprintf(msg_output, OS_MAXSTR, "%c:%s:%s: '%s'. ", LOCALFILE_MQ, "cybersentinel-agent", AG_IN_RCON, "...");
```

---

### 3.9 — `src/client-agent/start_agent.c`

**Line 405**

```c
// Change from:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "wazuh-agent", msg);

// Change to:
os_snprintf(fmsg, OS_MAXSTR, "%c:%s:%s", LOCALFILE_MQ, "cybersentinel-agent", msg);
```

---

### 3.10 — `src/wazuh_modules/wmodules_def.h`

**Line 24**

```c
// Change from:
#define ARGV0 "wazuh-modulesd"

// Change to:
#define ARGV0 "cybersentinel-modulesd"
```

---

### 3.11 — `src/shared_modules/content_manager/include/sharedDefs.hpp`

**Line 20**

```cpp
// Change from:
#define WM_CONTENTUPDATER "wazuh-modulesd:content-updater"

// Change to:
#define WM_CONTENTUPDATER "cybersentinel-modulesd:content-updater"
```

---

### 3.12 — `src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp`

**Line 16**

```cpp
// Change from:
#define WM_VULNSCAN_LOGTAG "wazuh-modulesd:" VS_WM_NAME

// Change to:
#define WM_VULNSCAN_LOGTAG "cybersentinel-modulesd:" VS_WM_NAME
```

---

### 3.13 — `src/os_execd/wcom.c`

**Line 385** — daemon whitelist array

```c
// Change from:
"bin/wazuh-integratord", "bin/wazuh-syscheckd", "bin/wazuh-maild",

// Change to:
"bin/wazuh-integratord", "bin/cybersentinel-syscheckd", "bin/wazuh-maild",
```

---

### 3.14 — `src/syscheckd/CMakeLists.txt`

**Line 3**
```cmake
# Change from:
project(wazuh-syscheckd)

# Change to:
project(cybersentinel-syscheckd)
```

**Line 37**
```cmake
# Change from:
add_definitions(-DARGV0="wazuh-syscheckd")

# Change to:
add_definitions(-DARGV0="cybersentinel-syscheckd")
```

**Line 88** — inside the `else()` block (non-Windows only)
```cmake
# Change from:
add_executable(wazuh-syscheckd ${SYSCHECKD_SRC})

# Change to:
add_executable(cybersentinel-syscheckd ${SYSCHECKD_SRC})
```

**Lines 91, 94, 97, 105, 117, 125, 128, 132** — all `target_link_libraries` calls

```cmake
# Change from (all occurrences):
target_link_libraries(wazuh-syscheckd ...)

# Change to:
target_link_libraries(cybersentinel-syscheckd ...)
```

> **Note:** Lines 83–86 contain `wazuh-syscheckd STATIC` and `wazuh-syscheckd-event STATIC` — these are inside a Windows-only `if(CMAKE_SYSTEM_NAME STREQUAL "Windows")` block. Leave them as-is.

---

### 3.15 — `src/init/inst-functions.sh`

**Line 760** — control script source

```bash
# Change from:
OSSEC_CONTROL_SRC='./init/wazuh-client.sh'

# Change to:
OSSEC_CONTROL_SRC='./init/cybersentinel-client.sh'
```

**Lines 969–976** — binary install commands

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

**Line 1422** — agentd install

```bash
# Change from:
${INSTALL} -m 0750 -o root -g 0 wazuh-agentd ${INSTALLDIR}/bin

# Change to:
${INSTALL} -m 0750 -o root -g 0 cybersentinel-agentd ${INSTALLDIR}/bin
```

---

### 3.16 — `src/init/init.sh`

**Lines 177, 180, 191, 194** — rc.local references

```bash
# Change from:
grep wazuh-control /etc/rc.local
echo "${INSTALLDIR}/bin/wazuh-control start" >> /etc/rc.local
grep wazuh-control /etc/rc.d/rc.local
echo "${INSTALLDIR}/bin/wazuh-control start" >> /etc/rc.d/rc.local

# Change to:
grep cybersentinel-control /etc/rc.local
echo "${INSTALLDIR}/bin/cybersentinel-control start" >> /etc/rc.local
grep cybersentinel-control /etc/rc.d/rc.local
echo "${INSTALLDIR}/bin/cybersentinel-control start" >> /etc/rc.d/rc.local
```

---

### 3.17 — `src/init/cybersentinel-client.sh` (new file)

Create this file as a rebranded copy of `wazuh-client.sh`. The complete ready-to-use file is available at:

**[https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/macOS/cybersentinel-client.sh](https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/macOS/cybersentinel-client.sh)**

Key differences from `wazuh-client.sh`:

| What | Old value | New value |
|---|---|---|
| `AUTHOR` | `Wazuh Inc.` | `Virtual Galaxy Infotech Ltd.` |
| `DAEMONS` | `wazuh-modulesd wazuh-logcollector wazuh-syscheckd wazuh-agentd wazuh-execd` | `cybersentinel-modulesd cybersentinel-logcollector cybersentinel-syscheckd cybersentinel-agentd cybersentinel-execd` |
| `chown` group | `wazuh:wazuh` | `cybersentinel:cybersentinel` |
| Start message | `Starting Wazuh $VERSION...` | `Starting CyberSentinel $VERSION...` |
| Stop message | `Wazuh $VERSION Stopped` | `CyberSentinel $VERSION Stopped` |
| Info vars | `WAZUH_VERSION` etc. | `CYBERSENTINEL_VERSION` etc. |
| reload section | `wazuh-agentd` reference | `cybersentinel-agentd` |

---

### 3.18 — `etc/preloaded-vars.conf`

Replace the **entire file** with:

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

## 4. Package Files Changes

All changes in `packages/macos/`.

---

### 4.1 — `packages/macos/package_files/introduction.txt`

Replace the **entire file**:

```
Welcome to the CyberSentinel Agent Installer.

CyberSentinel is an enterprise-ready security monitoring solution for threat
detection, integrity monitoring, incident response and compliance.

This package will install the CyberSentinel agent in your system.

Check out our documentation to learn more about CyberSentinel, and join our
community where our team and other users can help you.

To continue, click Next.
```

---

### 4.2 — `packages/macos/package_files/build.sh`

**Line 41** — use `gmake` for deps

```bash
# Change from:
make -C ${SOURCES_PATH}/src deps TARGET=agent

# Change to:
gmake -C ${SOURCES_PATH}/src deps TARGET=agent
```

**Lines 43–44** — use `gmake` for compilation and add group/user flags

```bash
# Change from:
echo "Generating Wazuh executables"
make -j $BUILD_JOBS -C ${SOURCES_PATH}/src DYLD_FORCE_FLAT_NAMESPACE=1 DEBUG=$DEBUG TARGET=agent build

# Change to:
echo "Generating CyberSentinel executables"
gmake -j $BUILD_JOBS -C ${SOURCES_PATH}/src DYLD_FORCE_FLAT_NAMESPACE=1 DEBUG=$DEBUG TARGET=agent WAZUH_GROUP=cybersentinel WAZUH_USER=cybersentinel build
```

> **⚠️ Critical:** `WAZUH_GROUP=cybersentinel WAZUH_USER=cybersentinel` is mandatory. Without it the compiled binaries have `wazuh` hardcoded as the required group and will fail at runtime with `CRITICAL: Invalid user '' or group 'wazuh'`.

---

### 4.3 — `packages/macos/package_files/postinstall.sh`

**Lines 11–12** — group/user variables

```bash
# Change from:
GROUP="wazuh"
USER="wazuh"

# Change to:
GROUP="cybersentinel"
USER="cybersentinel"
```

**Line 96** — chown on ossec.conf

```bash
# Change from:
chown root:wazuh ${DIR}/etc/ossec.conf

# Change to:
chown root:cybersentinel ${DIR}/etc/ossec.conf
```

**Line 92, 131** — echo messages: `Wazuh` → `CyberSentinel`

**Lines 160–164** — ossec→cybersentinel ownership migration

```bash
# Change from:
echo "Changing group from Ossec to Wazuh"
find ${DIR}/ -group ossec -user root -exec chown root:wazuh {} \ > /dev/null 2>&1 || true
echo "Changing user from Ossec to Wazuh"
find ${DIR}/ -group ossec -user ossec -exec chown wazuh:wazuh {} \ > /dev/null 2>&1 || true

# Change to:
echo "Changing group from Ossec to CyberSentinel"
find ${DIR}/ -group ossec -user root -exec chown root:cybersentinel {} \ > /dev/null 2>&1 || true
echo "Changing user from Ossec to CyberSentinel"
find ${DIR}/ -group ossec -user ossec -exec chown cybersentinel:cybersentinel {} \ > /dev/null 2>&1 || true
```

**Line 180** — LaunchDaemon path

```bash
# Change from:
launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist

# Change to:
launchctl bootstrap system /Library/LaunchDaemons/com.cybersentinel.agent.plist
```

---

### 4.4 — `packages/macos/package_files/preinstall.sh`

**Line 42**
```bash
# Change from:
echo "A Wazuh agent installation was found in ${DIR}. Will perform an upgrade."
# Change to:
echo "A CyberSentinel agent installation was found in ${DIR}. Will perform an upgrade."
```

**Lines 51, 53** — control binary
```bash
# Change from:
if ${DIR}/bin/wazuh-control status | grep "is running"
    ${DIR}/bin/wazuh-control stop
# Change to:
if ${DIR}/bin/cybersentinel-control status | grep "is running"
    ${DIR}/bin/cybersentinel-control stop
```

**Lines 66–67** — log folder rename
```bash
# Change from:
echo "Renaming ${DIR}/logs/ossec to ${DIR}/logs/wazuh"
mv ${DIR}/logs/ossec ${DIR}/logs/wazuh
# Change to:
echo "Renaming ${DIR}/logs/ossec to ${DIR}/logs/cybersentinel"
mv ${DIR}/logs/ossec ${DIR}/logs/cybersentinel
```

**Lines 75–77** — package receipt
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

**Line 104** — UID echo
```bash
# Change from:
echo "UID available for wazuh user is:";
# Change to:
echo "UID available for cybersentinel user is:";
```

**Lines 121–154** — all `wazuh` user/group DSCL entries → `cybersentinel`

Replace every occurrence of `/Groups/wazuh`, `/Users/wazuh`, `RealName wazuh`, `RecordName wazuh`, `/var/wazuh`, `GroupMembership wazuh` with the `cybersentinel` equivalent.

---

### 4.5 — `packages/macos/specs/build-info.json`

**Line 7**

```json
// Change from:
"identifier": "com.wazuh.pkg.wazuh-agent",

// Change to:
"identifier": "com.cybersentinel.pkg.cybersentinel-agent",
```

---

### 4.6 — `packages/macos/uninstall.sh`

Apply these replacements throughout the file:

| From | To |
|---|---|
| `/Library/Ossec/bin/wazuh-control stop` | `/Library/Ossec/bin/cybersentinel-control stop` |
| `com.wazuh.agent.plist` | `com.cybersentinel.agent.plist` |
| `/Library/StartupItems/WAZUH` | `/Library/StartupItems/CYBERSENTINEL` |
| `/Users/wazuh` | `/Users/cybersentinel` |
| `/Groups/wazuh` | `/Groups/cybersentinel` |
| `com.wazuh.pkg.wazuh-agent` | `com.cybersentinel.pkg.cybersentinel-agent` |
| `com.wazuh.pkg.wazuh-agent-etc` | `com.cybersentinel.pkg.cybersentinel-agent-etc` |
| `puppet_pkgdmg_installed_wazuh-agent` | `puppet_pkgdmg_installed_cybersentinel-agent` |
| `Wazuh agent correctly removed` | `CyberSentinel agent correctly removed` |

---

## 5. Pre-built Files

These two files are fully pre-built and available in the repository. Download and place them as shown — do not modify the originals manually.

| File | Destination | Link |
|---|---|---|
| `darwin-init.sh` | `src/init/darwin-init.sh` (replace original) | [darwin-init.sh](https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/macOS/darwin-init.sh) |
| `generate_cybersentinel_packages.sh` | `packages/macos/generate_cybersentinel_packages.sh` (new file) | [generate_cybersentinel_packages.sh](https://github.com/ansh-gadhia/CyberSentinel-Agent-Files/blob/main/macOS/generate_cybersentinel_packages.sh) |

> **Note:** `generate_cybersentinel_packages.sh` fixes the `clean_and_exit` function to use `gmake` instead of `make`, which is required on macOS Catalina where the system `make` is version 3.81 and causes silent exit.

---

## 6. Install Build Dependencies on Intel Mac

Run on the Mac as a **regular user** (not root):

```bash
# Xcode CLI tools
xcode-select --install

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# GNU make and cmake
brew install make cmake

# Verify gmake is version 4+
gmake --version

# munkipkg
git clone https://github.com/munki/munki-pkg.git ~/Developer/munki-pkg
mkdir -p /usr/local/bin
sudo ln -s ~/Developer/munki-pkg/munkipkg /usr/local/bin/munkipkg
munkipkg --version
```

---

## 7. Transfer Source to Intel Mac

After all source edits are done on Linux:

```bash
# On Linux
cd ~/Downloads/mac
zip -r cybersentinel-source.zip wazuh/

# Transfer to Mac (scp, USB, or any method)
scp cybersentinel-source.zip user@mac-ip:~/Agent1/mac/

# On Mac
cd ~/Agent1/mac
unzip cybersentinel-source.zip
```

---

## 8. Build the .pkg

Run on the **Intel Mac**:

```bash
cd ~/Agent1/mac/wazuh/packages/macos/

# Clean any previous build
sudo rm -rf cybersentinel-agent cyb-output/
rm -rf ../../src/syscheckd/build/

# Build
sudo MAKE=gmake ./generate_cybersentinel_packages.sh \
  -a intel64 \
  -s ./cyb-output \
  -j 4 \
  -r 1
```

Build takes 20–40 minutes. On success:

```
cyb-output/cybersentinel-agent_4.14.2-1_intel64_custom.pkg
cyb-output/cybersentinel-agent-debug-symbols-4.14.2-1.intel64-macos.zip
```

---

## 9. Self-Signed Certificate and Signing

### 9.1 Generate Certificate

```bash
mkdir ~/certs && cd ~/certs

# Root CA
openssl genrsa -out macca.key 2048
openssl req -x509 -new -nodes -key macca.key \
  -sha256 -days 1095 \
  -subj "/CN=VGIPLRootCA/O=Virtual Galaxy Infotech Ltd." \
  -out macca.crt

# Signing cert
openssl genrsa -out signing.key 2048
openssl req -new -key signing.key \
  -subj "/CN=CyberSentinel Installer/O=Virtual Galaxy Infotech Ltd." \
  -out signing.csr

openssl x509 -req -in signing.csr \
  -CA macca.crt -CAkey macca.key \
  -CAcreateserial -out signing.crt \
  -days 1095 -sha256

# Export to .p12 — -legacy flag required for macOS Catalina
openssl pkcs12 -legacy -export \
  -inkey signing.key -in signing.crt \
  -certfile macca.crt \
  -out signing.p12
# Enter a password when prompted (e.g. Virtual123)
```

> **⚠️ Always use `-legacy`** when creating `.p12` files for macOS Catalina. Newer OpenSSL defaults to AES-256 encryption which Catalina's `security` tool cannot read, causing `MAC verification failed` errors.

### 9.2 Import into Keychain

```bash
security import ~/certs/signing.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/productsign
# Enter .p12 password when prompted

# Trust the CA system-wide
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/certs/macca.crt

# Verify — should show 1 valid identity
security find-identity -v ~/Library/Keychains/login.keychain-db
```

### 9.3 Sign the .pkg

```bash
# Sign to temp location (cannot overwrite input file)
productsign \
  --sign "CyberSentinel Installer" \
  --keychain ~/Library/Keychains/login.keychain-db \
  ~/Agent1/mac/wazuh/packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_custom.pkg \
  /tmp/cybersentinel-agent_4.14.2-1_intel64_signed.pkg

mv /tmp/cybersentinel-agent_4.14.2-1_intel64_signed.pkg \
   ~/Agent1/mac/wazuh/packages/macos/cyb-output/

# Verify
pkgutil --check-signature \
  ~/Agent1/mac/wazuh/packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_signed.pkg
```

---

## 10. Deployment Bundle

### 10.1 Prepare Files

```bash
mkdir ~/cybersentinel-deploy
cp ~/certs/macca.crt ~/cybersentinel-deploy/ca.crt
cp ~/Agent1/mac/wazuh/packages/macos/cyb-output/cybersentinel-agent_4.14.2-1_intel64_signed.pkg \
   ~/cybersentinel-deploy/
```

### 10.2 Create `deploy.sh`

Create `~/cybersentinel-deploy/deploy.sh` — replace `192.168.1.222` with your manager IP:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MANAGER_IP="192.168.1.222"
AGENT_NAME="$(hostname)"
AGENT_GROUP="macos"

echo "[1/4] Trusting CyberSentinel CA..."
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$SCRIPT_DIR/ca.crt"

echo "[2/4] Verifying certificate..."
security verify-cert -c "$SCRIPT_DIR/ca.crt" -p basic

echo "[3/4] Setting environment variables..."
sudo sh -c "echo \"WAZUH_MANAGER=${MANAGER_IP}\" > /tmp/wazuh_envs"
sudo sh -c "echo \"WAZUH_AGENT_NAME=${AGENT_NAME}\" >> /tmp/wazuh_envs"
sudo sh -c "echo \"WAZUH_AGENT_GROUP=${AGENT_GROUP}\" >> /tmp/wazuh_envs"

echo "[4/4] Installing CyberSentinel Agent..."
sudo installer -pkg "$SCRIPT_DIR/cybersentinel-agent_4.14.2-1_intel64_signed.pkg" -target /

sudo rm -f /tmp/wazuh_envs
echo "✅ CyberSentinel Agent installed successfully."
```

```bash
chmod +x ~/cybersentinel-deploy/deploy.sh
cd ~ && zip -r cybersentinel-deploy-macos.zip cybersentinel-deploy/
```

### 10.3 Deploy on Target Mac

```bash
unzip cybersentinel-deploy-macos.zip
cd cybersentinel-deploy
sudo bash deploy.sh
```

---

## 11. Managing the Agent

### Make Control Script Globally Accessible

> **⚠️ Use a wrapper script, not a symlink.** The control script resolves daemon paths relative to its own directory. A symlink from `/usr/local/bin/` causes it to look in the wrong place for PID files and binaries.

```bash
sudo tee /usr/local/bin/cybersentinel-control << 'EOF'
#!/bin/bash
exec /Library/Ossec/bin/cybersentinel-control "$@"
EOF
sudo chmod +x /usr/local/bin/cybersentinel-control
```

### Control Commands

| Action | Command |
|---|---|
| Status | `sudo cybersentinel-control status` |
| Start | `sudo cybersentinel-control start` |
| Stop | `sudo cybersentinel-control stop` |
| Restart | `sudo cybersentinel-control restart` |
| Enable at boot | `sudo launchctl load -w /Library/LaunchDaemons/com.cybersentinel.agent.plist` |
| Disable at boot | `sudo launchctl unload -w /Library/LaunchDaemons/com.cybersentinel.agent.plist` |

### Key Paths

| Item | Path |
|---|---|
| Config | `/Library/Ossec/etc/ossec.conf` |
| Agent keys | `/Library/Ossec/etc/client.keys` |
| Logs | `/Library/Ossec/logs/ossec.log` |
| Live log | `sudo tail -f /Library/Ossec/logs/ossec.log` |
| LaunchDaemon | `/Library/LaunchDaemons/com.cybersentinel.agent.plist` |
| Binaries | `/Library/Ossec/bin/` |

---

## 12. Uninstall

```bash
sudo launchctl unload /Library/LaunchDaemons/com.cybersentinel.agent.plist 2>/dev/null || true
sudo /Library/Ossec/bin/cybersentinel-control stop 2>/dev/null || true
sudo rm -rf /Library/Ossec
sudo rm -f /Library/LaunchDaemons/com.cybersentinel.agent.plist
sudo rm -rf /Library/StartupItems/CYBERSENTINEL
sudo rm -f /usr/local/bin/cybersentinel-control
sudo dscl . -delete /Users/cybersentinel 2>/dev/null || true
sudo dscl . -delete /Groups/cybersentinel 2>/dev/null || true
sudo pkgutil --forget com.cybersentinel.pkg.cybersentinel-agent 2>/dev/null || true
sudo pkgutil --forget com.cybersentinel.pkg.cybersentinel-agent-etc 2>/dev/null || true
```

---

## 13. Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `CRITICAL: Invalid user '' or group 'wazuh'` | `build.sh` missing `WAZUH_GROUP=cybersentinel` | Add flag to gmake line in `build.sh` and rebuild |
| `Makefile:797: missing separator. Stop.` | `BUILD_SERVER+=` has `wazuh-reportd` on the next line — broken line | Join them: `BUILD_SERVER+=wazuh-reportd` |
| `MAC verification failed during PKCS12 import` | `.p12` created with AES-256 (new OpenSSL default), incompatible with Catalina | Recreate with `openssl pkcs12 -legacy -export ...` |
| `cybersentinel-syscheckd: No such file or directory` | `CMakeLists.txt` has `add_executable(cybersentinel-syscheckd)` but `target_link_libraries` still references `wazuh-syscheckd` | Change all `target_link_libraries(wazuh-syscheckd ...)` → `cybersentinel-syscheckd` and delete `syscheckd/build/` |
| `generate_cybersentinel_packages.sh` exits with no output | `clean_and_exit` calls `make` (v3.81 fails under `set -e`) | Use the pre-built script from the repository |
| `sudo cybersentinel-control` shows wrong status | Symlink causes wrong base directory for PID lookup | Replace symlink with wrapper script — see [Section 11](#11-managing-the-agent) |
| Stale PID files prevent start | Previous failed starts left PID files | `sudo rm -f /Library/Ossec/var/run/*.pid` |
| Agent starts but disconnects every ~60 seconds | Manager unreachable on port 1514 | Check firewall rules and that the Wazuh manager is running |

---

## 14. Complete File Change Summary

| File | Lines | What Changed |
|---|---|---|
| `src/headers/defs.h` | 71–74 | `__ossec_name`, `__author`, `__contact`, `__site` |
| `src/Makefile` | 807–814, 2086, 2094–2100, 2107–2116, 2132–2138, 2309, 2470 | BUILD_AGENT targets, ARGV0 flags, binary target names |
| `src/client-agent/main.c` | 21 | ARGV0 `wazuh-agentd` → `cybersentinel-agentd` |
| `src/client-agent/agentd.c` | 70 | Log message branding |
| `src/client-agent/notify.c` | 113 | Log message branding |
| `src/client-agent/buffer.c` | 209, 217, 225, 233 | 4× `wazuh-agent` → `cybersentinel-agent` |
| `src/client-agent/receiver.c` | 125, 288 | Log message + `wazuh-agent` → `cybersentinel-agent` |
| `src/client-agent/reload_agent.c` | 22, 73–85 | `AG_IN_RCON` + 7× `wazuh-agent` → `cybersentinel-agent` |
| `src/client-agent/start_agent.c` | 405 | `wazuh-agent` → `cybersentinel-agent` |
| `src/wazuh_modules/wmodules_def.h` | 24 | ARGV0 `wazuh-modulesd` → `cybersentinel-modulesd` |
| `src/shared_modules/content_manager/include/sharedDefs.hpp` | 20 | `WM_CONTENTUPDATER` |
| `src/wazuh_modules/vulnerability_scanner/include/vulnerabilityScannerDefs.hpp` | 16 | `WM_VULNSCAN_LOGTAG` |
| `src/os_execd/wcom.c` | 385 | Daemon whitelist: `bin/wazuh-syscheckd` → `bin/cybersentinel-syscheckd` |
| `src/syscheckd/CMakeLists.txt` | 3, 37, 88, 91, 94, 97, 105, 117, 125, 128, 132 | project name, ARGV0, executable, all `target_link_libraries` |
| `src/init/inst-functions.sh` | 760, 969–976, 1422 | Control script source, all binary install commands |
| `src/init/init.sh` | 177, 180, 191, 194 | `wazuh-control` → `cybersentinel-control` |
| `src/init/cybersentinel-client.sh` | — | New file (rebranded `wazuh-client.sh`) |
| `etc/preloaded-vars.conf` | entire file | Replaced with minimal agent config |
| `packages/macos/package_files/introduction.txt` | entire file | Full branding update |
| `packages/macos/package_files/build.sh` | 41, 43–44 | `make` → `gmake`, `WAZUH_GROUP/USER` flags |
| `packages/macos/package_files/postinstall.sh` | 11–12, 92, 96, 131, 160–164, 180 | GROUP/USER, chown, LaunchDaemon path, messages |
| `packages/macos/package_files/preinstall.sh` | 42, 51, 53, 66–67, 75–77, 104, 121–154 | All user/group/binary/path references |
| `packages/macos/specs/build-info.json` | 7 | `identifier` |
| `packages/macos/uninstall.sh` | throughout | All `wazuh` → `cybersentinel` references |
| `packages/macos/darwin-init.sh` | entire file | Pre-built from repository |
| `packages/macos/generate_cybersentinel_packages.sh` | entire file | Pre-built from repository |

---

*CyberSentinel Agent macOS Intel x64 Build Guide — Virtual Galaxy Infotech Ltd.*
