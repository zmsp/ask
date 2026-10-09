#!/usr/bin/env bash
# =============================================================================
#  install.sh — installer for ask (AI terminal assistant)
#
#  Usage:
#    curl -fsSL https://zmsp.github.io/ask/install.sh | bash
#
#  What it does:
#    1. Checks for required dependencies (curl, jq)
#    2. Downloads the latest `ask` script from GitHub
#    3. Installs it to /usr/local/bin (or ~/bin as a fallback)
#    4. Runs the interactive setup wizard
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO="${ASK_REPO:-zmsp/ask}"
RAW_URL="${ASK_RAW_URL:-https://raw.githubusercontent.com/${REPO}/main/ask.sh}"
BINARY_NAME="${ASK_BINARY_NAME:-ask}"

# ── Colors ────────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "  $(dim '·') $*"; }
success() { echo "  $(green '✔') $*"; }
warn()    { echo "  $(yellow '⚠') $*"; }
die()     { echo "  $(red '✖') $*" >&2; exit 1; }

# =============================================================================
#  PROFILE & PATH HELPERS
# =============================================================================
detect_shell_profile() {
    if [[ -n "${ASK_PROFILE_FILE:-}" ]]; then
        echo "$ASK_PROFILE_FILE"
        return
    fi
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    if [[ "$shell_name" == "zsh" ]] || [[ -f "$HOME/.zshrc" ]] || [[ "$(uname -s)" == "Darwin" && ! -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.zshrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        echo "$HOME/.bash_profile"
    else
        echo "$HOME/.bashrc"
    fi
}

add_to_path_profile() {
    local dir="$1"
    local rc_file
    rc_file="$(detect_shell_profile)"
    mkdir -p "$(dirname "$rc_file")"
    touch "$rc_file"
    if ! grep -qs "PATH=.*${dir}" "$rc_file"; then
        printf '\n# ask — AI terminal assistant\nexport PATH="%s:$PATH"\n' "$dir" >> "$rc_file"
        success "Added ${dir} to PATH in $(bold "$rc_file")"
    else
        info "${dir} already configured in $(bold "$rc_file")"
    fi
}

remove_from_path_profile() {
    local dir="$1"
    local rc_file
    rc_file="$(detect_shell_profile)"
    if [[ -f "$rc_file" ]]; then
        local tmp_rc
        tmp_rc=$(mktemp)
        grep -v "# ask — AI terminal assistant" "$rc_file" | grep -v "export PATH=\"${dir}:\$PATH\"" > "$tmp_rc" || true
        mv "$tmp_rc" "$rc_file"
        success "Cleaned PATH entry from $(bold "$rc_file")"
    fi
}

# =============================================================================
#  CHECKS & UNINSTALL
# =============================================================================
check_dependency() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
        die "Required dependency '$cmd' not found. $hint"
    fi
}

do_uninstall() {
    echo
    echo "$(bold '╔════════════════════════════════════╗')"
    echo "$(bold '║   ask  ·  AI terminal assistant    ║')"
    echo "$(bold '║   uninstaller                      ║')"
    echo "$(bold '╚════════════════════════════════════╝')"
    echo
    local removed=0
    local candidates=(
        "${ASK_INSTALL_DIR:-}/$BINARY_NAME"
        "/usr/local/bin/$BINARY_NAME"
        "$HOME/.local/bin/$BINARY_NAME"
        "$HOME/bin/$BINARY_NAME"
    )
    if command -v brew &>/dev/null; then
        candidates+=("$(brew --prefix)/bin/$BINARY_NAME")
    fi

    for bin_path in "${candidates[@]}"; do
        [[ -z "$bin_path" ]] && continue
        if [[ -f "$bin_path" ]]; then
            info "Removing ${bin_path}…"
            if [[ -w "$bin_path" ]] || [[ -w "$(dirname "$bin_path")" ]]; then
                rm -f "$bin_path"
                success "Removed $bin_path"
                removed=1
            elif sudo -n true 2>/dev/null; then
                sudo rm -f "$bin_path"
                success "Removed $bin_path (with sudo)"
                removed=1
            else
                warn "Cannot remove $bin_path (permission denied)"
            fi
        fi
    done

    remove_from_path_profile "$HOME/.local/bin"
    remove_from_path_profile "$HOME/bin"
    if [[ -n "${ASK_INSTALL_DIR:-}" ]]; then
        remove_from_path_profile "$ASK_INSTALL_DIR"
    fi

    echo
    if [[ $removed -eq 1 ]]; then
        success "$(bold 'ask uninstalled successfully!')"
    else
        warn "No installed ask binary found."
    fi
    info "Configuration ~/.ask_config and stats ~/.ask_stats preserved."
    echo
}

# =============================================================================
#  MAIN
# =============================================================================

# Return early if sourced as a library/test fixture
if [[ "${BASH_SOURCE[0]}" != "${0}" || "${ASK_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Handle uninstall flag
if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" || "${ASK_UNINSTALL:-false}" == "true" ]]; then
    do_uninstall
    exit 0
fi

echo
echo "$(bold '╔════════════════════════════════════╗')"
echo "$(bold '║   ask  ·  AI terminal assistant    ║')"
echo "$(bold '║   installer                        ║')"
echo "$(bold '╚════════════════════════════════════╝')"
echo
info "Repository: https://github.com/${REPO}"
echo

# ── Dependency checks ─────────────────────────────────────────────────────────
info "Checking dependencies…"
check_dependency curl  "Install with: brew install curl  OR  sudo apt install curl"
check_dependency jq    "Install with: brew install jq    OR  sudo apt install jq"
success "Dependencies OK"
echo

# ── Determine install location ────────────────────────────────────────────────
USE_SUDO=false
if [[ -n "${ASK_INSTALL_DIR:-}" ]]; then
    INSTALL_DIR="${ASK_INSTALL_DIR}"
elif [[ -w "/usr/local/bin" ]]; then
    INSTALL_DIR="/usr/local/bin"
elif sudo -n true 2>/dev/null && sudo mkdir -p "/usr/local/bin" 2>/dev/null && sudo test -w "/usr/local/bin" 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
    USE_SUDO=true
elif command -v brew &>/dev/null && [[ -w "$(brew --prefix)/bin" ]]; then
    INSTALL_DIR="$(brew --prefix)/bin"
else
    # User-space fallback: ~/.local/bin (standard) or ~/bin
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || [[ ! -d "$HOME/bin" ]]; then
        INSTALL_DIR="$HOME/.local/bin"
    else
        INSTALL_DIR="$HOME/bin"
    fi
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || true
DEST="${INSTALL_DIR}/${BINARY_NAME}"

# ── Auto-configure PATH if needed ─────────────────────────────────────────────
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    if [[ "${ASK_NO_MODIFY_PATH:-false}" != "true" ]]; then
        add_to_path_profile "$INSTALL_DIR"
    else
        warn "'$INSTALL_DIR' is not in your PATH."
        info "Add to shell profile: export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
fi

# ── Download ──────────────────────────────────────────────────────────────────
info "Downloading ask from GitHub…"
TMP=$(mktemp)
curl -fsSL "$RAW_URL" -o "$TMP" || die "Download failed. Check your network connection."
chmod +x "$TMP"
success "Downloaded"
echo

# ── Install ───────────────────────────────────────────────────────────────────
info "Installing to ${DEST}…"
if [[ "${USE_SUDO}" == "true" ]]; then
    sudo mv "$TMP" "$DEST"
    sudo chmod +x "$DEST"
else
    mv "$TMP" "$DEST"
fi
success "Installed → $(bold "$DEST")"
echo

# ── Verification check ────────────────────────────────────────────────────────
echo "$(bold 'Verification check…')"
echo
if [[ "${ASK_SKIP_VERIFY:-false}" == "true" ]]; then
    "$DEST" --version
else
    "$DEST" "echo hello world"
fi

echo
success "$(bold 'ask is ready!')"
echo
echo "  $(dim 'Try it:')"
echo "    ask \"list files modified in the last 24 hours\""
echo "    ask !! "
echo "    ask commit"
echo
