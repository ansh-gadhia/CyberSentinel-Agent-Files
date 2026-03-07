#!/bin/bash

# ============================================================
# CyberSentinel Uninstaller Script for CentOS (7 / 8 / 9 / Stream)
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/uninstall.log"

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
    echo -e "${RED}${BOLD}"
    echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
    echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
    echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
    echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
    echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
    echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
    echo "      S E N T I N E L   U N I N S T A L L E R"
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
skipped() { echo -e "  ${CYAN}  ${1} — not found, skipping.${NC}"; }

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

# ============================================================
# OS Detection
# ============================================================
step "OS Detection │ Identifying CentOS Version"

if [ ! -f /etc/centos-release ] && ! grep -qi "centos" /etc/os-release 2>/dev/null; then
    error "This uninstaller only supports CentOS. Detected OS does not appear to be CentOS."
    exit 1
fi

OS_VERSION_RAW=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null \
    || grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release \
    || grep -oP '[0-9]+' /etc/centos-release | head -1)
OS_MAJOR=$(echo "$OS_VERSION_RAW" | grep -oP '^[0-9]+')

if [ -z "$OS_MAJOR" ]; then
    error "Could not determine CentOS major version. Exiting."
    exit 1
fi

success "Detected: CentOS ${OS_MAJOR}"

if [ "$OS_MAJOR" = "7" ]; then
    PKG_REMOVE="yum remove -y"
else
    PKG_REMOVE="dnf remove -y"
fi

# ============================================================
# Confirmation prompt
# ============================================================
echo ""
echo -e "${RED}${BOLD}  !! WARNING !!${NC}"
echo -e "  This will completely remove CyberSentinel and all"
echo -e "  associated components from this system, including:"
echo ""
echo -e "  • cybersentinel-agent service & wazuh-agent package"
echo -e "  • Suricata IDS + rules + configuration"
echo -e "  • YARA v4.5.5 (built from source)"
echo -e "  • All YARA rules (/tmp/yara)"
echo -e "  • Active response scripts (/var/ossec/active-response/bin)"
echo -e "  • ossec configuration & data (/var/ossec)"
echo -e "  • Logrotate config (/etc/logrotate.d/cybersentinel)"
echo -e "  • Firewall rules added by the installer"
echo -e "  • All CyberSentinel logs & data (/opt/cybersentinel)"
echo ""
echo -e "  ${BOLD}This action is irreversible.${NC}"
echo ""

read -p "  Type CONFIRM to proceed with uninstallation: " CONFIRMATION
if [ "$CONFIRMATION" != "CONFIRM" ]; then
    echo -e "\n${YELLOW}  Uninstallation cancelled. Nothing was changed. Goodbye!${NC}\n"
    exit 0
fi

echo ""
warn "Starting uninstallation..."

# Redirect all further output to log while keeping console output
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# STEP 1 — Stop & Disable Services
# ============================================================
step "Step 1 │ Stopping & Disabling Services"

for svc in cybersentinel-agent wazuh-agent suricata; do
    if systemctl list-units --all | grep -q "${svc}.service"; then
        systemctl stop "$svc" &>>"$LOG_FILE" && \
        systemctl disable "$svc" &>>"$LOG_FILE"
        success "Stopped and disabled: ${svc}"
    else
        skipped "Service: ${svc}"
    fi
done

# ============================================================
# STEP 2 — Remove Wazuh / CyberSentinel Agent Package
# ============================================================
step "Step 2 │ Removing Wazuh Agent Package"

if rpm -q wazuh-agent &>/dev/null; then
    $PKG_REMOVE wazuh-agent &>>"$LOG_FILE" &
    spinner $! "Removing wazuh-agent package"
    if [ $? -eq 0 ]; then
        success "wazuh-agent package removed."
    else
        warn "Package removal returned errors — check $LOG_FILE for details."
    fi
else
    skipped "wazuh-agent package"
fi

# ============================================================
# STEP 3 — Remove Custom Systemd Service File
# ============================================================
step "Step 3 │ Removing Systemd Service Files"

SERVICE_FILES=(
    "/etc/systemd/system/cybersentinel-agent.service"
    "/lib/systemd/system/wazuh-agent.service"
)

for f in "${SERVICE_FILES[@]}"; do
    if [ -f "$f" ]; then
        rm -f "$f" &>>"$LOG_FILE"
        success "Removed: $f"
    else
        skipped "$f"
    fi
done

systemctl daemon-reload &>>"$LOG_FILE"
success "systemd daemon reloaded."

# ============================================================
# STEP 4 — Remove /var/ossec (Wazuh/CyberSentinel data dir)
# ============================================================
step "Step 4 │ Removing Wazuh / OSSEC Data Directory"

if [ -d /var/ossec ]; then
    rm -rf /var/ossec &>>"$LOG_FILE" &
    spinner $! "Removing /var/ossec"
    success "Removed: /var/ossec"
else
    skipped "/var/ossec"
fi

# ============================================================
# STEP 5 — Remove YARA (built from source)
# ============================================================
step "Step 5 │ Removing YARA"

YARA_VERSION="4.5.5"
YARA_SRC_DIR="/usr/local/bin/yara-${YARA_VERSION}"

# Uninstall via make uninstall if Makefile is still present
if [ -f "${YARA_SRC_DIR}/Makefile" ]; then
    echo -e "  ${BOLD}Running make uninstall...${NC}"
    (cd "$YARA_SRC_DIR" && make uninstall) &>>"$LOG_FILE" &
    spinner $! "make uninstall"
    success "YARA uninstalled via make uninstall."
else
    warn "YARA Makefile not found — removing binaries manually."
    # Remove installed binaries and libraries manually
    rm -f /usr/local/bin/yara
    rm -f /usr/local/bin/yarac
    rm -f /usr/local/lib/libyara*
    rm -f /usr/local/include/yara.h
    rm -f /usr/local/include/yara/
    success "YARA binaries and libraries removed manually."
fi

# Remove source directory
if [ -d "$YARA_SRC_DIR" ]; then
    rm -rf "$YARA_SRC_DIR" &>>"$LOG_FILE"
    success "Removed YARA source directory: ${YARA_SRC_DIR}"
else
    skipped "YARA source directory: ${YARA_SRC_DIR}"
fi

# Remove any leftover tarballs
rm -f /tmp/v${YARA_VERSION}.tar.gz &>>"$LOG_FILE"
rm -f /root/v${YARA_VERSION}.tar.gz &>>"$LOG_FILE"

# Update shared library cache after removing YARA libs
ldconfig &>>"$LOG_FILE"
success "Shared library cache updated."

# ============================================================
# STEP 6 — Remove YARA Rules
# ============================================================
step "Step 6 │ Removing YARA Rules"

if [ -d /tmp/yara ]; then
    rm -rf /tmp/yara &>>"$LOG_FILE"
    success "Removed: /tmp/yara (rules directory)"
else
    skipped "/tmp/yara"
fi

# ============================================================
# STEP 7 — Remove Suricata
# ============================================================
step "Step 7 │ Removing Suricata"

if rpm -q suricata &>/dev/null; then
    $PKG_REMOVE suricata &>>"$LOG_FILE" &
    spinner $! "Removing suricata package"
    if [ $? -eq 0 ]; then
        success "Suricata package removed."
    else
        warn "Suricata removal returned errors — check $LOG_FILE for details."
    fi
else
    skipped "suricata package"
fi

# Remove Suricata configuration and rules
SURICATA_DIRS=(
    "/etc/suricata"
    "/var/log/suricata"
    "/var/lib/suricata"
    "/run/suricata"
    "/tmp/rules"
    "/tmp/emerging.rules.tar.gz"
)

for path in "${SURICATA_DIRS[@]}"; do
    if [ -e "$path" ]; then
        rm -rf "$path" &>>"$LOG_FILE"
        success "Removed: $path"
    else
        skipped "$path"
    fi
done

# ============================================================
# STEP 8 — Remove Logrotate Configuration
# ============================================================
step "Step 8 │ Removing Logrotate Configuration"

LOGROTATE_CONF="/etc/logrotate.d/cybersentinel"
if [ -f "$LOGROTATE_CONF" ]; then
    rm -f "$LOGROTATE_CONF" &>>"$LOG_FILE"
    success "Removed: $LOGROTATE_CONF"
else
    skipped "$LOGROTATE_CONF"
fi

# ============================================================
# STEP 9 — Revert Firewall Rules
# ============================================================
step "Step 9 │ Reverting Firewall Rules"

WAZUH_AGENT_PORT=1514

if systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --remove-port="${WAZUH_AGENT_PORT}/tcp" &>>"$LOG_FILE"
    firewall-cmd --permanent --remove-port="${WAZUH_AGENT_PORT}/udp" &>>"$LOG_FILE"
    firewall-cmd --reload &>>"$LOG_FILE"
    success "Firewall rules removed: port ${WAZUH_AGENT_PORT} (TCP/UDP) closed."
else
    skipped "firewalld is not running — no firewall rules to revert"
fi

# ============================================================
# STEP 10 — Revert SELinux (Optional)
# ============================================================
step "Step 10 │ SELinux"

SELINUX_CONFIG="/etc/selinux/config"
if [ -f "$SELINUX_CONFIG" ]; then
    CURRENT_MODE=$(grep "^SELINUX=" "$SELINUX_CONFIG" | cut -d= -f2)
    if [ "$CURRENT_MODE" = "permissive" ]; then
        echo ""
        echo -e "  ${BOLD}SELinux is currently set to Permissive (may have been changed by the installer).${NC}"
        echo "  [1] Restore SELinux to Enforcing (recommended)"
        echo "  [2] Leave as Permissive"
        echo ""
        read -p "  Choice [1/2]: " SELINUX_CHOICE
        if [ "$SELINUX_CHOICE" = "1" ]; then
            sed -i 's/^SELINUX=permissive/SELINUX=enforcing/' "$SELINUX_CONFIG"
            setenforce 1 &>>"$LOG_FILE" || warn "Could not set SELinux to Enforcing immediately (may require reboot)."
            success "SELinux restored to Enforcing in ${SELINUX_CONFIG}."
            warn "A system reboot may be required for SELinux policy to fully re-apply."
        else
            warn "SELinux left as Permissive — you can manually change it in ${SELINUX_CONFIG}."
        fi
    else
        success "SELinux is ${CURRENT_MODE} — no changes needed."
    fi
else
    skipped "SELinux config not found"
fi

# ============================================================
# STEP 11 — Remove Wazuh RPM package file from /tmp
# ============================================================
step "Step 11 │ Cleaning Up Temporary Files"

WAZUH_RPM="wazuh-agent_4.12.0-1.x86_64.rpm"

TEMP_FILES=(
    "/tmp/${WAZUH_RPM}"
    "/tmp/emerging.rules.tar.gz"
)

for f in "${TEMP_FILES[@]}"; do
    if [ -f "$f" ]; then
        rm -f "$f" &>>"$LOG_FILE"
        success "Removed temp file: $f"
    else
        skipped "$f"
    fi
done

# ============================================================
# STEP 12 — Remove /opt/cybersentinel (logs & data)
# This is the LAST step — log is inside this dir
# ============================================================
step "Step 12 │ Removing CyberSentinel Data & Logs"

echo -e "  ${YELLOW}⚠ The installation log (${LOG_FILE}) will be deleted last.${NC}"

if [ -d "$LOG_DIR" ]; then
    # Save a final copy of the uninstall log to /tmp before deleting
    FINAL_LOG="/tmp/cybersentinel_uninstall_$(date +%Y%m%d_%H%M%S).log"
    cp "$LOG_FILE" "$FINAL_LOG" 2>/dev/null
    rm -rf "$LOG_DIR" &>/dev/null
    success "Removed: ${LOG_DIR}"
    success "Final uninstall log saved to: ${FINAL_LOG}"
else
    skipped "$LOG_DIR"
fi

# ============================================================
# Post-uninstall verification
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║    CyberSentinel Uninstallation Summary      ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"

# Check nothing is left behind
LEFTOVERS=false

rpm -q wazuh-agent &>/dev/null        && { warn "wazuh-agent package still present!";          LEFTOVERS=true; } || success "wazuh-agent package    →  removed"
rpm -q suricata &>/dev/null           && { warn "suricata package still present!";             LEFTOVERS=true; } || success "suricata package       →  removed"
command -v yara &>/dev/null           && { warn "yara binary still in PATH!";                  LEFTOVERS=true; } || success "yara binary            →  removed"
[ -d /var/ossec ]                     && { warn "/var/ossec still exists!";                    LEFTOVERS=true; } || success "/var/ossec             →  removed"
[ -d /etc/suricata ]                  && { warn "/etc/suricata still exists!";                 LEFTOVERS=true; } || success "/etc/suricata          →  removed"
[ -f /etc/systemd/system/cybersentinel-agent.service ] \
                                      && { warn "cybersentinel-agent.service still present!";  LEFTOVERS=true; } || success "systemd service file   →  removed"
[ -f /etc/logrotate.d/cybersentinel ] && { warn "logrotate config still present!";             LEFTOVERS=true; } || success "logrotate config       →  removed"
[ -d /tmp/yara ]                      && { warn "/tmp/yara still exists!";                     LEFTOVERS=true; } || success "yara rules dir         →  removed"
[ -d /opt/cybersentinel ]             && { warn "/opt/cybersentinel still exists!";            LEFTOVERS=true; } || success "/opt/cybersentinel     →  removed"

echo ""

if $LEFTOVERS; then
    warn "Some components could not be fully removed. Review warnings above."
    warn "Uninstall log saved at: ${FINAL_LOG:-/tmp/cybersentinel_uninstall.log}"
else
    echo -e "  ${GREEN}${BOLD}CyberSentinel fully uninstalled. System is clean. ✔${NC}"
fi

echo ""
