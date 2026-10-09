#!/usr/bin/env bash
# =============================================================================
#  tests/test_install_sh.sh — Isolated tests for install.sh
#
#  Usage:
#    ./tests/test_install_sh.sh                # run all tests
#    ./tests/test_install_sh.sh <test_name>    # run single test
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
ASK_SH="${REPO_ROOT}/ask.sh"

# Test isolation directory
TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ask_test_install_sh.XXXXXX")
cleanup() {
    rm -rf "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# Isolate HOME
export HOME="${TEST_TMP_DIR}/home"
mkdir -p "${HOME}"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "    $(red 'FAIL'): ${msg}" >&2
        echo "      expected: '${expected}'" >&2
        echo "      actual:   '${actual}'" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "    $(red 'FAIL'): ${msg}" >&2
        echo "      expected to contain: '${needle}'" >&2
        echo "      in: '${haystack}'" >&2
        return 1
    fi
}

run_test() {
    local test_func="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "  %-35s " "${test_func}..."
    if "${test_func}"; then
        printf "%s\n" "$(green 'PASS')"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "%s\n" "$(red 'FAILED')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
#  TEST CASES
# =============================================================================

test_check_dependency_success() {
    source "${INSTALL_SH}"

    # curl and sh should exist
    check_dependency "curl" "test hint"
    check_dependency "sh" "test hint"
}

test_check_dependency_failure() {
    source "${INSTALL_SH}"

    local err_output
    if err_output=$( (check_dependency "nonexistent_binary_xyz_123" "hint text") 2>&1 ); then
        echo "    $(red 'FAIL'): expected missing dependency to fail" >&2
        return 1
    fi
    assert_contains "$err_output" "Required dependency 'nonexistent_binary_xyz_123' not found" "dependency error message"
}

test_full_install_execution() {
    local install_dest="${TEST_TMP_DIR}/test_bin"
    mkdir -p "${install_dest}"

    local output
    output=$(
        ASK_INSTALL_DIR="${install_dest}" \
        ASK_RAW_URL="file://${ASK_SH}" \
        ASK_SKIP_VERIFY="true" \
        bash "${INSTALL_SH}"
    )

    assert_contains "$output" "Installed →" "installer reports installed"
    assert_contains "$output" "ask is ready!" "installer reports ready"

    # Verify target file
    local installed_bin="${install_dest}/ask"
    [[ -f "${installed_bin}" ]] || { echo "    $(red 'FAIL'): target binary does not exist" >&2; return 1; }
    [[ -x "${installed_bin}" ]] || { echo "    $(red 'FAIL'): target binary is not executable" >&2; return 1; }

    # Verify executed binary
    local ver_out; ver_out="$("${installed_bin}" --version)"
    assert_contains "$ver_out" "ask v2.1.0" "installed binary runs --version"
}

test_custom_binary_name() {
    local install_dest="${TEST_TMP_DIR}/custom_bin"
    mkdir -p "${install_dest}"

    local output
    output=$(
        ASK_INSTALL_DIR="${install_dest}" \
        ASK_BINARY_NAME="ask-custom" \
        ASK_RAW_URL="file://${ASK_SH}" \
        ASK_SKIP_VERIFY="true" \
        bash "${INSTALL_SH}"
    )

    local installed_bin="${install_dest}/ask-custom"
    [[ -x "${installed_bin}" ]] || { echo "    $(red 'FAIL'): custom binary not executable" >&2; return 1; }

    local ver_out; ver_out="$("${installed_bin}" --version)"
    assert_contains "$ver_out" "ask v2.1.0" "custom binary runs --version"
}

# =============================================================================
#  RUNNER
# =============================================================================

ALL_TESTS=(
    test_check_dependency_success
    test_check_dependency_failure
    test_full_install_execution
    test_custom_binary_name
)

echo
echo "$(bold 'Running install.sh tests (isolated environment):')"
echo

if [[ $# -gt 0 ]]; then
    target="$1"
    if declare -f "$target" > /dev/null; then
        run_test "$target"
    else
        echo "$(red "Unknown test function: $target")" >&2
        echo "Available tests: ${ALL_TESTS[*]}" >&2
        exit 1
    fi
else
    for t in "${ALL_TESTS[@]}"; do
        run_test "$t"
    done
fi

echo
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "$(green "All ${TESTS_PASSED}/${TESTS_RUN} install.sh tests passed.")"
    exit 0
else
    echo "$(red "${TESTS_FAILED}/${TESTS_RUN} install.sh tests failed.")"
    exit 1
fi
