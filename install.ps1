#!/usr/bin/env pwsh
# =============================================================================
#  install.ps1 — installer for ask.ps1 (AI terminal assistant for Windows)
#
#  Usage (from PowerShell):
#    irm https://zmsp.github.io/ask/install.ps1 | iex
# =============================================================================
#Requires -Version 5.1
param(
    [switch]$Uninstall = $false
)
$ErrorActionPreference = "Stop"

if ($env:ASK_UNINSTALL -eq "1" -or $env:ASK_UNINSTALL -eq "true") {
    $Uninstall = $true
}

# ── Config ────────────────────────────────────────────────────────────────────
$REPO      = if ($env:ASK_REPO) { $env:ASK_REPO } else { "zmsp/ask" }
$RAW_URL   = if ($env:ASK_RAW_URL) { $env:ASK_RAW_URL } else { "https://raw.githubusercontent.com/$REPO/main/ask.ps1" }
$DEST_DIR  = if ($env:ASK_INSTALL_DIR) { $env:ASK_INSTALL_DIR } else { Join-Path ($env:USERPROFILE ?? $env:HOME) "bin" }
$DEST_FILE = Join-Path $DEST_DIR "ask.ps1"
$WRAPPER   = "function ask { & '$DEST_FILE' @args }"

# ── Colors ────────────────────────────────────────────────────────────────────
function Bold   { param($t) "`e[1m$t`e[0m" }
function Green  { param($t) "`e[32m$t`e[0m" }
function Yellow { param($t) "`e[33m$t`e[0m" }
function Red    { param($t) "`e[31m$t`e[0m" }
function Dim    { param($t) "`e[2m$t`e[0m" }

function Info    { $s = Dim "·"; Write-Host "  $s $args" }
function Success { $s = Green "✔"; Write-Host "  $s $args" }
function Warn    { $s = Yellow "⚠"; Write-Host "  $s $args" }
function Fail    { $s = Red "✖"; Write-Host "  $s $args" -ForegroundColor Red; exit 1 }

# =============================================================================
#  MAIN
# =============================================================================

# Return early if sourced as a library/test fixture
if ($MyInvocation.InvocationName -eq '.' -or $env:ASK_SOURCE_ONLY -eq '1') {
    return
}

# Handle uninstall
if ($Uninstall) {
    Write-Host ""
    Write-Host (Bold "╔════════════════════════════════════╗")
    Write-Host (Bold "║   ask  ·  AI terminal assistant    ║")
    Write-Host (Bold "║   Windows uninstaller              ║")
    Write-Host (Bold "╚════════════════════════════════════╝")
    Write-Host ""

    $removed = $false
    if (Test-Path $DEST_FILE) {
        Info "Removing $DEST_FILE …"
        Remove-Item -Path $DEST_FILE -Force
        Success "Removed $DEST_FILE"
        $removed = $true
    }

    if (Test-Path $PROFILE) {
        Info "Cleaning PowerShell profile $PROFILE …"
        $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($content -match "ask") {
            $lines = ($content -split "`r?`n" | Where-Object { $_ -notmatch 'ask — AI terminal assistant' -and $_ -notmatch 'function ask' })
            Set-Content -Path $PROFILE -Value ($lines -join "`n").Trim()
            Success "Cleaned ask wrapper from profile"
        }
    }

    Write-Host ""
    if ($removed) {
        Success (Bold "ask uninstalled successfully!")
    } else {
        Warn "No installed ask.ps1 found at $DEST_FILE"
    }
    Info "Configuration ~/.ask_config preserved."
    Write-Host ""
    exit 0
}

Write-Host ""
$b1 = Bold "╔════════════════════════════════════╗"
$b2 = Bold "║   ask  ·  AI terminal assistant    ║"
$b3 = Bold "║   Windows installer                ║"
$b4 = Bold "╚════════════════════════════════════╝"
Write-Host $b1
Write-Host $b2
Write-Host $b3
Write-Host $b4
Write-Host ""
Info "Repository: https://github.com/$REPO"
Write-Host ""

# ── PowerShell version check ──────────────────────────────────────────────────
$psv = $PSVersionTable.PSVersion
Info "PowerShell version: $psv"
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Fail "PowerShell 5.1 or later is required. Download from https://aka.ms/powershell"
}
Success "PowerShell OK"
Write-Host ""

# ── Execution policy ──────────────────────────────────────────────────────────
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted", "AllSigned")) {
    Info "Setting PowerShell execution policy to RemoteSigned for current user…"
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Success "Execution policy updated"
    } catch {
        Warn "Could not change execution policy. You may need to run:"
        Write-Host "    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"
    }
}
Write-Host ""

# ── Create install directory ──────────────────────────────────────────────────
if (-not (Test-Path $DEST_DIR)) {
    Info "Creating $DEST_DIR …"
    New-Item -ItemType Directory -Path $DEST_DIR | Out-Null
    Success "Directory created"
}

# ── Download ──────────────────────────────────────────────────────────────────
Info "Downloading ask.ps1 from GitHub…"
try {
    if ($RAW_URL -like "file://*") {
        $localPath = [System.Uri]::new($RAW_URL).LocalPath
        Copy-Item -Path $localPath -Destination $DEST_FILE -Force
    } else {
        Invoke-WebRequest -Uri $RAW_URL -OutFile $DEST_FILE -UseBasicParsing
    }
    Success "Downloaded → $DEST_FILE"
} catch {
    Fail "Download failed: $_. Check your network connection."
}
Write-Host ""

# ── Add to PATH ───────────────────────────────────────────────────────────────
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$DEST_DIR*") {
    Info "Adding $DEST_DIR to user PATH…"
    if ($env:ASK_TEST_MODE -ne "true") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$DEST_DIR", "User")
    }
    $env:PATH += ";$DEST_DIR"
    Success "PATH updated"
} else {
    Info "$DEST_DIR already in PATH"
}
Write-Host ""

# ── Add shell wrapper to $PROFILE ─────────────────────────────────────────────
Info "Adding 'ask' function to PowerShell profile…"
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -notlike "*ask.ps1*") {
    Add-Content -Path $PROFILE -Value "`n# ask — AI terminal assistant`n$WRAPPER"
    Success "Added to $PROFILE"
} else {
    Info "'ask' wrapper already in profile"
}

# Activate wrapper for the current session
Invoke-Expression $WRAPPER
Write-Host ""

# ── Verification check ────────────────────────────────────────────────────────
Write-Host (Bold "Verification check…")
Write-Host ""
if ($env:ASK_SKIP_VERIFY -eq "true") {
    & "$DEST_FILE" --version
} else {
    & "$DEST_FILE" "echo hello world"
}

Write-Host ""
Success (Bold "ask is ready!")
Write-Host ""
$s1 = Dim "Try it (restart your terminal first, or run:"
Write-Host "  $s1"
Write-Host "    . `$PROFILE"
Write-Host "  then:"
Write-Host "    ask `"list all files modified today`""
Write-Host "    ask !!"
Write-Host "    ask commit"
Write-Host ""
$s2 = Dim "Re-run setup anytime:"
Write-Host "  $s2"
Write-Host "    ask --setup"
Write-Host ""
