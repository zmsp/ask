#!/usr/bin/env pwsh
# =============================================================================
#  ask.ps1 — AI-powered terminal assistant for Windows (PowerShell)
#
#  Turn plain-English descriptions into shell commands (and run them),
#  or use it as a general-purpose AI chat layer from your terminal.
#
#  Supports:  OpenAI (gpt-4.1-nano default) · Google Gemini (2.5-flash-lite)
#  Requires:  PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)
#
#  Project:   https://github.com/zmsp/ask
#  License:   MIT
# =============================================================================
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
#  CONSTANTS
# =============================================================================
$VERSION     = "2.0.0"
$CONFIG_FILE = Join-Path ($env:USERPROFILE ?? $env:HOME) ".ask_config"

# =============================================================================
#  RUNTIME STATE  (overridable via ~/.ask_config or environment variables)
# =============================================================================
$script:Provider     = "openai"
$script:Model        = ""
$script:MaxTokens    = 200
$script:OpenAIApiKey = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { "" }
$script:GeminiApiKey = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { "" }

# =============================================================================
#  COLOR HELPERS
#  Usage: Write-Host (Cyan "text") (Bold "more text")
#  Note:  Single-quoted args inside $() in a double-quoted string are a
#         PS parser error — always call these helpers via variables or
#         as standalone expressions in double-quoted here-strings.
# =============================================================================
function Bold   { param([string]$t) "`e[1m${t}`e[0m" }
function Dim    { param([string]$t) "`e[2m${t}`e[0m" }
function Cyan   { param([string]$t) "`e[36m${t}`e[0m" }
function Green  { param([string]$t) "`e[32m${t}`e[0m" }
function Yellow { param([string]$t) "`e[33m${t}`e[0m" }
function Red    { param([string]$t) "`e[31m${t}`e[0m" }

# =============================================================================
#  CONFIG — load / write ~/.ask_config
# =============================================================================

# Load key=value pairs from ~/.ask_config.
# Lines starting with # are ignored. Inline # comments are stripped.
# Environment variables always take priority over config file values.
function Load-Config {
    if (-not (Test-Path $CONFIG_FILE)) { return }

    foreach ($line in Get-Content $CONFIG_FILE) {
        $line = $line.Trim()
        if ($line -match "^#" -or $line -eq "") { continue }

        $line = ($line -split "#")[0].TrimEnd()
        if ($line -notmatch "^([^=]+)=(.*)$") { continue }
        $key   = $Matches[1].Trim()
        $value = $Matches[2].Trim()

        switch ($key) {
            "provider"        { $script:Provider     = $value }
            "model"           { $script:Model        = $value }
            "max_tokens"      { $script:MaxTokens    = [int]$value }
            "openai_api_key"  { if (-not $script:OpenAIApiKey) { $script:OpenAIApiKey = $value } }
            "gemini_api_key"  { if (-not $script:GeminiApiKey) { $script:GeminiApiKey = $value } }
        }
    }
}

# Persist current settings to ~/.ask_config (restricted file permissions).
function Write-Config {
    $date  = Get-Date -Format "yyyy-MM-dd"
    $lines = @(
        "# ask config — generated $date",
        "provider=$($script:Provider)",
        "model=$($script:Model)",
        "max_tokens=$($script:MaxTokens)"
    )
    if ($script:OpenAIApiKey) { $lines += "openai_api_key=$($script:OpenAIApiKey)" }
    if ($script:GeminiApiKey) { $lines += "gemini_api_key=$($script:GeminiApiKey)" }

    $lines | Set-Content -Path $CONFIG_FILE -Encoding UTF8

    # Restrict file to current user only (Windows ACL — non-fatal if unavailable)
    try {
        $acl  = Get-Acl $CONFIG_FILE
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, "FullControl", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl $CONFIG_FILE $acl
    } catch { }
}

# =============================================================================
#  SETUP WIZARD — interactive first-time or re-configuration
# =============================================================================
function Run-Setup {
    Write-Host ""
    Write-Host (Bold "╔══════════════════════════════════╗")
    Write-Host (Bold "║        ask  ·  setup wizard      ║")
    Write-Host (Bold "╚══════════════════════════════════╝")
    Write-Host ""

    # ── Provider ──────────────────────────────────────────────────────────────
    Write-Host (Bold "Choose an AI provider:")
    $c1 = Cyan "1)"
    $c2 = Cyan "2)"
    $d1 = Dim "(gpt-4.1-nano — fastest & cheapest)"
    $d2 = Dim "(gemini-2.5-flash-lite — fastest & cheapest)"
    Write-Host "  $c1 OpenAI    $d1"
    Write-Host "  $c2 Gemini    $d2"
    Write-Host ""

    do {
        $choice = Read-Host (Bold "Provider [1/2]")
    } while ($choice -notin @("1","2"))

    $script:Provider = if ($choice -eq "1") { "openai" } else { "gemini" }

    # ── Model ──────────────────────────────────────────────────────────────────
    Write-Host ""
    if ($script:Provider -eq "openai") {
        $url = Dim "https://platform.openai.com/docs/models"
        Write-Host "$(Bold 'Choose a model:')  $url"
        $n1 = Cyan "1)"
        $n2 = Cyan "2)"
        $n3 = Cyan "3)"
        $n4 = Cyan "4)"
        $n5 = Cyan "5)"
        $def = Dim "<- default, cheapest, 1M context"
        Write-Host "  $n1 gpt-4.1-nano   $def"
        Write-Host "  $n2 gpt-4.1-mini"
        Write-Host "  $n3 gpt-4.1"
        Write-Host "  $n4 gpt-4o-mini"
        Write-Host "  $n5 Custom..."
        $m = Read-Host (Bold "Model [1-5, default 1]")
        $script:Model = switch ($m) {
            "2"     { "gpt-4.1-mini" }
            "3"     { "gpt-4.1" }
            "4"     { "gpt-4o-mini" }
            "5"     { Read-Host "Model name" }
            default { "gpt-4.1-nano" }
        }
    } else {
        $url = Dim "https://ai.google.dev/gemini-api/docs/models"
        Write-Host "$(Bold 'Choose a model:')  $url"
        $n1 = Cyan "1)"
        $n2 = Cyan "2)"
        $n3 = Cyan "3)"
        $n4 = Cyan "4)"
        $def = Dim "<- default, cheapest, 1M context"
        Write-Host "  $n1 gemini-2.5-flash-lite  $def"
        Write-Host "  $n2 gemini-2.5-flash"
        Write-Host "  $n3 gemini-2.5-pro"
        Write-Host "  $n4 Custom..."
        $m = Read-Host (Bold "Model [1-4, default 1]")
        $script:Model = switch ($m) {
            "2"     { "gemini-2.5-flash" }
            "3"     { "gemini-2.5-pro" }
            "4"     { Read-Host "Model name" }
            default { "gemini-2.5-flash-lite" }
        }
    }

    # ── API key ────────────────────────────────────────────────────────────────
    Write-Host ""
    if ($script:Provider -eq "openai") {
        $hint = Dim "platform.openai.com/api-keys"
        Write-Host "$(Bold 'OpenAI API key')  $hint"
        $secureKey = Read-Host (Bold "Key (hidden)") -AsSecureString
        $script:OpenAIApiKey = [System.Net.NetworkCredential]::new("", $secureKey).Password
        if (-not $script:OpenAIApiKey) { Write-Host (Red "Key is required."); exit 1 }
    } else {
        $hint = Dim "aistudio.google.com/app/apikey"
        Write-Host "$(Bold 'Gemini API key')  $hint"
        $secureKey = Read-Host (Bold "Key (hidden)") -AsSecureString
        $script:GeminiApiKey = [System.Net.NetworkCredential]::new("", $secureKey).Password
        if (-not $script:GeminiApiKey) { Write-Host (Red "Key is required."); exit 1 }
    }

    # ── Max tokens ─────────────────────────────────────────────────────────────
    Write-Host ""
    $defLabel = Dim "[default 200]"
    $mt = Read-Host "$(Bold 'Max response tokens') $defLabel"
    if ($mt -match "^\d+$") { $script:MaxTokens = [int]$mt }

    Write-Config

    $savedLabel = Green "✔"
    $provVal    = Cyan $script:Provider
    $modVal     = Cyan $script:Model
    $tokVal     = Cyan "$($script:MaxTokens)"
    Write-Host ""
    Write-Host "$savedLabel Config saved -> $(Bold $CONFIG_FILE)"
    Write-Host "  provider   = $provVal"
    Write-Host "  model      = $modVal"
    Write-Host "  max_tokens = $tokVal"
    Write-Host ""
    Write-Host "  Run $(Bold 'ask --setup') at any time to reconfigure."
    Write-Host ""
}

# =============================================================================
#  HELP
# =============================================================================
function Show-Help {
    # Build colored labels first (no inline single-quote-in-$() issues)
    $bAsk      = Bold "ask"
    $bUsage    = Bold "USAGE"
    $bPiping   = Bold "PIPING"
    $bConfig   = Bold "CONFIG"
    $bEnv      = Bold "ENV VARS"
    $bExamples = Bold "EXAMPLES"
    $bProviders= Bold "PROVIDERS & DEFAULT MODELS"
    $bProject  = Bold "PROJECT"

    Write-Host @"
$bAsk v${VERSION} — AI terminal assistant

$bUsage
  ask <task description>        Generate a PowerShell command and optionally run it
  ask -q <question>             Free-form AI answer (no command wrapping)
  ask !!                        Explain the last command from history
  ask commit                    Generate a commit message, then git add + commit
  ask --setup                   (Re-)run the interactive setup wizard
  ask --help                    Show this help

$bPiping
  Pipe any content as context — ask responds in free-form (no run prompt):
    Get-Content error.log | ask "why is this failing?"
    git diff              | ask "summarise these changes"

$bConfig  $CONFIG_FILE
  provider=openai|gemini     AI service to use
  model=<name>               Model override (empty = cheapest default)
  max_tokens=200             Max tokens in response
  openai_api_key=sk-...      Your OpenAI key
  gemini_api_key=AIza...     Your Gemini key

$bEnv  (take priority over config file)
  OPENAI_API_KEY, GEMINI_API_KEY, VERBOSE=true

$bExamples
  ask "find all .log files modified in the last 7 days"
  ask "list processes using more than 500MB of memory"
  ask -q "What does HEAD~3 mean in git?"
  Get-Content crash.log | ask "what caused this?"
  ask !!
  ask commit

$bProviders
  openai  ->  gpt-4.1-nano            `$0.10 / 1M input tokens
  gemini  ->  gemini-2.5-flash-lite   `$0.10 / 1M input tokens

$bProject  https://github.com/zmsp/ask
"@
}

# =============================================================================
#  AI PROVIDER CALLS
# =============================================================================

# Call the OpenAI Chat Completions API.
# Reads $script:Model, $script:MaxTokens, $script:OpenAIApiKey.
function Invoke-OpenAI {
    param([string]$Prompt)

    $body = @{
        model       = $script:Model
        messages    = @(@{ role = "user"; content = $Prompt })
        temperature = 0
        max_tokens  = $script:MaxTokens
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
            -Uri     "https://api.openai.com/v1/chat/completions" `
            -Method  POST `
            -Headers @{
                "Authorization" = "Bearer $($script:OpenAIApiKey)"
                "Content-Type"  = "application/json"
            } `
            -Body $body
        return $response.choices[0].message.content
    } catch {
        Write-Host (Red "Error: OpenAI request failed.")
        Write-Host "Details: $_"
        Write-Host "Check your API key or run: ask --setup"
        exit 1
    }
}

# Call the Google Gemini generateContent API.
# Reads $script:Model, $script:MaxTokens, $script:GeminiApiKey.
function Invoke-Gemini {
    param([string]$Prompt)

    $body = @{
        contents         = @(@{ parts = @(@{ text = $Prompt }) })
        generationConfig = @{
            maxOutputTokens = $script:MaxTokens
            temperature     = 0
        }
    } | ConvertTo-Json -Depth 6

    $url = "https://generativelanguage.googleapis.com/v1beta/models/$($script:Model):generateContent?key=$($script:GeminiApiKey)"

    try {
        $response = Invoke-RestMethod `
            -Uri     $url `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body
        return $response.candidates[0].content.parts[0].text
    } catch {
        Write-Host (Red "Error: Gemini request failed.")
        Write-Host "Details: $_"
        Write-Host "Check your API key or run: ask --setup"
        exit 1
    }
}

# Route to the configured AI provider.
function Invoke-AI {
    param([string]$Prompt)
    switch ($script:Provider) {
        "openai" { return Invoke-OpenAI $Prompt }
        "gemini" { return Invoke-Gemini $Prompt }
        default  {
            Write-Host (Red "Unknown provider: $($script:Provider). Run: ask --setup")
            exit 1
        }
    }
}

# =============================================================================
#  INTERNAL HELPERS
# =============================================================================

# Set the cheapest default model for the current provider if none configured.
function Resolve-DefaultModel {
    if ($script:Model) { return }
    $script:Model = if ($script:Provider -eq "gemini") {
        "gemini-2.5-flash-lite"
    } else {
        "gpt-4.1-nano"
    }
}

# Strip markdown code fences the model may include in its response.
function Strip-Fences {
    param([string]$Text)
    # Remove ```lang and ``` lines
    $fence = [char]96 + [char]96 + [char]96
    $Text  = ($Text -split "`n" | Where-Object { -not $_.TrimStart().StartsWith($fence) }) -join "`n"
    return $Text.Trim()
}

# Returns $true if the command string contains high-risk patterns.
function Test-Dangerous {
    param([string]$Cmd)
    # Check for destructive or elevated patterns
    if ($Cmd -match "Remove-Item.+-Recurse") { return $true }
    if ($Cmd -match "rm\s+-[rRf]+")          { return $true }
    if ($Cmd -match "sudo\s")                { return $true }
    if ($Cmd -match "Format-Volume")         { return $true }
    if ($Cmd -match "Clear-Disk")            { return $true }
    if ($Cmd -match "dd\s+if=")              { return $true }
    if ($Cmd -match "\|\s*(sh|bash|cmd|pwsh)\s*$") { return $true }
    return $false
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
$allArgs = $args

# ── Help ──────────────────────────────────────────────────────────────────────
if ($allArgs.Count -eq 0 -or $allArgs[0] -in @("-h", "--help", "/?")) {
    Show-Help
    exit 0
}

# ── Setup ─────────────────────────────────────────────────────────────────────
if ($allArgs[0] -eq "--setup") {
    Load-Config
    Run-Setup
    exit 0
}

# ── ask !! — explain the last history command ─────────────────────────────────
if ($allArgs[0] -eq "!!") {
    Load-Config
    Resolve-DefaultModel

    $hist    = Get-History -Count 2
    $lastCmd = if ($hist.Count -ge 2) { $hist[-2].CommandLine } `
               elseif ($hist.Count -eq 1) { $hist[-1].CommandLine } `
               else { "" }

    if (-not $lastCmd -or $lastCmd -match "^ask\s*!!") {
        Write-Host (Yellow "No previous command found.")
        exit 1
    }

    $prompt = "Explain this PowerShell/shell command clearly and concisely — describe what it does, what each flag/argument means, and call out any gotchas or risks: $lastCmd"
    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }

    $raw = Invoke-AI $prompt
    Write-Host ""
    Write-Host (Bold "PS> $lastCmd")
    Write-Host ""
    Write-Host $raw
    exit 0
}

# ── ask commit — AI-powered git commit ───────────────────────────────────────
if ($allArgs[0] -eq "commit") {
    Load-Config
    Resolve-DefaultModel

    # Verify we're in a git repo
    $gitCheck = & git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host (Red "Not inside a git repository.")
        exit 1
    }

    $gitStatus = (& git status --short 2>&1) | Out-String
    if (-not $gitStatus.Trim()) {
        Write-Host (Green "Nothing to commit — working tree is clean.")
        exit 0
    }

    # git diff HEAD fails on fresh repos with no commits; fall back to --cached
    $gitDiff = (& git diff HEAD 2>$null) | Out-String
    if (-not $gitDiff.Trim()) {
        $gitDiff = (& git diff --cached 2>$null) | Out-String
    }

    $script:MaxTokens = 500
    $prompt = @"
Write a concise git commit message for these changes.
Rules:
- Subject line: imperative mood, max 72 characters
- Add a blank line + short bullet-point body ONLY if the changes are complex
- Output ONLY the commit message, no explanation, no markdown fences

Git status:
$gitStatus

Git diff:
$gitDiff
"@

    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }

    $raw       = Invoke-AI $prompt
    $commitMsg = (Strip-Fences $raw).Trim()

    if (-not $commitMsg) {
        Write-Host (Red "No response from AI. Check your API key or run: ask --setup")
        exit 1
    }

    Write-Host ""
    Write-Host (Bold "Git status:")
    & git status --short
    Write-Host ""
    Write-Host (Bold "Suggested commit message:")
    Write-Host $commitMsg
    Write-Host ""

    $confirm = Read-Host (Bold "Commit with this message? (y/n)")
    if ($confirm -match "^[Yy]$") {
        & git add -A
        & git commit -m $commitMsg
    } else {
        Write-Host "Cancelled."
    }
    exit 0
}

# ── Normal / free-form mode ───────────────────────────────────────────────────
Load-Config

# Trigger setup wizard if no config or missing API key
$needsSetup = $false
if (-not (Test-Path $CONFIG_FILE))                                   { $needsSetup = $true }
if ($script:Provider -eq "openai" -and -not $script:OpenAIApiKey)   { $needsSetup = $true }
if ($script:Provider -ne "openai" -and -not $script:GeminiApiKey)   { $needsSetup = $true }

if ($needsSetup) {
    Write-Host (Yellow "-> No config found. Launching setup.")
    Write-Host ""
    Run-Setup
    Load-Config
}

Resolve-DefaultModel

# ── Read piped stdin (if any) ─────────────────────────────────────────────────
$stdinData = ""
try {
    if ([Console]::IsInputRedirected) {
        $stdinData = $input | Out-String
    }
} catch { }

# ── Build the prompt ──────────────────────────────────────────────────────────
$userInput = $allArgs -join " "
$skipRun   = $false

if ($userInput.StartsWith("-")) {
    # Free-form mode: flags like -q, -e, etc.
    $prompt  = $userInput
    $skipRun = $true
} else {
    # Command generation mode — ask for a raw PowerShell command
    $prompt  = "Output only the raw PowerShell command to accomplish this task — no explanation, no markdown, no code fences: $userInput"
    $skipRun = $false
}

# Append piped stdin as context and switch to free-form mode
if ($stdinData.Trim()) {
    $prompt  += "`n`nContext (piped input):`n$stdinData"
    $skipRun  = $true
}

if ($env:VERBOSE -eq "true") {
    Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)"
    Write-Host "[debug] prompt=$prompt"
}

# ── Call the AI ───────────────────────────────────────────────────────────────
$raw     = Invoke-AI $prompt
$command = (Strip-Fences $raw).Trim()

if (-not $command) {
    Write-Host (Red "No response received. Check your API key or run: ask --setup")
    exit 1
}

Write-Host ""
Write-Host (Bold "Suggested:")
Write-Host $command
Write-Host ""

# ── Optionally execute ────────────────────────────────────────────────────────
if (-not $skipRun) {
    if (Test-Dangerous $command) {
        Write-Host (Yellow "Warning: This command looks dangerous. Type  yes  to run, anything else cancels.")
        $ans = Read-Host (Bold "Run ANYWAY?")
        if ($ans -eq "yes") {
            Invoke-Expression $command
        } else {
            Write-Host "Cancelled."
        }
    } else {
        $runLabel = Dim "(y/n)"
        $ans = Read-Host "$(Bold 'Run this command?') $runLabel"
        if ($ans -match "^[Yy]$") {
            Invoke-Expression $command
        } else {
            Write-Host "Cancelled."
        }
    }
}
