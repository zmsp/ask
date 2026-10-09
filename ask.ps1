#!/usr/bin/env pwsh
# =============================================================================
#  ask.ps1 — AI-powered terminal assistant for Windows & PowerShell
#
#  Turn plain-English descriptions into shell commands (and run them),
#  or use it as a general-purpose AI chat layer from your terminal.
#
#  Supports:  OpenAI (gpt-4.1-nano default) · Google Gemini (2.5-flash-lite)
#             Ollama (local / offline / free)
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
$VERSION     = "2.1.1"
$CONFIG_FILE = if ($env:ASK_CONFIG_FILE) { $env:ASK_CONFIG_FILE } else { Join-Path ($env:USERPROFILE ?? $env:HOME) ".ask_config" }
$STATS_FILE  = if ($env:ASK_STATS_FILE) { $env:ASK_STATS_FILE } else { Join-Path ($env:USERPROFILE ?? $env:HOME) ".ask_stats" }

# =============================================================================
#  RUNTIME STATE  (overridable via ~/.ask_config or environment variables)
# =============================================================================
$script:Provider       = "openai"
$script:Model          = ""
$script:MaxTokens      = 200
$script:OllamaEndpoint = "http://localhost:11434/v1"
$script:OpenAIApiKey   = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { "" }
$script:GeminiApiKey   = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { "" }

# =============================================================================
#  COLOR HELPERS
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
            "provider"        { $script:Provider       = $value }
            "model"           { $script:Model          = $value }
            "max_tokens"      { $script:MaxTokens      = [int]$value }
            "ollama_endpoint" { $script:OllamaEndpoint = $value }
            "openai_api_key"  { if (-not $script:OpenAIApiKey) { $script:OpenAIApiKey = $value } }
            "gemini_api_key"  { if (-not $script:GeminiApiKey) { $script:GeminiApiKey = $value } }
        }
    }
}

function Write-Config {
    $date  = Get-Date -Format "yyyy-MM-dd"
    $lines = @(
        "# ask config — generated $date",
        "provider=$($script:Provider)",
        "model=$($script:Model)",
        "max_tokens=$($script:MaxTokens)"
    )
    if ($script:OllamaEndpoint) { $lines += "ollama_endpoint=$($script:OllamaEndpoint)" }
    if ($script:OpenAIApiKey)   { $lines += "openai_api_key=$($script:OpenAIApiKey)" }
    if ($script:GeminiApiKey)   { $lines += "gemini_api_key=$($script:GeminiApiKey)" }

    $lines | Set-Content -Path $CONFIG_FILE -Encoding UTF8

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
#  SETUP WIZARD
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
    $c3 = Cyan "3)"
    $d1 = Dim "(gpt-4.1-nano — fastest & cheapest)"
    $d2 = Dim "(gemini-2.5-flash-lite — fastest & cheapest)"
    $d3 = Dim "(Local / offline / free — requires ollama)"
    Write-Host "  $c1 OpenAI    $d1"
    Write-Host "  $c2 Gemini    $d2"
    Write-Host "  $c3 Ollama    $d3"
    Write-Host ""

    do {
        $choice = Read-Host (Bold "Provider [1/2/3]")
    } while ($choice -notin @("1","2","3"))

    $script:Provider = switch ($choice) {
        "1" { "openai" }
        "2" { "gemini" }
        "3" { "ollama" }
    }

    # ── Model ──────────────────────────────────────────────────────────────────
    Write-Host ""
    if ($script:Provider -eq "openai") {
        $url = Dim "https://platform.openai.com/docs/models"
        $mHead = Bold "Choose a model:"
        Write-Host "$mHead  $url"
        $n1 = Cyan "1)"
        $n2 = Cyan "2)"
        $n3 = Cyan "3)"
        $n4 = Cyan "4)"
        $n5 = Cyan "5)"
        $def = Dim "<- default, cheapest, 1M context"
        Write-Host "  $n1 gpt-4.1-nano   $def"
        Write-Host "  $n2 gpt-4.1-mini"
        Write-Host "  $n3 gpt-4.1"
        Write-Host "  $n4 gpt-4o"
        Write-Host "  $n5 gpt-4o-mini"
        Write-Host "  $n6 o3-mini"
        Write-Host "  $n7 Custom..."
        $m = Read-Host (Bold "Model [1-7, default 1]")
        $script:Model = switch ($m) {
            "2"     { "gpt-4.1-mini" }
            "3"     { "gpt-4.1" }
            "4"     { "gpt-4o" }
            "5"     { "gpt-4o-mini" }
            "6"     { "o3-mini" }
            "7"     { Read-Host "Model name" }
            default { "gpt-4.1-nano" }
        }
    } elseif ($script:Provider -eq "gemini") {
        $url = Dim "https://ai.google.dev/gemini-api/docs/models"
        $mHead = Bold "Choose a model:"
        Write-Host "$mHead  $url"
        $n1 = Cyan "1)"
        $n2 = Cyan "2)"
        $n3 = Cyan "3)"
        $n4 = Cyan "4)"
        $n5 = Cyan "5)"
        $n6 = Cyan "6)"
        $n7 = Cyan "7)"
        $n8 = Cyan "8)"
        $n9 = Cyan "9)"
        $def = Dim "<- default, cheapest, 1M context"
        $lat = Dim "<- auto-updates to newest flash"
        $latl = Dim "<- auto-updates to newest flash-lite"
        $latp = Dim "<- auto-updates to newest pro"
        Write-Host "  $n1 gemini-2.5-flash-lite  $def"
        Write-Host "  $n2 gemini-2.5-flash"
        Write-Host "  $n3 gemini-2.5-pro"
        Write-Host "  $n4 gemini-3.5-flash-lite"
        Write-Host "  $n5 gemini-3.8-flash"
        Write-Host "  $n6 gemini-flash-latest    $lat"
        Write-Host "  $n7 gemini-flash-lite-latest $latl"
        Write-Host "  $n8 gemini-pro-latest      $latp"
        Write-Host "  $n9 Custom..."
        $m = Read-Host (Bold "Model [1-9, default 1]")
        $script:Model = switch ($m) {
            "2"     { "gemini-2.5-flash" }
            "3"     { "gemini-2.5-pro" }
            "4"     { "gemini-3.5-flash-lite" }
            "5"     { "gemini-3.8-flash" }
            "6"     { "gemini-flash-latest" }
            "7"     { "gemini-flash-lite-latest" }
            "8"     { "gemini-pro-latest" }
            "9"     { Read-Host "Model name" }
            default { "gemini-2.5-flash-lite" }
        }
    } else {
        $url = Dim "https://ollama.com/library"
        $mHead = Bold "Choose a model:"
        Write-Host "$mHead  $url"
        $n1 = Cyan "1)"
        $n2 = Cyan "2)"
        $n3 = Cyan "3)"
        $n4 = Cyan "4)"
        $def = Dim "<- default lightweight"
        $code = Dim "code-specialized"
        Write-Host "  $n1 llama3.2       $def"
        Write-Host "  $n2 qwen2.5-coder  $code"
        Write-Host "  $n3 codellama"
        Write-Host "  $n4 Custom..."
        $m = Read-Host (Bold "Model [1-4, default 1]")
        $script:Model = switch ($m) {
            "2"     { "qwen2.5-coder" }
            "3"     { "codellama" }
            "4"     { Read-Host "Model name" }
            default { "llama3.2" }
        }

        Write-Host ""
        $epPrompt = Bold "Ollama endpoint"
        $epDef    = Dim "[default http://localhost:11434/v1]"
        $ep = Read-Host "$epPrompt $epDef"
        if ($ep) { $script:OllamaEndpoint = $ep }
    }

    # ── API key (not required for Ollama) ──────────────────────────────────────
    if ($script:Provider -ne "ollama") {
        Write-Host ""
        if ($script:Provider -eq "openai") {
            $keyHead = Bold "OpenAI API key"
            $hint = Dim "platform.openai.com/api-keys"
            Write-Host "$keyHead  $hint"
            $secureKey = Read-Host (Bold "Key (hidden)") -AsSecureString
            $script:OpenAIApiKey = [System.Net.NetworkCredential]::new("", $secureKey).Password
            if (-not $script:OpenAIApiKey) { Write-Host (Red "Key is required."); exit 1 }
        } else {
            $keyHead = Bold "Gemini API key"
            $hint = Dim "aistudio.google.com/app/apikey"
            Write-Host "$keyHead  $hint"
            $secureKey = Read-Host (Bold "Key (hidden)") -AsSecureString
            $script:GeminiApiKey = [System.Net.NetworkCredential]::new("", $secureKey).Password
            if (-not $script:GeminiApiKey) { Write-Host (Red "Key is required."); exit 1 }
        }
    }

    # ── Max tokens ─────────────────────────────────────────────────────────────
    Write-Host ""
    $mtHead = Bold "Max response tokens"
    $defLabel = Dim "[default 200]"
    $mt = Read-Host "$mtHead $defLabel"
    if ($mt -match "^\d+$") { $script:MaxTokens = [int]$mt }

    Write-Config

    $savedLabel = Green "✔"
    $cfgPath    = Bold $CONFIG_FILE
    $provVal    = Cyan $script:Provider
    $modVal     = Cyan $script:Model
    $tokVal     = Cyan "$($script:MaxTokens)"
    $setupCmd   = Bold "ask --setup"

    Write-Host ""
    Write-Host "$savedLabel Config saved -> $cfgPath"
    Write-Host "  provider   = $provVal"
    Write-Host "  model      = $modVal"
    Write-Host "  max_tokens = $tokVal"
    if ($script:Provider -eq "ollama") {
        $epVal = Cyan $script:OllamaEndpoint
        Write-Host "  endpoint   = $epVal"
    }
    Write-Host ""
    Write-Host "  Run $setupCmd at any time to reconfigure."
    Write-Host ""
}

# =============================================================================
#  HELP
# =============================================================================
function Show-Help {
    $bAsk      = Bold "ask"
    $bUsage    = Bold "USAGE"
    $bPiping   = Bold "PIPING"
    $bExec     = Bold "EXECUTION PROMPT"
    $bConfig   = Bold "CONFIG"
    $bEnv      = Bold "ENV VARS"
    $bProviders= Bold "PROVIDERS & DEFAULT MODELS"
    $bProject  = Bold "PROJECT"

    Write-Host @"
$bAsk v${VERSION} — AI terminal assistant

$bUsage
  ask <task description>        Generate a PowerShell command with [y]es/[e]dit/[c]opy/[n]o
  ask --raw <task>              Output only raw command (scripting/keybinds)
  ask -q <question>             Free-form AI answer (no command wrapping)
  ask fix [optional context]    Diagnose & fix the last command or piped error
  ask cheat <tool>              Quick 5-recipe cheatsheet (e.g. ask cheat tar)
  ask !!                        Explain the last command from history
  ask commit                    Generate a commit message, then git add + commit
  ask review                    AI code review of uncommitted or branch changes
  ask branch <task>             Generate semantic git branch name & checkout
  ask --stats                   Show token usage & query statistics
  ask --init [bash|zsh|pwsh]    Print shell keybind snippet (Ctrl-X Ctrl-A)
  ask --setup                   (Re-)run the interactive setup wizard
  ask --help                    Show this help

$bPiping
  Pipe any content as context:
    Get-Content error.log | ask "why is this failing?"
    git diff              | ask "summarise these changes"
    cargo test 2>&1       | ask fix

$bExec
  When a command is suggested:
    [y]es   Run command immediately
    [e]dit  Edit command before running
    [c]opy  Copy command to clipboard
    [n]o    Cancel execution

$bConfig  $CONFIG_FILE
  provider=openai|gemini|ollama   AI service to use
  model=<name>                    Model override (empty = cheapest default)
  max_tokens=200                  Max tokens in response
  ollama_endpoint=http://...      Ollama endpoint URL
  openai_api_key=sk-...           OpenAI API key
  gemini_api_key=AIza...          Gemini API key

$bEnv  (take priority over config file)
  OPENAI_API_KEY, GEMINI_API_KEY, VERBOSE=true

$bProviders
  openai  ->  gpt-4.1-nano            `$0.10 / 1M input tokens
  gemini  ->  gemini-2.5-flash-lite   `$0.10 / 1M input tokens
  ollama  ->  llama3.2                Free / offline

$bProject  https://github.com/zmsp/ask
"@
}

# =============================================================================
#  HOST CONTEXT & UTILS
# =============================================================================

function Get-HostContext {
    $os = if ($IsWindows -or $env:OS -match "Windows") { "Windows" }
          elseif ($IsMacOS) { "macOS" }
          elseif ($IsLinux) { "Linux" }
          else { "Windows" }
    $psVer = $PSVersionTable.PSVersion.ToString()
    return "$os (PowerShell $psVer)"
}

function Copy-ToClipboard {
    param([string]$Text)
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $Text
            return $true
        } elseif (Get-Command clip.exe -ErrorAction SilentlyContinue) {
            $Text | clip.exe
            return $true
        }
    } catch { }
    return $false
}

function Record-Stats {
    param([string]$Provider, [string]$Model, [int]$PromptTokens, [int]$CompletionTokens)
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$date`t$Provider`t$Model`t$PromptTokens`t$CompletionTokens"
    try { Add-Content -Path $STATS_FILE -Value $line -Encoding UTF8 } catch { }
}

function Show-Stats {
    if (-not (Test-Path $STATS_FILE)) {
        Write-Host (Yellow "No usage stats recorded yet.")
        return
    }
    $lines = Get-Content $STATS_FILE
    if (-not $lines) {
        Write-Host (Yellow "No usage stats recorded yet.")
        return
    }
    $totalCalls = 0
    $promptTokens = 0
    $compTokens = 0
    $models = @{}

    foreach ($l in $lines) {
        $parts = $l -split "`t"
        if ($parts.Count -lt 5) { continue }
        $totalCalls++
        $p = 0; [int]::TryParse($parts[3], [ref]$p) | Out-Null
        $c = 0; [int]::TryParse($parts[4], [ref]$c) | Out-Null
        $promptTokens += $p
        $compTokens   += $c
        $key = "$($parts[1]) ($($parts[2]))"
        if ($models.ContainsKey($key)) { $models[$key]++ } else { $models[$key] = 1 }
    }

    Write-Host ""
    Write-Host (Bold "ask · Usage Statistics")
    $trackedLabel = Dim "Tracked in:"
    Write-Host "$trackedLabel $STATS_FILE"
    Write-Host ""
    Write-Host "Total queries:      $totalCalls"
    Write-Host "Prompt tokens:      $promptTokens"
    Write-Host "Completion tokens:  $compTokens"
    Write-Host "Total tokens:       $($promptTokens + $compTokens)"
    Write-Host ""
    Write-Host "Queries by provider/model:"
    foreach ($k in $models.Keys) {
        $count = $models[$k]
        Write-Host "  $($k.PadRight(32)) $count"
    }
    Write-Host ""
}

function Show-InitSnippet {
    param([string]$Target = "pwsh")
    switch ($Target.ToLower()) {
        "zsh" {
            Write-Host @'
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
'@
        }
        "bash" {
            Write-Host @'
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
'@
        }
        default {
            Write-Host @'
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
'@
        }
    }
}

# =============================================================================
#  AI PROVIDER CALLS
# =============================================================================

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

        $pTok = if ($response.usage) { [int]$response.usage.prompt_tokens } else { 0 }
        $cTok = if ($response.usage) { [int]$response.usage.completion_tokens } else { 0 }
        Record-Stats "openai" $script:Model $pTok $cTok

        return $response.choices[0].message.content
    } catch {
        Write-Host (Red "Error: OpenAI request failed.")
        Write-Host "Details: $_"
        Write-Host "Check your API key or run: ask --setup"
        exit 1
    }
}

function Invoke-Gemini {
    param([string]$Prompt)

    $body = @{
        contents         = @(@{ parts = @(@{ text = $Prompt }) })
        generationConfig = @{
            maxOutputTokens = $script:MaxTokens
            temperature     = 0
        }
    } | ConvertTo-Json -Depth 6

    $modelName = $script:Model
    if ($modelName -in @("latest", "gemini-latest")) { $modelName = "gemini-flash-latest" }
    if ($modelName -in @("flash-lite-latest", "lite-latest")) { $modelName = "gemini-flash-lite-latest" }
    $url = "https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=$($script:GeminiApiKey)"

    try {
        $response = Invoke-RestMethod `
            -Uri     $url `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body

        $pTok = if ($response.usageMetadata) { [int]$response.usageMetadata.promptTokenCount } else { 0 }
        $cTok = if ($response.usageMetadata) { [int]$response.usageMetadata.candidatesTokenCount } else { 0 }
        Record-Stats "gemini" $script:Model $pTok $cTok

        return $response.candidates[0].content.parts[0].text
    } catch {
        Write-Host (Red "Error: Gemini request failed.")
        Write-Host "Details: $_"
        Write-Host "Check your API key or run: ask --setup"
        exit 1
    }
}

function Invoke-Ollama {
    param([string]$Prompt)

    $body = @{
        model       = $script:Model
        messages    = @(@{ role = "user"; content = $Prompt })
        temperature = 0
        max_tokens  = $script:MaxTokens
    } | ConvertTo-Json -Depth 5

    $endpoint = "$($script:OllamaEndpoint.TrimEnd('/'))/chat/completions"

    try {
        $response = Invoke-RestMethod `
            -Uri     $endpoint `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body

        $pTok = if ($response.usage) { [int]$response.usage.prompt_tokens } else { 0 }
        $cTok = if ($response.usage) { [int]$response.usage.completion_tokens } else { 0 }
        Record-Stats "ollama" $script:Model $pTok $cTok

        return $response.choices[0].message.content
    } catch {
        Write-Host (Red "Error: Ollama request failed at $endpoint. Is Ollama running?")
        Write-Host "Details: $_"
        exit 1
    }
}

function Invoke-AI {
    param([string]$Prompt)
    switch ($script:Provider) {
        "openai" { return Invoke-OpenAI $Prompt }
        "gemini" { return Invoke-Gemini $Prompt }
        "ollama" { return Invoke-Ollama $Prompt }
        default  {
            Write-Host (Red "Unknown provider: $($script:Provider). Run: ask --setup")
            exit 1
        }
    }
}

# =============================================================================
#  INTERNAL HELPERS
# =============================================================================

function Resolve-DefaultModel {
    if ($script:Provider -eq "gemini") {
        if ($script:Model -in @("latest", "gemini-latest")) {
            $script:Model = "gemini-flash-latest"
        } elseif ($script:Model -in @("flash-lite-latest", "lite-latest")) {
            $script:Model = "gemini-flash-lite-latest"
        }
    }
    if ($script:Model) { return }
    $script:Model = switch ($script:Provider) {
        "gemini" { "gemini-2.5-flash-lite" }
        "ollama" { "llama3.2" }
        default  { "gpt-4.1-nano" }
    }
}

function Strip-Fences {
    param([string]$Text)
    $fence = [char]96 + [char]96 + [char]96
    $Text  = ($Text -split "`n" | Where-Object { -not $_.TrimStart().StartsWith($fence) }) -join "`n"
    return $Text.Trim()
}

function Test-Dangerous {
    param([string]$Cmd)
    if ($Cmd -match "Remove-Item.+-Recurse")        { return $true }
    if ($Cmd -match "rm\s+-[rRf]+")                 { return $true }
    if ($Cmd -match "sudo\s")                       { return $true }
    if ($Cmd -match "Format-Volume")                { return $true }
    if ($Cmd -match "Clear-Disk")                   { return $true }
    if ($Cmd -match "dd\s+if=")                     { return $true }
    if ($Cmd -match "\|\s*(sh|bash|cmd|pwsh)\s*$")  { return $true }
    return $false
}

function Read-ExecutionChoice {
    param([string]$PromptText)

    if ($env:ASK_MOCK_CHOICE) {
        return $env:ASK_MOCK_CHOICE
    }

    if ([Console]::IsInputRedirected) {
        return (Read-Host $PromptText)
    }

    Write-Host -NoNewline "$PromptText "
    $keyInfo = [System.Console]::ReadKey($true)
    $keyChar = $keyInfo.KeyChar

    switch -Regex ($keyChar) {
        "^[NnCcEe]$" {
            Write-Host $keyChar
            return [string]$keyChar
        }
        "^[Yy]$" {
            Write-Host -NoNewline $keyChar
            $rest = Read-Host
            return "$keyChar$rest"
        }
        default {
            if ($keyInfo.Key -eq [System.ConsoleKey]::Enter) {
                Write-Host ""
                return ""
            }
            Write-Host $keyChar
            return [string]$keyChar
        }
    }
}

function Prompt-Execute {
    param([string]$Cmd)
    $isDanger = Test-Dangerous $Cmd
    $promptText = ""

    if ($isDanger) {
        Write-Host (Yellow "Warning: This command looks dangerous.")
        $promptText = Bold "Type  yes  to run, [e]dit, [c]opy, or [n]o:"
    } else {
        $runPrompt = Bold "Run?"
        $runLabel  = Dim "[y]es / [e]dit / [c]opy / [n]o:"
        $promptText = "$runPrompt $runLabel"
    }

    $ans = Read-ExecutionChoice $promptText

    if ($isDanger) {
        if ($ans -eq "yes") {
            Invoke-Expression $Cmd
            return
        }
    } elseif ($ans -match "^[Yy]$") {
        Invoke-Expression $Cmd
        return
    }

    if ($ans -match "^[Ee]") {
        $origLabel = Dim "Original:"
        Write-Host "$origLabel $Cmd"
        $editPrompt = Bold "Edit (press Enter for original)"
        $edited = Read-Host $editPrompt
        if (-not $edited) { $edited = $Cmd }
        Invoke-Expression $edited
    } elseif ($ans -match "^[Cc]") {
        if (Copy-ToClipboard $Cmd) {
            Write-Host (Green "✔ Copied to clipboard.")
        } else {
            Write-Host (Yellow "No clipboard tool found.")
        }
    } else {
        Write-Host "Cancelled."
    }
}

# =============================================================================
#  ENTRY POINT
# =============================================================================

# Return early if sourced as a library/test fixture
if ($MyInvocation.InvocationName -eq '.' -or $env:ASK_SOURCE_ONLY -eq '1') {
    return
}

$allArgs = $args

# ── Help ──────────────────────────────────────────────────────────────────────
if ($allArgs.Count -eq 0 -or $allArgs[0] -in @("-h", "--help", "/?")) {
    Show-Help
    exit 0
}

# ── Version ───────────────────────────────────────────────────────────────────
if ($allArgs[0] -in @("-v", "--version")) {
    Write-Host "ask v$VERSION"
    exit 0
}

# ── Stats ─────────────────────────────────────────────────────────────────────
if ($allArgs[0] -in @("--stats", "stats")) {
    Show-Stats
    exit 0
}

# ── Init snippet ──────────────────────────────────────────────────────────────
if ($allArgs[0] -eq "--init") {
    $target = if ($allArgs.Count -ge 2) { $allArgs[1] } else { "pwsh" }
    Show-InitSnippet $target
    exit 0
}

# ── Setup ─────────────────────────────────────────────────────────────────────
if ($allArgs[0] -in @("--setup", "setup")) {
    Load-Config
    Run-Setup
    exit 0
}

# ── ask cheat <tool> ──────────────────────────────────────────────────────────
if ($allArgs[0] -eq "cheat") {
    Load-Config
    Resolve-DefaultModel
    if ($allArgs.Count -lt 2) {
        Write-Host (Yellow "Usage: ask cheat <tool>   (e.g. ask cheat tar, ask cheat ffmpeg)")
        exit 1
    }
    $tool = $allArgs[1]
    $envCtx = Get-HostContext
    $prompt = @"
Target environment: $envCtx. Give a concise cheatsheet for '$tool'.
List the top 5 most useful and common real-world commands with a brief description for each.
Format:
<command>
  # <description>
Output plain text only, no markdown code fences, no extra commentary.
"@
    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }
    $raw = Invoke-AI $prompt
    Write-Host ""
    Write-Host (Bold "Cheatsheet · $tool")
    Write-Host ""
    Write-Host (Strip-Fences $raw)
    Write-Host ""
    exit 0
}

# ── ask review ────────────────────────────────────────────────────────────────
if ($allArgs[0] -eq "review") {
    Load-Config
    Resolve-DefaultModel

    $gitCheck = & git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host (Red "Not inside a git repository.")
        exit 1
    }

    $gitDiff = (& git diff HEAD 2>$null) | Out-String
    if (-not $gitDiff.Trim()) {
        $gitDiff = (& git diff --cached 2>$null) | Out-String
    }
    if (-not $gitDiff.Trim()) {
        $base = (& git symbolic-ref refs/remotes/origin/HEAD 2>$null) -replace '^refs/remotes/origin/', ''
        if (-not $base) { $base = "main" }
        $gitDiff = (& git diff "$base...HEAD" 2>$null) | Out-String
    }

    if (-not $gitDiff.Trim()) {
        Write-Host (Green "Nothing to review — working tree is clean and up to date.")
        exit 0
    }

    $script:MaxTokens = 800
    $prompt = @"
Perform a concise, senior code review on this git diff.
Call out potential bugs, security flaws, performance gotchas, or missing edge cases.
If the changes look clean and well-structured, state that concisely.
Output plain text only.

Git diff:
$gitDiff
"@
    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }
    $raw = Invoke-AI $prompt
    Write-Host ""
    Write-Host (Bold "Code Review:")
    Write-Host ""
    Write-Host (Strip-Fences $raw)
    Write-Host ""
    exit 0
}

# ── ask branch <task> ─────────────────────────────────────────────────────────
if ($allArgs[0] -eq "branch") {
    Load-Config
    Resolve-DefaultModel

    if ($allArgs.Count -lt 2) {
        Write-Host (Yellow "Usage: ask branch <task description>   (e.g. ask branch add oauth login)")
        exit 1
    }

    $taskDesc = ($allArgs[1..($allArgs.Count - 1)]) -join " "
    $prompt = @"
Generate a single git branch name for this task: $taskDesc.
Rules:
- Format: <type>/<short-kebab-slug> (e.g. feat/oauth-login, fix/null-pointer, chore/dep-bump)
- Lowercase, hyphens for spaces, alphanumeric only, max 35 characters
- Output ONLY the branch name — no explanation, no markdown
"@
    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }
    $raw = Invoke-AI $prompt
    $branchName = (Strip-Fences $raw).Trim() -replace '[`"\s]', ''

    $brTitle = Bold "Suggested branch:"
    $brName  = Cyan $branchName
    Write-Host ""
    Write-Host "$brTitle $brName"
    Write-Host ""

    $brPrompt = Bold "Create and switch to this branch?"
    $brOpts   = Dim "[y]es / [c]opy / [n]o"
    $ans = Read-Host "$brPrompt $brOpts"
    if ($ans -match "^[Yy]$") {
        & git checkout -b $branchName
    } elseif ($ans -match "^[Cc]$") {
        if (Copy-ToClipboard $branchName) {
            Write-Host (Green "✔ Copied to clipboard.")
        }
    } else {
        Write-Host "Cancelled."
    }
    exit 0
}

# ── ask !! ────────────────────────────────────────────────────────────────────
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

# ── ask fix ───────────────────────────────────────────────────────────────────
if ($allArgs[0] -eq "fix") {
    Load-Config
    Resolve-DefaultModel

    $stdinData = ""
    try {
        if ([Console]::IsInputRedirected) { $stdinData = $input | Out-String }
    } catch { }

    $userContext = if ($allArgs.Count -ge 2) { ($allArgs[1..($allArgs.Count - 1)]) -join " " } else { "" }

    $hist    = Get-History -Count 2
    $lastCmd = if ($hist.Count -ge 2) { $hist[-2].CommandLine } `
               elseif ($hist.Count -eq 1) { $hist[-1].CommandLine } `
               else { "" }
    if ($lastCmd -match "^ask\s+fix") { $lastCmd = "" }

    $envCtx = Get-HostContext
    $prompt = @"
Target environment: $envCtx.
The user ran a shell command that failed.
Previous command: $(if ($lastCmd) { $lastCmd } else { '(unknown)' })
Error / output context:
$stdinData
$userContext

Output ONLY the corrected, executable PowerShell command to fix the issue and accomplish the goal — no explanation, no markdown, no code fences.
"@
    if ($env:VERBOSE -eq "true") { Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)" }
    $raw = Invoke-AI $prompt
    $command = (Strip-Fences $raw).Trim().Split("`n")[0].Trim()

    if (-not $command) {
        Write-Host (Red "No fix command suggested.")
        exit 1
    }

    Write-Host ""
    Write-Host (Bold "Suggested fix:")
    Write-Host $command
    Write-Host ""
    Prompt-Execute $command
    exit 0
}

# ── ask commit ────────────────────────────────────────────────────────────────
if ($allArgs[0] -eq "commit") {
    Load-Config
    Resolve-DefaultModel

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

    $cmPrompt = Bold "Commit with this message?"
    $cmOpts   = Dim "[y]es / [c]opy / [n]o"
    $confirm  = Read-Host "$cmPrompt $cmOpts"
    if ($confirm -match "^[Yy]$") {
        & git add -A
        & git commit -m $commitMsg
    } elseif ($confirm -match "^[Cc]$") {
        if (Copy-ToClipboard $commitMsg) {
            Write-Host (Green "✔ Copied to clipboard.")
        }
    } else {
        Write-Host "Cancelled."
    }
    exit 0
}

# ── Normal / free-form mode ───────────────────────────────────────────────────
Load-Config

$needsSetup = $false
if (-not (Test-Path $CONFIG_FILE))                                   { $needsSetup = $true }
if ($script:Provider -eq "openai" -and -not $script:OpenAIApiKey)   { $needsSetup = $true }
if ($script:Provider -eq "gemini" -and -not $script:GeminiApiKey)   { $needsSetup = $true }

if ($needsSetup) {
    Write-Host (Yellow "-> No config found. Launching setup.")
    Write-Host ""
    Run-Setup
    Load-Config
}

Resolve-DefaultModel

$stdinData = ""
try {
    if ([Console]::IsInputRedirected) { $stdinData = $input | Out-String }
} catch { }

$rawOutput = $false
$userArgs  = [System.Collections.Generic.List[string]]::new($allArgs)
if ($userArgs.Count -gt 0 -and $userArgs[0] -eq "--raw") {
    $rawOutput = $true
    $userArgs.RemoveAt(0)
}

$userInput = $userArgs -join " "
$skipRun   = $false

if ($userInput.StartsWith("-") -and -not $rawOutput) {
    $prompt  = $userInput
    $skipRun = $true
} else {
    $envCtx  = Get-HostContext
    $prompt  = "Target environment: $envCtx. Output only the raw PowerShell command to accomplish this task — no explanation, no markdown, no code fences: $userInput"
}

if ($stdinData.Trim()) {
    $prompt  = "$prompt`n`nContext (piped input):`n$stdinData"
    if (-not $rawOutput) { $skipRun = $true }
}

if ($env:VERBOSE -eq "true") {
    Write-Host "[debug] provider=$($script:Provider) model=$($script:Model)"
    Write-Host "[debug] prompt=$prompt"
}

$raw     = Invoke-AI $prompt
$command = (Strip-Fences $raw).Trim().Split("`n")[0].Trim()

if (-not $command) {
    Write-Host (Red "No response received. Check your API key or run: ask --setup")
    exit 1
}

if ($rawOutput) {
    Write-Output $command
    exit 0
}

if ($skipRun) {
    Write-Host ""
    Write-Host $raw
    exit 0
}

Write-Host ""
Write-Host (Bold "Suggested:")
Write-Host $command
Write-Host ""

Prompt-Execute $command
