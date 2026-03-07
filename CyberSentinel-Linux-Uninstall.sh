#!/bin/bash

# ============================================================
# CyberSentinel Uninstaller Script for Ubuntu
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

if systemctl is-active --quiet cybersentinel-agent 2>/dev/null; then
    systemctl stop cybersentinel-agent &>>"$LOG_FILE" &
    spinner $! "Stopping cybersentinel-agent"
    success "cybersentinel-agent stopped."
else
    warn "cybersentinel-agent was not running."
fi

if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    systemctl stop wazuh-agent &>>"$LOG_FILE" &
    spinner $! "Stopping wazuh-agent"
    success "wazuh-agent stopped."
else
    warn "wazuh-agent was not running."
fi

if systemctl is-enabled --quiet cybersentinel-agent 2>/dev/null; then
    systemctl disable cybersentinel-agent &>>"$LOG_FILE"
    success "cybersentinel-agent disabled from startup."
fi

if systemctl is-enabled --quiet wazuh-agent 2>/dev/null; then
    systemctl disable wazuh-agent &>>"$LOG_FILE"
    success "wazuh-agent disabled from startup."
fi

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

if dpkg -l wazuh-agent &>/dev/null 2>&1; then
    dpkg --purge wazuh-agent &>>"$LOG_FILE" &
    spinner $! "Purging wazuh-agent package"
    if [ $? -eq 0 ]; then
        success "wazuh-agent package purged."
    else
        warn "dpkg purge encountered issues — check $LOG_FILE."
    fi
else
    warn "wazuh-agent package not found (already removed?)."
fi

# Remove leftover ossec directories
for DIR in /var/ossec /etc/ossec-init.conf; do
    if [ -e "$DIR" ]; then
        rm -rf "$DIR" &>>"$LOG_FILE"
        success "Removed: $DIR"
    else
        warn "Not found (skipping): $DIR"
    fi
done

# Remove the downloaded .deb if it was left behind
DEB_TMP="/tmp/wazuh-agent_4.12.0-1_amd64.deb"
if [ -f "$DEB_TMP" ]; then
    rm -f "$DEB_TMP"
    success "Removed leftover package: $DEB_TMP"
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

# Remove YARA libraries installed by 'make install'
for LIB_PATH in /usr/local/lib/libyara* /usr/lib/libyara*; do
    if compgen -G "$LIB_PATH" > /dev/null 2>&1; then
        rm -f $LIB_PATH
        success "Removed library: $LIB_PATH"
    fi
done

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

# Update shared library cache
ldconfig &>>"$LOG_FILE"
success "Shared library cache updated."

# Clean up any leftover build directory (in case uninstall is run after a failed install)
if [ -d /tmp/yara-build ]; then
    rm -rf /tmp/yara-build
    success "Removed leftover YARA build directory."
fi

# ============================================================
# STEP 5 — Stop & Remove Suricata
# ============================================================
step "Step 5 │ Removing Suricata IDS"

if systemctl is-active --quiet suricata 2>/dev/null; then
    systemctl stop suricata &>>"$LOG_FILE" &
    spinner $! "Stopping Suricata"
    success "Suricata stopped."
else
    warn "Suricata was not running."
fi

if systemctl is-enabled --quiet suricata 2>/dev/null; then
    systemctl disable suricata &>>"$LOG_FILE"
    success "Suricata disabled from startup."
fi

if dpkg -l suricata &>/dev/null 2>&1; then
    apt-get purge suricata -y &>>"$LOG_FILE" &
    spinner $! "Purging Suricata package"
    if [ $? -eq 0 ]; then
        success "Suricata package purged."
    else
        warn "Suricata purge encountered issues — check $LOG_FILE."
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

# Remove Suricata PPA
if [ -f /etc/apt/sources.list.d/oisf-ubuntu-suricata-stable-*.list ] 2>/dev/null || \
   ls /etc/apt/sources.list.d/oisf* &>/dev/null 2>&1; then
    add-apt-repository --remove -y ppa:oisf/suricata-stable &>>"$LOG_FILE" &
    spinner $! "Removing Suricata PPA"
    success "Suricata PPA removed."
else
    warn "Suricata PPA not found (skipping)."
fi

apt-get autoremove -y &>>"$LOG_FILE" &
spinner $! "Running apt autoremove"
success "Unused dependencies cleaned up."

apt-get update -qq &>>"$LOG_FILE" &
spinner $! "Updating package lists"
success "Package lists updated."

# ============================================================
# STEP 6 — Remove Active Response Scripts
# ============================================================
step "Step 6 │ Removing Active Response Scripts"

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
    # Write final log entry before deleting the directory
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

# Wazuh/CyberSentinel agent
if dpkg -l wazuh-agent &>/dev/null 2>&1; then
    warn "wazuh-agent package still present."
    ERRORS=$((ERRORS + 1))
else
    success "wazuh-agent package  →  removed"
fi

if systemctl list-units --all 2>/dev/null | grep -q "cybersentinel-agent"; then
    warn "cybersentinel-agent service still visible in systemd."
    ERRORS=$((ERRORS + 1))
else
    success "cybersentinel-agent service  →  removed"
fi

# YARA
if command -v yara &>/dev/null; then
    warn "yara binary still in PATH: $(command -v yara)"
    ERRORS=$((ERRORS + 1))
else
    success "yara binary  →  removed"
fi

# Suricata
if dpkg -l suricata &>/dev/null 2>&1; then
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
fi
echo ""
