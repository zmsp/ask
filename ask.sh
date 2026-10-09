#!/usr/bin/env bash
# =============================================================================
#  ask — AI-powered terminal assistant
#
#  Turn plain-English descriptions into shell commands (and run them),
#  or use it as a general-purpose AI chat layer from your terminal.
#
#  Supports:  OpenAI (gpt-4.1-nano default) · Google Gemini (2.5-flash-lite)
#             Ollama (local / offline / free)
#  Requires:  curl · jq · bash 3.2+
#
#  Project:   https://github.com/zmsp/ask
#  License:   MIT
# =============================================================================
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
CONFIG_FILE="${ASK_CONFIG_FILE:-$HOME/.ask_config}"
STATS_FILE="${ASK_STATS_FILE:-$HOME/.ask_stats}"
VERSION="2.1.1"

# ── Runtime state (all overridable via ~/.ask_config or env vars) ─────────────
PROVIDER="openai"
MODEL=""
MAX_TOKENS=200
OLLAMA_ENDPOINT="http://localhost:11434/v1"
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
            ollama_endpoint) OLLAMA_ENDPOINT="$value" ;;
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
        [[ -n "$OLLAMA_ENDPOINT" ]] && echo "ollama_endpoint=$OLLAMA_ENDPOINT"
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
    echo "  $(cyan '3)') Ollama    $(dim '(Local / offline / free — requires ollama)')"
    echo
    while true; do
        read -rp "$(bold 'Provider [1/2/3]:') " choice < /dev/tty
        case "$choice" in
            1) PROVIDER="openai";  break ;;
            2) PROVIDER="gemini";  break ;;
            3) PROVIDER="ollama";  break ;;
            *) echo "  Please enter 1, 2, or 3." ;;
        esac
    done

    # ── Model ─────────────────────────────────────────────────────────────────
    echo
    if [[ "$PROVIDER" == "openai" ]]; then
        echo "$(bold 'Choose a model:')  $(dim 'https://platform.openai.com/docs/models')"
        echo "  $(cyan '1)') gpt-4.1-nano   $(dim '← default · cheapest · 1M context')"
        echo "  $(cyan '2)') gpt-4.1-mini"
        echo "  $(cyan '3)') gpt-4.1"
        echo "  $(cyan '4)') gpt-4o"
        echo "  $(cyan '5)') gpt-4o-mini"
        echo "  $(cyan '6)') o3-mini"
        echo "  $(cyan '7)') Custom…"
        read -rp "$(bold 'Model [1-7, default 1]:') " m < /dev/tty
        case "${m:-1}" in
            1) MODEL="gpt-4.1-nano" ;;
            2) MODEL="gpt-4.1-mini" ;;
            3) MODEL="gpt-4.1" ;;
            4) MODEL="gpt-4o" ;;
            5) MODEL="gpt-4o-mini" ;;
            6) MODEL="o3-mini" ;;
            7) read -rp "Model name: " MODEL < /dev/tty ;;
            *) MODEL="gpt-4.1-nano" ;;
        esac
    elif [[ "$PROVIDER" == "gemini" ]]; then
        echo "$(bold 'Choose a model:')  $(dim 'https://ai.google.dev/gemini-api/docs/models')"
        echo "  $(cyan '1)') gemini-2.5-flash-lite  $(dim '← default · cheapest · 1M context')"
        echo "  $(cyan '2)') gemini-2.5-flash"
        echo "  $(cyan '3)') gemini-2.5-pro"
        echo "  $(cyan '4)') gemini-3.5-flash-lite"
        echo "  $(cyan '5)') gemini-3.8-flash"
        echo "  $(cyan '6)') gemini-flash-latest    $(dim 'auto-updates to newest flash')"
        echo "  $(cyan '7)') gemini-flash-lite-latest $(dim 'auto-updates to newest flash-lite')"
        echo "  $(cyan '8)') gemini-pro-latest      $(dim 'auto-updates to newest pro')"
        echo "  $(cyan '9)') Custom…"
        read -rp "$(bold 'Model [1-9, default 1]:') " m < /dev/tty
        case "${m:-1}" in
            1) MODEL="gemini-2.5-flash-lite" ;;
            2) MODEL="gemini-2.5-flash" ;;
            3) MODEL="gemini-2.5-pro" ;;
            4) MODEL="gemini-3.5-flash-lite" ;;
            5) MODEL="gemini-3.8-flash" ;;
            6) MODEL="gemini-flash-latest" ;;
            7) MODEL="gemini-flash-lite-latest" ;;
            8) MODEL="gemini-pro-latest" ;;
            9) read -rp "Model name: " MODEL < /dev/tty ;;
            *) MODEL="gemini-2.5-flash-lite" ;;
        esac
    else
        echo "$(bold 'Choose a model:')  $(dim 'https://ollama.com/library')"
        echo "  $(cyan '1)') llama3.2       $(dim '← default lightweight')"
        echo "  $(cyan '2)') qwen2.5-coder  $(dim 'code-specialized')"
        echo "  $(cyan '3)') codellama"
        echo "  $(cyan '4)') Custom…"
        read -rp "$(bold 'Model [1-4, default 1]:') " m < /dev/tty
        case "${m:-1}" in
            1) MODEL="llama3.2" ;;
            2) MODEL="qwen2.5-coder" ;;
            3) MODEL="codellama" ;;
            4) read -rp "Model name: " MODEL < /dev/tty ;;
            *) MODEL="llama3.2" ;;
        esac

        echo
        read -rp "$(bold 'Ollama endpoint') $(dim '[default http://localhost:11434/v1]:') " ep < /dev/tty
        [[ -n "$ep" ]] && OLLAMA_ENDPOINT="$ep"
    fi

    # ── API key (not required for Ollama) ────────────────────────────────────
    if [[ "$PROVIDER" != "ollama" ]]; then
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
    [[ "$PROVIDER" == "ollama" ]] && echo "  endpoint   = $(cyan "$OLLAMA_ENDPOINT")"
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
  ask <task description>        Generate a shell command with [y]es/[e]dit/[c]opy/[n]o
  ask --raw <task>              Output only raw command (scripting/keybinds)
  ask -<flag> <question>        Free-form AI answer (no command wrapping)
  ask fix [optional context]    Diagnose & fix the last command or piped error
  ask cheat <tool>              Quick 5-recipe cheatsheet (e.g. ask cheat tar)
  ask !!                        Explain the last shell command
  ask commit                    Generate a commit message, then git add + commit
  ask review                    AI code review of uncommitted or branch changes
  ask branch <task>             Generate semantic git branch name & checkout
  ask --stats                   Show token usage & query statistics
  ask --init [bash|zsh|pwsh]    Print shell keybind snippet (Ctrl-X Ctrl-A)
  ask --setup                   (Re-)run the interactive setup wizard
  ask --help                    Show this help

$(bold 'PIPING')
  Pipe any content as context:
    cat error.log | ask "why is this failing?"
    git diff      | ask "summarise these changes"
    npm test 2>&1 | ask fix

$(bold 'EXECUTION PROMPT')
  When a command is suggested:
    [y]es   Run command immediately
    [e]dit  Edit in readline before running
    [c]opy  Copy command to clipboard (pbcopy, wl-copy, xclip, clip.exe)
    [n]o    Cancel execution

$(bold 'CONFIG')  ~/.ask_config  (chmod 600)
  provider=openai|gemini|ollama   AI service to use
  model=<name>                    Model override (empty = cheapest default)
  max_tokens=200                  Max tokens in response
  ollama_endpoint=http://...      Ollama endpoint URL
  openai_api_key=sk-...           OpenAI API key
  gemini_api_key=AIza...          Gemini API key

$(bold 'ENV VARS')  (take priority over config file)
  OPENAI_API_KEY, GEMINI_API_KEY, VERBOSE=true

$(bold 'PROVIDERS & DEFAULT MODELS')
  openai  →  gpt-4.1-nano            \$0.10 / 1M input tokens
  gemini  →  gemini-2.5-flash-lite   \$0.10 / 1M input tokens
  ollama  →  llama3.2                Free / offline

$(bold 'PROJECT')  https://github.com/zmsp/ask
EOF
}

# =============================================================================
#  HOST CONTEXT & UTILS
# =============================================================================

# Detect host OS, distro, architecture, and shell for context-aware prompts
detect_environment() {
    local os arch distro shell_name
    os="$(uname -s 2>/dev/null || echo "Unix")"
    arch="$(uname -m 2>/dev/null || echo "")"
    shell_name="${SHELL##*/}"
    [[ -z "$shell_name" ]] && shell_name="bash"

    if [[ "$os" == "Darwin" ]]; then
        distro="macOS"
    elif [[ "$os" == "Linux" && -f /etc/os-release ]]; then
        distro="$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
        [[ -z "$distro" ]] && distro="Linux"
    else
        distro="$os"
    fi
    echo "$distro $arch ($shell_name)"
}

# Copy string to clipboard with zero external package dependency
copy_to_clipboard() {
    local text="$1"
    if command -v pbcopy &>/dev/null; then
        printf '%s' "$text" | pbcopy && return 0
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy &>/dev/null; then
        printf '%s' "$text" | wl-copy && return 0
    elif command -v xclip &>/dev/null; then
        printf '%s' "$text" | xclip -selection clipboard && return 0
    elif command -v xsel &>/dev/null; then
        printf '%s' "$text" | xsel -b && return 0
    elif command -v clip.exe &>/dev/null; then
        printf '%s' "$text" | clip.exe && return 0
    fi
    return 1
}

# Append request tokens to ~/.ask_stats
record_stats() {
    local provider="$1"
    local model="$2"
    local json="$3"
    local p_tok=0 c_tok=0
    if [[ "$provider" == "gemini" ]]; then
        p_tok=$(echo "$json" | jq -r '.usageMetadata.promptTokenCount // 0' 2>/dev/null || echo 0)
        c_tok=$(echo "$json" | jq -r '.usageMetadata.candidatesTokenCount // 0' 2>/dev/null || echo 0)
    else
        p_tok=$(echo "$json" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null || echo 0)
        c_tok=$(echo "$json" | jq -r '.usage.completion_tokens // 0' 2>/dev/null || echo 0)
    fi
    [[ "$p_tok" =~ ^[0-9]+$ ]] || p_tok=0
    [[ "$c_tok" =~ ^[0-9]+$ ]] || c_tok=0
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$provider" "$model" "$p_tok" "$c_tok" >> "$STATS_FILE" 2>/dev/null || true
}

# Display stats report from ~/.ask_stats
show_stats() {
    if [[ ! -f "$STATS_FILE" || ! -s "$STATS_FILE" ]]; then
        echo "$(yellow 'No usage stats recorded yet.')"
        return 0
    fi
    echo
    echo "$(bold 'ask · Usage Statistics')"
    echo "$(dim "Tracked in: $STATS_FILE")"
    echo
    awk -F'\t' '
    {
        calls++
        prompt_total += $4
        comp_total += $5
        key = $2 " (" $3 ")"
        models[key]++
    }
    END {
        printf "Total queries:      %d\n", calls
        printf "Prompt tokens:      %d\n", prompt_total
        printf "Completion tokens:  %d\n", comp_total
        printf "Total tokens:       %d\n\n", (prompt_total + comp_total)
        print "Queries by provider/model:"
        for (k in models) {
            printf "  %-32s %d\n", k, models[k]
        }
    }' "$STATS_FILE"
    echo
}

# Print shell keybind snippet
show_init_snippet() {
    local target="${1:-bash}"
    case "$target" in
        zsh)
            cat <<'EOF'
# Add to ~/.zshrc:
_ask_inline() {
    [[ -z "$BUFFER" ]] && return
    local cmd
    cmd=$(ask --raw "$BUFFER" 2>/dev/null)
    if [[ -n "$cmd" ]]; then
        BUFFER="$cmd"
        CURSOR=${#BUFFER}
    fi
}
zle -N _ask_inline
bindkey '^X^A' _ask_inline
EOF
            ;;
        pwsh|powershell)
            cat <<'EOF'
# Add to $PROFILE:
Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+a' -ScriptBlock {
    $line = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
    if (-not $line) { return }
    $cmd = ask --raw $line 2>$null
    if ($cmd) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($cmd)
    }
}
EOF
            ;;
        *)
            cat <<'EOF'
# Add to ~/.bashrc:
_ask_inline() {
    [[ -z "$READLINE_LINE" ]] && return
    local cmd
    cmd=$(ask --raw "$READLINE_LINE" 2>/dev/null)
    if [[ -n "$cmd" ]]; then
        READLINE_LINE="$cmd"
        READLINE_POINT=${#READLINE_LINE}
    fi
}
bind -x '"\C-x\C-a": _ask_inline'
EOF
            ;;
    esac
}

# =============================================================================
#  AI PROVIDER CALLS
# =============================================================================

# Call OpenAI Chat Completions API
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

    record_stats "openai" "$MODEL" "$response"
    echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Call Google Gemini generateContent API
call_gemini() {
    local payload response
    local model_name="$MODEL"
    [[ "$model_name" == "latest" || "$model_name" == "gemini-latest" ]] && model_name="gemini-flash-latest"
    [[ "$model_name" == "flash-lite-latest" || "$model_name" == "lite-latest" ]] && model_name="gemini-flash-lite-latest"

    payload=$(jq -n \
        --arg  msg "$prompt" \
        --argjson max "$MAX_TOKENS" \
        '{contents:[{parts:[{text:$msg}]}],generationConfig:{maxOutputTokens:$max,temperature:0}}')

    response=$(curl -fsSL \
        "https://generativelanguage.googleapis.com/v1beta/models/${model_name}:generateContent?key=${GEMINI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload") || {
            echo "$(red 'Error: Gemini request failed. Check your API key and network.')" >&2
            exit 1
        }

    record_stats "gemini" "$model_name" "$response"
    echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty'
}

# Call local Ollama API (OpenAI-compatible)
call_ollama() {
    local endpoint="${OLLAMA_ENDPOINT%/}/chat/completions"
    local payload response
    payload=$(jq -n \
        --arg  model  "$MODEL" \
        --arg  msg    "$prompt" \
        --argjson max "$MAX_TOKENS" \
        '{model:$model,messages:[{role:"user",content:$msg}],temperature:0,max_tokens:$max}')

    response=$(curl -fsSL "$endpoint" \
        -H "Content-Type: application/json" \
        -d "$payload") || {
            echo "$(red "Error: Ollama request failed at $endpoint. Is Ollama running?")" >&2
            exit 1
        }

    record_stats "ollama" "$MODEL" "$response"
    echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Route to the configured provider
call_ai() {
    case "$PROVIDER" in
        openai) call_openai ;;
        gemini) call_gemini ;;
        ollama) call_ollama ;;
        *)
            echo "$(red "Unknown provider '$PROVIDER'.")" >&2
            echo "Run: ask --setup" >&2
            exit 1 ;;
    esac
}

# =============================================================================
#  INTERNAL HELPERS
# =============================================================================

resolve_default_model() {
    if [[ "$PROVIDER" == "gemini" ]]; then
        case "$MODEL" in
            latest|gemini-latest) MODEL="gemini-flash-latest" ;;
            flash-lite-latest|lite-latest) MODEL="gemini-flash-lite-latest" ;;
        esac
    fi
    [[ -n "$MODEL" ]] && return
    case "$PROVIDER" in
        gemini) MODEL="gemini-2.5-flash-lite" ;;
        ollama) MODEL="llama3.2" ;;
        *)      MODEL="gpt-4.1-nano" ;;
    esac
}

# Read single keypress for [n]/[c]/[e], require Enter for [y]/[yes]
read_execution_choice() {
    local prompt_str="$1"
    local first_char=""
    local rest=""
    local choice=""

    if [[ -r /dev/tty ]] && [[ -t 0 || -t 1 ]]; then
        printf '%s' "$prompt_str" > /dev/tty
        read -r -s -n 1 first_char < /dev/tty 2>/dev/null || true
        case "$first_char" in
            [NnCcEe])
                printf '%s\n' "$first_char" > /dev/tty
                choice="$first_char"
                ;;
            [Yy])
                printf '%s' "$first_char" > /dev/tty
                read -r rest < /dev/tty 2>/dev/null || true
                choice="${first_char}${rest}"
                ;;
            "")
                printf '\n' > /dev/tty
                choice=""
                ;;
            *)
                printf '%s\n' "$first_char" > /dev/tty
                choice="$first_char"
                ;;
        esac
    else
        read -rp "$prompt_str" choice || true
    fi
    printf '%s' "$choice"
}

# Interactive prompt to run, edit, copy, or cancel a suggested command
prompt_execute() {
    local command="$1"
    local danger_pattern='(rm[[:space:]]+-[^ ]*r|-rf[[:space:]]|sudo[[:space:]]|>[[:space:]]*/dev/|dd[[:space:]]+if=|\|[[:space:]]*(sh|bash|zsh)[[:space:]]*$|chmod[[:space:]]+-R[[:space:]]+[0-7]*7|mkfs)'
    local is_danger=false
    local prompt_msg

    if printf '%s' "$command" | grep -qE "$danger_pattern"; then
        is_danger=true
        echo "$(yellow '⚠  This command looks dangerous.')"
        prompt_msg="$(bold 'Type  yes  to run, [e]dit, [c]opy, or [n]o:') "
    else
        prompt_msg="$(bold 'Run?') $(dim '[y]es / [e]dit / [c]opy / [n]o:') "
    fi

    local ans
    ans="$(read_execution_choice "$prompt_msg")"

    case "$ans" in
        yes|[Yy])
            if $is_danger && [[ "$ans" != "yes" ]]; then
                echo "Cancelled."
            else
                eval "$command"
            fi
            ;;
        [Ee]*)
            local edited_cmd=""
            if (( BASH_VERSINFO[0] >= 4 )); then
                read -e -i "$command" -p "$(bold 'Edit: ') " edited_cmd < /dev/tty || true
            else
                echo "$(dim "Original: $command")"
                read -e -p "$(bold 'Edit: ') " edited_cmd < /dev/tty || true
                edited_cmd="${edited_cmd:-$command}"
            fi
            if [[ -n "$edited_cmd" ]]; then
                eval "$edited_cmd"
            else
                echo "Cancelled."
            fi
            ;;
        [Cc]*)
            if copy_to_clipboard "$command"; then
                echo "$(green '✔') Copied to clipboard."
            else
                echo "$(yellow 'No clipboard tool found (pbcopy, wl-copy, xclip, clip.exe).')"
            fi
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
}

# =============================================================================
#  ENTRY POINT
# =============================================================================

# Return early if sourced as a library/test fixture
if [[ "${BASH_SOURCE[0]}" != "${0}" || "${ASK_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# ── --help / -h ───────────────────────────────────────────────────────────────
if [[ $# -eq 0 || "$1" =~ ^(-h|--help)$ ]]; then
    show_help
    exit 0
fi

# ── --version / -v ───────────────────────────────────────────────────────────
if [[ "$1" =~ ^(-v|--version)$ ]]; then
    echo "ask v${VERSION}"
    exit 0
fi

# ── --stats ───────────────────────────────────────────────────────────────────
if [[ "$1" == "--stats" || "$1" == "stats" ]]; then
    show_stats
    exit 0
fi

# ── --init (shell keybind helper) ─────────────────────────────────────────────
if [[ "$1" == "--init" ]]; then
    show_init_snippet "${2:-bash}"
    exit 0
fi

# ── Setup / Configuration ─────────────────────────────────────────────────────
if [[ "$1" == "--setup" || "$1" == "setup" ]]; then
    load_config
    run_setup
    exit 0
fi

# ── ask cheat <tool> — quick reference ────────────────────────────────────────
if [[ "$1" == "cheat" ]]; then
    load_config
    resolve_default_model
    tool="${2:-}"
    if [[ -z "$tool" ]]; then
        echo "$(yellow 'Usage: ask cheat <tool>   (e.g. ask cheat tar, ask cheat ffmpeg)')"
        exit 1
    fi

    MAX_TOKENS=500
    env_ctx=$(detect_environment)
    prompt="Target environment: ${env_ctx}. Give a concise cheatsheet for '${tool}'.
List the top 5 most useful and common real-world commands with a brief description for each.
Format:
<command>
  # <description>
Output plain text only, no markdown code fences, no extra commentary."

    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2
    raw=$(call_ai)
    echo
    echo "$(bold "Cheatsheet · ${tool}")"
    echo
    printf '%s\n' "$raw" | sed '/^```/d'
    echo
    exit 0
fi

# ── ask review — AI code review for git diff ──────────────────────────────────
if [[ "$1" == "review" ]]; then
    load_config
    resolve_default_model

    if ! git rev-parse --git-dir &>/dev/null; then
        echo "$(red 'Not inside a git repository.')"
        exit 1
    fi

    # Check uncommitted diff first, then branch diff against default branch
    git_diff=$(git diff HEAD 2>/dev/null || git diff --cached 2>/dev/null)
    if [[ -z "$git_diff" ]]; then
        base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
        [[ -z "$base_branch" ]] && base_branch="main"
        git_diff=$(git diff "${base_branch}...HEAD" 2>/dev/null || git diff master...HEAD 2>/dev/null || true)
    fi

    if [[ -z "$git_diff" ]]; then
        echo "$(green 'Nothing to review — working tree is clean and up to date.')"
        exit 0
    fi

    MAX_TOKENS=800
    prompt="Perform a concise, senior code review on this git diff.
Call out potential bugs, security flaws, performance gotchas, or missing edge cases.
If the changes look clean and well-structured, state that concisely.
Output plain text only.

Git diff:
${git_diff}"

    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2
    raw=$(call_ai)
    echo
    echo "$(bold 'Code Review:')"
    echo
    printf '%s\n' "$raw" | sed '/^```/d'
    echo
    exit 0
fi

# ── ask branch <task> — semantic git branch name generator ────────────────────
if [[ "$1" == "branch" ]]; then
    load_config
    resolve_default_model

    shift
    task_desc="$*"
    if [[ -z "$task_desc" ]]; then
        echo "$(yellow 'Usage: ask branch <task description>   (e.g. ask branch add oauth login)')"
        exit 1
    fi

    prompt="Generate a single git branch name for this task: ${task_desc}.
Rules:
- Format: <type>/<short-kebab-slug> (e.g. feat/oauth-login, fix/null-pointer, chore/dep-bump)
- Lowercase, hyphens for spaces, alphanumeric only, max 35 characters
- Output ONLY the branch name — no explanation, no markdown"

    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2
    raw=$(call_ai)
    branch_name=$(printf '%s' "$raw" | tr -d '`"'\'' ' | head -1)

    echo
    echo "$(bold 'Suggested branch:') $(cyan "$branch_name")"
    echo
    read -rp "$(bold 'Create and switch to this branch?') $(dim '[y]es / [c]opy / [n]o:') " ans < /dev/tty
    case "$ans" in
        [Yy]*)
            git checkout -b "$branch_name"
            ;;
        [Cc]*)
            if copy_to_clipboard "$branch_name"; then
                echo "$(green '✔') Copied to clipboard."
            fi
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
    exit 0
fi

# ── ask !! — explain the last shell command ───────────────────────────────────
if [[ "$1" == "!!" ]]; then
    load_config
    resolve_default_model

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

# ── ask fix — diagnose and fix last command or piped error ───────────────────
if [[ "$1" == "fix" ]]; then
    load_config
    resolve_default_model

    stdin_data=""
    if [[ ! -t 0 ]]; then
        stdin_data=$(cat)
    fi

    shift
    user_context="$*"

    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//' \
               || history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')

    if [[ "$last_cmd" =~ ^ask[[:space:]]+fix ]]; then
        last_cmd=""
    fi

    env_ctx=$(detect_environment)
    prompt="Target environment: ${env_ctx}.
The user ran a shell command that failed.
Previous command: ${last_cmd:-"(unknown)"}
Error / output context:
${stdin_data}
${user_context}

Output ONLY the corrected, executable shell command to fix the issue and accomplish the goal — no explanation, no markdown, no code fences."

    [[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL" >&2
    raw=$(call_ai)
    command=$(printf '%s' "$raw" | sed '/^```/d; s/^`//; s/`$//' | head -1)

    if [[ -z "$command" ]]; then
        echo "$(red 'No fix command suggested.')" >&2
        exit 1
    fi

    echo
    echo "$(bold 'Suggested fix:')"
    echo "$command"
    echo
    prompt_execute "$command"
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

    read -rp "$(bold 'Commit with this message?') $(dim '[y]es / [c]opy / [n]o:') " confirm < /dev/tty
    case "$confirm" in
        [Yy]*)
            git add -A
            git commit -m "$commit_msg"
            ;;
        [Cc]*)
            if copy_to_clipboard "$commit_msg"; then
                echo "$(green '✔') Copied to clipboard."
            fi
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
    exit 0
fi

# ── Normal / free-form mode ───────────────────────────────────────────────────
load_config

# Trigger setup wizard if no config or missing API key (Ollama needs no key)
needs_setup=false
[[ ! -f "$CONFIG_FILE" ]]                                      && needs_setup=true
[[ "$PROVIDER" == "openai" && -z "$OPENAI_API_KEY" ]]          && needs_setup=true
[[ "$PROVIDER" == "gemini" && -z "$GEMINI_API_KEY" ]]          && needs_setup=true

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

# ── Check for --raw flag ──────────────────────────────────────────────────────
raw_output=false
if [[ "$1" == "--raw" ]]; then
    raw_output=true
    shift
fi

# ── Build the prompt ──────────────────────────────────────────────────────────
if [[ "${1:0:1}" == "-" && "$raw_output" != true ]]; then
    # Flags like -q, -e etc. → free-form answer, no run prompt
    prompt="$*"
    skip_run=true
else
    # Command generation with host environment context
    env_ctx=$(detect_environment)
    prompt="Target environment: ${env_ctx}. Output only the raw shell command to accomplish this task — no explanation, no markdown, no code fences: $*"
    skip_run=false
fi

# Append piped content as additional context; switch to free-form mode unless raw
if [[ -n "$stdin_data" ]]; then
    prompt="${prompt}"$'\n\n'"Context (piped input):"$'\n'"${stdin_data}"
    [[ "$raw_output" != true ]] && skip_run=true
fi

[[ "${VERBOSE:-}" == "true" ]] && echo "[debug] provider=$PROVIDER model=$MODEL prompt=$prompt" >&2

# ── Call the AI ───────────────────────────────────────────────────────────────
raw=$(call_ai)

# Strip any residual markdown fences the model may have included
command=$(printf '%s' "$raw" | sed '/^```/d; s/^`//; s/`$//' | head -1)

if [[ -z "$command" ]]; then
    echo "$(red 'No response received.')" >&2
    echo "Check your API key or run: ask --setup" >&2
    exit 1
fi

if [[ "$raw_output" == true ]]; then
    printf '%s\n' "$command"
    exit 0
fi

if [[ "$skip_run" == true ]]; then
    echo
    printf '%s\n' "$raw"
    exit 0
fi

echo
echo "$(bold 'Suggested:')"
echo "$command"
echo

prompt_execute "$command"
