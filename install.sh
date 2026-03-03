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
REPO="zmsp/ask"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main/ask"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="ask"

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
#  CHECKS
# =============================================================================
check_dependency() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
        die "Required dependency '$cmd' not found. $hint"
    fi
}

# =============================================================================
#  MAIN
# =============================================================================
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
if [[ -w "$INSTALL_DIR" ]]; then
    DEST="${INSTALL_DIR}/${BINARY_NAME}"
elif sudo -n true 2>/dev/null; then
    # sudo available without password
    DEST="${INSTALL_DIR}/${BINARY_NAME}"
    USE_SUDO=true
else
    # Fall back to ~/bin
    warn "/usr/local/bin is not writable. Installing to ~/bin instead."
    mkdir -p "$HOME/bin"
    DEST="$HOME/bin/${BINARY_NAME}"
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        warn "Add ~/bin to your PATH:"
        echo
        echo '    echo '"'"'export PATH="$HOME/bin:$PATH"'"'"' >> ~/.zshrc  # or ~/.bashrc'
        echo '    source ~/.zshrc'
        echo
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
if [[ "${USE_SUDO:-false}" == "true" ]]; then
    sudo mv "$TMP" "$DEST"
    sudo chmod +x "$DEST"
else
    mv "$TMP" "$DEST"
fi
success "Installed → $(bold "$DEST")"
echo

# ── Verify ────────────────────────────────────────────────────────────────────
if ! command -v "$BINARY_NAME" &>/dev/null; then
    warn "'ask' is not in your PATH yet."
    info "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo
    echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
    echo
fi

# ── Verification check ────────────────────────────────────────────────────────
echo "$(bold 'Verification check…')"
echo
"$DEST" "echo hello world"

echo
success "$(bold 'ask is ready!')"
echo
echo "  $(dim 'Try it:')"
echo "    ask \"list files modified in the last 24 hours\""
echo "    ask !! "
echo "    ask commit"
echo
