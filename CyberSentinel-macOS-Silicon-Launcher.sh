#!/bin/bash

# ============================================================
# CyberSentinel — Public Launcher (macOS Apple Silicon)
# Validates the GitHub token, then streams the private
# installer directly into bash. The user sees one seamless
# flow — no launcher UI, no duplicate banners, no step headers.
# ============================================================

GITHUB_REPO="cybersentinel-06/CyberSentinel-SIEM"
PRIVATE_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/AGENTS/INSTALLATION-SCRIPTS/CyberSentinel-macOS-Silicon-Install.sh"
SELF_URL="https://raw.githubusercontent.com/ansh-gadhia/CyberSentinel-Agent-Files/main/CyberSentinel-macOS-Silicon-Launcher.sh"

# ============================================================
# Resolve bash 4+ for compatibility with &>> and other
# bash 4+ features used in the private installer script.
# macOS ships with bash 3.2 (GPL). Homebrew installs bash 5
# at /opt/homebrew/bin/bash (Apple Silicon) or
# /usr/local/bin/bash (Intel under Rosetta).
# ============================================================
BASH4=""
for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$_candidate" ]; then
        _ver=$("$_candidate" --version 2>/dev/null | awk 'NR==1{print $4}' | cut -d. -f1)
        if [ "${_ver:-0}" -ge 4 ] 2>/dev/null; then
            BASH4="$_candidate"
            break
        fi
    fi
done

# ============================================================
# TTY guard — re-exec with a real terminal if stdin is a pipe.
# Triggered when the user runs: curl ... | sudo bash
# Downloads itself to /tmp (no /dev/shm on macOS), re-runs
# with /dev/tty as stdin/stdout/stderr so tcsetattr() has a
# real controlling terminal across the sudo transition.
# ============================================================
if [ ! -t 0 ]; then
    SELF_TMP=$(mktemp /tmp/.cs_launcher_XXXXXX)
    chmod 700 "$SELF_TMP"
    if ! curl -fsSL "$SELF_URL" -o "$SELF_TMP" 2>/dev/null; then
        echo "Error: Failed to fetch installer. Check your network connection." >&2
        rm -f "$SELF_TMP"
        exit 1
    fi
    # Re-exec with full tty attachment: stdin, stdout AND stderr
    # from /dev/tty so bash's read and stty have a real terminal
    # to operate on after the sudo/pipe transition.
    exec bash "$SELF_TMP" </dev/tty >/dev/tty 2>/dev/tty
    # exec replaces the process; lines below are never reached,
    # but the cleanup trap on the child will remove SELF_TMP.
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
    # Make sure the terminal is restored to echo mode no matter
    # how we exit (Ctrl-C mid-input, error, etc.)
    stty echo </dev/tty 2>/dev/null || true
    [ -n "${SELF_TMP:-}" ]    && rm -f "$SELF_TMP"
    [ -n "${INSTALL_TMP:-}" ] && rm -f "$INSTALL_TMP"
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
# macOS Apple Silicon architecture guard
# ============================================================
ARCH=$(uname -m)
IS_ROSETTA=$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)

if [ "$ARCH" != "arm64" ] && [ "$IS_ROSETTA" != "1" ]; then
    echo -e "${RED}This installer is for Apple Silicon (arm64) Macs only.${NC}"
    echo -e "${YELLOW}Detected architecture: ${ARCH}${NC}"
    echo -e "${YELLOW}Please use the Intel edition for x86_64 Macs.${NC}"
    exit 1
fi

if [ "$IS_ROSETTA" = "1" ]; then
    echo -e "${YELLOW}⚠ Bash is running under Rosetta 2 on Apple Silicon.${NC}"
    echo -e "${YELLOW}  Please run this script in a native arm64 terminal for best results.${NC}"
    echo -e "${YELLOW}  Continuing anyway...${NC}"
    echo ""
fi

# ============================================================
# macOS version check — require 11.0 (Big Sur) or later
# ============================================================
OS_VER=$(sw_vers -productVersion 2>/dev/null || echo "0.0")
OS_MAJOR=$(echo "$OS_VER" | cut -d. -f1)

if [ "$OS_MAJOR" -lt 11 ]; then
    echo -e "${RED}macOS ${OS_VER} is not supported on Apple Silicon.${NC}"
    echo -e "${YELLOW}CyberSentinel requires macOS 11 (Big Sur) or later on arm64.${NC}"
    exit 1
fi

# ============================================================
# Masked token input
#
# FIX: Previous version used `read -rs` which calls tcsetattr()
# internally. After a `curl | sudo bash` pipeline followed by
# an exec re-attach to /dev/tty, that tcsetattr() call can be
# interrupted (EINTR) producing:
#
#     read: error setting terminal attributes: Interrupted system call
#
# New approach:
#   1. Use `stty -echo` directly on /dev/tty (external binary,
#      gets a fresh tty handle — not subject to bash's internal
#      fd confusion).
#   2. Use `read -r -n1` WITHOUT -s (we handled echo ourselves).
#   3. Retry the read loop on transient failures.
#   4. Always restore terminal via trap, even on Ctrl-C.
# ============================================================
read_masked() {
    local __var="$1" __prompt="$2" __input="" __char=""
    local __old_stty=""

    # Save current terminal settings so we can restore them
    __old_stty=$(stty -g </dev/tty 2>/dev/null) || __old_stty=""

    # Restore-on-exit helper (local to this function's scope)
    _restore_tty() {
        if [ -n "$__old_stty" ]; then
            stty "$__old_stty" </dev/tty 2>/dev/null || \
                stty echo </dev/tty 2>/dev/null || true
        else
            stty echo </dev/tty 2>/dev/null || true
        fi
    }

    # Trap SIGINT so Ctrl-C doesn't leave the tty in -echo mode.
    trap '_restore_tty; trap - INT; kill -INT $$' INT

    # Disable echo via stty directly (not via read -s)
    stty -echo </dev/tty 2>/dev/null || true

    printf "%s" "$__prompt"

    # Read one char at a time. Retry on transient read failures
    # (rare EINTR situations after sudo/pipe transitions).
    while :; do
        __char=""
        local __attempts=0
        local __read_ok=0
        while [ $__attempts -lt 5 ]; do
            if IFS= read -r -n1 __char </dev/tty; then
                __read_ok=1
                break
            fi
            __attempts=$((__attempts + 1))
            sleep 0.05
        done

        # If we still can't read, bail cleanly
        if [ $__read_ok -eq 0 ]; then
            break
        fi

        # Enter key → empty __char from -n1 on newline
        if [[ -z "$__char" ]]; then
            break
        fi

        # Backspace handling (DEL 0x7f or BS 0x08)
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

    # Restore terminal + remove trap
    _restore_tty
    trap - INT

    echo  # newline after masked input
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
# Banner + Step 0 header — printed here by the launcher so the
# main script can skip them entirely when pre-validated.
# ============================================================
echo -e "${CYAN}${BOLD}"
echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗"
echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗"
echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝"
echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗"
echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║"
echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝"
echo "    S E N T I N E L   I N S T A L L E R"
echo "        macOS Apple Silicon Edition"
echo -e "${NC}"
echo -e "  macOS ${OS_VER} on ${ARCH} — confirmed."
echo ""
echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "  ${BOLD}Step 0 │ GitHub Token Validation${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# ============================================================
# Token validation loop — 3 attempts max
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
# Stream and execute the private installer script.
#
# macOS ships with bash 3.2, which does not support &>>
# (append stdout+stderr) or &> (redirect stdout+stderr).
# We handle this in priority order:
#
#   1. Use Homebrew bash 4/5 if available  (cleanest)
#   2. Download to a temp file, patch &>> / &> with sed,
#      then run with /bin/bash              (safe fallback)
#
# CS_TOKEN_PREVALIDATED=1 tells the main script to skip its
# own Step 0 block so the banner isn't printed twice.
# Token is passed via env var and scrubbed immediately after.
# ============================================================
export CS_GITHUB_TOKEN="$_RAW_TOKEN"
export CS_TOKEN_PREVALIDATED="1"
unset _RAW_TOKEN

if [ -n "$BASH4" ]; then
    # ── Path 1: bash 4+ found — stream directly ──────────────
    "$BASH4" <(curl -fsSL \
        --tlsv1.2 \
        -H "Authorization: Bearer $CS_GITHUB_TOKEN" \
        "$PRIVATE_SCRIPT_URL")
    INSTALL_EXIT=$?
else
    # ── Path 2: Only bash 3.2 available — download, patch, run ─
    echo -e "  ${YELLOW}ℹ bash 4+ not found; applying bash 3.2 compatibility patch.${NC}"
    echo -e "  ${YELLOW}  Install Homebrew bash for a cleaner experience: brew install bash${NC}"
    echo ""

    INSTALL_TMP=$(mktemp /tmp/.cs_install_XXXXXX.sh)
    chmod 700 "$INSTALL_TMP"

    if ! curl -fsSL \
            --tlsv1.2 \
            -H "Authorization: Bearer $CS_GITHUB_TOKEN" \
            "$PRIVATE_SCRIPT_URL" \
            -o "$INSTALL_TMP"; then
        error "Failed to download the installer script."
        unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED
        exit 1
    fi

    # Patch bash 4+ redirect operators to bash 3.2 equivalents:
    #   &>> FILE  →  >> FILE 2>&1
    #   &>  FILE  →  >  FILE 2>&1
    PATCH_TMP=$(mktemp /tmp/.cs_patch_XXXXXX.sh)
    chmod 700 "$PATCH_TMP"

    sed \
        -e 's/&>>[[:space:]]*\([^[:space:]&|;)]*\)/>> \1 2>\&1/g' \
        -e 's/&>[[:space:]]*\([^[:space:]&|;)]*\)/> \1 2>\&1/g' \
        "$INSTALL_TMP" > "$PATCH_TMP"

    mv "$PATCH_TMP" "$INSTALL_TMP"

    /bin/bash "$INSTALL_TMP"
    INSTALL_EXIT=$?

    rm -f "$INSTALL_TMP"
    unset INSTALL_TMP
fi

unset CS_GITHUB_TOKEN CS_TOKEN_PREVALIDATED
exit $INSTALL_EXIT
