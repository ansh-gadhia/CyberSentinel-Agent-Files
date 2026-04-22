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
# This makes fd 0 be the tty — so plain `stty` (no redirection)
# works correctly.
# ============================================================
if [ ! -t 0 ]; then
    SELF_TMP=$(mktemp /tmp/.cs_launcher_XXXXXX)
    chmod 700 "$SELF_TMP"
    if ! curl -fsSL "$SELF_URL" -o "$SELF_TMP" 2>/dev/null; then
        echo "Error: Failed to fetch installer. Check your network connection." >&2
        rm -f "$SELF_TMP"
        exit 1
    fi
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
    # how we exit (Ctrl-C mid-input, error, etc.). Operate on
    # current stdin (the tty) — not via /dev/tty redirection.
    stty echo 2>/dev/null || true
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
# FIX HISTORY:
#   v1: `read -rs` → EINTR on `tcsetattr: Interrupted system call`
#       after curl|sudo bash re-exec.
#   v2: `stty -echo </dev/tty` — </dev/tty opens a FRESH fd, and
#       tcsetattr on that fd didn't affect the tty that bash's
#       `read` reads from. Result: chars appeared BOTH as the
#       real char (terminal default echo) AND as '*' (our manual
#       print). e.g. "ansh" → "a*n*s*h*".
#   v3 (THIS VERSION): After the launcher's
#       `exec bash ... </dev/tty >/dev/tty 2>/dev/tty`, fd 0 IS
#       the tty. So `stty -echo` with NO redirection operates
#       on fd 0 — the same fd that `read -r -n1` reads from.
#       One fd, one tcsetattr, echo actually gets disabled.
#
#   Also: removed `|| true` on the critical stty -echo call so
#   if it genuinely fails we fall back to visible input rather
#   than silently producing double-echoed garbage.
# ============================================================
read_masked() {
    local __var="$1" __prompt="$2" __input="" __char=""
    local __old_stty=""

    # Save current tty settings. Operate on fd 0 (current stdin),
    # which after the exec above IS the controlling terminal.
    __old_stty=$(stty -g 2>/dev/null) || __old_stty=""

    _restore_tty() {
        if [ -n "$__old_stty" ]; then
            stty "$__old_stty" 2>/dev/null
        fi
        # Belt-and-suspenders: always force echo back on
        stty echo 2>/dev/null
    }

    # SIGINT handler: restore tty and exit cleanly
    trap '_restore_tty; trap - INT; exit 130' INT

    # Disable echo on the current tty. If this fails for any
    # reason, fall back to plain visible input — better than
    # double-echoed garbage.
    if ! stty -echo 2>/dev/null; then
        _restore_tty
        trap - INT
        echo -e "${YELLOW}  ⚠ Cannot disable terminal echo — input will be visible.${NC}" >&2
        printf "%s" "$__prompt"
        IFS= read -r __input
        printf -v "$__var" '%s' "$__input"
        return 0
    fi

    printf "%s" "$__prompt"

    # Read one char at a time. No -s (we handled echo via stty).
    # No </dev/tty redirection (fd 0 is already the tty).
    while IFS= read -r -n1 __char; do
        # Enter key → -n1 returns empty string on newline
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
