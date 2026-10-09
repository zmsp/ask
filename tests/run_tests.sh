#!/usr/bin/env bash
# =============================================================================
#  tests/run_tests.sh — Master test runner for ask-bash
#
#  Usage:
#    ./tests/run_tests.sh               # Run all available tests (sh + ps1)
#    ./tests/run_tests.sh --sh-only     # Run bash/sh tests only
#    ./tests/run_tests.sh --ps1-only    # Run PowerShell tests only
#    ./tests/run_tests.sh --app-only    # Run ask.sh / ask.ps1 tests only
#    ./tests/run_tests.sh --install-only# Run installer tests only
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="all"
case "${1:-}" in
    --sh-only)      MODE="sh" ;;
    --ps1-only)     MODE="ps1" ;;
    --app-only)     MODE="app" ;;
    --install-only) MODE="install" ;;
    "")             MODE="all" ;;
    *)
        echo "Usage: $0 [--sh-only | --ps1-only | --app-only | --install-only]" >&2
        exit 1
        ;;
esac

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
cyan()  { printf '\033[36m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }

PWSH_CMD=""
if command -v pwsh &>/dev/null; then
    PWSH_CMD="pwsh"
elif command -v powershell &>/dev/null; then
    PWSH_CMD="powershell"
fi

SUITES_RUN=0
SUITES_PASSED=0
SUITES_FAILED=0

run_suite() {
    local suite_name="$1"
    local cmd="$2"

    SUITES_RUN=$((SUITES_RUN + 1))
    echo
    echo "$(bold "==> Running suite: ${suite_name}")"

    if eval "${cmd}"; then
        SUITES_PASSED=$((SUITES_PASSED + 1))
    else
        SUITES_FAILED=$((SUITES_FAILED + 1))
    fi
}

echo "$(bold '═══════════════════════════════════════════════════')"
echo "$(bold '           ask-bash Test Suite Runner             ')"
echo "$(bold '═══════════════════════════════════════════════════')"

# 1. ask.sh tests
if [[ "$MODE" == "all" || "$MODE" == "sh" || "$MODE" == "app" ]]; then
    run_suite "ask.sh unit & functional tests" "${SCRIPT_DIR}/test_ask_sh.sh"
fi

# 2. install.sh tests
if [[ "$MODE" == "all" || "$MODE" == "sh" || "$MODE" == "install" ]]; then
    run_suite "install.sh isolated installation tests" "${SCRIPT_DIR}/test_install_sh.sh"
fi

# 3. ask.ps1 tests
if [[ "$MODE" == "all" || "$MODE" == "ps1" || "$MODE" == "app" ]]; then
    if [[ -n "$PWSH_CMD" ]]; then
        run_suite "ask.ps1 unit & functional tests" "${PWSH_CMD} ${SCRIPT_DIR}/test_ask_ps1.ps1"
    else
        echo
        echo "  $(yellow '⚠') Skipping ask.ps1 tests (pwsh not installed)"
    fi
fi

# 4. install.ps1 tests
if [[ "$MODE" == "all" || "$MODE" == "ps1" || "$MODE" == "install" ]]; then
    if [[ -n "$PWSH_CMD" ]]; then
        run_suite "install.ps1 isolated installation tests" "${PWSH_CMD} ${SCRIPT_DIR}/test_install_ps1.ps1"
    else
        echo
        echo "  $(yellow '⚠') Skipping install.ps1 tests (pwsh not installed)"
    fi
fi

echo
echo "$(bold '═══════════════════════════════════════════════════')"
if [[ $SUITES_FAILED -eq 0 ]]; then
    echo "$(green "All ${SUITES_PASSED}/${SUITES_RUN} test suites passed successfully.")"
    exit 0
else
    echo "$(red "${SUITES_FAILED}/${SUITES_RUN} test suites failed.")"
    exit 1
fi
