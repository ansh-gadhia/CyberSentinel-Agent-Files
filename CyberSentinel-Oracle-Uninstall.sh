#!/bin/bash

# ============================================================
# CyberSentinel Uninstaller Script for Oracle Linux (9 / 10+)
# Mirrors the install steps in reverse and cleans all artefacts.
# Must be run as root.
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/uninstall.log"
BIN_DIR="/var/ossec/active-response/bin"
YARA_VERSION="4.5.5"
YARA_SRC_DIR="/usr/local/bin/yara-${YARA_VERSION}"
YARA_RULES_DIR="/tmp/yara/rules"

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
    echo "      S E N T I N E L   U N I N S T A L L E R"
    echo -e "${NC}"
}

spinner() {
    local pid=$1 msg="${2:-Working}" delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 len=10
    printf "  ${CYAN}${msg}${NC} "
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${msg}${NC} [${YELLOW}${spinstr:$((i%len)):1}${NC}]"
        i=$((i+1)); sleep $delay
    done
    wait "$pid"; local exit_code=$?
    [ $exit_code -eq 0 ] \
        && printf "\r  ${CYAN}${msg}${NC} [${GREEN}✔${NC}]\n" \
        || printf "\r  ${CYAN}${msg}${NC} [${RED}✘${NC}]\n"
    return $exit_code
}

step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}\n  ${BOLD}${1}${NC}\n${CYAN}══════════════════════════════════════════${NC}"; }
success() { echo -e "  ${GREEN}✔ ${1}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${1}${NC}"; }
error()   { echo -e "  ${RED}✘ ${1}${NC}" >&2; }

skipped() { echo -e "  ${CYAN}– ${1} (not present — skipped)${NC}"; }

# ============================================================
# Privilege check
# ============================================================
[ "$EUID" -ne 0 ] && { echo -e "${RED}Please run as root (sudo).${NC}"; exit 1; }

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

print_banner

# ============================================================
# Confirmation prompt
# ============================================================
echo -e "  ${BOLD}${RED}WARNING:${NC} This will completely remove CyberSentinel,"
echo -e "  Wazuh agent, YARA, Suricata, and all related configuration."
echo ""
read -p "  Are you sure you want to proceed? [yes/N]: " CONFIRM
if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "YES" ]]; then
    echo -e "\n${YELLOW}Uninstall cancelled.${NC}\n"
    exit 0
fi

echo ""
echo -e "  ${BOLD}Preserve log files in ${LOG_DIR}?${NC}"
read -p "  [y/N]: " KEEP_LOGS
[[ "$KEEP_LOGS" =~ ^[Yy]$ ]] && PRESERVE_LOGS=true || PRESERVE_LOGS=false

# ============================================================
# STEP 1 — Stop and Disable Services
# ============================================================
step "Step 1 │ Stop & Disable Services"

for svc in cybersentinel-agent wazuh-agent suricata; do
    if systemctl list-units --all --full | grep -q "^${svc}.service"; then
        systemctl stop    "$svc" &>>"$LOG_FILE" && \
        systemctl disable "$svc" &>>"$LOG_FILE"
        success "Stopped and disabled: ${svc}"
    else
        skipped "$svc service"
    fi
done

# ============================================================
# STEP 2 — Remove Systemd Service File
# ============================================================
step "Step 2 │ Remove Systemd Service File"

SERVICE_DST="/etc/systemd/system/cybersentinel-agent.service"
if [ -f "$SERVICE_DST" ]; then
    rm -f "$SERVICE_DST" &>>"$LOG_FILE"
    success "Removed: $SERVICE_DST"
else
    skipped "$SERVICE_DST"
fi

systemctl daemon-reload &>>"$LOG_FILE"
systemctl reset-failed  &>>"$LOG_FILE"
success "systemd daemon reloaded."

# ============================================================
# STEP 3 — Remove Wazuh / CyberSentinel Agent Package
# ============================================================
step "Step 3 │ Remove Wazuh Agent Package"

if rpm -q wazuh-agent &>/dev/null; then
    dnf remove -y wazuh-agent &>>"$LOG_FILE" &
    spinner $! "Removing wazuh-agent RPM"
    success "wazuh-agent package removed."
else
    skipped "wazuh-agent package (not installed)"
fi

# ============================================================
# STEP 4 — Remove Wazuh / CyberSentinel Data Directory
# ============================================================
step "Step 4 │ Remove Agent Data Directory (/var/ossec)"

if [ -d /var/ossec ]; then
    rm -rf /var/ossec &>>"$LOG_FILE" &
    spinner $! "Removing /var/ossec"
    success "/var/ossec removed."
else
    skipped "/var/ossec (not present)"
fi

# ============================================================
# STEP 5 — Remove Active Response Scripts
# ============================================================
step "Step 5 │ Remove Active Response Scripts"

for file in llm_query.py remove-threat.sh yara.sh; do
    target="$BIN_DIR/$file"
    if [ -f "$target" ]; then
        rm -f "$target"
        success "Removed: $target"
    else
        skipped "$target"
    fi
done

# Remove the bin dir if now empty
if [ -d "$BIN_DIR" ] && [ -z "$(ls -A "$BIN_DIR" 2>/dev/null)" ]; then
    rmdir "$BIN_DIR" &>>"$LOG_FILE"
    success "Removed empty directory: $BIN_DIR"
fi

# ============================================================
# STEP 6 — Remove YARA
# ============================================================
step "Step 6 │ Remove YARA v${YARA_VERSION}"

YARA_BIN="/usr/local/bin/yara"
YARA_YARAC="/usr/local/bin/yarac"
YARA_LIB="/usr/local/lib/libyara*"

if [ -f "$YARA_BIN" ] || [ -d "$YARA_SRC_DIR" ]; then
    # Attempt make uninstall if the build directory is still present
    if [ -f "${YARA_SRC_DIR}/Makefile" ]; then
        (cd "$YARA_SRC_DIR" && make uninstall) &>>"$LOG_FILE" &
        spinner $! "Running make uninstall for YARA"
    fi

    # Belt-and-braces: remove known installed files manually
    rm -f "$YARA_BIN" "$YARA_YARAC"
    # shellcheck disable=SC2086
    rm -f $YARA_LIB
    rm -f /usr/local/lib/pkgconfig/yara.pc
    rm -rf /usr/local/include/yara

    # Remove the source / build tree
    rm -rf "$YARA_SRC_DIR"

    ldconfig &>>"$LOG_FILE"
    success "YARA and build tree removed."
else
    skipped "YARA binaries / source directory"
fi

# Remove YARA rules
if [ -d "$YARA_RULES_DIR" ]; then
    rm -rf "$YARA_RULES_DIR" &>>"$LOG_FILE"
    success "YARA rules directory removed: $YARA_RULES_DIR"
else
    skipped "YARA rules directory ($YARA_RULES_DIR)"
fi

# ============================================================
# STEP 7 — Remove Suricata
# ============================================================
step "Step 7 │ Remove Suricata IDS"

if command -v suricata &>/dev/null || rpm -q suricata &>/dev/null 2>/dev/null; then
    dnf remove -y suricata &>>"$LOG_FILE" &
    spinner $! "Removing Suricata package"
    success "Suricata package removed."
else
    skipped "Suricata (not installed)"
fi

# Remove Suricata config and rules
for path in /etc/suricata /var/log/suricata /tmp/emerging.rules.tar.gz /tmp/rules; do
    if [ -e "$path" ]; then
        rm -rf "$path" &>>"$LOG_FILE"
        success "Removed: $path"
    else
        skipped "$path"
    fi
done

# ============================================================
# STEP 8 — Remove Temporary Install Artefacts
# ============================================================
step "Step 8 │ Remove Temporary Artefacts"

for path in /tmp/wazuh-agent*.rpm /tmp/v${YARA_VERSION}.tar.gz; do
    # Use glob expansion safely
    for f in $path; do
        if [ -e "$f" ]; then
            rm -f "$f"
            success "Removed: $f"
        fi
    done
done

# ============================================================
# STEP 9 — Remove CyberSentinel Log Directory
# ============================================================
step "Step 9 │ CyberSentinel Log Directory"

if [ -d "$LOG_DIR" ]; then
    if $PRESERVE_LOGS; then
        warn "Log directory preserved at: $LOG_DIR"
    else
        # Copy the current uninstall log somewhere safe first, then wipe
        TMPLOG=$(mktemp /tmp/cybersentinel-uninstall-XXXXXX.log)
        cp "$LOG_FILE" "$TMPLOG" 2>/dev/null || true
        rm -rf "$LOG_DIR" &>/dev/null
        success "Log directory removed. Final log saved to: $TMPLOG"
    fi
else
    skipped "$LOG_DIR (not present)"
fi

# ============================================================
# STEP 10 — Final Verification
# ============================================================
step "Step 10 │ Verification"

ISSUES=0

for svc in cybersentinel-agent wazuh-agent; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        warn "$svc is still running — manual investigation required."
        ISSUES=$((ISSUES+1))
    else
        success "$svc is stopped / absent."
    fi
done

for bin in /usr/local/bin/yara /var/ossec /etc/suricata; do
    if [ -e "$bin" ]; then
        warn "Still present on disk: $bin"
        ISSUES=$((ISSUES+1))
    else
        success "Confirmed removed: $bin"
    fi
done

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     CyberSentinel Uninstall Summary          ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"

if [ $ISSUES -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}CyberSentinel fully removed. ✔${NC}"
else
    echo -e "  ${YELLOW}${BOLD}Uninstall completed with ${ISSUES} warning(s). ⚠${NC}"
    echo -e "  ${YELLOW}Review the output above and check any remaining items manually.${NC}"
fi

echo ""
echo -e "  Components removed:"
echo -e "    • cybersentinel-agent / wazuh-agent service & RPM"
echo -e "    • /var/ossec (agent data + active-response scripts)"
echo -e "    • YARA v${YARA_VERSION} binary, libraries, build tree & rules"
echo -e "    • Suricata IDS package, config & rules"
echo -e "    • Temporary install artefacts in /tmp"
$PRESERVE_LOGS \
    && echo -e "    • Logs preserved in ${LOG_DIR}" \
    || echo -e "    • CyberSentinel log directory removed"
echo ""
