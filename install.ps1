#!/usr/bin/env pwsh
# =============================================================================
#  install.ps1 — installer for ask.ps1 (AI terminal assistant for Windows)
#
#  Usage (from PowerShell — run as Administrator for system-wide install):
#    irm https://zmsp.github.io/ask/install.ps1 | iex
#
#  What it does:
#    1. Checks for required PowerShell version
#    2. Downloads the latest ask.ps1 from GitHub
#    3. Installs it to a directory in your PATH
#    4. Creates an `ask` wrapper function in your $PROFILE
#    5. Runs the interactive setup wizard
# =============================================================================
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── Config ────────────────────────────────────────────────────────────────────
$REPO      = "zmsp/ask"
$RAW_URL   = "https://raw.githubusercontent.com/$REPO/main/ask.ps1"
$DEST_DIR  = "$env:USERPROFILE\bin"
$DEST_FILE = Join-Path $DEST_DIR "ask.ps1"
$WRAPPER   = "function ask { & '$DEST_FILE' @args }"

# ── Colors ────────────────────────────────────────────────────────────────────
function Bold  { "`e[1m$args`e[0m" }
function Green { "`e[32m$args`e[0m" }
function Yellow{ "`e[33m$args`e[0m" }
function Red   { "`e[31m$args`e[0m" }
function Dim   { "`e[2m$args`e[0m" }

function Info    { Write-Host "  $(Dim '·') $args" }
function Success { Write-Host "  $(Green '✔') $args" }
function Warn    { Write-Host "  $(Yellow '⚠') $args" }
function Fail    { Write-Host "  $(Red '✖') $args" -ForegroundColor Red; exit 1 }

# =============================================================================
#  MAIN
# =============================================================================
Write-Host ""
Write-Host (Bold "╔════════════════════════════════════╗")
Write-Host (Bold "║   ask  ·  AI terminal assistant    ║")
Write-Host (Bold "║   Windows installer                ║")
Write-Host (Bold "╚════════════════════════════════════╝")
Write-Host ""
Info "Repository: https://github.com/$REPO"
Write-Host ""

# ── PowerShell version check ──────────────────────────────────────────────────
Info "PowerShell version: $($PSVersionTable.PSVersion)"
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
    Invoke-WebRequest -Uri $RAW_URL -OutFile $DEST_FILE -UseBasicParsing
    Success "Downloaded → $DEST_FILE"
} catch {
    Fail "Download failed: $_. Check your network connection."
}
Write-Host ""

# ── Add to PATH ───────────────────────────────────────────────────────────────
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$DEST_DIR*") {
    Info "Adding $DEST_DIR to user PATH…"
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$DEST_DIR", "User")
    $env:PATH += ";$DEST_DIR"
    Success "PATH updated"
} else {
    Info "$DEST_DIR already in PATH"
}
Write-Host ""

# ── Add shell wrapper to $PROFILE ─────────────────────────────────────────────
# The wrapper lets users type `ask` instead of `ask.ps1` in PowerShell sessions
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

# ── Setup wizard ──────────────────────────────────────────────────────────────
Write-Host (Bold "Running first-time setup…")
Write-Host ""
& $DEST_FILE --setup

Write-Host ""
Success (Bold "ask is ready!")
Write-Host ""
Write-Host "  $(Dim 'Try it (restart your terminal first, or run:')"
Write-Host "    . `$PROFILE"
Write-Host "  then:"
Write-Host "    ask `"list all files modified today`""
Write-Host "    ask !!"
Write-Host "    ask commit"
Write-Host ""
Write-Host "  $(Dim 'Re-run setup anytime:')"
Write-Host "    ask --setup"
Write-Host ""
