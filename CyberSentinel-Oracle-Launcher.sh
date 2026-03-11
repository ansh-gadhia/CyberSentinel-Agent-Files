#!/bin/bash

# ============================================================
# CyberSentinel — Public Launcher for Oracle Linux (silent passthrough)
# Validates the GitHub token, then streams the private
# installer directly into bash. The user sees one seamless
# flow — no launcher UI, no duplicate banners, no step headers.
# ============================================================

GITHUB_REPO="cybersentinel-06/CyberSentinel-SIEM"
PRIVATE_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/AGENTS/INSTALLATION-SCRIPTS/CyberSentinel-Oracle-Install.sh"
SELF_URL="https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/CyberSentinel-Oracle-Launcher.sh"

# ============================================================
# TTY guard — re-exec with a real terminal if stdin is a pipe.
# Happens when the user runs: curl ... | sudo bash
# Downloads itself to tmpfs, re-runs with /dev/tty as stdin,
# then wipes the temp file. Second run hits a real TTY and
# falls through to normal execution.
# ============================================================
if [ ! -t 0 ]; then
    SELF_TMP=$(mktemp /dev/shm/.cs_oracle_launcher_XXXXXX)
    chmod 700 "$SELF_TMP"
    if ! curl -fsSL "$SELF_URL" -o "$SELF_TMP" 2>/dev/null; then
        echo "Error: Failed to fetch installer. Check your network connection." >&2
        rm -f "$SELF_TMP"
        exit 1
    fi
    bash "$SELF_TMP" < /dev/tty
    EXIT_CODE=$?
    rm -f "$SELF_TMP"
    exit $EXIT_CODE
fi

# ============================================================
# Colours
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

success() { echo -e "  ${GREEN}✔ ${1}${NC}"; }
error()   { echo -e "  ${RED}✘ ${1}${NC}" >&2; }

# ============================================================
# Cleanup trap — wipe token from memory on any exit
# ============================================================
cleanup() {
    unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED _RAW_TOKEN
}
trap cleanup EXIT

# ============================================================
# Privilege check
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

# ============================================================
# Masked token input
# ============================================================
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
    local token="$1" http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/user")
    [ "$http_code" -ne 200 ] && return 1
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.github.com/repos/$GITHUB_REPO")
    if [ "$http_code" -eq 200 ]; then
        return 0
    elif [ "$http_code" -eq 404 ] || [ "$http_code" -eq 403 ]; then
        echo -e "\n  ${YELLOW}⚠ Token valid but cannot access repo '${GITHUB_REPO}' (HTTP $http_code).${NC}"
        echo -e "  ${YELLOW}  Ensure the token has 'repo' or 'contents:read' scope.${NC}"
        return 2
    else
        return 1
    fi
}

# ============================================================
# Banner + Step 0 header — printed here by the launcher so
# the main script can skip them entirely when pre-validated.
# Result: user sees one unbroken flow, identical to running
# the script directly.
# ============================================================
echo -e "${CYAN}${BOLD}"
echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
echo "       S E N T I N E L   I N S T A L L E R"
echo -e "${NC}"
echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "  ${BOLD}Step 0 │ GitHub Token Validation${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# ============================================================
# Token validation loop (3 attempts)
# ============================================================
MAX_ATTEMPTS=3
attempt=0
_RAW_TOKEN=""

while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))

    read_masked _RAW_TOKEN "  Enter GitHub Personal Access Token: "

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
        exit 1
    fi
    echo -e "  ${YELLOW}Please try again.${NC}"
done

# ============================================================
# Pass token to main script and stream it into bash silently.
# CS_TOKEN_PREVALIDATED=1 suppresses the entire Step 0 block
# in the main script (banner, header, token prompt, success msg)
# so nothing is repeated and the flow looks completely native.
# ============================================================
export CS_GITHUB_TOKEN="$_RAW_TOKEN"
export CS_TOKEN_PREVALIDATED="1"
unset _RAW_TOKEN

bash <(curl -fsSL \
    --tlsv1.2 \
    -H "Authorization: Bearer $CS_GITHUB_TOKEN" \
    "$PRIVATE_SCRIPT_URL")

INSTALL_EXIT=$?
unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED
exit $INSTALL_EXIT
