#!/bin/bash

# CyberSentinel Installer Script - CentOS Edition
# Uses GitHub API contents endpoint for reliable private repo access.
# Note: -k is used for TLS because CentOS 7's default CA bundle is often
# outdated and rejects GitHub's modern cert chain. If you've updated
# ca-certificates (yum install -y ca-certificates && update-ca-trust extract)
# you can remove -k for proper TLS verification.

LOG_DIR="/opt/cybersentinel"
LOG_FILE="$LOG_DIR/install.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# GitHub API contents endpoint — works reliably for private repos with PAT auth.
# Format: https://api.github.com/repos/<owner>/<repo>/contents/<path>?ref=<branch>
API_BASE="https://api.github.com/repos/cybersentinel-06/CyberSentinel-SIEM/contents/AGENTS/CENTOS-AGENT"
BRANCH="main"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Helper: download a file from the repo using the API contents endpoint
gh_download() {
    local remote_path="$1"
    local local_path="$2"
    curl --tlsv1.2 -k -fsSL \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.raw" \
        -o "$local_path" \
        "$API_BASE/$remote_path?ref=$BRANCH"
}

# ─────────────────────────────────────────────
# STEP 1: Ask for GitHub Token and validate it
# ─────────────────────────────────────────────
echo ""
log "${CYAN}=== CyberSentinel Agent Installer (CentOS) ===${NC}"
echo ""

while true; do
    read -rsp "Enter GitHub Personal Access Token: " GITHUB_TOKEN
    echo ""

    if [[ -z "$GITHUB_TOKEN" ]]; then
        log "${RED}[ERROR] Token cannot be empty. Please try again.${NC}"
        continue
    fi

    HTTP_STATUS=$(curl --tlsv1.2 -k -s -o /dev/null -w "%{http_code}" \
        --max-time 15 \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.raw" \
        "$API_BASE/ossec.conf?ref=$BRANCH")

    if [[ "$HTTP_STATUS" == "200" ]]; then
        log "${GREEN}[OK] Token is valid. Repository access confirmed.${NC}"
        break
    elif [[ "$HTTP_STATUS" == "401" ]]; then
        log "${RED}[ERROR] Token is invalid or expired (HTTP 401). Please enter a valid token.${NC}"
    elif [[ "$HTTP_STATUS" == "403" ]]; then
        log "${RED}[ERROR] Forbidden (HTTP 403). Token lacks scope, or SSO not authorized for this org.${NC}"
    elif [[ "$HTTP_STATUS" == "404" ]]; then
        log "${RED}[ERROR] Not found (HTTP 404). Check token has 'repo' scope, or path is wrong.${NC}"
    elif [[ "$HTTP_STATUS" == "000" ]]; then
        log "${RED}[ERROR] No response from server (HTTP 000). Network/DNS/TLS failure.${NC}"
        log "${YELLOW}        Try: curl --tlsv1.2 -k -v https://api.github.com${NC}"
    else
        log "${RED}[ERROR] Unexpected response (HTTP $HTTP_STATUS).${NC}"
    fi
done

# ─────────────────────────────────────────────
# STEP 2: Ask for Manager IP and Agent Name
# ─────────────────────────────────────────────
echo ""
read -rp "Enter Manager IP: " MANAGER_IP
read -rp "Enter Agent Name: " AGENT_NAME
echo ""

if [[ -z "$MANAGER_IP" || -z "$AGENT_NAME" ]]; then
    log "${RED}[ERROR] Manager IP and Agent Name cannot be empty. Exiting.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
# STEP 3: Check if agent already exists
# ─────────────────────────────────────────────
AGENT_EXISTS=false

if rpm -q wazuh-agent &>/dev/null || systemctl list-units --full --all 2>/dev/null | grep -q "cybersentinel-agent"; then
    AGENT_EXISTS=true
fi

if $AGENT_EXISTS; then
    echo ""
    log "${YELLOW}[INFO] An existing CyberSentinel Agent installation was detected.${NC}"
    echo ""
    echo "  What would you like to do?"
    echo "  1) Reinstall   - Remove and reinstall the agent fresh"
    echo "  2) Reconfigure - Reapply Manager IP, Agent Name, and config files only"
    echo "  3) Exit        - Abort and make no changes"
    echo ""
    read -rp "Enter your choice [1/2/3]: " USER_CHOICE
    echo ""

    case "$USER_CHOICE" in
        1)
            log "${YELLOW}[INFO] Reinstalling CyberSentinel Agent...${NC}"
            systemctl stop cybersentinel-agent &>>"$LOG_FILE" || true
            systemctl stop wazuh-agent &>>"$LOG_FILE" || true
            systemctl disable cybersentinel-agent &>>"$LOG_FILE" || true
            rpm -e wazuh-agent &>>"$LOG_FILE" || true
            rm -f /etc/systemd/system/cybersentinel-agent.service
            systemctl daemon-reload &>>"$LOG_FILE"
            log "${GREEN}[OK] Existing agent removed. Proceeding with fresh installation...${NC}"
            ;;
        2)
            log "${YELLOW}[INFO] Reconfiguring existing agent...${NC}"

            log "[INFO] Fetching ossec.conf from repository..."
            if ! gh_download "ossec.conf" /var/ossec/etc/ossec.conf; then
                log "${RED}[ERROR] Failed to download ossec.conf.${NC}"
                exit 1
            fi

            sed -i "s/\${ManagerIP}/$MANAGER_IP/g" /var/ossec/etc/ossec.conf
            sed -i "s/\${AgentName}/$AGENT_NAME/g" /var/ossec/etc/ossec.conf

            log "[INFO] Fetching active response scripts..."
            BIN_DIR="/var/ossec/active-response/bin"
            mkdir -p "$BIN_DIR"

            for SCRIPT in llm_query.py remove-threat.sh yara.sh; do
                if ! gh_download "ACTIVE-RESPONSE/$SCRIPT" "$BIN_DIR/$SCRIPT"; then
                    log "${RED}[ERROR] Failed to fetch $SCRIPT.${NC}"
                    exit 1
                fi
            done

            chmod +x "$BIN_DIR"/*
            chown root:ossec "$BIN_DIR"/* 2>/dev/null || chown root "$BIN_DIR"/*

            log "[INFO] Restarting CyberSentinel Agent..."
            systemctl restart cybersentinel-agent &>>"$LOG_FILE" \
                || systemctl restart wazuh-agent &>>"$LOG_FILE"

            log "${GREEN}[OK] Reconfiguration complete. CyberSentinel Agent restarted.${NC}"
            exit 0
            ;;
        3)
            log "${YELLOW}[INFO] Exiting. No changes were made.${NC}"
            exit 0
            ;;
        *)
            log "${RED}[ERROR] Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
fi

# ─────────────────────────────────────────────
# STEP 4: Download and install the agent (CentOS RPM)
# ─────────────────────────────────────────────
log "[INFO] Downloading CyberSentinel Agent package (v4.14.0, CentOS)..."

PACKAGE_URL="https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.0-1.x86_64.rpm"
PACKAGE_FILE="/tmp/wazuh-agent-4.14.0-1.x86_64.rpm"

if ! curl --tlsv1.2 -k -fsSL -o "$PACKAGE_FILE" "$PACKAGE_URL" || [[ ! -f "$PACKAGE_FILE" ]]; then
    log "${RED}[ERROR] Failed to download CyberSentinel Agent package.${NC}"
    exit 1
fi

log "${GREEN}[OK] Package downloaded.${NC}"

log "[INFO] Installing CyberSentinel Agent..."
WAZUH_MANAGER="$MANAGER_IP" \
WAZUH_AGENT_GROUP="linux" \
WAZUH_AGENT_NAME="$AGENT_NAME" \
    rpm -ivh "$PACKAGE_FILE" &>>"$LOG_FILE"

if [[ $? -ne 0 ]]; then
    log "${RED}[ERROR] Installation failed. Check $LOG_FILE for details.${NC}"
    exit 1
fi

log "${GREEN}[OK] Agent installed successfully.${NC}"

# ─────────────────────────────────────────────
# STEP 5: Fetch ossec.conf from private repo
# ─────────────────────────────────────────────
log "[INFO] Fetching ossec.conf from repository..."

if ! gh_download "ossec.conf" /var/ossec/etc/ossec.conf; then
    log "${RED}[ERROR] Failed to download ossec.conf.${NC}"
    exit 1
fi

sed -i "s/\${ManagerIP}/$MANAGER_IP/g" /var/ossec/etc/ossec.conf
sed -i "s/\${AgentName}/$AGENT_NAME/g" /var/ossec/etc/ossec.conf

log "${GREEN}[OK] ossec.conf applied.${NC}"

# ─────────────────────────────────────────────
# STEP 6: Fetch Active Response Scripts
# ─────────────────────────────────────────────
log "[INFO] Fetching active response scripts..."

BIN_DIR="/var/ossec/active-response/bin"
mkdir -p "$BIN_DIR"

for SCRIPT in llm_query.py remove-threat.sh yara.sh; do
    if ! gh_download "ACTIVE-RESPONSE/$SCRIPT" "$BIN_DIR/$SCRIPT"; then
        log "${RED}[ERROR] Failed to fetch $SCRIPT.${NC}"
        exit 1
    fi
    log "  [OK] $SCRIPT fetched."
done

chmod +x "$BIN_DIR"/*
chown root:ossec "$BIN_DIR"/* 2>/dev/null || chown root "$BIN_DIR"/*

log "${GREEN}[OK] Active response scripts installed.${NC}"

# ─────────────────────────────────────────────
# STEP 7: Set up CyberSentinel systemd service
# ─────────────────────────────────────────────
log "[INFO] Configuring CyberSentinel systemd service..."

systemctl stop wazuh-agent &>>"$LOG_FILE" || true

SERVICE_SRC="/lib/systemd/system/wazuh-agent.service"
SERVICE_DST="/etc/systemd/system/cybersentinel-agent.service"

if [[ -f "$SERVICE_SRC" ]]; then
    cp "$SERVICE_SRC" "$SERVICE_DST"
    sed -i 's/wazuh-agent/cybersentinel-agent/g' "$SERVICE_DST"
    systemctl daemon-reload &>>"$LOG_FILE"
    log "${GREEN}[OK] cybersentinel-agent service registered.${NC}"
else
    log "${RED}[ERROR] wazuh-agent.service not found. Cannot create cybersentinel-agent service.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
# STEP 8: Enable and start the agent
# ─────────────────────────────────────────────
log "[INFO] Enabling and starting CyberSentinel Agent..."

systemctl enable cybersentinel-agent &>>"$LOG_FILE"
systemctl start cybersentinel-agent &>>"$LOG_FILE"

if [[ $? -ne 0 ]]; then
    log "${RED}[ERROR] Failed to start CyberSentinel Agent. Check $LOG_FILE for details.${NC}"
    exit 1
fi

echo ""
log "${GREEN}================================================${NC}"
log "${GREEN}  CyberSentinel Agent installed successfully!  ${NC}"
log "${GREEN}  cybersentinel-agent is running.              ${NC}"
log "${GREEN}================================================${NC}"
echo ""
