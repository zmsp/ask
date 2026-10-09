# ask — AI terminal assistant

> Turn plain-English descriptions into shell commands. Powered by OpenAI, Google Gemini, or local Ollama. Zero external dependencies.

![Demo](https://github.com/zmsp/ask/blob/main/docs/screenshot.gif?raw=true)

---

## Features

- **Command generation** — Get shell commands tailored to your OS, architecture, and shell.
- **Interactive execution** — `[y]es` run, `[e]dit` in readline before running, `[c]opy` to clipboard, or `[n]o`.
- **`ask fix`** — Diagnose and correct the last failed command or piped error stream.
- **`ask cheat <tool>`** — Instant 5-recipe cheatsheet for tricky utilities (`tar`, `ffmpeg`, `jq`).
- **`ask !!`** — Explain the last shell command from history.
- **Git workflow suite**:
  - **`ask commit`** — Generate clean commit messages from git status & diff.
  - **`ask review`** — AI code review on uncommitted or branch changes.
  - **`ask branch <task>`** — Semantic kebab-case branch name generator + checkout.
- **Local AI support** — Run completely offline and free via Ollama (no API key required).
- **Token & query tracker** — `ask --stats` tracks usage across models and providers.
- **Inline shell keybinds** — `ask --init` provides `Ctrl-X Ctrl-A` inline completion for Bash, Zsh, and PowerShell.
- **`--raw` scripting flag** — Pure command string output for aliases, scripts, and shell integrations.
- **Dangerous command guard** — Warns and requires explicit confirmation for risky patterns (`rm -rf`, `sudo`).
- **0 external dependencies** — Written in pure Bash and PowerShell; uses only standard OS utilities.

---

## Quick Install

### macOS (Homebrew — Recommended)
```bash
brew tap zmsp/ask
brew install ask
```

### macOS / Linux (Installer Script)
```bash
curl -fsSL https://zmsp.github.io/ask/install.sh | bash
```

Or manually:
```bash
curl -fsSL https://raw.githubusercontent.com/zmsp/ask/main/ask.sh -o /usr/local/bin/ask
chmod +x /usr/local/bin/ask
ask --setup
```

### Windows (PowerShell)
```powershell
irm https://zmsp.github.io/ask/install.ps1 | iex
```

Or manually:
```powershell
irm https://raw.githubusercontent.com/zmsp/ask/main/ask.ps1 -OutFile "$env:USERPROFILE\bin\ask.ps1"
# Add $env:USERPROFILE\bin to your PATH, then:
ask --setup
```

## Uninstall

```bash
# Homebrew
brew uninstall ask

# macOS / Linux installer
curl -fsSL https://zmsp.github.io/ask/install.sh | bash -s -- --uninstall

# Windows (PowerShell)
& ([scriptblock]::Create((irm https://zmsp.github.io/ask/install.ps1))) -Uninstall
```

| Platform | Script | Installer |
|----------|--------|-----------|
| macOS (Brew) | `Formula/ask.rb` | `brew install zmsp/ask/ask` |
| macOS / Linux | `ask.sh` (bash) | `install.sh` |
| Windows | `ask.ps1` (PowerShell 5.1+) | `install.ps1` |

---

## Requirements

| Tool | Install |
|------|---------|
| `bash` 3.2+ or `pwsh` | Pre-installed on macOS/Linux/Windows |
| `curl` | `brew install curl` / `apt install curl` |
| `jq` | `brew install jq` / `apt install jq` (Bash script only) |
| AI provider | [OpenAI](https://platform.openai.com/api-keys), [Gemini](https://aistudio.google.com/app/apikey), or [Ollama](https://ollama.com) (local) |

---

## Usage

### Generate & run a shell command
```bash
ask "list all .log files modified in the last 7 days"
ask "restart nginx if it's not running"
ask "find the 5 largest files in my home directory"
```

```
Suggested:
find ~ -type f -mtime -7 -name "*.log"

Run? [y]es / [e]dit / [c]opy / [n]o: e
Edit: find ~ -type f -mtime -14 -name "*.log"
```
- `y` runs the command immediately.
- `e` lets you edit the command inline in terminal readline before executing.
- `c` copies it directly to your clipboard (`pbcopy`, `wl-copy`, `xclip`, or `clip.exe`).
- `n` cancels.

### Diagnose & fix errors (`ask fix`)
```bash
# Fix last failed command from shell history
docker run -p 80:80 myapp
# Error: port 80 is already allocated
ask fix

# Or pipe stderr directly
cargo build 2>&1 | ask fix
git push 2>&1    | ask fix
```

### CLI Cheatsheet (`ask cheat <tool>`)
```bash
ask cheat tar
ask cheat ffmpeg
ask cheat jq
```

### Explain the last command (`ask !!`)
```bash
tar -czvf backup.tar.gz --exclude="*.log" ./data
ask !!
# → Explains flags, paths, compression behavior, and risks
```

### Code review & Git helpers
```bash
# Concise senior review of current uncommitted or branch diff
ask review

# Generate semantic branch name and switch to it
ask branch "add user password reset with email token"
# → Suggested: feat/user-password-reset
# Create and switch to this branch? [y]es / [c]opy / [n]o: y

# AI-powered commit message generator
ask commit
```

### Free-form AI question
```bash
ask -q "What does HEAD~3 mean in git?"
ask -e "Explain the difference between CMD and ENTRYPOINT in Docker"
```

### Pipe content as context
```bash
cat error.log  | ask "why is this failing?"
git diff       | ask "summarise these changes"
cat config.yml | ask "is anything misconfigured here?"
```

### Track token usage & stats
```bash
ask --stats
```
```
ask · Usage Statistics
Tracked in: ~/.ask_stats

Total queries:      14
Prompt tokens:      2,350
Completion tokens:  410
Total tokens:       2,760

Queries by provider/model:
  openai (gpt-4.1-nano)            10
  ollama (llama3.2)                4
```

### Shell Keybinding (Inline AI expansion)
Press `Ctrl-X Ctrl-A` on any line to replace what you typed with the AI-suggested command.

```bash
# Print keybind configuration for your shell:
ask --init bash  # or zsh or pwsh

# Quick install into ~/.zshrc:
eval "$(ask --init zsh)"
```

---

## Configuration

Configuration is stored in `~/.ask_config` (mode 600, user-readable only).

Run the interactive wizard:
```bash
ask --setup
```

Or edit directly:
```ini
# ~/.ask_config
provider=openai          # openai | gemini | ollama
model=gpt-4.1-nano       # leave blank for cheapest default
max_tokens=200
ollama_endpoint=http://localhost:11434/v1
openai_api_key=sk-...
gemini_api_key=AIza...
```

### Environment variables

Environment variables take priority over config file values:

```bash
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="AIza..."
export VERBOSE=true           # print debug info
```

---

## Provider & Model Reference

| Provider | Default model | Price (input/output per 1M tokens) |
|----------|--------------|--------------------------------------|
| `openai` | `gpt-4.1-nano` | $0.10 / $0.40 |
| `gemini` | `gemini-2.5-flash-lite` | $0.10 / $0.40 |
| `ollama` | `llama3.2` | Free (runs locally) |

**OpenAI models:** `gpt-4.1-nano` · `gpt-4.1-mini` · `gpt-4.1` · `gpt-4o` · `gpt-4o-mini` · `o3-mini`  
**Gemini models:** `gemini-2.5-flash-lite` · `gemini-2.5-flash` · `gemini-2.5-pro` · `gemini-3.5-flash-lite` · `gemini-3.8-flash` · `gemini-flash-latest` (`latest`) · `gemini-flash-lite-latest` · `gemini-pro-latest`  
**Ollama models:** `llama3.2` · `qwen2.5-coder` · `codellama` · any local model

---

## License

MIT © [Zobair](https://github.com/zmsp)
