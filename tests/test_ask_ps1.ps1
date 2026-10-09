#!/usr/bin/env pwsh
# =============================================================================
#  tests/test_ask_ps1.ps1 — Unit and functional tests for ask.ps1
#
#  Usage:
#    pwsh tests/test_ask_ps1.ps1                     # run all tests
#    pwsh tests/test_ask_ps1.ps1 -TestName Test-LoadConfig  # run single test
# =============================================================================
param(
    [string]$TestName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$AskPs1   = Join-Path $RepoRoot "ask.ps1"

# Temporary sandbox directory for complete system isolation
$TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ask_test_ps1_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

$script:OriginalHome        = $env:HOME
$script:OriginalUserProfile = $env:USERPROFILE
$script:OriginalOpenAiKey   = $env:OPENAI_API_KEY
$script:OriginalGeminiKey   = $env:GEMINI_API_KEY

$env:HOME            = $TestDir
$env:USERPROFILE     = $TestDir
$env:ASK_CONFIG_FILE = Join-Path $TestDir ".ask_config"
$env:ASK_STATS_FILE  = Join-Path $TestDir ".ask_stats"
$env:OPENAI_API_KEY  = ""
$env:GEMINI_API_KEY  = ""

$script:TestsRun    = 0
$script:TestsPassed = 0
$script:TestsFailed = 0

function Green { param([string]$t) "`e[32m${t}`e[0m" }
function Red   { param([string]$t) "`e[31m${t}`e[0m" }
function Bold  { param([string]$t) "`e[1m${t}`e[0m" }

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "")
    if ($Expected -ne $Actual) {
        Write-Host "    $((Red 'FAIL')): $Message"
        Write-Host "      expected: '$Expected'"
        Write-Host "      actual:   '$Actual'"
        throw "Assertion failure"
    }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Message = "")
    if (-not $Haystack.Contains($Needle)) {
        Write-Host "    $((Red 'FAIL')): $Message"
        Write-Host "      expected to contain: '$Needle'"
        Write-Host "      in: '$Haystack'"
        throw "Assertion failure"
    }
}

function Run-SingleTest {
    param([string]$Fn)
    $script:TestsRun++
    $display = "{0,-35} " -f ($Fn + "...")
    Write-Host -NoNewline "  $display"

    try {
        & $Fn
        Write-Host (Green "PASS")
        $script:TestsPassed++
    } catch {
        Write-Host (Red "FAILED")
        $script:TestsFailed++
    }
}

# =============================================================================
#  TEST CASES
# =============================================================================

function Test-Colors {
    . $AskPs1
    Assert-Equal "`e[1mhello`e[0m" (Bold "hello") "Bold format"
    Assert-Equal "`e[2mhello`e[0m" (Dim "hello") "Dim format"
    Assert-Equal "`e[36mhello`e[0m" (Cyan "hello") "Cyan format"
    Assert-Equal "`e[32mhello`e[0m" (Green "hello") "Green format"
    Assert-Equal "`e[33mhello`e[0m" (Yellow "hello") "Yellow format"
    Assert-Equal "`e[31mhello`e[0m" (Red "hello") "Red format"
}

function Test-LoadConfig {
    . $AskPs1

    $cfg = @"
# Comment
provider=gemini
model=gemini-2.5-flash-lite # inline comment
max_tokens=250
ollama_endpoint=http://127.0.0.1:11434/v1
openai_api_key=cfg_key_open
gemini_api_key=cfg_key_gem
"@
    Set-Content -Path $env:ASK_CONFIG_FILE -Value $cfg -Encoding UTF8

    $script:Provider       = "openai"
    $script:Model          = ""
    $script:MaxTokens      = 200
    $script:OllamaEndpoint = ""
    $script:OpenAIApiKey   = ""
    $script:GeminiApiKey   = ""

    Load-Config

    Assert-Equal "gemini" $script:Provider "Load provider"
    Assert-Equal "gemini-2.5-flash-lite" $script:Model "Load model"
    Assert-Equal 250 $script:MaxTokens "Load max_tokens"
    Assert-Equal "http://127.0.0.1:11434/v1" $script:OllamaEndpoint "Load endpoint"
    Assert-Equal "cfg_key_open" $script:OpenAIApiKey "Load openai_api_key"
    Assert-Equal "cfg_key_gem" $script:GeminiApiKey "Load gemini_api_key"
}

function Test-LoadConfigEnvPriority {
    . $AskPs1

    $cfg = @"
provider=openai
openai_api_key=config_open
gemini_api_key=config_gem
"@
    Set-Content -Path $env:ASK_CONFIG_FILE -Value $cfg -Encoding UTF8

    $script:OpenAIApiKey = "env_open_priority"
    $script:GeminiApiKey = "env_gem_priority"

    Load-Config

    Assert-Equal "env_open_priority" $script:OpenAIApiKey "OpenAI key env precedence"
    Assert-Equal "env_gem_priority" $script:GeminiApiKey "Gemini key env precedence"
}

function Test-WriteConfig {
    . $AskPs1

    $script:Provider       = "ollama"
    $script:Model          = "llama3.2"
    $script:MaxTokens      = 320
    $script:OllamaEndpoint = "http://localhost:11434/v1"
    $script:OpenAIApiKey   = "test_open"
    $script:GeminiApiKey   = "test_gem"

    Write-Config

    $content = Get-Content $env:ASK_CONFIG_FILE -Raw
    Assert-Contains $content "provider=ollama" "Written provider"
    Assert-Contains $content "model=llama3.2" "Written model"
    Assert-Contains $content "max_tokens=320" "Written max_tokens"
    Assert-Contains $content "openai_api_key=test_open" "Written openai key"
    Assert-Contains $content "gemini_api_key=test_gem" "Written gemini key"
}

function Test-ResolveDefaultModel {
    . $AskPs1

    $script:Provider = "openai"
    $script:Model    = ""
    Resolve-DefaultModel
    Assert-Equal "gpt-4.1-nano" $script:Model "Default openai model"

    $script:Provider = "gemini"
    $script:Model    = ""
    Resolve-DefaultModel
    Assert-Equal "gemini-2.5-flash-lite" $script:Model "Default gemini model"

    $script:Provider = "gemini"
    $script:Model    = "latest"
    Resolve-DefaultModel
    Assert-Equal "gemini-flash-latest" $script:Model "Alias latest"

    $script:Provider = "gemini"
    $script:Model    = "flash-lite-latest"
    Resolve-DefaultModel
    Assert-Equal "gemini-flash-lite-latest" $script:Model "Alias flash-lite-latest"

    $script:Provider = "ollama"
    $script:Model    = ""
    Resolve-DefaultModel
    Assert-Equal "llama3.2" $script:Model "Default ollama model"

    $script:Provider = "openai"
    $script:Model    = "custom-test-model"
    Resolve-DefaultModel
    Assert-Equal "custom-test-model" $script:Model "Custom model preserved"
}

function Test-GetHostContext {
    . $AskPs1

    $ctx = Get-HostContext
    Assert-Contains $ctx "PowerShell" "Context contains PowerShell"
}

function Test-RecordStatsAndShow {
    . $AskPs1

    if (Test-Path $env:ASK_STATS_FILE) { Remove-Item $env:ASK_STATS_FILE }

    Record-Stats "openai" "gpt-4.1-nano" 150 75
    Record-Stats "openai" "gpt-4.1-nano" 50 25
    Record-Stats "gemini" "gemini-2.5-flash-lite" 100 50

    $output = (Show-Stats 6>&1 | Out-String)
    Assert-Contains $output "Total queries:      3" "Show-Stats query count"
    Assert-Contains $output "Prompt tokens:      300" "Show-Stats prompt tokens"
    Assert-Contains $output "Completion tokens:  150" "Show-Stats completion tokens"
    Assert-Contains $output "openai (gpt-4.1-nano)" "Show-Stats model breakdown"
}

function Test-ShowInitSnippet {
    . $AskPs1

    $snippet = (Show-InitSnippet "pwsh" 6>&1 | Out-String)
    Assert-Contains $snippet "Set-PSReadLineKeyHandler" "Init snippet keyhandler"
    Assert-Contains $snippet "ask --raw" "Init snippet script reference"
}

function Test-StripFences {
    . $AskPs1

    $tripleTick = [string][char]96 + [char]96 + [char]96
    $fenced = "${tripleTick}bash`necho hello`n${tripleTick}"
    $stripped = Strip-Fences $fenced
    Assert-Equal "echo hello" $stripped "Strip-Fences markdown fence"
}

function Test-Dangerous {
    . $AskPs1

    Assert-Equal $true (Test-Dangerous "rm -rf /") "Detects rm -rf"
    Assert-Equal $true (Test-Dangerous "Remove-Item foo -Recurse") "Detects Remove-Item -Recurse"
    Assert-Equal $true (Test-Dangerous "Format-Volume -DriveLetter C") "Detects Format-Volume"
    Assert-Equal $true (Test-Dangerous "Clear-Disk -Number 1") "Detects Clear-Disk"
    Assert-Equal $false (Test-Dangerous "git status") "Safe git status"
    Assert-Equal $false (Test-Dangerous "Get-ChildItem") "Safe Get-ChildItem"
}

function Test-ShowHelp {
    . $AskPs1

    $helpOut = (Show-Help 6>&1 | Out-String)
    Assert-Contains $helpOut "ask v2.1.0" "Help header"
    Assert-Contains $helpOut "USAGE" "Help usage"
    Assert-Contains $helpOut "PIPING" "Help piping"
}

function Test-CliVersionAndHelp {
    $verOut = (& pwsh -NoProfile -File $AskPs1 -v) | Out-String
    Assert-Contains $verOut "ask v2.1.0" "CLI -v"

    $longVer = (& pwsh -NoProfile -File $AskPs1 --version) | Out-String
    Assert-Contains $longVer "ask v2.1.0" "CLI --version"

    $helpOut = (& pwsh -NoProfile -File $AskPs1 --help) | Out-String
    Assert-Contains $helpOut "USAGE" "CLI --help"
}

function Test-CliCheatValidation {
    $out = (& pwsh -NoProfile -File $AskPs1 cheat 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) {
        throw "Expected cheat with no args to exit with non-zero exit code"
    }
    Assert-Contains $out "Usage: ask cheat <tool>" "Cheat argument error"
}

function Test-CliBranchValidation {
    $out = (& pwsh -NoProfile -File $AskPs1 branch 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) {
        throw "Expected branch with no args to exit with non-zero exit code"
    }
    Assert-Contains $out "Usage: ask branch <task description>" "Branch argument error"
}

# =============================================================================
#  RUNNER
# =============================================================================

$AllTests = @(
    "Test-Colors",
    "Test-LoadConfig",
    "Test-LoadConfigEnvPriority",
    "Test-WriteConfig",
    "Test-ResolveDefaultModel",
    "Test-GetHostContext",
    "Test-RecordStatsAndShow",
    "Test-ShowInitSnippet",
    "Test-StripFences",
    "Test-Dangerous",
    "Test-ShowHelp",
    "Test-CliVersionAndHelp",
    "Test-CliCheatValidation",
    "Test-CliBranchValidation"
)

try {
    Write-Host ""
    Write-Host (Bold "Running ask.ps1 tests (isolated environment):")
    Write-Host ""

    if ($TestName) {
        if ($AllTests -contains $TestName) {
            Run-SingleTest $TestName
        } else {
            Write-Host (Red "Unknown test function: $TestName")
            Write-Host "Available tests: $($AllTests -join ', ')"
            exit 1
        }
    } else {
        foreach ($t in $AllTests) {
            Run-SingleTest $t
        }
    }

    Write-Host ""
    if ($script:TestsFailed -eq 0) {
        Write-Host (Green "All $($script:TestsPassed)/$($script:TestsRun) ask.ps1 tests passed.")
        exit 0
    } else {
        Write-Host (Red "$($script:TestsFailed)/$($script:TestsRun) ask.ps1 tests failed.")
        exit 1
    }
} finally {
    # Restore original environment and cleanup sandbox
    $env:HOME            = $script:OriginalHome
    $env:USERPROFILE     = $script:OriginalUserProfile
    $env:OPENAI_API_KEY  = $script:OriginalOpenAiKey
    $env:GEMINI_API_KEY  = $script:OriginalGeminiKey
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}
