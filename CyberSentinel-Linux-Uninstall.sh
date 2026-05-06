#!/bin/bash

# ============================================================
# CyberSentinel Uninstaller Script for Ubuntu  (PATCHED)
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/uninstall.log"
BIN_DIR="/var/ossec/active-response/bin"
LOGROTATE_CONF="/etc/logrotate.d/cybersentinel"

# ============================================================
# Colours
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Helpers
# ============================================================

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
    echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
    echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
    echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
    echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
    echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
    echo "       S E N T I N E L   U N I N S T A L L E R"
    echo -e "${NC}"
}

spinner() {
    local pid=$1
    local msg="${2:-Working}"
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local len=${#spinstr}
    printf "  ${CYAN}${msg}${NC} "
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinstr:$((i % len)):1}"
        printf "\r  ${CYAN}${msg}${NC} [${YELLOW}${char}${NC}]"
        i=$((i + 1))
        sleep $delay
    done
    wait "$pid"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r  ${CYAN}${msg}${NC} [${GREEN}✔${NC}]\n"
    else
        printf "\r  ${CYAN}${msg}${NC} [${RED}✘${NC}]\n"
    fi
    return $exit_code
}

step() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}${1}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
}

success() { echo -e "  ${GREEN}✔ ${1}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${1}${NC}"; }
error()   { echo -e "  ${RED}✘ ${1}${NC}" >&2; }

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

# ============================================================
# Setup log dir
# ============================================================
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

print_banner

# Redirect all further output to log while keeping console output
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "  ${BOLD}Uninstall started: $(date)${NC}"

# ============================================================
# Confirmation prompt
# ============================================================
echo ""
echo -e "  ${YELLOW}${BOLD}WARNING: This will completely remove CyberSentinel Agent${NC}"
echo -e "  ${YELLOW}and all associated components from this system:${NC}"
echo ""
echo -e "  • CyberSentinel / Wazuh Agent (service + package)"
echo -e "  • YARA (compiled from source)"
echo -e "  • Suricata IDS (package + rules + config)"
echo -e "  • Active response scripts"
echo -e "  • Log rotation config"
echo -e "  • CyberSentinel log directory (optional)"
echo ""
read -p "  Are you sure you want to continue? [yes/no]: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "\n${YELLOW}Uninstallation cancelled. Goodbye!${NC}\n"
    exit 0
fi

echo ""
read -p "  Also remove all CyberSentinel logs in ${LOG_DIR}? [yes/no]: " REMOVE_LOGS
echo ""

# ============================================================
# STEP 1 — Stop & disable CyberSentinel / Wazuh Agent service
# ============================================================
step "Step 1 │ Stopping CyberSentinel Agent Service"

for svc in cybersentinel-agent wazuh-agent; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" &>>"$LOG_FILE"
        success "$svc stopped."
    else
        warn "$svc was not running."
    fi

    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable "$svc" &>>"$LOG_FILE"
        success "$svc disabled from startup."
    fi
done

# Kill any lingering wazuh/ossec processes that block the dpkg purge
echo -e "  ${BOLD}Checking for lingering Wazuh/OSSEC processes...${NC}"
KILLED_ANY=false
for proc in wazuh-agentd wazuh-execd wazuh-syscheckd wazuh-logcollector \
            wazuh-modulesd ossec-agentd ossec-execd ossec-syscheckd \
            ossec-logcollector; do
    if pgrep -x "$proc" &>/dev/null; then
        pkill -9 -x "$proc" &>>"$LOG_FILE" || true
        success "Killed lingering process: $proc"
        KILLED_ANY=true
    fi
done

# Catch-all for anything else with "wazuh" in the name
if pgrep -f wazuh &>/dev/null; then
    pkill -9 -f wazuh &>>"$LOG_FILE" || true
    success "Killed remaining wazuh-* processes."
    KILLED_ANY=true
fi

$KILLED_ANY && sleep 2 || warn "No lingering processes found."

# ============================================================
# STEP 2 — Remove systemd service file
# ============================================================
step "Step 2 │ Removing Systemd Service"

SERVICE_DST="/etc/systemd/system/cybersentinel-agent.service"

if [ -f "$SERVICE_DST" ]; then
    rm -f "$SERVICE_DST" &>>"$LOG_FILE"
    success "Removed: $SERVICE_DST"
else
    warn "Service file not found (already removed?): $SERVICE_DST"
fi

systemctl daemon-reload &>>"$LOG_FILE"
systemctl reset-failed &>>"$LOG_FILE" 2>/dev/null || true
success "Systemd daemon reloaded."

# ============================================================
# STEP 3 — Purge Wazuh Agent package & ossec data
# ============================================================
step "Step 3 │ Removing Wazuh Agent Package"

# Check ANY dpkg state — installed, half-installed, config-files-only, etc.
PKG_STATE=$(dpkg-query -W -f='${db:Status-Abbrev}' wazuh-agent 2>/dev/null | tr -d ' ')

if [ -n "$PKG_STATE" ]; then
    echo "  Current package state: '$PKG_STATE'" | tee -a "$LOG_FILE"

    # First attempt — clean purge in foreground (real exit code, no spinner masking)
    echo -e "  ${BOLD}Attempt 1: Standard purge...${NC}"
    if DEBIAN_FRONTEND=noninteractive dpkg --purge wazuh-agent &>>"$LOG_FILE"; then
        success "wazuh-agent purged cleanly."
    else
        warn "Standard purge failed — trying with --force-all."

        # Second attempt — force-all bypasses most failure conditions
        echo -e "  ${BOLD}Attempt 2: Forced purge...${NC}"
        DEBIAN_FRONTEND=noninteractive dpkg --purge --force-all wazuh-agent &>>"$LOG_FILE" || true

        # If still present, the postrm/prerm script is the blocker — neutralise it
        if dpkg-query -W -f='${db:Status-Abbrev}' wazuh-agent 2>/dev/null | grep -q .; then
            warn "Package still present — neutralising maintainer scripts."
            rm -f /var/lib/dpkg/info/wazuh-agent.postrm \
                  /var/lib/dpkg/info/wazuh-agent.prerm \
                  /var/lib/dpkg/info/wazuh-agent.postinst \
                  /var/lib/dpkg/info/wazuh-agent.preinst

            echo -e "  ${BOLD}Attempt 3: Forced purge after script removal...${NC}"
            DEBIAN_FRONTEND=noninteractive dpkg --purge --force-all wazuh-agent &>>"$LOG_FILE" || true
        fi

        # Last resort — manually scrub dpkg's database entry
        if dpkg-query -W -f='${db:Status-Abbrev}' wazuh-agent 2>/dev/null | grep -q .; then
            warn "Package still in dpkg DB — manually clearing entries."
            rm -f /var/lib/dpkg/info/wazuh-agent.* 2>/dev/null || true
            # Edit the status file to remove the wazuh-agent stanza
            if [ -f /var/lib/dpkg/status ]; then
                cp /var/lib/dpkg/status /var/lib/dpkg/status.cybersentinel-bak
                awk 'BEGIN{RS=""; ORS="\n\n"} !/^Package: wazuh-agent/' \
                    /var/lib/dpkg/status > /var/lib/dpkg/status.new \
                    && mv /var/lib/dpkg/status.new /var/lib/dpkg/status
                success "Manually scrubbed wazuh-agent from dpkg status."
            fi
        fi
    fi

    # Final verification
    if dpkg-query -W -f='${db:Status-Abbrev}' wazuh-agent 2>/dev/null | grep -q .; then
        error "wazuh-agent could not be fully removed — manual intervention required."
        error "Check $LOG_FILE for details."
    else
        success "wazuh-agent fully purged."
    fi
else
    warn "wazuh-agent package not present."
fi

# Remove leftover ossec directories
for DIR in /var/ossec /etc/ossec-init.conf /var/log/wazuh /var/run/wazuh /run/wazuh; do
    if [ -e "$DIR" ]; then
        rm -rf "$DIR" &>>"$LOG_FILE"
        success "Removed: $DIR"
    fi
done

# Final cleanup of any remaining dpkg metadata
rm -f /var/lib/dpkg/info/wazuh-agent.* 2>/dev/null || true

# Remove any leftover .deb files (any version)
shopt -s nullglob
DEB_LEFTOVERS=(/tmp/wazuh-agent_*.deb)
shopt -u nullglob
if [ ${#DEB_LEFTOVERS[@]} -gt 0 ]; then
    rm -f "${DEB_LEFTOVERS[@]}"
    success "Removed leftover package(s): ${DEB_LEFTOVERS[*]}"
fi

# Remove the wazuh user/group if they exist (created by the package)
if id wazuh &>/dev/null; then
    userdel wazuh &>>"$LOG_FILE" || true
    success "Removed 'wazuh' user."
fi
if getent group wazuh &>/dev/null; then
    groupdel wazuh &>>"$LOG_FILE" || true
    success "Removed 'wazuh' group."
fi

# ============================================================
# STEP 4 — Remove YARA
# ============================================================
step "Step 4 │ Removing YARA"

YARA_BINS=(yara yarac)
for bin in "${YARA_BINS[@]}"; do
    BIN_PATH=$(command -v "$bin" 2>/dev/null || true)
    if [ -n "$BIN_PATH" ]; then
        rm -f "$BIN_PATH"
        success "Removed binary: $BIN_PATH"
    else
        warn "Binary not found (skipping): $bin"
    fi
done

# Remove YARA libraries installed by 'make install' (use globbing properly)
shopt -s nullglob
YARA_LIBS=(/usr/local/lib/libyara* /usr/lib/libyara* /usr/lib/x86_64-linux-gnu/libyara*)
shopt -u nullglob
if [ ${#YARA_LIBS[@]} -gt 0 ]; then
    for LIB in "${YARA_LIBS[@]}"; do
        rm -f "$LIB"
        success "Removed library: $LIB"
    done
fi

# Remove YARA headers
if [ -d /usr/local/include/yara ]; then
    rm -rf /usr/local/include/yara
    success "Removed YARA headers: /usr/local/include/yara"
fi
for HEADER in /usr/local/include/yara.h /usr/include/yara.h; do
    if [ -f "$HEADER" ]; then
        rm -f "$HEADER"
        success "Removed header: $HEADER"
    fi
done

# Remove pkgconfig entry
for PC_FILE in /usr/local/lib/pkgconfig/yara.pc /usr/lib/pkgconfig/yara.pc; do
    if [ -f "$PC_FILE" ]; then
        rm -f "$PC_FILE"
        success "Removed pkgconfig: $PC_FILE"
    fi
done

# Remove YARA source/build dirs from the installer
shopt -s nullglob
YARA_SRC_DIRS=(/usr/local/bin/yara-* /tmp/yara-build /tmp/yara /tmp/v*.tar.gz)
shopt -u nullglob
for DIR in "${YARA_SRC_DIRS[@]}"; do
    if [ -e "$DIR" ]; then
        rm -rf "$DIR"
        success "Removed: $DIR"
    fi
done

# Update shared library cache
ldconfig &>>"$LOG_FILE"
success "Shared library cache updated."

# ============================================================
# STEP 5 — Stop & Remove Suricata
# ============================================================
step "Step 5 │ Removing Suricata IDS"

if systemctl is-active --quiet suricata 2>/dev/null; then
    systemctl stop suricata &>>"$LOG_FILE"
    success "Suricata stopped."
else
    warn "Suricata was not running."
fi

if systemctl is-enabled --quiet suricata 2>/dev/null; then
    systemctl disable suricata &>>"$LOG_FILE"
    success "Suricata disabled from startup."
fi

# Kill any lingering suricata processes
if pgrep -x suricata &>/dev/null; then
    pkill -9 -x suricata &>>"$LOG_FILE" || true
    success "Killed lingering suricata process."
    sleep 1
fi

if dpkg-query -W -f='${db:Status-Abbrev}' suricata 2>/dev/null | grep -q .; then
    echo -e "  ${BOLD}Purging Suricata package...${NC}"
    if ! DEBIAN_FRONTEND=noninteractive apt-get purge suricata -y &>>"$LOG_FILE"; then
        warn "apt purge failed — falling back to forced dpkg purge."
        DEBIAN_FRONTEND=noninteractive dpkg --purge --force-all suricata &>>"$LOG_FILE" || true
    fi

    if dpkg-query -W -f='${db:Status-Abbrev}' suricata 2>/dev/null | grep -q .; then
        error "Suricata could not be fully removed — check $LOG_FILE."
    else
        success "Suricata package purged."
    fi
else
    warn "Suricata package not found (already removed?)."
fi

# Remove Suricata config & rules directories
for DIR in /etc/suricata /var/log/suricata /var/lib/suricata /run/suricata; do
    if [ -e "$DIR" ]; then
        rm -rf "$DIR" &>>"$LOG_FILE"
        success "Removed: $DIR"
    fi
done

# Remove leftover Emerging Threats rules tarball
if [ -f /tmp/emerging.rules.tar.gz ]; then
    rm -f /tmp/emerging.rules.tar.gz
    success "Removed leftover Suricata rules archive."
fi
if [ -d /tmp/rules ]; then
    rm -rf /tmp/rules
    success "Removed leftover /tmp/rules directory."
fi

# Remove Suricata PPA — use ls properly without the broken [ -f ] glob test
if ls /etc/apt/sources.list.d/oisf* &>/dev/null; then
    add-apt-repository --remove -y ppa:oisf/suricata-stable &>>"$LOG_FILE"
    success "Suricata PPA removed."
    # Belt-and-braces: nuke any leftover list files
    rm -f /etc/apt/sources.list.d/oisf* 2>/dev/null
else
    warn "Suricata PPA not found (skipping)."
fi

apt-get autoremove -y &>>"$LOG_FILE" &
spinner $! "Running apt autoremove"

apt-get update -qq &>>"$LOG_FILE" &
spinner $! "Updating package lists"

# ============================================================
# STEP 6 — Remove Active Response Scripts
# ============================================================
step "Step 6 │ Removing Active Response Scripts"

# Note: $BIN_DIR is under /var/ossec, which Step 3 already wiped.
# This step is a safety net for unusual cases where /var/ossec survived.
for file in llm_query.py remove-threat.sh yara.sh; do
    TARGET="$BIN_DIR/$file"
    if [ -f "$TARGET" ]; then
        rm -f "$TARGET"
        success "Removed: $TARGET"
    else
        warn "Not found (skipping): $TARGET"
    fi
done

# Remove the bin dir itself if empty
if [ -d "$BIN_DIR" ] && [ -z "$(ls -A "$BIN_DIR" 2>/dev/null)" ]; then
    rm -rf "$BIN_DIR"
    success "Removed empty directory: $BIN_DIR"
fi

# ============================================================
# STEP 7 — Remove Log Rotation Config
# ============================================================
step "Step 7 │ Removing Log Rotation Config"

if [ -f "$LOGROTATE_CONF" ]; then
    rm -f "$LOGROTATE_CONF"
    success "Removed: $LOGROTATE_CONF"
else
    warn "Log rotation config not found (skipping): $LOGROTATE_CONF"
fi

# ============================================================
# STEP 8 — Optionally remove CyberSentinel log directory
# ============================================================
step "Step 8 │ CyberSentinel Log Directory"

if [[ "$REMOVE_LOGS" == "yes" ]]; then
    echo "Uninstall completed: $(date)" >> "$LOG_FILE"
    rm -rf "$LOG_DIR"
    echo -e "  ${GREEN}✔ Removed log directory: ${LOG_DIR}${NC}"
else
    success "Log directory preserved: ${LOG_DIR}"
    success "Uninstall log saved to: ${LOG_FILE}"
fi

# ============================================================
# STEP 9 — Post-Uninstall Verification
# ============================================================
step "Step 9 │ Post-Uninstall Verification"

sleep 1

ERRORS=0

# Wazuh/CyberSentinel agent — check ANY dpkg state, not just installed
if dpkg-query -W -f='${db:Status-Abbrev}' wazuh-agent 2>/dev/null | grep -q .; then
    warn "wazuh-agent package still present in dpkg database."
    ERRORS=$((ERRORS + 1))
else
    success "wazuh-agent package  →  removed"
fi

if systemctl list-unit-files 2>/dev/null | grep -q "cybersentinel-agent\|wazuh-agent"; then
    warn "CyberSentinel/Wazuh service unit still visible in systemd."
    ERRORS=$((ERRORS + 1))
else
    success "cybersentinel-agent service  →  removed"
fi

if [ -d /var/ossec ]; then
    warn "/var/ossec directory still exists."
    ERRORS=$((ERRORS + 1))
else
    success "/var/ossec  →  removed"
fi

# YARA
if command -v yara &>/dev/null; then
    warn "yara binary still in PATH: $(command -v yara)"
    ERRORS=$((ERRORS + 1))
else
    success "yara binary  →  removed"
fi

# Suricata
if dpkg-query -W -f='${db:Status-Abbrev}' suricata 2>/dev/null | grep -q .; then
    warn "suricata package still present."
    ERRORS=$((ERRORS + 1))
else
    success "suricata package  →  removed"
fi

if systemctl is-active --quiet suricata 2>/dev/null; then
    warn "suricata service still running."
    ERRORS=$((ERRORS + 1))
else
    success "suricata service  →  stopped/removed"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     CyberSentinel Uninstall Summary          ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo -e "  Components removed:"
echo -e "  • CyberSentinel / Wazuh Agent (service + package)"
echo -e "  • YARA binaries, libraries, and headers"
echo -e "  • Suricata IDS (package, config, rules, PPA)"
echo -e "  • Active response scripts"
echo -e "  • Log rotation config"
if [[ "$REMOVE_LOGS" == "yes" ]]; then
    echo -e "  • CyberSentinel log directory (${LOG_DIR})"
else
    echo -e "  • Log directory preserved: ${LOG_DIR}"
fi
echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}CyberSentinel fully uninstalled. ✔${NC}"
else
    echo -e "  ${YELLOW}${BOLD}Uninstall completed with ${ERRORS} warning(s). Check output above.${NC}"
    echo -e "  ${YELLOW}Consider running this script once more, or check ${LOG_FILE}.${NC}"
fi
echo ""
