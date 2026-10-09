#!/usr/bin/env pwsh
# =============================================================================
#  tests/run_tests.ps1 — Master test runner for PowerShell
#
#  Usage:
#    pwsh tests/run_tests.ps1               # Run all available tests
#    pwsh tests/run_tests.ps1 -Ps1Only      # Run PowerShell tests only
#    pwsh tests/run_tests.ps1 -ShOnly       # Run bash/sh tests only
#    pwsh tests/run_tests.ps1 -AppOnly      # Run ask.sh / ask.ps1 tests only
#    pwsh tests/run_tests.ps1 -InstallOnly  # Run installer tests only
# =============================================================================
param(
    [switch]$Ps1Only,
    [switch]$ShOnly,
    [switch]$AppOnly,
    [switch]$InstallOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot

function Bold   { param([string]$t) "`e[1m${t}`e[0m" }
function Green  { param([string]$t) "`e[32m${t}`e[0m" }
function Red    { param([string]$t) "`e[31m${t}`e[0m" }
function Yellow { param([string]$t) "`e[33m${t}`e[0m" }

$BashCmd = Get-Command "bash" -ErrorAction SilentlyContinue

$script:SuitesRun    = 0
$script:SuitesPassed = 0
$script:SuitesFailed = 0

function Run-Suite {
    param([string]$SuiteName, [scriptblock]$Action)

    $script:SuitesRun++
    Write-Host ""
    Write-Host (Bold "==> Running suite: $SuiteName")

    try {
        & $Action
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "Suite failed with exit code $LASTEXITCODE"
        }
        $script:SuitesPassed++
    } catch {
        $script:SuitesFailed++
    }
}

Write-Host (Bold "═══════════════════════════════════════════════════")
Write-Host (Bold "           ask-bash Test Suite Runner             ")
Write-Host (Bold "═══════════════════════════════════════════════════")

$runSh      = (-not $Ps1Only)
$runPs1     = (-not $ShOnly)
$runApp     = (-not $InstallOnly)
$runInstall = (-not $AppOnly)

# 1. ask.ps1 tests
if ($runPs1 -and $runApp) {
    Run-Suite "ask.ps1 unit & functional tests" {
        & pwsh (Join-Path $ScriptDir "test_ask_ps1.ps1")
    }
}

# 2. install.ps1 tests
if ($runPs1 -and $runInstall) {
    Run-Suite "install.ps1 isolated installation tests" {
        & pwsh (Join-Path $ScriptDir "test_install_ps1.ps1")
    }
}

# 3. ask.sh tests
if ($runSh -and $runApp) {
    if ($BashCmd) {
        Run-Suite "ask.sh unit & functional tests" {
            & bash (Join-Path $ScriptDir "test_ask_sh.sh")
        }
    } else {
        Write-Host ""
        Write-Host "  $((Yellow '⚠')) Skipping ask.sh tests (bash not found)"
    }
}

# 4. install.sh tests
if ($runSh -and $runInstall) {
    if ($BashCmd) {
        Run-Suite "install.sh isolated installation tests" {
            & bash (Join-Path $ScriptDir "test_install_sh.sh")
        }
    } else {
        Write-Host ""
        Write-Host "  $((Yellow '⚠')) Skipping install.sh tests (bash not found)"
    }
}

Write-Host ""
Write-Host (Bold "═══════════════════════════════════════════════════")
if ($script:SuitesFailed -eq 0) {
    Write-Host (Green "All $($script:SuitesPassed)/$($script:SuitesRun) test suites passed successfully.")
    exit 0
} else {
    Write-Host (Red "$($script:SuitesFailed)/$($script:SuitesRun) test suites failed.")
    exit 1
}
