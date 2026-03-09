#!/bin/bash

# ============================================================
# CyberSentinel Installer Script for CentOS (7 / 8 / 9 / Stream)
# ============================================================

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/install.log"
GITHUB_REPO="cybersentinel-06/CyberSentinel-SIEM"
BIN_DIR="/var/ossec/active-response/bin"
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
# wget helpers
# ============================================================
wget_get() {
    local out="$1"
    local url="$2"
    wget -q --tries=3 --timeout=60 --no-check-certificate -O "$out" "$url"
}

wget_api() {
    local out="$1"
    local url="$2"
    wget -q --tries=3 --timeout=60 --no-check-certificate \
         --header="Authorization: Bearer ${GITHUB_TOKEN}" \
         -O "$out" "$url"
}

wget_status() {
    local url="$1"
    local header="${2:-}"
    local tmp
    tmp=$(mktemp)
    local code
    if [ -n "$header" ]; then
        code=$(wget -q --tries=1 --timeout=15 --no-check-certificate \
                    --server-response --header="$header" \
                    -O "$tmp" "$url" 2>&1 \
               | awk '/^  HTTP/{code=$2} END{print code+0}')
    else
        code=$(wget -q --tries=1 --timeout=15 --no-check-certificate \
                    --server-response \
                    -O "$tmp" "$url" 2>&1 \
               | awk '/^  HTTP/{code=$2} END{print code+0}')
    fi
    rm -f "$tmp"
    echo "${code:-0}"
}

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
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

print_banner

# ============================================================
# STEP 0 — GitHub Token
# ============================================================
step "Step 0 │ GitHub Token Validation"

read_masked() {
    local __var="$1"
    local __prompt="$2"
    local __input=""
    local __char=""
    printf "%s" "$__prompt"
    stty -echo -icanon min 1 time 0
    while IFS= read -r -d '' -n1 __char 2>/dev/null; do
        if [[ "$__char" == $'\n' || "$__char" == $'\r' || -z "$__char" ]]; then
            break
        fi
        if [[ "$__char" == $'\x7f' || "$__char" == $'\x08' ]]; then
            if [ ${#__input} -gt 0 ]; then
                __input="${__input%?}"
                printf '\b \b'
            fi
        else
            __input+="$__char"
            printf '*'
        fi
    done
    stty sane
    echo
    printf -v "$__var" '%s' "$__input"
}

validate_github_token() {
    local token="$1"
    local auth_header="Authorization: Bearer ${token}"
    local http_code
    http_code=$(wget_status "https://api.github.com/user" "$auth_header")
    if [ "$http_code" != "200" ]; then
        return 1
    fi
    http_code=$(wget_status "https://api.github.com/repos/$GITHUB_REPO" "$auth_header")
    if [ "$http_code" = "200" ]; then
        return 0
    elif [ "$http_code" = "404" ] || [ "$http_code" = "403" ]; then
        echo -e "\n  ${YELLOW}⚠ Token valid but cannot access repo '${GITHUB_REPO}' (HTTP $http_code).${NC}"
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
    read_masked GITHUB_TOKEN "  Enter GitHub Personal Access Token: "
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
        success "Token is valid and has repository access."
        break
    elif [ $val_result -eq 2 ]; then
        error "Token lacks repo scope (attempt $attempt/$MAX_ATTEMPTS)."
    else
        error "Invalid or expired token (attempt $attempt/$MAX_ATTEMPTS)."
    fi
    if [ $attempt -eq $MAX_ATTEMPTS ]; then
        error "Too many failed attempts. Exiting."
        exit 1
    fi
    echo -e "  ${YELLOW}Please try again.${NC}"
done

# ============================================================
# OS DETECTION
# ============================================================
step "OS Detection │ Identifying CentOS Version"

if [ ! -f /etc/centos-release ] && ! grep -qi "centos" /etc/os-release 2>/dev/null; then
    error "This installer only supports CentOS."
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
    AGENT_PATH="CENTOS-7-AGENT"
    WAZUH_RPM="wazuh-agent_4.14.0-1.x86_64.rpm"
    WAZUH_PKG_URL="https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.0-1.x86_64.rpm"
    PKG_MANAGER="yum"
    success "Agent path: ${AGENT_PATH} (CentOS 7)"
else
    AGENT_PATH="CENTOS-AGENT"
    WAZUH_RPM="wazuh-agent_4.14.0-1.x86_64.rpm"
    WAZUH_PKG_URL="https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.0-1.x86_64.rpm"
    PKG_MANAGER="dnf"
    success "Agent path: ${AGENT_PATH} (CentOS ${OS_MAJOR})"
fi

BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/AGENTS/${AGENT_PATH}"
success "Base URL: ${BASE_URL}"

# ============================================================
# STEP 1 — Manager IP + Agent Name
# ============================================================
step "Step 1 │ Configuration"

read -p "  Enter Manager IP: " MANAGER_IP
while [[ -z "$MANAGER_IP" ]]; do
    warn "Manager IP cannot be empty."
    read -p "  Enter Manager IP: " MANAGER_IP
done

printf "  Checking Manager reachability on port ${WAZUH_AGENT_PORT}..."
if nc -z -w5 "$MANAGER_IP" "$WAZUH_AGENT_PORT" &>/dev/null; then
    success "Manager reachable at ${MANAGER_IP}:${WAZUH_AGENT_PORT}."
else
    echo ""
    warn "Cannot reach ${MANAGER_IP}:${WAZUH_AGENT_PORT}."
    echo -e "  ${BOLD}How would you like to proceed?${NC}"
    echo "  [1] Continue anyway"
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
        *) echo -e "\n${YELLOW}Installation cancelled.${NC}\n"; exit 0 ;;
    esac
fi

read -p "  Enter Agent Name: " AGENT_NAME
while [[ -z "$AGENT_NAME" ]]; do
    warn "Agent Name cannot be empty."
    read -p "  Enter Agent Name: " AGENT_NAME
done

read -r InterfaceName AgentIP <<< "$(ip -4 -o addr show | grep -v '127.0.0.1' | awk '{print $2, $4}' | cut -d/ -f1 | head -n 1)"
success "Detected interface: ${InterfaceName} (${AgentIP})"

# ============================================================
# STEP 2 — Existing Agent Detection
# ============================================================
step "Step 2 │ Existing Agent Detection"

AGENT_EXISTS=false
if rpm -q wazuh-agent &>/dev/null || \
   systemctl list-units --all | grep -q "cybersentinel-agent" || \
   [ -f /var/ossec/etc/ossec.conf ]; then
    AGENT_EXISTS=true
fi

if $AGENT_EXISTS; then
    warn "Existing CyberSentinel/Wazuh agent detected."
    if systemctl is-active --quiet cybersentinel-agent 2>/dev/null; then
        echo -e "  Service: ${GREEN}Running (cybersentinel-agent)${NC}"
    elif systemctl is-active --quiet wazuh-agent 2>/dev/null; then
        echo -e "  Service: ${YELLOW}Running (wazuh-agent)${NC}"
    else
        echo -e "  Service: ${RED}Stopped${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo "  [1] Reinstall / Overwrite"
    echo "  [2] Repair configuration only"
    echo "  [3] Exit"
    read -p "  Choice [1/2/3]: " EXISTING_CHOICE
    case "$EXISTING_CHOICE" in
        1)
            warn "Stopping and removing existing installation..."
            systemctl stop cybersentinel-agent wazuh-agent &>/dev/null
            $PKG_MANAGER remove -y wazuh-agent &>>"$LOG_FILE"
            rm -f /etc/systemd/system/cybersentinel-agent.service
            systemctl daemon-reload &>>"$LOG_FILE"
            success "Old installation removed."
            SKIP_PACKAGE=false
            ;;
        2)
            warn "Skipping package reinstall — reconfigure only."
            SKIP_PACKAGE=true
            ;;
        3) echo -e "\n${YELLOW}Cancelled.${NC}\n"; exit 0 ;;
        *) error "Invalid choice."; exit 1 ;;
    esac
else
    success "No existing agent found. Fresh installation."
    SKIP_PACKAGE=false
fi

# Redirect output to log + console
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# STEP 3 — Prerequisites
# ============================================================
step "Step 3 │ Prerequisites"

if [ "$OS_MAJOR" = "7" ]; then
    # CentOS 7 — yum repos are broken (EOL/vault TLS), install only what's missing via direct RPM
    VAULT_OS="https://vault.centos.org/7.9.2009/os/x86_64/Packages"
    VAULT_UPD="https://vault.centos.org/7.9.2009/updates/x86_64/Packages"
    PREREQ_DIR="/tmp/cs-prereq-rpms"
    mkdir -p "$PREREQ_DIR"

    if ! command -v wget &>/dev/null; then
        printf "  ${CYAN}%-52s${NC}" "Downloading wget..."
        wget_get "$PREREQ_DIR/wget.rpm" \
            "${VAULT_UPD}/wget-1.14-18.el7_6.1.x86_64.rpm" >> "$LOG_FILE" 2>&1
        rpm -Uvh --nosignature --nodeps --replacepkgs \
            "$PREREQ_DIR/wget.rpm" >> "$LOG_FILE" 2>&1 \
            && printf " [${GREEN}✔${NC}]\n" || printf " [${YELLOW}already present${NC}]\n"
    fi

    if ! command -v nc &>/dev/null; then
        printf "  ${CYAN}%-52s${NC}" "Downloading nmap-ncat..."
        wget_get "$PREREQ_DIR/nmap-ncat.rpm" \
            "${VAULT_OS}/nmap-ncat-6.40-19.el7.x86_64.rpm" >> "$LOG_FILE" 2>&1
        rpm -Uvh --nosignature --nodeps --replacepkgs \
            "$PREREQ_DIR/nmap-ncat.rpm" >> "$LOG_FILE" 2>&1 \
            && printf " [${GREEN}✔${NC}]\n" || printf " [${YELLOW}already present${NC}]\n"
    fi

    rm -rf "$PREREQ_DIR"
    success "Prerequisites ready (CentOS 7)."
else
    $PKG_MANAGER install -y wget nmap-ncat &>>"$LOG_FILE" &
    spinner $! "Installing prerequisites (wget, nc)"
    handle_error $? "Failed to install prerequisites."
    success "Prerequisites ready."
fi

# ============================================================
# STEP 4 — Agent Package
# ============================================================
step "Step 4 │ Agent Package"

if ! $SKIP_PACKAGE; then
    wget_get "/tmp/$WAZUH_RPM" "$WAZUH_PKG_URL" >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading agent package"
    handle_error $? "Failed to download agent package."

    WAZUH_MANAGER="$MANAGER_IP" \
    WAZUH_AGENT_GROUP="Linux" \
    WAZUH_AGENT_NAME="$AGENT_NAME" \
    rpm -ivh "/tmp/$WAZUH_RPM" &>>"$LOG_FILE" &
    spinner $! "Installing agent package"
    handle_error $? "Failed to install agent package."
    success "Agent package installed."
else
    success "Package installation skipped (repair mode)."
fi

# ============================================================
# STEP 5 — YARA v4.5.5
# ============================================================
step "Step 5 │ YARA v4.5.5 Installation"

YARA_RULES_DIR="/tmp/yara/rules"

if [ "$OS_MAJOR" = "7" ]; then
    warn "YARA binary installation skipped on CentOS 7 (EOL — build toolchain unavailable)."
    YARA_VER="skipped"

    mkdir -p "$YARA_RULES_DIR"
    wget -q --tries=3 --timeout=60 --no-check-certificate \
         --header='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         --header='Referer: https://valhalla.nextron-systems.com/' \
         --header='DNT: 1' \
         --post-data='demo=demo&apikey=1111111111111111111111111111111111111111111111111111111111111111&format=text' \
         -O "${YARA_RULES_DIR}/yara_rules.yar" \
         'https://valhalla.nextron-systems.com/api/v1/get' &
    spinner $! "Downloading Valhalla YARA rules"
    handle_error $? "Failed to download Valhalla YARA rules."

    if [ -s "${YARA_RULES_DIR}/yara_rules.yar" ]; then
        RULE_COUNT=$(grep -c "^rule " "${YARA_RULES_DIR}/yara_rules.yar" 2>/dev/null || echo "unknown")
        success "Valhalla rules → ${YARA_RULES_DIR}/yara_rules.yar (${RULE_COUNT} rules)"
    else
        warn "Valhalla rules file is empty — check API key or connectivity."
    fi
else
    YARA_VERSION="4.5.5"
    YARA_TARBALL="v${YARA_VERSION}.tar.gz"
    YARA_URL="https://github.com/VirusTotal/yara/archive/${YARA_TARBALL}"
    YARA_SRC_DIR="/usr/local/bin/yara-${YARA_VERSION}"

    $PKG_MANAGER install -y make gcc autoconf automake libtool openssl-devel pkgconfig jq &>>"$LOG_FILE" &
    spinner $! "Installing YARA build dependencies"
    handle_error $? "Failed to install YARA build dependencies."

    wget_get "$YARA_TARBALL" "$YARA_URL" >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading YARA v${YARA_VERSION}"
    handle_error $? "Failed to download YARA."

    tar -xvzf "$YARA_TARBALL" -C /usr/local/bin/ &>>"$LOG_FILE" && rm -f "$YARA_TARBALL"
    handle_error $? "Failed to extract YARA."

    (cd "$YARA_SRC_DIR" && ./bootstrap.sh) &>>"$LOG_FILE" &
    spinner $! "Bootstrapping YARA"
    handle_error $? "YARA bootstrap failed."

    (cd "$YARA_SRC_DIR" && ./configure) &>>"$LOG_FILE" &
    spinner $! "Configuring YARA"
    handle_error $? "YARA configure failed."

    (cd "$YARA_SRC_DIR" && make) &>>"$LOG_FILE" &
    spinner $! "Compiling YARA"
    handle_error $? "YARA compilation failed."

    (cd "$YARA_SRC_DIR" && make install) &>>"$LOG_FILE" &
    spinner $! "Installing YARA"
    handle_error $? "YARA install failed."

    (cd "$YARA_SRC_DIR" && make check) &>>"$LOG_FILE" &
    spinner $! "Running YARA test suite"
    [ $? -ne 0 ] && warn "YARA tests had failures — check $LOG_FILE." || success "YARA test suite passed."

    ldconfig &>>"$LOG_FILE"

    YARA_VER=$(yara --version 2>/dev/null || echo "not found")
    [ "$YARA_VER" != "not found" ] \
        && success "YARA ${YARA_VER} installed → $(command -v yara)" \
        || warn "YARA binary not found after install."

    mkdir -p "$YARA_RULES_DIR"
    wget -q --tries=3 --timeout=60 --no-check-certificate \
         --header='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         --header='Referer: https://valhalla.nextron-systems.com/' \
         --header='DNT: 1' \
         --post-data='demo=demo&apikey=1111111111111111111111111111111111111111111111111111111111111111&format=text' \
         -O "${YARA_RULES_DIR}/yara_rules.yar" \
         'https://valhalla.nextron-systems.com/api/v1/get' &
    spinner $! "Downloading Valhalla YARA rules"
    handle_error $? "Failed to download Valhalla YARA rules."

    if [ -s "${YARA_RULES_DIR}/yara_rules.yar" ]; then
        RULE_COUNT=$(grep -c "^rule " "${YARA_RULES_DIR}/yara_rules.yar" 2>/dev/null || echo "unknown")
        success "Valhalla rules → ${YARA_RULES_DIR}/yara_rules.yar (${RULE_COUNT} rules)"
    else
        warn "Valhalla rules file is empty — check API key or connectivity."
    fi
fi

# ============================================================
# STEP 6 — ossec.conf
# ============================================================
step "Step 6 │ Configuration File"

wget_api /var/ossec/etc/ossec.conf "$BASE_URL/ossec.conf" >> "$LOG_FILE" 2>&1 &
spinner $! "Downloading ossec.conf"
handle_error $? "Failed to download ossec.conf."

sed -i "s/\${ManagerIP}/$MANAGER_IP/g" /var/ossec/etc/ossec.conf
sed -i "s/\${AgentName}/$AGENT_NAME/g" /var/ossec/etc/ossec.conf
success "ossec.conf applied."

# ============================================================
# STEP 7 — Systemd Service
# ============================================================
step "Step 7 │ Systemd Service"

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
    handle_error 1 "Wazuh service file not found."
fi

# ============================================================
# STEP 8 — Active Response Scripts
# ============================================================
step "Step 8 │ Active Response Scripts"

mkdir -p "$BIN_DIR"

if [ "$OS_MAJOR" = "7" ]; then
    # CentOS 7 — skip llm_query.py (no Python 3); keep yara.sh for future use
    AR_FILES="remove-threat.sh yara.sh"
else
    AR_FILES="llm_query.py remove-threat.sh yara.sh"
fi

for file in $AR_FILES; do
    wget_api "$BIN_DIR/$file" "$BASE_URL/ACTIVE-RESPONSE/$file" >> "$LOG_FILE" 2>&1 &
    spinner $! "Fetching $file"
    handle_error $? "Failed to download $file."
done

chmod +x "$BIN_DIR"/*
chown root:wazuh "$BIN_DIR"/*
success "Active response scripts installed."

# ============================================================
# STEP 9 — Suricata IDS
# ============================================================
step "Step 9 │ Suricata IDS"

if [ "$OS_MAJOR" = "7" ]; then
    $PKG_MANAGER install -y epel-release &>>"$LOG_FILE" &
    spinner $! "Adding EPEL repository"
    $PKG_MANAGER install -y suricata &>>"$LOG_FILE" &
    spinner $! "Installing Suricata"
else
    $PKG_MANAGER install -y epel-release &>>"$LOG_FILE" &
    spinner $! "Adding EPEL repository"
    if [ "$OS_MAJOR" = "8" ]; then
        $PKG_MANAGER config-manager --set-enabled powertools &>>"$LOG_FILE" || \
        $PKG_MANAGER config-manager --set-enabled PowerTools &>>"$LOG_FILE" || true
    else
        $PKG_MANAGER config-manager --set-enabled crb &>>"$LOG_FILE" || true
    fi
    $PKG_MANAGER install -y suricata &>>"$LOG_FILE" &
    spinner $! "Installing Suricata"
fi
handle_error $? "Failed to install Suricata."

wget_get /tmp/emerging.rules.tar.gz \
    "https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz" \
    >> "$LOG_FILE" 2>&1 &
spinner $! "Downloading Emerging Threats rules"

tar -xzf /tmp/emerging.rules.tar.gz -C /tmp/ &>>"$LOG_FILE"
mkdir -p /etc/suricata/rules
mv /tmp/rules/*.rules /etc/suricata/rules/
chmod 640 /etc/suricata/rules/*.rules
success "Suricata rules installed."

wget_api /etc/suricata/suricata.yaml "$BASE_URL/suricata.yaml" >> "$LOG_FILE" 2>&1 &
spinner $! "Downloading suricata.yaml"
handle_error $? "Failed to download suricata.yaml."

sed -i "s/AgentIP/$AgentIP/g"             /etc/suricata/suricata.yaml
sed -i "s/InterfaceName/$InterfaceName/g" /etc/suricata/suricata.yaml

systemctl enable suricata &>>"$LOG_FILE"
systemctl restart suricata &>>"$LOG_FILE" &
spinner $! "Starting Suricata"
success "Suricata configured and running."

# ============================================================
# STEP 10 — SELinux & Firewall
# ============================================================
step "Step 10 │ SELinux & Firewall"

if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        warn "SELinux Enforcing — setting to Permissive..."
        setenforce 0 &>>"$LOG_FILE"
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
        success "SELinux set to Permissive."
    else
        success "SELinux: ${SELINUX_STATUS} — no changes needed."
    fi
fi

if systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port="${WAZUH_AGENT_PORT}/tcp" &>>"$LOG_FILE"
    firewall-cmd --permanent --add-port="${WAZUH_AGENT_PORT}/udp" &>>"$LOG_FILE"
    firewall-cmd --reload &>>"$LOG_FILE"
    success "Firewall: port ${WAZUH_AGENT_PORT} opened."
else
    warn "firewalld not running — skipping firewall rule."
fi

# ============================================================
# STEP 11 — Start Service
# ============================================================
step "Step 11 │ Starting CyberSentinel Agent"

systemctl enable cybersentinel-agent &>>"$LOG_FILE"
systemctl start cybersentinel-agent &>>"$LOG_FILE" &
spinner $! "Starting cybersentinel-agent"
handle_error $? "Failed to start CyberSentinel Agent."

# ============================================================
# STEP 12 — Log Rotation
# ============================================================
step "Step 12 │ Log Rotation"

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

# ============================================================
# STEP 13 — Verification
# ============================================================
step "Step 13 │ Post-Install Verification"

sleep 2

CS_STATUS=$(systemctl is-active cybersentinel-agent 2>/dev/null)
SURICATA_STATUS=$(systemctl is-active suricata 2>/dev/null)

[ "$CS_STATUS"       = "active" ] && success "cybersentinel-agent  → running"  || warn "cybersentinel-agent  → ${CS_STATUS}"
[ "$SURICATA_STATUS" = "active" ] && success "suricata             → running"  || warn "suricata             → ${SURICATA_STATUS}"

if [ "$OS_MAJOR" = "7" ]; then
    warn "yara              → skipped (CentOS 7)"
else
    YARA_CHECK=$(yara --version 2>/dev/null || echo "not found")
    [ "$YARA_CHECK" != "not found" ] \
        && success "yara              → v${YARA_CHECK}" \
        || warn "yara              → not found"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║      CyberSentinel Installation Summary      ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo -e "  OS           : ${BOLD}CentOS ${OS_MAJOR}${NC}"
echo -e "  Agent Path   : ${BOLD}${AGENT_PATH}${NC}"
echo -e "  Manager IP   : ${BOLD}${MANAGER_IP}${NC}"
echo -e "  Agent Name   : ${BOLD}${AGENT_NAME}${NC}"
echo -e "  Agent IP     : ${BOLD}${AgentIP}${NC} (${InterfaceName})"
echo -e "  YARA Version : ${BOLD}$( [ "$OS_MAJOR" = "7" ] && echo 'skipped (CentOS 7)' || echo "${YARA_VER}" )${NC}"
echo -e "  YARA Rules   : ${BOLD}${YARA_RULES_DIR}/yara_rules.yar${NC}"
echo -e "  Install Log  : ${BOLD}${LOG_FILE}${NC}"
echo -e "  Log Rotation : ${BOLD}${LOGROTATE_CONF}${NC}"
echo -e "  Mode         : ${BOLD}$( $SKIP_PACKAGE && echo 'Repair/Reconfigure' || echo 'Full Install' )${NC}"
echo -e "  LLM Query    : ${BOLD}$( [ "$OS_MAJOR" = "7" ] && echo 'Skipped (CentOS 7)' || echo 'Installed' )${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}CyberSentinel Agent installed successfully! ✔${NC}"
echo ""
