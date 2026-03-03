#!/usr/bin/env bash
# =============================================================================
#  ask — AI-powered terminal assistant
#
#  Turn plain-English descriptions into shell commands (and run them),
#  or use it as a general-purpose AI chat layer from your terminal.
#
#  Supports:  OpenAI (gpt-4.1-nano default) · Google Gemini (2.5-flash-lite)
#  Requires:  curl · jq · bash 4+
#
#  Project:   https://github.com/zmsp/ask
#  License:   MIT
# =============================================================================
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
readonly CONFIG_FILE="$HOME/.ask_config"
readonly VERSION="2.0.0"

# ── Runtime state (all overridable via ~/.ask_config or env vars) ─────────────
PROVIDER="openai"
MODEL=""
MAX_TOKENS=200
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"

# =============================================================================
#  COLOR HELPERS
# =============================================================================
bold()  { printf '\033[1m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }
cyan()  { printf '\033[36m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }

# =============================================================================
#  CONFIG — load / write ~/.ask_config
# =============================================================================

# Load key=value pairs from ~/.ask_config.
# Lines starting with # are ignored. Values may have inline #-comments.
# Environment variables (OPENAI_API_KEY, GEMINI_API_KEY) always take priority.
load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    while IFS='=' read -r key value; do
        key="${key#"${key%%[! ]*}"}"   # trim leading whitespace
        key="${key%"${key##*[! ]}"}"   # trim trailing whitespace
        [[ "$key" =~ ^#|^$ ]] && continue
        value="${value%%#*}"           # strip inline comments
        value="${value#"${value%%[! ]*}"}"
        value="${value%"${value##*[! ]}"}"
        case "$key" in
            provider)        PROVIDER="$value" ;;
            model)           MODEL="$value" ;;
            max_tokens)      MAX_TOKENS="$value" ;;
            openai_api_key)  [[ -z "$OPENAI_API_KEY" ]] && OPENAI_API_KEY="$value" ;;
            gemini_api_key)  [[ -z "$GEMINI_API_KEY" ]] && GEMINI_API_KEY="$value" ;;
        esac
    done < "$CONFIG_FILE"
}

# Persist current settings to ~/.ask_config (mode 600 — user-only).
write_config() {
    {
        echo "# ask config — generated $(date '+%Y-%m-%d')"
        echo "provider=$PROVIDER"
        echo "model=$MODEL"
        echo "max_tokens=$MAX_TOKENS"
        [[ -n "$OPENAI_API_KEY" ]] && echo "openai_api_key=$OPENAI_API_KEY"
        [[ -n "$GEMINI_API_KEY" ]] && echo "gemini_api_key=$GEMINI_API_KEY"
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# =============================================================================
#  SETUP WIZARD — interactive first-time or re-configuration
# =============================================================================
run_setup() {
    echo
    echo "$(bold '╔══════════════════════════════════╗')"
    echo "$(bold '║        ask  ·  setup wizard      ║')"
    echo "$(bold '╚══════════════════════════════════╝')"
    echo

    # ── Provider ─────────────────────────────────────────────────────────────
    echo "$(bold 'Choose an AI provider:')"
    echo "  $(cyan '1)') OpenAI    $(dim '(gpt-4.1-nano — fastest & cheapest)')"
    echo "  $(cyan '2)') Gemini    $(dim '(gemini-2.5-flash-lite — fastest & cheapest)')"
    echo
    while true; do
        read -rp "$(bold 'Provider [1/2]:') " choice < /dev/tty
        case "$choice" in
            1) PROVIDER="openai";  break ;;
            2) PROVIDER="gemini";  break ;;
            *) echo "  Please enter 1 or 2." ;;
        esac
    done

    # ── Model ─────────────────────────────────────────────────────────────────
    echo
    if [[ "$PROVIDER" == "openai" ]]; then
        echo "$(bold 'Choose a model:')  $(dim 'https://platform.openai.com/docs/models')"
        echo "  $(cyan '1)') gpt-4.1-nano   $(dim '← default · cheapest · 1M context')"
        echo "  $(cyan '2)') gpt-4.1-mini"
        echo "  $(cyan '3)') gpt-4.1"
        echo "  $(cyan '4)') gpt-4o-mini"
        echo "  $(cyan '5)') Custom…"
        read -rp "$(bold 'Model [1-5, default 1]:') " m < /dev/tty
        case "${m:-1}" in
            1) MODEL="gpt-4.1-nano" ;;
            2) MODEL="gpt-4.1-mini" ;;
            3) MODEL="gpt-4.1" ;;
            4) MODEL="gpt-4o-mini" ;;
            5) read -rp "Model name: " MODEL < /dev/tty ;;
            *) MODEL="gpt-4.1-nano" ;;
        esac
    else
        echo "$(bold 'Choose a model:')  $(dim 'https://ai.google.dev/gemini-api/docs/models')"
        echo "  $(cyan '1)') gemini-2.5-flash-lite  $(dim '← default · cheapest · 1M context')"
        echo "  $(cyan '2)') gemini-2.5-flash"
        echo "  $(cyan '3)') gemini-2.5-pro"
        echo "  $(cyan '4)') Custom…"
        read -rp "$(bold 'Model [1-4, default 1]:') " m < /dev/tty
        case "${m:-1}" in
            1) MODEL="gemini-2.5-flash-lite" ;;
            2) MODEL="gemini-2.5-flash" ;;
            3) MODEL="gemini-2.5-pro" ;;
            4) read -rp "Model name: " MODEL < /dev/tty ;;
            *) MODEL="gemini-2.5-flash-lite" ;;
        esac
    fi

    # ── API key ───────────────────────────────────────────────────────────────
    echo
    if [[ "$PROVIDER" == "openai" ]]; then
        echo "$(bold 'OpenAI API key')  $(dim 'platform.openai.com/api-keys')"
        read -rsp "$(bold 'Key (hidden):') " OPENAI_API_KEY < /dev/tty; echo
        [[ -z "$OPENAI_API_KEY" ]] && echo "$(red 'Key is required.')" && exit 1
    else
        echo "$(bold 'Gemini API key')  $(dim 'aistudio.google.com/app/apikey')"
        read -rsp "$(bold 'Key (hidden):') " GEMINI_API_KEY < /dev/tty; echo
        [[ -z "$GEMINI_API_KEY" ]] && echo "$(red 'Key is required.')" && exit 1
    fi

    # ── Max tokens ────────────────────────────────────────────────────────────
    echo
    read -rp "$(bold 'Max response tokens') $(dim '[default 200]:') " mt < /dev/tty
    [[ -n "$mt" ]] && MAX_TOKENS="$mt"

    write_config

    echo
    echo "$(green '✔') Config saved → $(bold "$CONFIG_FILE")"
    echo "  provider   = $(cyan "$PROVIDER")"
    echo "  model      = $(cyan "$MODEL")"
    echo "  max_tokens = $(cyan "$MAX_TOKENS")"
    echo
    echo "  Run $(bold 'ask --setup') at any time to reconfigure."
    echo
}

# =============================================================================
#  HELP
# =============================================================================
show_help() {
    cat <<EOF
$(bold 'ask') v${VERSION} — AI terminal assistant

$(bold 'USAGE')
  ask <task description>        Generate a bash command and optionally run it
  ask -<flag> <question>        Free-form AI answer (no command wrapping)
  ask !!                        Explain the last shell command
  ask commit                    Generate a commit message, then git add + commit
  ask --setup                   (Re-)run the interactive setup wizard
  ask --help                    Show this help

$(bold 'PIPING')
  Pipe any content as context — ask responds in free-form (no run prompt):
    cat error.log | ask "why is this failing?"
    git diff      | ask "summarise these changes"

$(bold 'CONFIG')  ~/.ask_config  (chmod 600)
  provider=openai|gemini     AI service to use
  model=<name>               Model override (empty = cheapest default)
  max_tokens=200             Max tokens in response
  openai_api_key=sk-...      Your OpenAI key
  gemini_api_key=AIza...     Your Gemini key

$(bold 'ENV VARS')  (take priority over config file)
  OPENAI_API_KEY, GEMINI_API_KEY, VERBOSE=true

$(bold 'EXAMPLES')
  ask "find all .log files modified in the last 7 days"
  ask "restart nginx if it is not running"
  ask -q "What does the HEAD~3 ref mean in git?"
  cat crash.log | ask "what caused this?"
  ask !!
  ask commit

$(bold 'PROVIDERS & DEFAULT MODELS')
  openai  →  gpt-4.1-nano        \$0.10 / 1M input tokens
  gemini  →  gemini-2.5-flash-lite

$(bold 'PROJECT')  https://github.com/zmsp/ask
EOF
}

# =============================================================================
#  AI PROVIDER CALLS
# =============================================================================

# Call the OpenAI Chat Completions API.
# Uses $prompt, $MODEL, $MAX_TOKENS, $OPENAI_API_KEY (all set before calling).
call_openai() {
    local payload response
    payload=$(jq -n \
        --arg  model  "$MODEL" \
        --arg  msg    "$prompt" \
        --argjson max "$MAX_TOKENS" \
        '{model:$model,messages:[{role:"user",content:$msg}],temperature:0,max_tokens:$max}')

    response=$(curl -fsSL https://api.openai.com/v1/chat/completions \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload") || {
            echo "$(red 'Error: OpenAI request failed. Check your API key and network.')" >&2
            exit 1
        }

    echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Call the Google Gemini generateContent API.
# Uses $prompt, $MODEL, $MAX_TOKENS, $GEMINI_API_KEY.
call_gemini() {
    local payload response
    payload=$(jq -n \
        --arg  msg "$prompt" \
        --argjson max "$MAX_TOKENS" \
        '{contents:[{parts:[{text:$msg}]}],generationConfig:{maxOutputTokens:$max,temperature:0}}')

    response=$(curl -fsSL \
        "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload") || {
            echo "$(red 'Error: Gemini request failed. Check your API key and network.')" >&2
            exit 1
        }

    echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty'
}

# Route to the configured provider.
call_ai() {
    case "$PROVIDER" in
        openai) call_openai ;;
        gemini) call_gemini ;;
        *)
            echo "$(red "Unknown provider '$PROVIDER'.")" >&2
            echo "Run: ask --setup" >&2
            exit 1 ;;
    esac
}

# =============================================================================
#  INTERNAL HELPERS
# =============================================================================

# Resolve default model for the current provider (used when model is unset).
resolve_default_model() {
    [[ -n "$MODEL" ]] && return
    case "$PROVIDER" in
        gemini) MODEL="gemini-2.5-flash-lite" ;;
        *)      MODEL="gpt-4.1-nano" ;;
    esac
}

# Print a guard warning and require the user to type "yes" before continuing.
# Usage: confirm_dangerous <command>
# Returns 0 if user confirmed, 1 if cancelled.
confirm_dangerous() {
    echo
    echo "$(yellow '⚠  Dangerous command — review before running:')"
    echo "   $1"
    echo
    read -rp "$(bold 'Type  yes  to run, anything else to cancel:') " ans < /dev/tty
    [[ "$ans" == "yes" ]]
}

# =============================================================================
#  ENTRY POINT
# =============================================================================

# ── --help ────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 || "$1" =~ ^(-h|--help)$ ]]; then
    show_help
    exit 0
fi

# ── Setup / Configuration ──────────────────────────────────────────────────
if [[ "$1" == "--setup" || "$1" == "setup" ]]; then
    load_config
    run_setup
    exit 0
fi

# ── ask !! — explain the last shell command ───────────────────────────────────
if [[ "$1" == "!!" ]]; then
    load_config
    resolve_default_model

    # fc -ln -1 works in bash; fall back to history for other shells
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//' \
               || history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')

    if [[ -z "$last_cmd" || "$last_cmd" =~ ^ask[[:space:]]+!! ]]; then
        echo "$(yellow 'No previous command found.')"
        exit 1
    fi

    prompt="Explain this shell command clearly and concisely — describe what it does, what each flag/argument means, and call out any gotchas or risks: ${last_cmd}"
    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2

    raw=$(call_ai)
    echo
    echo "$(bold "$ ${last_cmd}")"
    echo
    printf '%s\n' "$raw"
    exit 0
fi

# ── ask commit — AI-powered git commit ───────────────────────────────────────
if [[ "$1" == "commit" ]]; then
    load_config
    resolve_default_model

    if ! git rev-parse --git-dir &>/dev/null; then
        echo "$(red 'Not inside a git repository.')"
        exit 1
    fi

    git_status=$(git status --short 2>&1)
    if [[ -z "$git_status" ]]; then
        echo "$(green 'Nothing to commit — working tree is clean.')"
        exit 0
    fi

    # git diff HEAD fails on a repo with no commits; fall back to --cached
    git_diff=$(git diff HEAD 2>/dev/null || git diff --cached 2>/dev/null)
    [[ -z "$git_diff" ]] && git_diff=$(git diff --cached 2>/dev/null)

    MAX_TOKENS=500
    prompt="Write a concise git commit message for these changes.\n\
Rules:\n\
- Subject line: imperative mood, max 72 characters\n\
- Add a blank line + short bullet-point body ONLY if the changes are complex\n\
- Output ONLY the commit message — no explanation, no markdown fences\n\n\
Git status:\n${git_status}\n\nGit diff:\n${git_diff}"

    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2

    raw=$(call_ai)
    commit_msg=$(printf '%s' "$raw" | sed '/^```/d; /^`/d' | sed '/^[[:space:]]*$/d' | head -20)

    if [[ -z "$commit_msg" ]]; then
        echo "$(red 'No response from AI.')" >&2
        echo "Check your API key or run: ask --setup" >&2
        exit 1
    fi

    echo
    echo "$(bold 'Git status:')"
    git status --short
    echo
    echo "$(bold 'Suggested commit message:')"
    echo "$commit_msg"
    echo

    read -rp "$(bold 'Commit with this message? (y/n):') " confirm < /dev/tty
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        git add -A
        git commit -m "$commit_msg"
    else
        echo "Cancelled."
    fi
    exit 0
fi

# ── Normal / free-form mode ───────────────────────────────────────────────────
load_config

# Trigger setup wizard if no config or missing API key
needs_setup=false
[[ ! -f "$CONFIG_FILE" ]]                                     && needs_setup=true
[[ "$PROVIDER" == "openai" && -z "$OPENAI_API_KEY" ]]         && needs_setup=true
[[ "$PROVIDER" != "openai" && -z "$GEMINI_API_KEY" ]]         && needs_setup=true

if $needs_setup; then
    echo "$(yellow '→') No config found — launching setup."
    echo
    run_setup
    load_config
fi

resolve_default_model

# ── Read piped stdin (if any) ─────────────────────────────────────────────────
stdin_data=""
if [[ ! -t 0 ]]; then
    stdin_data=$(cat)
fi

# ── Build the prompt ──────────────────────────────────────────────────────────
if [[ "${1:0:1}" == "-" ]]; then
    # Flags like -q, -e etc. → free-form answer, no run prompt
    prompt="$*"
    skip_run=true
else
    # Default: ask for a single executable bash command
    prompt="Output only the raw bash command to accomplish this task — no explanation, no markdown, no code fences: $*"
    skip_run=false
fi

# Append piped content as additional context; switch to free-form mode
if [[ -n "$stdin_data" ]]; then
    prompt="${prompt}"$'\n\n'"Context (piped input):"$'\n'"${stdin_data}"
    skip_run=true
fi

[[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL prompt=$prompt" >&2

# ── Call the AI ───────────────────────────────────────────────────────────────
raw=$(call_ai)

# Strip any residual markdown fences the model may have included
command=$(printf '%s' "$raw" | sed '/^```/d; s/^`//; s/`$//')

if [[ -z "$command" ]]; then
    echo "$(red 'No response received.')" >&2
    echo "Check your API key or run: ask --setup" >&2
    exit 1
fi

echo
echo "$(bold 'Suggested:')"
echo "$command"
echo

# ── Optionally execute ────────────────────────────────────────────────────────
if [[ "$skip_run" != true ]]; then

    # Dangerous-command guard — require full "yes" for high-risk patterns
    danger_pattern='(rm[[:space:]]+-[^ ]*r|-rf[[:space:]]|sudo[[:space:]]|>[[:space:]]*/dev/|dd[[:space:]]+if=|\|[[:space:]]*(sh|bash|zsh)[[:space:]]*$|chmod[[:space:]]+-R[[:space:]]+[0-7]*7|mkfs)'
    if printf '%s' "$command" | grep -qE "$danger_pattern"; then
        echo "$(yellow '⚠  This command looks dangerous. Type  yes  to run, anything else cancels.')"
        read -rp "$(bold 'Run ANYWAY?') " ans < /dev/tty
        if [[ "$ans" == "yes" ]]; then
            eval "$command"
        else
            echo "Cancelled."
        fi
    else
        read -rp "$(bold 'Run this command?') $(dim '(y/n):') " ans < /dev/tty
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            eval "$command"
        else
            echo "Cancelled."
        fi
    fi
fi
