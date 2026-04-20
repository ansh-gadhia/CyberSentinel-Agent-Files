#!/bin/bash

# ============================================================
# CyberSentinel — macOS Uninstaller (Apple Silicon)
# Removes: agent package, launchd daemon, ossec dir, control
# binary, YARA (symlink + rules), Suricata config/logs, trusted
# CA cert, and optionally the brew-installed tooling.
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/uninstall.log"
OSSEC_DIR="/Library/Ossec"
AR_DIR="/Library/Ossec/active-response/bin"
YARA_PREFIX="/opt/cybersentinel/yara"
YARA_BASE_DIR="/Library/Ossec/ruleset/yara"
CS_PLIST="/Library/LaunchDaemons/com.cybersentinel.agent.plist"
CS_CONTROL_LINK="/usr/local/bin/cybersentinel-control"

# Apple Silicon: Homebrew lives under /opt/homebrew
BREW_BIN="/opt/homebrew/bin/brew"
BREW_PREFIX="/opt/homebrew"

# ============================================================
# Colours
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
    echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
    echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
    echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
    echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
    echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
    echo "    S E N T I N E L   U N I N S T A L L"
    echo "        macOS Apple Silicon Edition"
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
info()    { echo -e "  ${CYAN}ℹ ${1}${NC}"; }

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    # Only log to file if log dir still exists (we may be mid-removal)
    [ -d "$LOG_DIR" ] && echo "$ts [INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

# ============================================================
# Apple Silicon architecture check
# ============================================================
ARCH=$(uname -m)
IS_ROSETTA=$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)
if [ "$ARCH" != "arm64" ] && [ "$IS_ROSETTA" != "1" ]; then
    echo -e "${RED}This uninstaller is for Apple Silicon (arm64) Macs only.${NC}"
    echo -e "${YELLOW}Detected architecture: ${ARCH}${NC}"
    echo -e "${YELLOW}Please use the Intel edition for x86_64 Macs.${NC}"
    exit 1
fi

# ============================================================
# Capture real user for Homebrew (brew refuses root)
# ============================================================
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    warn "Could not determine invoking user — brew cleanup will be skipped."
    REAL_USER=""
fi

print_banner
echo -e "  ${BOLD}Architecture: Apple Silicon (arm64)${NC}"
echo ""

# Setup log dir up front (best effort — may get removed later)
mkdir -p "$LOG_DIR" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true
log "Uninstaller started — arch: $ARCH — user: ${REAL_USER:-root}"

# ============================================================
# Pre-flight: what's actually installed?
# ============================================================
step "Pre-flight │ Detecting installed components"

HAS_AGENT=false
HAS_PLIST=false
HAS_PKG_RECEIPT=false
HAS_CONTROL_LINK=false
HAS_YARA_SYMLINK=false
HAS_YARA_RULES=false
HAS_SURICATA_CONFIG=false
HAS_SURICATA_LOGS=false
HAS_LOG_DIR=false

[ -d "$OSSEC_DIR" ]                                              && HAS_AGENT=true
[ -f "$CS_PLIST" ]                                               && HAS_PLIST=true
pkgutil --pkg-info com.cybersentinel.pkg.agent &>/dev/null       && HAS_PKG_RECEIPT=true
[ -L "$CS_CONTROL_LINK" ] || [ -f "$CS_CONTROL_LINK" ]           && HAS_CONTROL_LINK=true
[ -L "$YARA_PREFIX/bin/yara" ] || [ -f "$YARA_PREFIX/bin/yara" ] && HAS_YARA_SYMLINK=true
[ -d "$YARA_BASE_DIR" ]                                          && HAS_YARA_RULES=true
[ -d /etc/suricata ]                                             && HAS_SURICATA_CONFIG=true
[ -d /var/log/suricata ]                                         && HAS_SURICATA_LOGS=true
[ -d "$LOG_DIR" ]                                                && HAS_LOG_DIR=true

if ! $HAS_AGENT && ! $HAS_PLIST && ! $HAS_PKG_RECEIPT && \
   ! $HAS_CONTROL_LINK && ! $HAS_YARA_SYMLINK && ! $HAS_YARA_RULES && \
   ! $HAS_SURICATA_CONFIG && ! $HAS_LOG_DIR; then
    warn "No CyberSentinel components detected on this system."
    echo -e "  ${YELLOW}Nothing to uninstall. Exiting.${NC}"
    exit 0
fi

echo -e "  ${BOLD}Components detected:${NC}"
$HAS_AGENT           && echo "    • Agent directory       (${OSSEC_DIR})"
$HAS_PLIST           && echo "    • launchd daemon        (${CS_PLIST})"
$HAS_PKG_RECEIPT     && echo "    • Package receipt       (com.cybersentinel.pkg.agent)"
$HAS_CONTROL_LINK    && echo "    • Control symlink       (${CS_CONTROL_LINK})"
$HAS_YARA_SYMLINK    && echo "    • YARA symlink          (${YARA_PREFIX}/bin/yara)"
$HAS_YARA_RULES      && echo "    • YARA rules directory  (${YARA_BASE_DIR})"
$HAS_SURICATA_CONFIG && echo "    • Suricata config       (/etc/suricata)"
$HAS_SURICATA_LOGS   && echo "    • Suricata logs         (/var/log/suricata)"
$HAS_LOG_DIR         && echo "    • CyberSentinel logs    (${LOG_DIR})"

# ============================================================
# User confirmation + mode selection
# ============================================================
echo ""
echo -e "  ${BOLD}Uninstall mode:${NC}"
echo "  [1] Standard   — Remove CyberSentinel only (keep brew tools: yara, suricata, jq)"
echo "  [2] Full       — Standard + uninstall brew formulas installed for CyberSentinel"
echo "  [3] Cancel"
echo ""
exec 3</dev/tty
read -p "  Choice [1/2/3]: " MODE_CHOICE <&3
exec 3<&-

case "$MODE_CHOICE" in
    1) UNINSTALL_MODE="standard" ;;
    2) UNINSTALL_MODE="full" ;;
    *) echo -e "\n${YELLOW}Uninstall cancelled.${NC}\n"; exit 0 ;;
esac
log "Mode: $UNINSTALL_MODE"

echo ""
warn "This will permanently remove CyberSentinel from this system."
if [ "$UNINSTALL_MODE" = "full" ]; then
    warn "Full mode will also uninstall: yara, suricata, jq (brew formulas)."
    warn "Other brew dependencies will be LEFT ALONE since other apps on the"
    warn "system may depend on them."
fi
echo ""
exec 3</dev/tty
read -p "  Type 'YES' to continue: " CONFIRM <&3
exec 3<&-

if [ "$CONFIRM" != "YES" ]; then
    echo -e "\n${YELLOW}Uninstall cancelled.${NC}\n"
    exit 0
fi

# ============================================================
# Step 1 — Stop & unload launchd daemon
# ============================================================
step "Step 1 │ Stopping agent service"

if [ -f "$CS_PLIST" ]; then
    launchctl unload -w "$CS_PLIST" &>/dev/null &
    spinner $! "Unloading com.cybersentinel.agent"
    log "launchd daemon unloaded"
elif launchctl list 2>/dev/null | grep -q "com.cybersentinel.agent"; then
    launchctl remove com.cybersentinel.agent 2>/dev/null || true
    warn "plist missing but service was loaded — used 'launchctl remove'."
    log "launchd service removed (no plist)"
else
    info "No running launchd service to unload."
fi

if [ -x "$OSSEC_DIR/bin/cybersentinel-control" ]; then
    "$OSSEC_DIR/bin/cybersentinel-control" stop &>/dev/null || true
    log "cybersentinel-control stop issued"
fi

sleep 2
# Force-kill any lingering agent processes
AGENT_PIDS=$(pgrep -f 'ossec-|wazuh-|cybersentinel' 2>/dev/null || true)
if [ -n "$AGENT_PIDS" ]; then
    echo "$AGENT_PIDS" | xargs kill -TERM 2>/dev/null || true
    sleep 2
    AGENT_PIDS=$(pgrep -f 'ossec-|wazuh-|cybersentinel' 2>/dev/null || true)
    [ -n "$AGENT_PIDS" ] && echo "$AGENT_PIDS" | xargs kill -KILL 2>/dev/null || true
    warn "Force-killed lingering agent processes."
    log "Lingering agent processes killed"
fi
success "Agent service stopped."

# ============================================================
# Step 2 — Remove pkg receipt & agent directory
# ============================================================
step "Step 2 │ Removing agent package & files"

if $HAS_PKG_RECEIPT; then
    pkgutil --forget com.cybersentinel.pkg.agent &>>"$LOG_FILE" 2>/dev/null || true
    success "Package receipt removed (com.cybersentinel.pkg.agent)."
    log "pkg receipt forgotten"
fi

# Also forget stale Wazuh receipts if any survived the install
pkgutil --forget com.wazuh.pkg.wazuh-agent &>/dev/null 2>&1 || true

if $HAS_AGENT; then
    rm -rf "$OSSEC_DIR" &
    spinner $! "Removing ${OSSEC_DIR}"
    success "Removed ${OSSEC_DIR}"
    log "Removed $OSSEC_DIR"
fi

if $HAS_PLIST; then
    rm -f "$CS_PLIST"
    success "Removed ${CS_PLIST}"
    log "Removed plist"
fi

if $HAS_CONTROL_LINK; then
    rm -f "$CS_CONTROL_LINK"
    success "Removed ${CS_CONTROL_LINK}"
    log "Removed control symlink"
fi

# Also clean any stray Wazuh artifacts
[ -f /Library/LaunchDaemons/com.wazuh.agent.plist ] && \
    rm -f /Library/LaunchDaemons/com.wazuh.agent.plist && \
    log "Removed stale com.wazuh.agent.plist"

# ============================================================
# Step 3 — Remove YARA symlink & rules
# ============================================================
step "Step 3 │ Removing YARA integration"

if $HAS_YARA_SYMLINK; then
    rm -f "$YARA_PREFIX/bin/yara"
    rmdir "$YARA_PREFIX/bin" 2>/dev/null || true
    success "Removed YARA symlink: ${YARA_PREFIX}/bin/yara"
    log "Removed YARA symlink"
fi

if $HAS_YARA_RULES; then
    rm -rf "$YARA_BASE_DIR"
    success "Removed YARA rules directory: ${YARA_BASE_DIR}"
    log "Removed YARA rules dir"
fi

# /Library/Ossec/ruleset is part of $OSSEC_DIR, so if the agent dir
# was removed above this is a no-op. Left here for clarity.

# ============================================================
# Step 4 — Remove Suricata config & logs
# ============================================================
step "Step 4 │ Removing Suricata artifacts"

if $HAS_SURICATA_CONFIG; then
    rm -rf /etc/suricata
    success "Removed /etc/suricata"
    log "Removed /etc/suricata"
fi

if $HAS_SURICATA_LOGS; then
    rm -rf /var/log/suricata
    success "Removed /var/log/suricata"
    log "Removed /var/log/suricata"
fi

# ============================================================
# Step 5 — Remove trusted CA from System Keychain
# ============================================================
step "Step 5 │ Removing trusted CA certificate"

CA_SUBJECT_PATTERNS=("CyberSentinel" "cybersentinel" "CyberSentinel CA")
CA_REMOVED=false
for pattern in "${CA_SUBJECT_PATTERNS[@]}"; do
    # Find matching certs in the System keychain
    CERT_HASHES=$(security find-certificate -a -c "$pattern" \
        -Z /Library/Keychains/System.keychain 2>/dev/null | \
        awk '/SHA-1 hash:/{print $3}' | sort -u)

    if [ -n "$CERT_HASHES" ]; then
        while IFS= read -r hash; do
            [ -z "$hash" ] && continue
            security delete-certificate -Z "$hash" \
                /Library/Keychains/System.keychain &>>"$LOG_FILE" 2>&1 || true
            log "Removed cert with SHA-1 $hash (matched '$pattern')"
            CA_REMOVED=true
        done <<< "$CERT_HASHES"
    fi
done

if $CA_REMOVED; then
    success "CyberSentinel CA certificate(s) removed from System Keychain."
else
    info "No CyberSentinel CA certificate found in System Keychain (already removed or never installed)."
fi

# ============================================================
# Step 6 — Optional: uninstall brew formulas (full mode only)
# ============================================================
if [ "$UNINSTALL_MODE" = "full" ]; then
    step "Step 6 │ Removing brew formulas (full mode)"

    if [ -z "$REAL_USER" ]; then
        warn "Invoking user unknown — skipping brew cleanup."
    elif ! sudo -u "$REAL_USER" "$BREW_BIN" --version &>/dev/null; then
        warn "Homebrew not found at ${BREW_BIN} — skipping brew cleanup."
    else
        # Only remove formulas explicitly installed BY CyberSentinel.
        # Shared deps are left alone — removing them could break
        # unrelated software on the system.
        CS_FORMULAS=(yara suricata jq)

        for formula in "${CS_FORMULAS[@]}"; do
            if sudo -u "$REAL_USER" "$BREW_BIN" list --formula 2>/dev/null | grep -qx "$formula"; then
                echo -e "  ${BOLD}Uninstalling ${formula}...${NC}"
                (sudo -u "$REAL_USER" "$BREW_BIN" uninstall --ignore-dependencies "$formula" \
                    &>>"$LOG_FILE") &
                spinner $! "Uninstalling ${formula}"
                log "brew uninstall $formula"
            else
                info "${formula} not installed via brew — skipping."
            fi
        done

        success "Brew formula cleanup complete."
        echo ""
        info "Shared dependencies (bash, curl, and any transitive deps) were kept."
        info "Remove unused deps with 'brew autoremove' if you are sure nothing"
        info "else on this system needs them."
    fi
else
    info "Standard mode — brew-installed tools (yara, suricata, jq) were kept."
    info "Run this uninstaller with the 'Full' option to remove them."
fi

# ============================================================
# Step 7 — Remove /opt/cybersentinel (log dir)
# ============================================================
step "Step 7 │ Removing installer logs & working directory"

# Flush the log to a safe place before we nuke /opt/cybersentinel
FINAL_LOG=""
if [ -f "$LOG_FILE" ]; then
    FINAL_LOG="/tmp/cybersentinel-uninstall-$(date +%Y%m%d-%H%M%S).log"
    cp "$LOG_FILE" "$FINAL_LOG" 2>/dev/null || FINAL_LOG=""
fi

if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
    success "Removed ${LOG_DIR}"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   CyberSentinel — Uninstall Summary          ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo -e "  Architecture  : ${BOLD}Apple Silicon (arm64)${NC}"
echo -e "  Mode          : ${BOLD}${UNINSTALL_MODE}${NC}"
[ -n "$FINAL_LOG" ]  && echo -e "  Log saved     : ${BOLD}${FINAL_LOG}${NC}"
echo ""
echo -e "  ${YELLOW}Note: This agent was NOT deregistered from the Manager.${NC}"
echo -e "  ${YELLOW}Remove it manually from the Manager UI/API if required.${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}CyberSentinel has been removed from this system. ✔${NC}"
echo ""

# Verification pass — anything still lingering?
LEFTOVERS=()
[ -d "$OSSEC_DIR" ]        && LEFTOVERS+=("$OSSEC_DIR")
[ -f "$CS_PLIST" ]         && LEFTOVERS+=("$CS_PLIST")
[ -e "$CS_CONTROL_LINK" ]  && LEFTOVERS+=("$CS_CONTROL_LINK")
[ -d /opt/cybersentinel ]  && LEFTOVERS+=("/opt/cybersentinel")
[ -d "$YARA_BASE_DIR" ]    && LEFTOVERS+=("$YARA_BASE_DIR")
pkgutil --pkg-info com.cybersentinel.pkg.agent &>/dev/null && \
    LEFTOVERS+=("pkg receipt: com.cybersentinel.pkg.agent")

if [ ${#LEFTOVERS[@]} -gt 0 ]; then
    warn "The following items could not be fully removed:"
    for item in "${LEFTOVERS[@]}"; do
        echo -e "    ${YELLOW}• ${item}${NC}"
    done
    echo -e "  ${YELLOW}You may need to remove these manually.${NC}"
    exit 2
fi

exit 0
