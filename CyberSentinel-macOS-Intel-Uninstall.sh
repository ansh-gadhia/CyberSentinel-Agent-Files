#!/bin/bash

# ============================================================
# CyberSentinel Uninstaller — macOS (Intel)
# Removes everything installed by CyberSentinel-macOS-Intel-Install.sh:
#   • CyberSentinel agent (pkg + /Library/Ossec)
#   • launchd daemon plist
#   • cybersentinel-control symlink
#   • YARA build (/opt/cybersentinel/yara) and rules
#   • Suricata build + config + logs + rules
#   • CA certificate from System Keychain
#   • Install log directory (/opt/cybersentinel)
#   • Any stale Wazuh remnants (belt-and-suspenders)
# ============================================================

OSSEC_DIR="/Library/Ossec"
CS_PLIST="/Library/LaunchDaemons/com.cybersentinel.agent.plist"
CONTROL_BIN="/usr/local/bin/cybersentinel-control"
YARA_PREFIX="/opt/cybersentinel/yara"
LOG_DIR="/opt/cybersentinel"
SURICATA_VERSION="8.0.3"   # must match what the installer used

# ============================================================
# Colours
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}\n  ${BOLD}${1}${NC}\n${CYAN}══════════════════════════════════════════${NC}"; }
success() { echo -e "  ${GREEN}✔ ${1}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${1}${NC}"; }
error()   { echo -e "  ${RED}✘ ${1}${NC}" >&2; }
skipped() { echo -e "  ${CYAN}– ${1} (not found — skipped)${NC}"; }

spinner() {
    local pid=$1 msg="${2:-Working}" delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 len=10
    printf "  ${CYAN}${msg}${NC} "
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinstr:$((i % len)):1}"
        printf "\r  ${CYAN}${msg}${NC} [${YELLOW}${char}${NC}]"
        i=$((i + 1)); sleep $delay
    done
    wait "$pid"; local ec=$?
    if [ $ec -eq 0 ]; then
        printf "\r  ${CYAN}${msg}${NC} [${GREEN}✔${NC}]\n"
    else
        printf "\r  ${CYAN}${msg}${NC} [${RED}✘${NC}]\n"
    fi
    return $ec
}

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

# ============================================================
# macOS Intel guard
# ============================================================
if [ "$(uname -m)" != "x86_64" ]; then
    echo -e "${RED}This uninstaller is for Intel (x86_64) Macs only.${NC}"
    exit 1
fi

# ============================================================
# Banner
# ============================================================
echo -e "${CYAN}${BOLD}"
echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
echo "    S E N T I N E L   U N I N S T A L L E R"
echo "           macOS Intel Edition"
echo -e "${NC}"

# ============================================================
# Pre-flight: detect what is actually installed
# ============================================================
step "Pre-flight │ Installed Component Detection"

FOUND_AGENT=false
FOUND_PLIST=false
FOUND_CONTROL=false
FOUND_YARA=false
FOUND_SURICATA=false
FOUND_CERT=false
FOUND_WAZUH_REMNANT=false

[ -d "$OSSEC_DIR" ]       && FOUND_AGENT=true
[ -f "$CS_PLIST" ]        && FOUND_PLIST=true
[ -f "$CONTROL_BIN" ]     && FOUND_CONTROL=true
[ -d "$YARA_PREFIX" ]     && FOUND_YARA=true
command -v suricata &>/dev/null && FOUND_SURICATA=true

# Check for CA cert in System Keychain by subject/label
security find-certificate -c "CyberSentinel" \
    /Library/Keychains/System.keychain &>/dev/null && FOUND_CERT=true

# Stale Wazuh remnant check
if launchctl list 2>/dev/null | grep -q "com.wazuh.agent" || \
   pkgutil --pkg-info com.wazuh.pkg.wazuh-agent &>/dev/null 2>&1 || \
   [ -f "/Library/LaunchDaemons/com.wazuh.agent.plist" ]; then
    FOUND_WAZUH_REMNANT=true
fi

# Display what was found
echo ""
printf "  %-35s %b\n" "CyberSentinel agent ($OSSEC_DIR)" "$($FOUND_AGENT  && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
printf "  %-35s %b\n" "launchd plist"                    "$($FOUND_PLIST  && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
printf "  %-35s %b\n" "cybersentinel-control binary"     "$($FOUND_CONTROL && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
printf "  %-35s %b\n" "YARA ($YARA_PREFIX)"              "$($FOUND_YARA && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
printf "  %-35s %b\n" "Suricata"                         "$($FOUND_SURICATA && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
printf "  %-35s %b\n" "CA certificate (System Keychain)" "$($FOUND_CERT && echo "${GREEN}found${NC}" || echo "${YELLOW}not found${NC}")"
if $FOUND_WAZUH_REMNANT; then
    printf "  %-35s %b\n" "Stale Wazuh remnant" "${YELLOW}found — will clean${NC}"
fi
echo -e "${NC}"

# Abort if nothing to remove
if ! $FOUND_AGENT && ! $FOUND_PLIST && ! $FOUND_CONTROL && \
   ! $FOUND_YARA  && ! $FOUND_SURICATA && ! $FOUND_CERT && \
   ! $FOUND_WAZUH_REMNANT; then
    warn "Nothing to uninstall — no CyberSentinel components detected."
    exit 0
fi

# ============================================================
# Confirmation prompt
# Opens /dev/tty so the read works even when stdin is a pipe
# (e.g. curl … | sudo bash)
# ============================================================
echo -e "  ${BOLD}${RED}This will permanently remove all CyberSentinel"
echo -e "  components listed above from this machine.${NC}"
echo ""

exec 3</dev/tty
read -p "  Are you sure you want to proceed? (yes/no): " CONFIRM <&3
exec 3<&-

if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "\n${YELLOW}  Uninstallation cancelled. No changes made.${NC}\n"
    exit 0
fi

# ============================================================
# STEP 1 — Stop and unload the agent daemon
# ============================================================
step "Step 1 │ Stopping CyberSentinel Agent"

if $FOUND_PLIST; then
    launchctl unload -w "$CS_PLIST" &>/dev/null && \
        success "com.cybersentinel.agent daemon unloaded." || \
        warn    "launchctl unload returned non-zero (may already be stopped)."
    sleep 2
else
    skipped "com.cybersentinel.agent plist"
fi

# Belt-and-suspenders: stop via control binary if the agent process is still up
if [ -x "$OSSEC_DIR/bin/cybersentinel-control" ]; then
    "$OSSEC_DIR/bin/cybersentinel-control" stop &>/dev/null || true
    sleep 1
fi

# ============================================================
# STEP 2 — Remove launchd plist
# ============================================================
step "Step 2 │ Removing launchd Plist"

if $FOUND_PLIST; then
    rm -f "$CS_PLIST"
    success "Removed: $CS_PLIST"
else
    skipped "$CS_PLIST"
fi

# ============================================================
# STEP 3 — Remove agent package and directory
# ============================================================
step "Step 3 │ Removing Agent Package"

# Forget pkg receipt (suppresses macOS "still installed" warnings)
if pkgutil --pkg-info com.cybersentinel.pkg.agent &>/dev/null 2>&1; then
    pkgutil --forget com.cybersentinel.pkg.agent &>/dev/null && \
        success "Package receipt forgotten (com.cybersentinel.pkg.agent)." || \
        warn    "pkgutil --forget returned non-zero."
else
    skipped "Package receipt (com.cybersentinel.pkg.agent)"
fi

if $FOUND_AGENT; then
    job_pid=""
    (rm -rf "$OSSEC_DIR") &
    job_pid=$!
    spinner $job_pid "Removing $OSSEC_DIR"
    if [ $? -eq 0 ]; then
        success "Removed: $OSSEC_DIR"
    else
        error "Failed to fully remove $OSSEC_DIR — check for locked files."
    fi
else
    skipped "$OSSEC_DIR"
fi

# ============================================================
# STEP 4 — Remove cybersentinel-control symlink
# ============================================================
step "Step 4 │ Removing Control Binary"

if $FOUND_CONTROL; then
    rm -f "$CONTROL_BIN"
    success "Removed: $CONTROL_BIN"
else
    skipped "$CONTROL_BIN"
fi

# ============================================================
# STEP 5 — Remove YARA
# ============================================================
step "Step 5 │ Removing YARA"

if $FOUND_YARA; then
    (rm -rf "$YARA_PREFIX") &
    spinner $! "Removing YARA prefix ($YARA_PREFIX)"
    success "Removed: $YARA_PREFIX"
else
    skipped "$YARA_PREFIX"
fi

# Remove YARA rules directory (lives inside OSSEC_DIR, already gone,
# but clean up standalone path if it somehow exists separately)
YARA_RULES_DIR="/Library/Ossec/ruleset/yara"
if [ -d "$YARA_RULES_DIR" ]; then
    rm -rf "$YARA_RULES_DIR"
    success "Removed: $YARA_RULES_DIR"
fi

# ============================================================
# STEP 6 — Remove Suricata
# ============================================================
step "Step 6 │ Removing Suricata"

if $FOUND_SURICATA; then
    # Binaries installed by make install on Intel macOS
    for bin in suricata suricatasc suricata-update; do
        BIN_PATH="/usr/local/bin/$bin"
        if [ -f "$BIN_PATH" ]; then
            rm -f "$BIN_PATH"
            success "Removed: $BIN_PATH"
        else
            skipped "$BIN_PATH"
        fi
    done

    # Remove shared libraries installed by make install
    for lib in libhtp.a libhtp.la; do
        LIB_PATH="/usr/local/lib/$lib"
        [ -f "$LIB_PATH" ] && rm -f "$LIB_PATH" && success "Removed: $LIB_PATH"
    done
    LIB_HTP_DIR="/usr/local/include/htp"
    [ -d "$LIB_HTP_DIR" ] && rm -rf "$LIB_HTP_DIR" && success "Removed: $LIB_HTP_DIR"
else
    skipped "Suricata binaries"
fi

# Config and rules — remove regardless of binary presence
if [ -d "/etc/suricata" ]; then
    (rm -rf /etc/suricata) &
    spinner $! "Removing /etc/suricata"
    success "Removed: /etc/suricata"
else
    skipped "/etc/suricata"
fi

if [ -d "/var/log/suricata" ]; then
    (rm -rf /var/log/suricata) &
    spinner $! "Removing /var/log/suricata"
    success "Removed: /var/log/suricata"
else
    skipped "/var/log/suricata"
fi

# Remove the Suricata source directory if the user aborted mid-build
# and it wasn't cleaned up (lives in the real user's HOME, not root)
REAL_USER="${SUDO_USER:-}"
if [ -n "$REAL_USER" ]; then
    REAL_HOME=$(eval echo "~$REAL_USER")
    SURI_SRC="${REAL_HOME}/suricata-${SURICATA_VERSION}"
    if [ -d "$SURI_SRC" ]; then
        (rm -rf "$SURI_SRC") &
        spinner $! "Removing leftover Suricata source ($SURI_SRC)"
        success "Removed: $SURI_SRC"
    fi
fi

# ============================================================
# STEP 7 — Remove CA certificate from System Keychain
# ============================================================
step "Step 7 │ Removing CA Certificate"

if $FOUND_CERT; then
    # Find and delete all certs with "CyberSentinel" in the subject from the System keychain
    # security delete-certificate doesn't support -c directly for System keychain deletions,
    # so we iterate over SHA-1 hashes of matching certs.
    CERT_HASHES=$(security find-certificate -c "CyberSentinel" -Z \
        /Library/Keychains/System.keychain 2>/dev/null | \
        awk '/SHA-1/{print $NF}')

    if [ -n "$CERT_HASHES" ]; then
        while IFS= read -r hash; do
            security delete-certificate -Z "$hash" \
                /Library/Keychains/System.keychain 2>/dev/null && \
                success "Removed certificate (SHA-1: ${hash:0:16}...)" || \
                warn    "Could not remove certificate hash $hash — may require manual removal."
        done <<< "$CERT_HASHES"
    else
        warn "Certificate found earlier but hash lookup returned nothing — skipping."
    fi
else
    skipped "CyberSentinel CA certificate (System Keychain)"
fi

# ============================================================
# STEP 8 — Remove stale Wazuh remnants (if any)
# ============================================================
step "Step 8 │ Stale Wazuh Remnant Cleanup"

if $FOUND_WAZUH_REMNANT; then
    launchctl unload /Library/LaunchDaemons/com.wazuh.agent.plist 2>/dev/null || true
    rm -f /Library/LaunchDaemons/com.wazuh.agent.plist
    pkgutil --forget com.wazuh.pkg.wazuh-agent 2>/dev/null || true
    success "Stale Wazuh remnants removed."
else
    skipped "Stale Wazuh remnants"
fi

# ============================================================
# STEP 9 — Temp file sweep
# Catches anything the installer may have left behind if it
# was interrupted before its own cleanup ran.
# ============================================================
step "Step 9 │ Temp File Sweep"

SWEPT=0
for artifact in \
    /tmp/cybersentinel-agent.pkg \
    /tmp/macca.crt \
    /tmp/wazuh_envs \
    /tmp/emerging.rules.tar.gz \
    /tmp/rules \
    /tmp/yara-src \
    /tmp/.cs_curl_*; do
    # glob expands — use nullglob-style test
    for f in $artifact; do
        if [ -e "$f" ]; then
            rm -rf "$f"
            success "Swept: $f"
            SWEPT=$((SWEPT + 1))
        fi
    done
done

[ $SWEPT -eq 0 ] && skipped "Temp artifacts (none found)"

# ============================================================
# STEP 10 — Remove install log directory
# /opt/cybersentinel contains YARA prefix + install log.
# YARA was removed in Step 5, so if the directory is now empty
# (or only has the log) remove it entirely.
# ============================================================
step "Step 10 │ Removing Install Log Directory"

if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
    success "Removed: $LOG_DIR"
else
    skipped "$LOG_DIR"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   CyberSentinel Uninstallation Complete      ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  All CyberSentinel components have been removed."
echo ""

# Post-removal verification
REMAINING=()
[ -d "$OSSEC_DIR" ]   && REMAINING+=("$OSSEC_DIR still present")
[ -f "$CS_PLIST" ]    && REMAINING+=("$CS_PLIST still present")
[ -f "$CONTROL_BIN" ] && REMAINING+=("$CONTROL_BIN still present")
[ -d "$YARA_PREFIX" ] && REMAINING+=("$YARA_PREFIX still present")
command -v suricata &>/dev/null && REMAINING+=("suricata binary still in PATH")
[ -d "/etc/suricata" ] && REMAINING+=("/etc/suricata still present")

if [ ${#REMAINING[@]} -gt 0 ]; then
    warn "The following items could not be fully removed:"
    for item in "${REMAINING[@]}"; do
        echo -e "  ${RED}  • $item${NC}"
    done
    echo ""
    warn "These may require manual removal or a reboot to release file locks."
else
    echo -e "  ${GREEN}${BOLD}Verification passed — no CyberSentinel artifacts remain. ✔${NC}"
fi

echo ""
echo -e "  ${YELLOW}Note: Homebrew and its packages (openssl, automake, etc.)${NC}"
echo -e "  ${YELLOW}were NOT removed as they may be used by other software.${NC}"
echo -e "  ${YELLOW}Run 'brew uninstall <package>' manually if needed.${NC}"
echo ""