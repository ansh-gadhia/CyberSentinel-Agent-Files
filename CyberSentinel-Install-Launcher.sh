#!/bin/bash

# ============================================================
# CyberSentinel — Public Launcher
# ============================================================
# This is the ONLY script that lives on a public repo.
# It validates the GitHub token, then streams the private
# main installer directly into bash via a kernel pipe —
# the installer is NEVER written to disk on the client.
# ============================================================

GITHUB_REPO="cybersentinel-06/CyberSentinel-SIEM"
PRIVATE_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/AGENTS/INSTALLATION-SCRIPTS/CyberSentinel-Linux-Install.sh"

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
    echo "       S E N T I N E L   L A U N C H E R"
    echo -e "${NC}"
}

step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}\n  ${BOLD}${1}${NC}\n${CYAN}══════════════════════════════════════════${NC}"; }
success() { echo -e "  ${GREEN}✔ ${1}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${1}${NC}"; }
error()   { echo -e "  ${RED}✘ ${1}${NC}" >&2; }

# ============================================================
# Cleanup trap — always wipe the token from memory on exit,
# regardless of whether the installer succeeded or failed.
# ============================================================
cleanup() {
    unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED
}
trap cleanup EXIT

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

print_banner

# ============================================================
# STEP 0 — Collect & validate GitHub token
# ============================================================
step "Step 0 │ GitHub Token Validation"

# Masked password input — token never echoed to terminal.
read_masked() {
    local __var="$1" __prompt="$2" __input="" __char=""
    printf "%s" "$__prompt"
    stty -echo -icanon min 1 time 0
    while IFS= read -r -d '' -n1 __char 2>/dev/null; do
        [[ "$__char" == $'\n' || "$__char" == $'\r' || -z "$__char" ]] && break
        if [[ "$__char" == $'\x7f' || "$__char" == $'\x08' ]]; then
            [ ${#__input} -gt 0 ] && { __input="${__input%?}"; printf '\b \b'; }
        else
            __input+="$__char"; printf '*'
        fi
    done
    stty sane; echo
    printf -v "$__var" '%s' "$__input"
}

validate_github_token() {
    local token="$1"
    local http_code

    # 1 — Check the token itself is valid.
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/user")
    if [ "$http_code" -ne 200 ]; then
        return 1
    fi

    # 2 — Check the token can read the private repo.
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
_RAW_TOKEN=""

while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))

    read_masked _RAW_TOKEN "  Enter GitHub Personal Access Token: "

    # Show masked confirmation.
    if [ ${#_RAW_TOKEN} -gt 8 ]; then
        masked="${_RAW_TOKEN:0:4}$(printf '%0.s*' $(seq 1 $((${#_RAW_TOKEN} - 8))))${_RAW_TOKEN: -4}"
    else
        masked="****"
    fi
    echo -e "  Token entered: ${YELLOW}${masked}${NC}"

    printf "  Validating token..."
    validate_github_token "$_RAW_TOKEN"
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
        unset _RAW_TOKEN
        exit 1
    fi
    echo -e "  ${YELLOW}Please try again.${NC}"
done

# ============================================================
# STEP 1 — Stream & execute the private installer
# ============================================================
step "Step 1 │ Launching Installer"

echo -e "  ${BOLD}Fetching and executing private installer...${NC}"
echo -e "  ${YELLOW}The installer script is streamed directly into memory.${NC}"
echo -e "  ${YELLOW}It is never written to disk at any point.${NC}"
echo ""

# Export the validated token and the pre-validation flag so the main script
# skips its own Step 0 entirely. Both vars are wiped by the cleanup trap
# the moment this launcher process exits — success or failure.
export CS_GITHUB_TOKEN="$_RAW_TOKEN"
export CS_TOKEN_PREVALIDATED="1"

# Scrub the local copy immediately — the exported env var is the only copy now.
unset _RAW_TOKEN

# ── The core security line ──────────────────────────────────
# bash <(...) uses a file descriptor (e.g. /dev/fd/63), NOT a temp file.
# The script content lives only in the kernel pipe buffer.
# There is nothing on disk to recover, even if the process is killed mid-run.
# ───────────────────────────────────────────────────────────
bash <(curl -fsSL \
    --tlsv1.2 \
    -H "Authorization: Bearer $CS_GITHUB_TOKEN" \
    "$PRIVATE_SCRIPT_URL")

INSTALL_EXIT=$?

# env vars are wiped by the trap on EXIT, but unset here too for explicitness.
unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED

if [ $INSTALL_EXIT -eq 0 ]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}Launcher finished successfully.${NC}"
else
    echo ""
    error "Installer exited with code ${INSTALL_EXIT}. See /opt/cybersentinel/install.log for details."
fi

exit $INSTALL_EXIT
