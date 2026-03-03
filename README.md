# ask — AI terminal assistant

> Turn plain-English descriptions into shell commands. Powered by OpenAI or Google Gemini.

![Demo](https://github.com/zmsp/ask/blob/main/docs/screenshot.gif?raw=true)

---

## Features

- **Command generation** — Get shell commands from plain English.
- **Stdin piping** — Pipe content for context (`cat file | ask "..."`).
- **Free-form chat** — Chat directly with the AI using a `-` prefix.
- **`ask !!`** — Explain the last command from your history.
- **`ask commit`** — Generate a commit message for current changes and commit them.
- **Dangerous command guard** — Warns before running risky commands (`rm -rf`, `sudo`).
- **Multi-provider** — Supports OpenAI and Google Gemini.
- **Persistent config** — Saves settings to `~/.ask_config`.

---

## Quick Install

### macOS / Linux
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

| Platform | Script | Installer |
|----------|--------|-----------|
| macOS / Linux | `ask` (bash) | `install.sh` |
| Windows | `ask.ps1` (PowerShell 5.1+) | `install.ps1` |

---

## Requirements

| Tool | Install |
|------|---------|
| `bash` 4+ | Pre-installed on macOS/Linux |
| `curl` | `brew install curl` / `apt install curl` |
| `jq` | `brew install jq` / `apt install jq` |
| AI API key | [OpenAI](https://platform.openai.com/api-keys) or [Gemini](https://aistudio.google.com/app/apikey) |

---

## Usage

### Generate & run a bash command
```bash
ask "list all .log files modified in the last 7 days"
ask "restart nginx if it's not running"
ask "find the 5 largest files in my home directory"
```

```
Suggested:
find ~ -type f -printf '%s %p\n' | sort -rn | head -5

Run this command? (y/n): y
```

### Free-form AI question (no command wrapping)
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

### Explain the last command
```bash
ls -la /etc/hosts
ask !!
# → Explains ls, -l (long format), -a (hidden files), and the path
```

### AI-powered git commit
```bash
ask commit
```
```
Git status:
 M src/index.js
 M README.md

Suggested commit message:
Update index.js routing and expand README usage section

Commit with this message? (y/n): y
[main 3f2a1b4] Update index.js routing and expand README usage section
```

### Dangerous command guard
```bash
ask "recursively delete all files in /tmp/cache"

Suggested:
rm -rf /tmp/cache/*

⚠  This command looks dangerous. Type  yes  to run, anything else cancels.
Run ANYWAY? yes
```

---

## Configuration

Configuration is stored in `~/.ask_config` (user-readable only).

Run the interactive wizard:
```bash
ask --setup
```

Or edit the file directly:
```ini
# ~/.ask_config
provider=openai          # openai | gemini
model=gpt-4.1-nano       # leave blank for cheapest default
max_tokens=200
openai_api_key=sk-...
gemini_api_key=AIza...
```

### Environment variables

Environment variables always take priority over the config file:

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

**OpenAI models:** `gpt-4.1-nano` · `gpt-4.1-mini` · `gpt-4.1` · `gpt-4o-mini`  
**Gemini models:** `gemini-2.5-flash-lite` · `gemini-2.5-flash` · `gemini-2.5-pro`

---

## License

MIT © [Zobair](https://github.com/zmsp)
