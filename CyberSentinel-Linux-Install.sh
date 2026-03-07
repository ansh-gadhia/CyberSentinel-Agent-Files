#!/bin/bash

# ============================================================
# CyberSentinel Installer Script for Ubuntu
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/install.log"
BASE_URL="https://raw.githubusercontent.com/cybersentinel-06/CyberSentinel-SIEM/main/AGENTS/UBUNTU-AGENT"
BIN_DIR="/var/ossec/active-response/bin"

WAZUH_DEB="wazuh-agent_4.12.0-1_amd64.deb"
WAZUH_PKG_URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/$WAZUH_DEB"
GITHUB_REPO="cybersentinel-06/CyberSentinel-SIEM"
WAZUH_AGENT_PORT=1514
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
    echo "       S E N T I N E L   I N S T A L L E R"
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

handle_error() {
    local exit_code=$1
    local msg="${2//wazuh/cybersentinel}"
    if [ "$exit_code" -ne 0 ]; then
        error "$msg"
        exit "$exit_code"
    fi
}

# ============================================================
# Rollback trap — cleans up on unexpected exit
# ============================================================
ROLLBACK_ENABLED=false   # armed after package install begins

rollback() {
    local exit_code=$?
    # Only roll back if we actually started installing and it failed
    if $ROLLBACK_ENABLED && [ $exit_code -ne 0 ]; then
        echo ""
        warn "Installation failed (exit code $exit_code). Running rollback..."
        systemctl stop cybersentinel-agent wazuh-agent &>/dev/null || true
        dpkg --purge wazuh-agent &>/dev/null || true
        rm -f /etc/systemd/system/cybersentinel-agent.service
        rm -f /tmp/"$WAZUH_DEB"
        rm -rf /usr/local/bin/yara-4.5.5
        systemctl daemon-reload &>/dev/null || true
        error "Rollback complete. System restored to pre-install state."
        error "Check the log for details: $LOG_FILE"
    fi
}

trap rollback EXIT

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

# ============================================================
# Setup log dir early (before exec redirect)
# ============================================================
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

print_banner

# ============================================================
# STEP 0 — Collect & validate GitHub token
# ============================================================
step "Step 0 │ GitHub Token Validation"

validate_github_token() {
    local token="$1"
    local http_code
    # 1. Check token is valid (authenticates successfully)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/user")
    if [ "$http_code" -ne 200 ]; then
        return 1
    fi
    # 2. Check token can actually read the target repo
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/repos/$GITHUB_REPO")
    if [ "$http_code" -eq 200 ]; then
        return 0
    elif [ "$http_code" -eq 404 ] || [ "$http_code" -eq 403 ]; then
        echo -e "\n  ${YELLOW}⚠ Token is valid but cannot access repo '${GITHUB_REPO}' (HTTP $http_code).${NC}"
        echo -e "  ${YELLOW}  Ensure the token has 'repo' or 'contents:read' scope.${NC}"
        return 2
    else
        return 1
    fi
}

MAX_ATTEMPTS=3
attempt=0
GITHUB_TOKEN=""

while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))

    # Read token silently (hidden input)
    printf "  Enter GitHub Personal Access Token: "
    stty -echo
    read -r GITHUB_TOKEN
    stty echo
    echo   # newline after hidden input

    # Show masked version for confirmation
    if [ ${#GITHUB_TOKEN} -gt 8 ]; then
        masked="${GITHUB_TOKEN:0:4}$(printf '%0.s*' $(seq 1 $((${#GITHUB_TOKEN} - 8))))${GITHUB_TOKEN: -4}"
    else
        masked="****"
    fi
    echo -e "  Token entered: ${YELLOW}${masked}${NC}"

    printf "  Validating token..."
    validate_github_token "$GITHUB_TOKEN"
    val_result=$?

    if [ $val_result -eq 0 ]; then
        success "Token is valid and has access to the repository."
        break
    elif [ $val_result -eq 2 ]; then
        # Repo access denied — clear message already printed inside function
        error "Please provide a token with 'repo' or 'contents:read' scope (attempt $attempt/$MAX_ATTEMPTS)."
    else
        error "Invalid or expired token (attempt $attempt/$MAX_ATTEMPTS)."
    fi

    if [ $attempt -eq $MAX_ATTEMPTS ]; then
        error "Too many failed attempts. Exiting."
        exit 1
    fi
    echo -e "  ${YELLOW}Please try again.${NC}"
done

HEADERS="Authorization: Bearer $GITHUB_TOKEN"

# ============================================================
# STEP 1 — Collect Manager IP and Agent Name
# ============================================================
step "Step 1 │ Configuration"

read -p "  Enter Manager IP: " MANAGER_IP
while [[ -z "$MANAGER_IP" ]]; do
    warn "Manager IP cannot be empty."
    read -p "  Enter Manager IP: " MANAGER_IP
done

# Reachability check — probe Wazuh agent port
printf "  Checking Manager reachability on port ${WAZUH_AGENT_PORT}..."
if nc -z -w5 "$MANAGER_IP" "$WAZUH_AGENT_PORT" &>/dev/null; then
    success "Manager is reachable at ${MANAGER_IP}:${WAZUH_AGENT_PORT}."
else
    echo ""
    warn "Cannot reach ${MANAGER_IP}:${WAZUH_AGENT_PORT}."
    warn "The manager may be down, the port blocked, or the IP incorrect."
    echo ""
    echo -e "  ${BOLD}How would you like to proceed?${NC}"
    echo "  [1] Continue anyway (I know what I'm doing)"
    echo "  [2] Re-enter Manager IP"
    echo "  [3] Exit"
    read -p "  Choice [1/2/3]: " REACH_CHOICE
    case "$REACH_CHOICE" in
        1) warn "Continuing despite unreachable manager." ;;
        2)
            read -p "  Enter Manager IP: " MANAGER_IP
            while [[ -z "$MANAGER_IP" ]]; do
                warn "Manager IP cannot be empty."
                read -p "  Enter Manager IP: " MANAGER_IP
            done
            ;;
        *)
            echo -e "\n${YELLOW}Installation cancelled. Goodbye!${NC}\n"
            exit 0
            ;;
    esac
fi

read -p "  Enter Agent Name: " AGENT_NAME
while [[ -z "$AGENT_NAME" ]]; do
    warn "Agent Name cannot be empty."
    read -p "  Enter Agent Name: " AGENT_NAME
done

# Detect network interface and agent IP
read -r InterfaceName AgentIP <<< "$(ip -4 -o addr show | grep -v '127.0.0.1' | awk '{print $2, $4}' | cut -d/ -f1 | head -n 1)"
success "Detected interface: ${InterfaceName} (${AgentIP})"

# ============================================================
# STEP 2 — Check for existing agent installation
# ============================================================
step "Step 2 │ Existing Agent Detection"

AGENT_EXISTS=false
if dpkg -l wazuh-agent &>/dev/null || \
   systemctl list-units --all | grep -q "cybersentinel-agent" || \
   [ -f /var/ossec/etc/ossec.conf ]; then
    AGENT_EXISTS=true
fi

if $AGENT_EXISTS; then
    warn "An existing CyberSentinel/Wazuh agent installation was detected."

    # Show current agent status
    if systemctl is-active --quiet cybersentinel-agent 2>/dev/null; then
        echo -e "  Service status: ${GREEN}Running (cybersentinel-agent)${NC}"
    elif systemctl is-active --quiet wazuh-agent 2>/dev/null; then
        echo -e "  Service status: ${YELLOW}Running (wazuh-agent)${NC}"
    else
        echo -e "  Service status: ${RED}Stopped / Not running${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo "  [1] Reinstall / Overwrite existing installation"
    echo "  [2] Repair configuration only (skip package reinstall)"
    echo "  [3] Exit"
    echo ""
    read -p "  Enter choice [1/2/3]: " EXISTING_CHOICE

    case "$EXISTING_CHOICE" in
        1)
            warn "Proceeding with full reinstall. Stopping existing services..."
            systemctl stop cybersentinel-agent wazuh-agent &>/dev/null
            dpkg --purge wazuh-agent &>>"$LOG_FILE"
            rm -f /etc/systemd/system/cybersentinel-agent.service
            systemctl daemon-reload &>>"$LOG_FILE"
            success "Old installation removed."
            SKIP_PACKAGE=false
            ;;
        2)
            warn "Skipping package reinstall — will reconfigure only."
            SKIP_PACKAGE=true
            ;;
        3)
            echo -e "\n${YELLOW}Installation cancelled. Goodbye!${NC}\n"
            exit 0
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    success "No existing agent found. Proceeding with fresh installation."
    SKIP_PACKAGE=false
fi

# Redirect all further output to log (while keeping console output via tee)
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# STEP 3 — Download & Install CyberSentinel Agent package
# ============================================================
step "Step 3 │ Agent Package"

if ! $SKIP_PACKAGE; then
    ROLLBACK_ENABLED=true   # arm rollback — we're about to make changes
    echo -e "  ${BOLD}Downloading agent package...${NC}"
    wget -q "$WAZUH_PKG_URL" -O "/tmp/$WAZUH_DEB" &
    spinner $! "Downloading"
    handle_error $? "Failed to download CyberSentinel Agent package."

    echo -e "  ${BOLD}Verifying package checksum...${NC}"
    EXPECTED_SHA512=$(curl -s "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/" \
        | grep -oP "(?<=SHA512:)[a-f0-9]{128}" | head -1 || true)
    if [ -n "$EXPECTED_SHA512" ]; then
        ACTUAL_SHA512=$(sha512sum "/tmp/$WAZUH_DEB" | awk '{print $1}')
        if [ "$ACTUAL_SHA512" != "$EXPECTED_SHA512" ]; then
            handle_error 1 "Checksum mismatch! Package may be corrupted or tampered with. Aborting."
        fi
        success "Checksum verified."
    else
        warn "Could not retrieve upstream checksum — skipping verification."
    fi

    echo -e "  ${BOLD}Installing agent package...${NC}"
    WAZUH_MANAGER="$MANAGER_IP" \
    WAZUH_AGENT_GROUP="Linux" \
    WAZUH_AGENT_NAME="$AGENT_NAME" \
    dpkg -i "/tmp/$WAZUH_DEB" &>>"$LOG_FILE" &
    spinner $! "Installing"
    handle_error $? "Failed to install CyberSentinel Agent package."
    success "Agent package installed."
else
    success "Package installation skipped (repair mode)."
fi

# ============================================================
# STEP 3.5 — Install YARA (latest version from source)
# ============================================================
step "Step 3.5 │ YARA v4.5.5 Installation"

YARA_VERSION="4.5.5"
YARA_TARBALL="v${YARA_VERSION}.tar.gz"
YARA_URL="https://github.com/VirusTotal/yara/archive/${YARA_TARBALL}"
YARA_SRC_DIR="/usr/local/bin/yara-${YARA_VERSION}"
YARA_RULES_DIR="/tmp/yara/rules"

# 1 — Dependencies
echo -e "  ${BOLD}Installing YARA build dependencies...${NC}"
apt-get update -qq &>>"$LOG_FILE"
apt-get install -y make gcc autoconf libtool libssl-dev pkg-config jq &>>"$LOG_FILE" &
spinner $! "Installing build dependencies"
handle_error $? "Failed to install YARA build dependencies."

# 2 — Download source tarball
echo -e "  ${BOLD}Downloading YARA v${YARA_VERSION} source...${NC}"
curl -LO "$YARA_URL" &>>"$LOG_FILE" &
spinner $! "Downloading YARA v${YARA_VERSION}"
handle_error $? "Failed to download YARA source tarball."

# 3 — Extract directly into /usr/local/bin and remove tarball
echo -e "  ${BOLD}Extracting YARA source to /usr/local/bin/...${NC}"
tar -xvzf "$YARA_TARBALL" -C /usr/local/bin/ &>>"$LOG_FILE" \
    && rm -f "$YARA_TARBALL"
handle_error $? "Failed to extract YARA source."

# 4 — Bootstrap
echo -e "  ${BOLD}Bootstrapping YARA...${NC}"
(cd "$YARA_SRC_DIR" && ./bootstrap.sh) &>>"$LOG_FILE" &
spinner $! "Bootstrapping"
handle_error $? "YARA bootstrap failed."

# 5 — Configure
echo -e "  ${BOLD}Configuring YARA...${NC}"
(cd "$YARA_SRC_DIR" && ./configure) &>>"$LOG_FILE" &
spinner $! "Configuring"
handle_error $? "YARA configure failed."

# 6 — Compile
echo -e "  ${BOLD}Compiling YARA (this may take a moment)...${NC}"
(cd "$YARA_SRC_DIR" && make) &>>"$LOG_FILE" &
spinner $! "Compiling"
handle_error $? "YARA compilation failed."

# 7 — Install
echo -e "  ${BOLD}Installing YARA...${NC}"
(cd "$YARA_SRC_DIR" && make install) &>>"$LOG_FILE" &
spinner $! "Installing YARA"
handle_error $? "YARA make install failed."

# 8 — Run test suite
echo -e "  ${BOLD}Running YARA test suite...${NC}"
(cd "$YARA_SRC_DIR" && make check) &>>"$LOG_FILE" &
spinner $! "Running make check"
if [ $? -ne 0 ]; then
    warn "YARA test suite reported failures — check $LOG_FILE for details."
else
    success "YARA test suite passed."
fi

# 9 — Update shared library cache
ldconfig &>>"$LOG_FILE"

# 10 — Verify binary
YARA_INSTALLED_VER=$(yara --version 2>/dev/null || true)
if [ -n "$YARA_INSTALLED_VER" ]; then
    success "YARA ${YARA_INSTALLED_VER} installed successfully → $(command -v yara)"
else
    warn "YARA binary not found in PATH after install — check $LOG_FILE for details."
fi

# 11 — Download Valhalla community YARA rules
echo -e "  ${BOLD}Downloading Valhalla community YARA rules...${NC}"
mkdir -p "$YARA_RULES_DIR"
curl -s \
    -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    -H 'Accept-Language: en-US,en;q=0.5' \
    --compressed \
    -H 'Referer: https://valhalla.nextron-systems.com/' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H 'DNT: 1' \
    -H 'Connection: keep-alive' \
    -H 'Upgrade-Insecure-Requests: 1' \
    --data 'demo=demo&apikey=1111111111111111111111111111111111111111111111111111111111111111&format=text' \
    -o "${YARA_RULES_DIR}/yara_rules.yar" \
    'https://valhalla.nextron-systems.com/api/v1/get' &
spinner $! "Downloading Valhalla YARA rules"
handle_error $? "Failed to download Valhalla YARA rules."

if [ -s "${YARA_RULES_DIR}/yara_rules.yar" ]; then
    RULE_COUNT=$(grep -c "^rule " "${YARA_RULES_DIR}/yara_rules.yar" 2>/dev/null || echo "unknown")
    success "Valhalla rules saved → ${YARA_RULES_DIR}/yara_rules.yar (${RULE_COUNT} rules)"
else
    warn "Valhalla rules file is empty — verify API key or network connectivity."
fi

# ============================================================
# STEP 4 — Download & apply ossec.conf
# ============================================================
step "Step 4 │ Configuration File"

curl -s -H "$HEADERS" -o /var/ossec/etc/ossec.conf \
    "$BASE_URL/ossec.conf" &
spinner $! "Downloading ossec.conf"
handle_error $? "Failed to download ossec.conf from GitHub."

sed -i "s/\${ManagerIP}/$MANAGER_IP/g"   /var/ossec/etc/ossec.conf
sed -i "s/\${AgentName}/$AGENT_NAME/g"   /var/ossec/etc/ossec.conf
success "ossec.conf applied and placeholders replaced."

# ============================================================
# STEP 5 — Systemd service setup
# ============================================================
step "Step 5 │ Systemd Service"

systemctl stop wazuh-agent &>>"$LOG_FILE"

SERVICE_SRC="/lib/systemd/system/wazuh-agent.service"
SERVICE_DST="/etc/systemd/system/cybersentinel-agent.service"

if [ -f "$SERVICE_SRC" ]; then
    cp "$SERVICE_SRC" "$SERVICE_DST"
    sed -i 's/wazuh-agent/cybersentinel-agent/g' "$SERVICE_DST"
    sed -i 's/Wazuh/CyberSentinel/g'             "$SERVICE_DST"
    systemctl daemon-reexec &>>"$LOG_FILE"
    systemctl daemon-reload &>>"$LOG_FILE"
    success "cybersentinel-agent.service created."
else
    handle_error 1 "Wazuh agent service definition not found — cannot create cybersentinel-agent service."
fi

# ============================================================
# STEP 6 — Active Response Scripts
# ============================================================
step "Step 6 │ Active Response Scripts"

mkdir -p "$BIN_DIR"

for file in llm_query.py remove-threat.sh yara.sh; do
    curl -s -H "$HEADERS" -o "$BIN_DIR/$file" \
        "$BASE_URL/ACTIVE-RESPONSE/$file" &
    spinner $! "Fetching $file"
    handle_error $? "Failed to download $file."
done

chmod +x "$BIN_DIR"/*
chown root:wazuh "$BIN_DIR"/*
success "Active response scripts installed and permissions set."

# ============================================================
# STEP 7 — Suricata IDS
# ============================================================
step "Step 7 │ Suricata IDS"

add-apt-repository -y ppa:oisf/suricata-stable &>>"$LOG_FILE" &
spinner $! "Adding Suricata PPA"

apt-get update -qq &>>"$LOG_FILE" &
spinner $! "Updating package lists"

apt-get install suricata -y &>>"$LOG_FILE" &
spinner $! "Installing Suricata"
handle_error $? "Failed to install Suricata."

cd /tmp/ && curl -sLO https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz &>>"$LOG_FILE" &
spinner $! "Downloading Emerging Threats rules"

tar -xzf /tmp/emerging.rules.tar.gz -C /tmp/ &>>"$LOG_FILE"
mkdir -p /etc/suricata/rules
mv /tmp/rules/*.rules /etc/suricata/rules/
chmod 640 /etc/suricata/rules/*.rules
success "Suricata rules installed."

curl -s -H "$HEADERS" -o /etc/suricata/suricata.yaml \
    "$BASE_URL/suricata.yaml" &
spinner $! "Downloading suricata.yaml"
handle_error $? "Failed to download suricata.yaml."

sed -i "s/AgentIP/$AgentIP/g"           /etc/suricata/suricata.yaml
sed -i "s/InterfaceName/$InterfaceName/g" /etc/suricata/suricata.yaml

systemctl restart suricata &>>"$LOG_FILE" &
spinner $! "Restarting Suricata"
success "Suricata configured and running."

# ============================================================
# STEP 8 — Start CyberSentinel service
# ============================================================
step "Step 8 │ Starting CyberSentinel Agent"

systemctl enable cybersentinel-agent &>>"$LOG_FILE"
systemctl start cybersentinel-agent &>>"$LOG_FILE" &
spinner $! "Starting cybersentinel-agent"
handle_error $? "Failed to start CyberSentinel Agent service."

# ============================================================
# STEP 9 — Configure log rotation
# ============================================================
step "Step 9 │ Log Rotation"

cat > "$LOGROTATE_CONF" <<'EOF'
/opt/cybersentinel/install.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    copytruncate
}
EOF

success "Log rotation configured → ${LOGROTATE_CONF}"
success "Logs will rotate weekly, keeping 8 compressed archives."

# ============================================================
# STEP 10 — Post-install verification
# ============================================================
step "Step 10 │ Post-Install Verification"

sleep 2  # Give service a moment to settle

CS_STATUS=$(systemctl is-active cybersentinel-agent 2>/dev/null)
SURICATA_STATUS=$(systemctl is-active suricata 2>/dev/null)
YARA_VER=$(yara --version 2>/dev/null || echo "not found")

if [ "$CS_STATUS" = "active" ]; then
    success "cybersentinel-agent  →  ${GREEN}running${NC}"
else
    warn "cybersentinel-agent  →  ${RED}${CS_STATUS}${NC}"
fi

if [ "$SURICATA_STATUS" = "active" ]; then
    success "suricata             →  ${GREEN}running${NC}"
else
    warn "suricata             →  ${RED}${SURICATA_STATUS}${NC}"
fi

if [ "$YARA_VER" != "not found" ]; then
    success "yara                 →  ${GREEN}v${YARA_VER}${NC}"
else
    warn "yara                 →  ${RED}not found${NC}"
fi

# Disarm rollback — installation succeeded
ROLLBACK_ENABLED=false

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║      CyberSentinel Installation Summary      ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo -e "  Manager IP   : ${BOLD}$MANAGER_IP${NC}"
echo -e "  Agent Name   : ${BOLD}$AGENT_NAME${NC}"
echo -e "  Agent IP     : ${BOLD}$AgentIP${NC} (${InterfaceName})"
echo -e "  YARA Version : ${BOLD}${YARA_VER}${NC}"
echo -e "  YARA Rules   : ${BOLD}/tmp/yara/rules/yara_rules.yar${NC}"
echo -e "  Install Log  : ${BOLD}$LOG_FILE${NC}"
echo -e "  Log Rotation : ${BOLD}${LOGROTATE_CONF}${NC} (weekly, 8 archives)"
echo -e "  Mode         : ${BOLD}$( $SKIP_PACKAGE && echo 'Repair/Reconfigure' || echo 'Full Install' )${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}CyberSentinel Agent installed successfully! ✔${NC}"
echo ""
