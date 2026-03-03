#!/bin/bash
# =============================================================================
#  demo.sh — cinematic demonstration script for ask
# =============================================================================

ASK_CMD="/Users/z/code/ask-bash/ask"

# Simulate typing character by character
typewriter() {
    local text="$1"
    local delay="${2:-0.01}"
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

run_demo() {
    local purpose=$1
    local cmd=$2
    
    echo
    echo -e "\033[1;34mPURPOSE:\033[0m $purpose"
    echo
    printf '\033[1m$ \033[0m'
    typewriter "$cmd"
    eval "$cmd"
    echo ""
    sleep 3
    clear
}

clear

# ── 1. Installer Demo ─────────────────────────────────────────────────────────
run_demo "Install ask via one-liner" \
    "echo \"curl -fsSL https://zmsp.github.io/ask/install.sh | bash\""

# ── 2. Command Generation ─────────────────────────────────────────────────────
run_demo "Generate a shell command from natural language" \
    "$ASK_CMD 'find all files in /tmp that are empty'"

# ── 3. Free-form Question ─────────────────────────────────────────────────────
run_demo "Ask a general technical question (no command wrapping)" \
    "$ASK_CMD -q 'What directory are the log files on ubuntu'"

# ── 4. Stdin Piping ───────────────────────────────────────────────────────────
run_demo "Pipe terminal output as context for instant AI help" \
    "echo 'curl: (6) Could not resolve host: arjkeajrkl.com' | $ASK_CMD 'what does this mean?'"

# ── 5. ask !! (Previous Command Explanation) ──────────────────────────────────
# Run a "failed" or confusing command first
curl arjkeajrkl.com > /dev/null 2>&1 || true
run_demo "Explain or fix the last command executed in history" \
    "$ASK_CMD '!!'"

# ── 6. Dangerous Command Guard ────────────────────────────────────────────────
run_demo "Safety first — requires typing 'yes' for high-risk commands" \
    "$ASK_CMD 'delete everything in /tmp recursively'"

# ── 7. Git Commit ─────────────────────────────────────────────────────────────
run_demo "Automate staging and AI-generated commit messages" \
    "$ASK_CMD commit"

echo
sleep 1
clear
