#!/usr/bin/env pwsh
# =============================================================================
#  tests/test_install_ps1.ps1 — Isolated tests for install.ps1
#
#  Usage:
#    pwsh tests/test_install_ps1.ps1                     # run all tests
#    pwsh tests/test_install_ps1.ps1 -TestName Test-FullInstall  # run single test
# =============================================================================
param(
    [string]$TestName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot   = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallPs1 = Join-Path $RepoRoot "install.ps1"
$AskPs1     = Join-Path $RepoRoot "ask.ps1"

# Temporary sandbox directory for complete system isolation
$TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ask_test_inst_ps1_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

$script:OriginalHome        = $env:HOME
$script:OriginalUserProfile = $env:USERPROFILE
$script:OriginalPath        = $env:PATH

$env:HOME            = $TestDir
$env:USERPROFILE     = $TestDir
$env:ASK_INSTALL_DIR = Join-Path $TestDir "bin"
$env:ASK_RAW_URL     = (New-Object System.Uri (Resolve-Path $AskPs1)).AbsoluteUri
$env:ASK_SKIP_VERIFY = "true"
$env:ASK_TEST_MODE   = "true"

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

function Test-InstallHelpers {
    . $InstallPs1

    Assert-Equal "`e[1mhi`e[0m" (Bold "hi") "Bold helper"
    Assert-Equal "`e[32mhi`e[0m" (Green "hi") "Green helper"

    $infoOut = (Info "testing info" 6>&1 | Out-String)
    Assert-Contains $infoOut "testing info" "Info helper"

    $successOut = (Success "testing success" 6>&1 | Out-String)
    Assert-Contains $successOut "testing success" "Success helper"

    $warnOut = (Warn "testing warn" 6>&1 | Out-String)
    Assert-Contains $warnOut "testing warn" "Warn helper"
}

function Test-FullInstallExecution {
    $installOutput = (& pwsh -NoProfile -File $InstallPs1 6>&1) | Out-String

    Assert-Contains $installOutput "ask is ready!" "Install reports readiness"

    $destFile = Join-Path $env:ASK_INSTALL_DIR "ask.ps1"
    if (-not (Test-Path $destFile)) {
        throw "Expected $destFile to exist after installation"
    }

    # Verify profile was populated
    $profilePath = Join-Path $TestDir "Microsoft.PowerShell_profile.ps1"
    if (Test-Path $PROFILE) {
        $profileContent = Get-Content $PROFILE -Raw
        Assert-Contains $profileContent "function ask" "Profile wrapper function"
    }

    # Verify installed ask.ps1 can be executed directly
    $verOut = (& pwsh -NoProfile -File $destFile --version) | Out-String
    Assert-Contains $verOut "ask v2.1.0" "Installed binary executes --version"
}

function Test-ProfileIdempotency {
    # Run installer second time
    $installOutput = (& pwsh -NoProfile -File $InstallPs1 6>&1) | Out-String
    Assert-Contains $installOutput "already in profile" "Idempotent profile registration"
}

# =============================================================================
#  RUNNER
# =============================================================================

$AllTests = @(
    "Test-InstallHelpers",
    "Test-FullInstallExecution",
    "Test-ProfileIdempotency"
)

try {
    Write-Host ""
    Write-Host (Bold "Running install.ps1 tests (isolated environment):")
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
        Write-Host (Green "All $($script:TestsPassed)/$($script:TestsRun) install.ps1 tests passed.")
        exit 0
    } else {
        Write-Host (Red "$($script:TestsFailed)/$($script:TestsRun) install.ps1 tests failed.")
        exit 1
    }
} finally {
    $env:HOME            = $script:OriginalHome
    $env:USERPROFILE     = $script:OriginalUserProfile
    $env:PATH            = $script:OriginalPath
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}
