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

# ============================================================
# Setup log dir early
# ============================================================
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

print_banner

# ============================================================
# OS DETECTION — Must be CentOS
# ============================================================
step "OS Detection │ Identifying CentOS Version"

if [ ! -f /etc/centos-release ] && ! grep -qi "centos" /etc/os-release 2>/dev/null; then
    error "This installer only supports CentOS. Detected OS does not appear to be CentOS."
    error "Please use the appropriate installer for your operating system."
    exit 1
fi

# Parse the major version number
OS_VERSION_RAW=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null \
    || grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release \
    || grep -oP '[0-9]+' /etc/centos-release | head -1)
OS_MAJOR=$(echo "$OS_VERSION_RAW" | grep -oP '^[0-9]+')

if [ -z "$OS_MAJOR" ]; then
    error "Could not determine CentOS major version. Exiting."
    exit 1
fi

success "Detected: CentOS ${OS_MAJOR}"

# ============================================================
# Set agent path and package vars based on CentOS version
# ============================================================
if [ "$OS_MAJOR" = "7" ]; then
    AGENT_PATH="CENTOS-7-AGENT"
    WAZUH_RPM="wazuh-agent_4.14.0-1.x86_64.rpm"
    WAZUH_PKG_URL="https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.0-1.x86_64.rpm"
    PKG_MANAGER="yum"
    success "Agent path set to: ${AGENT_PATH} (CentOS 7 — legacy path)"
else
    # CentOS 8, 9, Stream, or any future version
    AGENT_PATH="CENTOS-AGENT"
    WAZUH_RPM="wazuh-agent_4.14.0-1.x86_64.rpm"
    WAZUH_PKG_URL="https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.0-1.x86_64.rpm"
    PKG_MANAGER="dnf"
    success "Agent path set to: ${AGENT_PATH} (CentOS ${OS_MAJOR})"
fi

BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/AGENTS/${AGENT_PATH}"
success "Base URL: ${BASE_URL}"

# ============================================================
# PYTHON 3 — CentOS 7 only (compile from source — most reliable)
# ============================================================
install_python3_centos7() {
    local PYTHON_VER="3.11.9"
    local PYTHON_SRC_URL="https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tgz"
    local PYTHON_SRC_DIR="/usr/local/src/Python-${PYTHON_VER}"

    # Helper: run a command with spinner, logging stdout+stderr to LOG_FILE
    # Usage: run_logged "Label" cmd arg1 arg2 ...
    run_logged() {
        local label="$1"; shift
        "$@" >> "$LOG_FILE" 2>&1 &
        spinner $! "$label"
        local rc=$?
        if [ $rc -ne 0 ]; then
            echo -e "  ${RED}✘ '$label' failed (exit $rc). Last 10 lines of log:${NC}" >&2
            tail -10 "$LOG_FILE" | sed 's/^/    /' >&2
            exit $rc
        fi
    }

    # --- Build dependencies ---
    run_logged "Installing build dependencies" \
        yum install -y gcc make openssl-devel bzip2-devel libffi-devel \
                       zlib-devel readline-devel sqlite-devel xz-devel wget curl

    # --- Download source ---
    run_logged "Downloading Python ${PYTHON_VER}" \
        curl -fL -o "/tmp/Python-${PYTHON_VER}.tgz" "$PYTHON_SRC_URL"

    # --- Extract ---
    mkdir -p /usr/local/src
    tar -xzf "/tmp/Python-${PYTHON_VER}.tgz" -C /usr/local/src/ >> "$LOG_FILE" 2>&1
    handle_error $? "Failed to extract Python source."

    # --- Configure ---
    run_logged "Configuring Python ${PYTHON_VER}" \
        bash -c "cd '$PYTHON_SRC_DIR' && ./configure --enable-optimizations --with-ensurepip=install"

    # --- Compile ---
    run_logged "Compiling Python ${PYTHON_VER} (may take several minutes)" \
        bash -c "cd '$PYTHON_SRC_DIR' && make -j$(nproc)"

    # --- Install (altinstall preserves system python2) ---
    run_logged "Installing Python ${PYTHON_VER}" \
        bash -c "cd '$PYTHON_SRC_DIR' && make altinstall"

    # Symlink python3 → python3.11
    [ ! -f /usr/bin/python3  ] && ln -s /usr/local/bin/python3.11  /usr/bin/python3
    [ ! -f /usr/bin/pip3     ] && ln -s /usr/local/bin/pip3.11     /usr/bin/pip3     2>/dev/null || true

    # Cleanup
    rm -f "/tmp/Python-${PYTHON_VER}.tgz"
}

if [ "$OS_MAJOR" = "7" ]; then
    step "Python 3 │ Installation (CentOS 7)"

    PYTHON3_BIN=$(command -v python3 2>/dev/null || true)
    PYTHON3_VER=""
    if [ -n "$PYTHON3_BIN" ]; then
        PYTHON3_VER=$("$PYTHON3_BIN" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi

    if [ -n "$PYTHON3_VER" ]; then
        success "Python 3 already installed: ${PYTHON3_BIN} (v${PYTHON3_VER})"
    else
        warn "Python 3 not found. Installing Python 3.11.9 from source..."
        install_python3_centos7

        PYTHON3_BIN=$(command -v python3 2>/dev/null || true)
        if [ -z "$PYTHON3_BIN" ]; then
            error "Python 3 installation failed — binary not found in PATH."
            exit 1
        fi
        PYTHON3_VER=$("$PYTHON3_BIN" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        success "Python 3 installed successfully: ${PYTHON3_BIN} (v${PYTHON3_VER})"

        "$PYTHON3_BIN" -m pip install --upgrade pip &>>"$LOG_FILE" &
        spinner $! "Upgrading pip"
    fi

    export PATH="/usr/local/bin:/usr/bin:$PATH"
    success "Python 3 is ready: $(python3 --version 2>&1)"
fi

# ============================================================
# Rollback trap — cleans up on unexpected exit
# ============================================================
ROLLBACK_ENABLED=false

rollback() {
    local exit_code=$?
    if $ROLLBACK_ENABLED && [ $exit_code -ne 0 ]; then
        echo ""
        warn "Installation failed (exit code $exit_code). Running rollback..."
        systemctl stop cybersentinel-agent wazuh-agent &>/dev/null || true
        if [ "$OS_MAJOR" = "7" ]; then
            yum remove -y wazuh-agent &>/dev/null || true
        else
            dnf remove -y wazuh-agent &>/dev/null || true
        fi
        rm -f /etc/systemd/system/cybersentinel-agent.service
        rm -f /tmp/"$WAZUH_RPM"
        rm -rf /usr/local/bin/yara-4.5.5
        rm -rf /usr/local/src/Python-3.11.9
        rm -f /tmp/Python-3.11.9.tgz
        systemctl daemon-reload &>/dev/null || true
        error "Rollback complete. System restored to pre-install state."
        error "Check the log for details: $LOG_FILE"
    fi
}

trap rollback EXIT

# ============================================================
# STEP 0 — Collect & validate GitHub token
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
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/user")
    if [ "$http_code" -ne 200 ]; then
        return 1
    fi
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
        success "Token is valid and has access to the repository."
        break
    elif [ $val_result -eq 2 ]; then
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

# Reachability check
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
if rpm -q wazuh-agent &>/dev/null || \
   systemctl list-units --all | grep -q "cybersentinel-agent" || \
   [ -f /var/ossec/etc/ossec.conf ]; then
    AGENT_EXISTS=true
fi

if $AGENT_EXISTS; then
    warn "An existing CyberSentinel/Wazuh agent installation was detected."

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
            if [ "$OS_MAJOR" = "7" ]; then
                yum remove -y wazuh-agent &>>"$LOG_FILE"
            else
                dnf remove -y wazuh-agent &>>"$LOG_FILE"
            fi
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
# STEP 3 — Install prerequisites (curl, wget, nc)
# ============================================================
step "Step 3 │ Prerequisites"

echo -e "  ${BOLD}Ensuring required tools are present...${NC}"

if [ "$OS_MAJOR" = "7" ]; then
    yum install -y curl wget nmap-ncat &>>"$LOG_FILE" &
else
    dnf install -y curl wget nmap-ncat &>>"$LOG_FILE" &
fi
spinner $! "Installing prerequisites (curl, wget, nc)"
handle_error $? "Failed to install prerequisites."
success "Prerequisites ready."

# ============================================================
# STEP 4 — Download & Install CyberSentinel Agent package
# ============================================================
step "Step 4 │ Agent Package"

if ! $SKIP_PACKAGE; then
    ROLLBACK_ENABLED=true   # arm rollback

    echo -e "  ${BOLD}Downloading agent package...${NC}"
    curl -L -o "/tmp/$WAZUH_RPM" "$WAZUH_PKG_URL" &>>"$LOG_FILE" &
    spinner $! "Downloading"
    handle_error $? "Failed to download CyberSentinel Agent package."

    echo -e "  ${BOLD}Installing agent package...${NC}"
    WAZUH_MANAGER="$MANAGER_IP" \
    WAZUH_AGENT_GROUP="Linux" \
    WAZUH_AGENT_NAME="$AGENT_NAME" \
    rpm -ivh "/tmp/$WAZUH_RPM" &>>"$LOG_FILE" &
    spinner $! "Installing"
    handle_error $? "Failed to install CyberSentinel Agent package."
    success "Agent package installed."
else
    success "Package installation skipped (repair mode)."
fi

# ============================================================
# STEP 5 — Install YARA v4.5.5 from source
# ============================================================
step "Step 5 │ YARA v4.5.5 Installation"

YARA_VERSION="4.5.5"
YARA_TARBALL="v${YARA_VERSION}.tar.gz"
YARA_URL="https://github.com/VirusTotal/yara/archive/${YARA_TARBALL}"
YARA_SRC_DIR="/usr/local/bin/yara-${YARA_VERSION}"
YARA_RULES_DIR="/tmp/yara/rules"

# 1 — Dependencies
echo -e "  ${BOLD}Installing YARA build dependencies...${NC}"
if [ "$OS_MAJOR" = "7" ]; then
    yum install -y make gcc autoconf automake libtool openssl-devel pkgconfig jq &>>"$LOG_FILE" &
else
    dnf install -y make gcc autoconf automake libtool openssl-devel pkgconfig jq &>>"$LOG_FILE" &
fi
spinner $! "Installing build dependencies"
handle_error $? "Failed to install YARA build dependencies."

# 2 — Download source tarball
echo -e "  ${BOLD}Downloading YARA v${YARA_VERSION} source...${NC}"
curl -L -o "$YARA_TARBALL" "$YARA_URL" &>>"$LOG_FILE" &
spinner $! "Downloading YARA v${YARA_VERSION}"
handle_error $? "Failed to download YARA source tarball."

# 3 — Extract
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
# STEP 6 — Download & apply ossec.conf
# ============================================================
step "Step 6 │ Configuration File"

curl -s -H "$HEADERS" -o /var/ossec/etc/ossec.conf \
    "$BASE_URL/ossec.conf" &
spinner $! "Downloading ossec.conf"
handle_error $? "Failed to download ossec.conf from GitHub."

sed -i "s/\${ManagerIP}/$MANAGER_IP/g"   /var/ossec/etc/ossec.conf
sed -i "s/\${AgentName}/$AGENT_NAME/g"   /var/ossec/etc/ossec.conf
success "ossec.conf applied and placeholders replaced."

# ============================================================
# STEP 7 — Systemd service setup
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
    handle_error 1 "Wazuh agent service definition not found — cannot create cybersentinel-agent service."
fi

# ============================================================
# STEP 8 — Active Response Scripts
# ============================================================
step "Step 8 │ Active Response Scripts"

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
# STEP 9 — Suricata IDS
# ============================================================
step "Step 9 │ Suricata IDS"

echo -e "  ${BOLD}Installing Suricata via EPEL...${NC}"

if [ "$OS_MAJOR" = "7" ]; then
    # CentOS 7 — EPEL via yum
    yum install -y epel-release &>>"$LOG_FILE" &
    spinner $! "Adding EPEL repository"
    yum install -y suricata &>>"$LOG_FILE" &
    spinner $! "Installing Suricata"
else
    # CentOS 8/9/Stream — EPEL via dnf; also enable PowerTools/CRB for deps
    dnf install -y epel-release &>>"$LOG_FILE" &
    spinner $! "Adding EPEL repository"

    # Enable PowerTools (CentOS 8) or CRB (CentOS 9/Stream)
    if [ "$OS_MAJOR" = "8" ]; then
        dnf config-manager --set-enabled powertools &>>"$LOG_FILE" || \
        dnf config-manager --set-enabled PowerTools &>>"$LOG_FILE" || true
    else
        dnf config-manager --set-enabled crb &>>"$LOG_FILE" || true
    fi

    dnf install -y suricata &>>"$LOG_FILE" &
    spinner $! "Installing Suricata"
fi
handle_error $? "Failed to install Suricata."

# Download Emerging Threats rules
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

sed -i "s/AgentIP/$AgentIP/g"             /etc/suricata/suricata.yaml
sed -i "s/InterfaceName/$InterfaceName/g" /etc/suricata/suricata.yaml

systemctl enable suricata &>>"$LOG_FILE"
systemctl restart suricata &>>"$LOG_FILE" &
spinner $! "Restarting Suricata"
success "Suricata configured and running."

# ============================================================
# STEP 10 — SELinux / Firewall adjustments
# ============================================================
step "Step 10 │ SELinux & Firewall"

# SELinux — set to permissive if enforcing (Wazuh agent known issue on CentOS 7)
if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        warn "SELinux is Enforcing. Setting to Permissive for agent compatibility..."
        setenforce 0 &>>"$LOG_FILE"
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
        success "SELinux set to Permissive (persisted in /etc/selinux/config)."
    else
        success "SELinux status: ${SELINUX_STATUS} — no changes needed."
    fi
fi

# Firewall — open Wazuh agent port if firewalld is active
if systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port="${WAZUH_AGENT_PORT}/tcp" &>>"$LOG_FILE"
    firewall-cmd --permanent --add-port="${WAZUH_AGENT_PORT}/udp" &>>"$LOG_FILE"
    firewall-cmd --reload &>>"$LOG_FILE"
    success "Firewall rule added: port ${WAZUH_AGENT_PORT} (TCP/UDP) opened."
else
    warn "firewalld is not running — skipping firewall rule (check iptables manually if needed)."
fi

# ============================================================
# STEP 11 — Start CyberSentinel service
# ============================================================
step "Step 11 │ Starting CyberSentinel Agent"

systemctl enable cybersentinel-agent &>>"$LOG_FILE"
systemctl start cybersentinel-agent &>>"$LOG_FILE" &
spinner $! "Starting cybersentinel-agent"
handle_error $? "Failed to start CyberSentinel Agent service."

# ============================================================
# STEP 12 — Configure log rotation
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
success "Logs will rotate weekly, keeping 8 compressed archives."

# ============================================================
# STEP 13 — Post-install verification
# ============================================================
step "Step 13 │ Post-Install Verification"

sleep 2

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

if [ "$OS_MAJOR" = "7" ]; then
    PYTHON3_CHECK=$(python3 --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "not found")
    if [ "$PYTHON3_CHECK" != "not found" ]; then
        success "python3              →  ${GREEN}v${PYTHON3_CHECK}${NC}"
    else
        warn "python3              →  ${RED}not found${NC}"
    fi
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
echo -e "  OS           : ${BOLD}CentOS ${OS_MAJOR}${NC}"
echo -e "  Agent Path   : ${BOLD}${AGENT_PATH}${NC}"
[ "$OS_MAJOR" = "7" ] && echo -e "  Python 3     : ${BOLD}$(python3 --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo 'n/a')${NC}"
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
