$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path .).Path
$OutputRoot = Join-Path $ProjectRoot "Output"
$StageRoot = Join-Path $ProjectRoot "PackageStage"
$StageExpertsRoot = Join-Path $StageRoot "E"
$StageLibrariesRoot = Join-Path $StageRoot "L"

if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

# Verify staged payload
$requiredStageFiles = @(
    (Join-Path $StageExpertsRoot "MultiBotPro.ex5"),
    (Join-Path $StageLibrariesRoot "accel.dll")
)
foreach ($f in $requiredStageFiles) {
    if (-not (Test-Path $f)) {
        throw "Missing staged file: $f. Run build_installer.ps1 first."
    }
}

# ---- ZIP bundle ----
$zipPath = Join-Path $OutputRoot "MultiBotPro_v2.0_Bundle.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$items = @(
    (Join-Path $StageRoot '*')
)
Compress-Archive -Path (Join-Path $StageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
Write-Host ">>> ZIP bundle: $zipPath" -ForegroundColor Green
Write-Host ">>> Size: $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB" -ForegroundColor Cyan

# ---- PowerShell installer ----
$installPs1 = Join-Path $OutputRoot "Install_MultiBotPro.ps1"
@'
<#
.SYNOPSIS
    MultiBotPro v2.0 - Self-contained Installer
.DESCRIPTION
    Copies the bot, Python runtime, database, and native DLL into all detected
    MetaTrader 5 terminal directories. Run this script from the folder that
    contains the extracted bundle (Experts and Libraries folders side by side).
#>

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "MultiBotPro v2.0 Installer"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MultiBotPro v2.0 - Standalone Installer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }
$payloadExperts = Join-Path $scriptDir "Experts"
$payloadLibraries = Join-Path $scriptDir "Libraries"

if (-not (Test-Path $payloadExperts)) {
    throw "Payload Experts folder not found at $payloadExperts. Extract the full bundle first."
}
if (-not (Test-Path $payloadLibraries)) {
    throw "Payload Libraries folder not found at $payloadLibraries. Extract the full bundle first."
}

$terminalsPath = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (-not (Test-Path $terminalsPath)) {
    Write-Warning "No MetaTrader 5 installation found at $terminalsPath"
    Write-Host "Make sure MetaTrader 5 is installed and has been run at least once." -ForegroundColor Yellow
    pause
    exit 1
}

$terminals = Get-ChildItem -LiteralPath $terminalsPath -Directory | Where-Object {
    $_.Name -notin @('.', '..', 'Common') -and $_.Name.Length -eq 32
}

if ($terminals.Count -eq 0) {
    Write-Warning "No MT5 terminal directories found."
    pause
    exit 1
}

Write-Host "Found $($terminals.Count) MetaTrader 5 instance(s):" -ForegroundColor Green
for ($i = 0; $i -lt $terminals.Count; $i++) {
    $originFile = Join-Path $terminals[$i].FullName "origin.txt"
    $label = $terminals[$i].Name
    if (Test-Path $originFile) {
        $origin = Get-Content $originFile -First 1
        if ($origin) { $label = "$origin [$($terminals[$i].Name)]" }
    }
    Write-Host "  [$($i + 1)] $label"
}
Write-Host ""

Write-Host "Installing to ALL detected terminals..." -ForegroundColor Yellow
Write-Host ""

foreach ($terminal in $terminals) {
    $mql5Experts = Join-Path $terminal.FullName "MQL5\Experts\MultiBotPro2"
    $mql5Libraries = Join-Path $terminal.FullName "MQL5\Libraries"

    Write-Host "  Installing to: $($terminal.Name) ..." -ForegroundColor Gray

    if (Test-Path $mql5Experts) {
        Remove-Item $mql5Experts -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item $payloadExperts $mql5Experts -Recurse -Force

    if (-not (Test-Path $mql5Libraries)) {
        New-Item -ItemType Directory $mql5Libraries -Force | Out-Null
    }
    Copy-Item (Join-Path $payloadLibraries '*') $mql5Libraries -Recurse -Force

    Write-Host "    Done." -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Installation Complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Restart MetaTrader 5"
Write-Host "  2. Open Navigator (Ctrl+N) -> Expert Advisors"
Write-Host "  3. Drag 'MultiBotPro' onto a chart"
Write-Host "  4. Configure inputs and enable coordinator mode if needed"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
pause
'@ | Set-Content $installPs1 -Encoding UTF8

Write-Host ">>> PowerShell installer: $installPs1" -ForegroundColor Green

# ---- Deployment folder ----
$deployRoot = Join-Path $OutputRoot "MultiBotPro_v2.0"
if (Test-Path $deployRoot) { Remove-Item $deployRoot -Recurse -Force }
New-Item -ItemType Directory $deployRoot | Out-Null

Copy-Item $StageExpertsRoot (Join-Path $deployRoot "Experts") -Recurse -Force
Copy-Item $StageLibrariesRoot (Join-Path $deployRoot "Libraries") -Recurse -Force
Copy-Item $installPs1 (Join-Path $deployRoot "Install_MultiBotPro.ps1") -Force

# README
@'
MultiBotPro v2.0 - Installation
===============================

CONTENTS:
  Experts\MultiBotPro2\    - The bot (.ex5), Python engine, database, assets
  Libraries\               - Native C++ accelerator DLL
  Install_MultiBotPro.ps1  - PowerShell installer script

QUICK START:
  1. Right-click Install_MultiBotPro.ps1 -> Run with PowerShell
     (or open PowerShell and run the script)
  2. The script detects your MetaTrader 5 terminals and installs automatically.
  3. Restart MT5 and find "MultiBotPro" in the Navigator.

MANUAL INSTALL:
  1. Copy the "Experts" folder contents to:
     %APPDATA%\MetaQuotes\Terminal\<your-terminal>\MQL5\Experts\
  2. Copy the "Libraries" folder contents to:
     %APPDATA%\MetaQuotes\Terminal\<your-terminal>\MQL5\Libraries\
  3. Restart MT5.

REQUIREMENTS:
  - Windows 10/11 64-bit
  - MetaTrader 5 (build 5000+)
  - No external Python installation needed (bundled)

VERSION: 2.0 (2026-09-16)
'@ | Set-Content (Join-Path $deployRoot "README.txt") -Encoding UTF8

$sfxZip = Join-Path $OutputRoot "MultiBotPro_v2.0_Setup.zip"
if (Test-Path $sfxZip) { Remove-Item $sfxZip -Force }
Compress-Archive -Path (Join-Path $deployRoot '*') -DestinationPath $sfxZip -CompressionLevel Optimal -Force
Remove-Item $deployRoot -Recurse -Force

Write-Host ">>> Final setup archive: $sfxZip" -ForegroundColor Green
Write-Host ">>> Size: $([math]::Round((Get-Item $sfxZip).Length / 1MB, 2)) MB" -ForegroundColor Cyan
Write-Host ""
Write-Host ">>> Build complete!" -ForegroundColor Cyan