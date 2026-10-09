#!/usr/bin/env bash
# =============================================================================
#  tests/test_ask_sh.sh — Unit and functional tests for ask.sh
#
#  Usage:
#    ./tests/test_ask_sh.sh                # run all tests
#    ./tests/test_ask_sh.sh <test_name>    # run single test (e.g. test_load_config)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASK_SH="${REPO_ROOT}/ask.sh"

# Test isolation directory
TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ask_test_sh.XXXXXX")
cleanup() {
    rm -rf "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# Export isolated home and configs
export HOME="${TEST_TMP_DIR}/home"
mkdir -p "${HOME}"
export ASK_CONFIG_FILE="${HOME}/.ask_config"
export ASK_STATS_FILE="${HOME}/.ask_stats"

# Unset user API keys for clean test state
unset OPENAI_API_KEY || true
unset GEMINI_API_KEY || true

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helpers
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
#  TEST CASES FOR INDIVIDUAL FUNCTIONS
# =============================================================================

test_colors() {
    source "${ASK_SH}"

    local b; b="$(bold 'hello')"
    assert_eq $'\033[1mhello\033[0m' "$b" "bold formatting"

    local d; d="$(dim 'hello')"
    assert_eq $'\033[2mhello\033[0m' "$d" "dim formatting"

    local c; c="$(cyan 'hello')"
    assert_eq $'\033[36mhello\033[0m' "$c" "cyan formatting"

    local g; g="$(green 'hello')"
    assert_eq $'\033[32mhello\033[0m' "$g" "green formatting"

    local y; y="$(yellow 'hello')"
    assert_eq $'\033[33mhello\033[0m' "$y" "yellow formatting"

    local r; r="$(red 'hello')"
    assert_eq $'\033[31mhello\033[0m' "$r" "red formatting"
}

test_load_config() {
    source "${ASK_SH}"

    cat << 'EOF' > "${ASK_CONFIG_FILE}"
# Comments should be ignored
provider=gemini
model=gemini-2.5-flash-lite  # inline comment
max_tokens=300
ollama_endpoint=http://127.0.0.1:11434/v1
openai_api_key=cfg_key_open
gemini_api_key=cfg_key_gem
EOF

    # Reset vars
    PROVIDER="openai"
    MODEL=""
    MAX_TOKENS=200
    OLLAMA_ENDPOINT=""
    OPENAI_API_KEY=""
    GEMINI_API_KEY=""

    load_config

    assert_eq "gemini" "$PROVIDER" "load provider"
    assert_eq "gemini-2.5-flash-lite" "$MODEL" "load model"
    assert_eq "300" "$MAX_TOKENS" "load max_tokens"
    assert_eq "http://127.0.0.1:11434/v1" "$OLLAMA_ENDPOINT" "load ollama_endpoint"
    assert_eq "cfg_key_open" "$OPENAI_API_KEY" "load openai_api_key"
    assert_eq "cfg_key_gem" "$GEMINI_API_KEY" "load gemini_api_key"
}

test_load_config_env_priority() {
    source "${ASK_SH}"

    cat << 'EOF' > "${ASK_CONFIG_FILE}"
provider=openai
openai_api_key=config_val
gemini_api_key=config_val
EOF

    OPENAI_API_KEY="env_open_priority"
    GEMINI_API_KEY="env_gem_priority"

    load_config

    assert_eq "env_open_priority" "$OPENAI_API_KEY" "env OPENAI_API_KEY priority"
    assert_eq "env_gem_priority" "$GEMINI_API_KEY" "env GEMINI_API_KEY priority"
}

test_write_config() {
    source "${ASK_SH}"

    PROVIDER="ollama"
    MODEL="qwen2.5-coder"
    MAX_TOKENS=350
    OLLAMA_ENDPOINT="http://localhost:11434/v1"
    OPENAI_API_KEY="key1"
    GEMINI_API_KEY="key2"

    write_config

    [[ -f "${ASK_CONFIG_FILE}" ]] || return 1
    local content; content="$(cat "${ASK_CONFIG_FILE}")"
    assert_contains "$content" "provider=ollama" "written provider"
    assert_contains "$content" "model=qwen2.5-coder" "written model"
    assert_contains "$content" "max_tokens=350" "written max_tokens"
    assert_contains "$content" "openai_api_key=key1" "written openai key"
    assert_contains "$content" "gemini_api_key=key2" "written gemini key"

    local perms
    perms=$(stat -f "%OLp" "${ASK_CONFIG_FILE}" 2>/dev/null || stat -c "%a" "${ASK_CONFIG_FILE}" 2>/dev/null || echo "600")
    assert_eq "600" "$perms" "config file permission is 600"
}

test_resolve_default_model() {
    source "${ASK_SH}"

    PROVIDER="openai"
    MODEL=""
    resolve_default_model
    assert_eq "gpt-4.1-nano" "$MODEL" "default openai model"

    PROVIDER="gemini"
    MODEL=""
    resolve_default_model
    assert_eq "gemini-2.5-flash-lite" "$MODEL" "default gemini model"

    PROVIDER="gemini"
    MODEL="latest"
    resolve_default_model
    assert_eq "gemini-flash-latest" "$MODEL" "alias latest"

    PROVIDER="gemini"
    MODEL="flash-lite-latest"
    resolve_default_model
    assert_eq "gemini-flash-lite-latest" "$MODEL" "alias flash-lite-latest"

    PROVIDER="ollama"
    MODEL=""
    resolve_default_model
    assert_eq "llama3.2" "$MODEL" "default ollama model"

    PROVIDER="openai"
    MODEL="custom-model-x"
    resolve_default_model
    assert_eq "custom-model-x" "$MODEL" "custom model preserved"
}

test_detect_environment() {
    source "${ASK_SH}"

    local env_info; env_info="$(detect_environment)"
    [[ -n "$env_info" ]] || return 1
    assert_contains "$env_info" "(" "detect environment format"
    assert_contains "$env_info" ")" "detect environment format"
}

test_stats_record_and_show() {
    source "${ASK_SH}"

    rm -f "${ASK_STATS_FILE}"

    local json_openai='{"usage":{"prompt_tokens":100,"completion_tokens":50}}'
    local json_gemini='{"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":20}}'

    record_stats "openai" "gpt-4.1-nano" "$json_openai"
    record_stats "openai" "gpt-4.1-nano" "$json_openai"
    record_stats "gemini" "gemini-2.5-flash-lite" "$json_gemini"

    [[ -f "${ASK_STATS_FILE}" ]] || return 1

    local output; output="$(show_stats)"
    assert_contains "$output" "Total queries:      3" "stats query count"
    assert_contains "$output" "Prompt tokens:      250" "stats prompt tokens"
    assert_contains "$output" "Completion tokens:  120" "stats completion tokens"
    assert_contains "$output" "openai (gpt-4.1-nano)" "stats shows openai model"
    assert_contains "$output" "gemini (gemini-2.5-flash-lite)" "stats shows gemini model"
}

test_show_init_snippet() {
    source "${ASK_SH}"

    local bash_snippet; bash_snippet="$(show_init_snippet bash)"
    assert_contains "$bash_snippet" "_ask_inline" "bash snippet contains _ask_inline"
    assert_contains "$bash_snippet" "bind -x" "bash snippet contains bind -x"

    local zsh_snippet; zsh_snippet="$(show_init_snippet zsh)"
    assert_contains "$zsh_snippet" "zle -N" "zsh snippet contains zle -N"
}

test_show_help() {
    source "${ASK_SH}"

    local help_txt; help_txt="$(show_help)"
    assert_contains "$help_txt" "AI terminal assistant" "help header"
    assert_contains "$help_txt" "USAGE" "help usage"
    assert_contains "$help_txt" "PIPING" "help piping"
}

test_cli_version_and_help() {
    local ver_out; ver_out="$("${ASK_SH}" --version)"
    assert_contains "$ver_out" "ask v2.1.1" "--version output"

    local short_ver; short_ver="$("${ASK_SH}" -v)"
    assert_contains "$short_ver" "ask v2.1.1" "-v output"

    local help_out; help_out="$("${ASK_SH}" --help)"
    assert_contains "$help_out" "USAGE" "--help output"
}

test_cli_cheat_validation() {
    local cheat_out
    if cheat_out="$("${ASK_SH}" cheat 2>&1)"; then
        echo "    $(red 'FAIL'): expected ask cheat with no args to exit with error" >&2
        return 1
    fi
    assert_contains "$cheat_out" "Usage: ask cheat <tool>" "cheat usage error"
}

test_cli_branch_validation() {
    local branch_out
    if branch_out="$("${ASK_SH}" branch 2>&1)"; then
        echo "    $(red 'FAIL'): expected ask branch with no args to exit with error" >&2
        return 1
    fi
    assert_contains "$branch_out" "Usage: ask branch <task description>" "branch usage error"
}

test_mock_ai_raw_query() {
    local mock_bin_dir="${TEST_TMP_DIR}/mock_bin"
    mkdir -p "${mock_bin_dir}"

    cat << 'EOF' > "${mock_bin_dir}/curl"
#!/bin/sh
cat << 'RESPONSE'
{
  "choices": [
    {
      "message": {
        "content": "git status --short"
      }
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 5
  }
}
RESPONSE
EOF
    chmod +x "${mock_bin_dir}/curl"

    # Set dummy config so it doesn't trigger setup wizard
    cat << 'EOF' > "${ASK_CONFIG_FILE}"
provider=openai
model=gpt-4.1-nano
openai_api_key=mock_key
EOF

    local result
    result=$(PATH="${mock_bin_dir}:${PATH}" "${ASK_SH}" --raw "show status")
    assert_eq "git status --short" "$result" "mock AI --raw query output"
}

test_read_execution_choice() {
    source "${ASK_SH}"

    local res_n; res_n="$(printf 'n\n' | read_execution_choice "Run?")"
    assert_eq "n" "$res_n" "execution choice n"

    local res_c; res_c="$(printf 'c\n' | read_execution_choice "Run?")"
    assert_eq "c" "$res_c" "execution choice c"

    local res_e; res_e="$(printf 'e\n' | read_execution_choice "Run?")"
    assert_eq "e" "$res_e" "execution choice e"

    local res_y; res_y="$(printf 'y\n' | read_execution_choice "Run?")"
    assert_eq "y" "$res_y" "execution choice y"

    local res_yes; res_yes="$(printf 'yes\n' | read_execution_choice "Run?")"
    assert_eq "yes" "$res_yes" "execution choice yes"
}

# =============================================================================
#  RUNNER
# =============================================================================

ALL_TESTS=(
    test_colors
    test_load_config
    test_load_config_env_priority
    test_write_config
    test_resolve_default_model
    test_detect_environment
    test_stats_record_and_show
    test_show_init_snippet
    test_show_help
    test_cli_version_and_help
    test_cli_cheat_validation
    test_cli_branch_validation
    test_mock_ai_raw_query
    test_read_execution_choice
)

echo
echo "$(bold 'Running ask.sh tests (isolated environment):')"
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
    echo "$(green "All ${TESTS_PASSED}/${TESTS_RUN} ask.sh tests passed.")"
    exit 0
else
    echo "$(red "${TESTS_FAILED}/${TESTS_RUN} ask.sh tests failed.")"
    exit 1
fi
