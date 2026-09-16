$ErrorActionPreference = "Stop"

$ProjectRoot = (Get-Location).Path
$Mql5Root = (Resolve-Path (Join-Path $ProjectRoot "..\..")).Path
$StageRoot = Join-Path $ProjectRoot "PackageStage"
$StageExpertsRoot = Join-Path $StageRoot "E"
$StageLibrariesRoot = Join-Path $StageRoot "L"
$StagePresetsRoot = Join-Path $StageRoot "P"
$StageTemplatesRoot = Join-Path $StageRoot "T"
$OutputRoot = Join-Path $ProjectRoot "Output"
$ShadowMasterSource = Join-Path $ProjectRoot "PythonApp\ShadowMaster.py"
$ShadowMasterSpec = Join-Path $ProjectRoot "build\spec\ShadowMaster.spec"
$ShadowMasterDistRoot = Join-Path $ProjectRoot "build\dist_shadow"
$ShadowMasterWorkRoot = Join-Path $ProjectRoot "build\ShadowMaster_rebuild"
$RebuiltShadowMasterExe = Join-Path $ShadowMasterDistRoot "ShadowMaster.exe"
$HelperDistRoot = Join-Path $ProjectRoot "build\dist_helpers"
$HelperWorkRoot = Join-Path $ProjectRoot "build\helpers_rebuild"
$InnoCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
# Fall back to user-level install location
if (-not (Test-Path $InnoCompiler)) {
    $InnoCompiler = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path $InnoCompiler)) {
    $InnoCompiler = "$env:LOCALAPPDATA\Programs\Antigravity\resources\app\node_modules\innosetup\bin\ISCC.exe"
}
# $SystemPythonRoot was used by Stage-TrimmedPythonRuntime to fall back to a system
# Python install when the workspace WinPython payload was empty. Both are now
# dead code — ShadowMaster.exe is a self-contained PyInstaller binary so no
# WinPython is staged any more. Kept here for reference only.
function New-CleanDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path | Out-Null
}

function Copy-TreeContent {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path $Source)) { return }

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    if (-not (Test-Path $Source)) {
        throw "Missing required file: $Source"
    }

    if (-not (Test-Path $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $DestinationDirectory -Force
}

function Copy-OptionalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    if (-not (Test-Path $Source)) { return }

    if (-not (Test-Path $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $DestinationDirectory -Force
}

function Resolve-PyInstallerCommand {
    $cmd = Get-Command pyinstaller.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return ,@($cmd.Source)
    }

    $pythonCandidates = @(
        (Join-Path $ProjectRoot "PythonApp\WinPython\python.exe"),
        "python.exe",
        "py.exe"
    )

    foreach ($candidate in $pythonCandidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            return ,@($cmd.Source, "-m", "PyInstaller")
        }
        if (Test-Path $candidate) {
            return ,@($candidate, "-m", "PyInstaller")
        }
    }

    throw "PyInstaller was not found. Install it or restore PythonApp\WinPython with PyInstaller available."
}

function Invoke-ShadowMasterRepackage {
    if (-not (Test-Path $ShadowMasterSource)) {
        throw "Missing ShadowMaster source file: $ShadowMasterSource"
    }
    if (-not (Test-Path $ShadowMasterSpec)) {
        throw "Missing ShadowMaster PyInstaller spec: $ShadowMasterSpec"
    }

    if (-not (Test-Path $ShadowMasterDistRoot)) {
        New-Item -ItemType Directory -Path $ShadowMasterDistRoot | Out-Null
    }
    if (Test-Path $RebuiltShadowMasterExe) {
        Remove-Item -LiteralPath $RebuiltShadowMasterExe -Force
    }

    $pyInstallerCommand = Resolve-PyInstallerCommand
    $exe = $pyInstallerCommand[0]
    $prefixArgs = @()
    if ($pyInstallerCommand.Count -gt 1) {
        $prefixArgs = $pyInstallerCommand[1..($pyInstallerCommand.Count - 1)]
    }

    Write-Host ">>> Repackaging ShadowMaster.exe from PythonApp\ShadowMaster.py" -ForegroundColor Yellow
    Push-Location (Split-Path -Parent $ShadowMasterSpec)
    try {
        & $exe @prefixArgs "--noconfirm" "--distpath" $ShadowMasterDistRoot "--workpath" $ShadowMasterWorkRoot $ShadowMasterSpec
        if ($LASTEXITCODE -ne 0) {
            throw "ShadowMaster PyInstaller build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path $RebuiltShadowMasterExe)) {
        throw "ShadowMaster PyInstaller build did not produce $RebuiltShadowMasterExe"
    }

    $workspaceExeRefreshed = $false
    try {
        Copy-Item -LiteralPath $RebuiltShadowMasterExe -Destination (Join-Path $ProjectRoot "PythonApp\ShadowMaster.exe") -Force
        $workspaceExeRefreshed = $true
    }
    catch {
        Write-Warning "Could not refresh PythonApp\ShadowMaster.exe because it is locked. The installer will still stage the rebuilt EXE from build\dist_shadow."
    }
    if ($workspaceExeRefreshed) {
        Write-Host ">>> PythonApp\ShadowMaster.exe refreshed" -ForegroundColor Green
    }
    Write-Host ">>> Rebuilt ShadowMaster.exe ready for staging" -ForegroundColor Green
}

function Invoke-PythonHelperRepackage {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    $scriptPath = Join-Path $ProjectRoot "PythonApp\$ScriptName.py"
    $rebuiltExe = Join-Path $HelperDistRoot "$ScriptName.exe"
    $workspaceExe = Join-Path $ProjectRoot "PythonApp\$ScriptName.exe"
    $helperWorkPath = Join-Path $HelperWorkRoot $ScriptName

    if (-not (Test-Path $scriptPath)) {
        throw "Missing helper source file: $scriptPath"
    }
    if (-not (Test-Path $HelperDistRoot)) {
        New-Item -ItemType Directory -Path $HelperDistRoot | Out-Null
    }
    if (Test-Path $rebuiltExe) {
        Remove-Item -LiteralPath $rebuiltExe -Force
    }

    $pyInstallerCommand = Resolve-PyInstallerCommand
    $exe = $pyInstallerCommand[0]
    $prefixArgs = @()
    if ($pyInstallerCommand.Count -gt 1) {
        $prefixArgs = $pyInstallerCommand[1..($pyInstallerCommand.Count - 1)]
    }

    Write-Host ">>> Repackaging $ScriptName.exe from PythonApp\$ScriptName.py" -ForegroundColor Yellow
    & $exe @prefixArgs "--noconfirm" "--onefile" "--console" "--name" $ScriptName "--distpath" $HelperDistRoot "--workpath" $helperWorkPath $scriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptName PyInstaller build failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path $rebuiltExe)) {
        throw "$ScriptName PyInstaller build did not produce $rebuiltExe"
    }

    try {
        Copy-Item -LiteralPath $rebuiltExe -Destination $workspaceExe -Force
    }
    catch {
        Write-Warning "Could not refresh PythonApp\$ScriptName.exe because it is locked. The installer will still stage the rebuilt EXE from build\dist_helpers."
    }
    Write-Host ">>> Rebuilt $ScriptName.exe ready for staging" -ForegroundColor Green
}

Write-Host ">>> Building self-contained MultiBotPro installer payload" -ForegroundColor Cyan

$requiredWorkspaceFiles = @(
    "MultiBotPro.ex5",
    "accel.dll",
    "romeo.bmp",
    "romeo_panel.bmp",
    "romeo.ico",
    "runtime_v3.json",
    "sqlite_schema.sql",
    "MultiBotPro_v3.db",
    "PythonApp\ShadowMaster.py",
    "PythonApp\init_database.py",
    "PythonApp\renko_fallback.py",
    "PythonApp\renko_fallback.bmp",
    "PythonApp\README.txt"
)

foreach ($relativePath in $requiredWorkspaceFiles) {
    $fullPath = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path $fullPath)) {
        throw "Missing required file: $relativePath"
    }
}

Invoke-ShadowMasterRepackage
Invoke-PythonHelperRepackage -ScriptName "init_database"
Invoke-PythonHelperRepackage -ScriptName "renko_fallback"

New-CleanDirectory -Path $StageRoot
New-Item -ItemType Directory -Path $StageExpertsRoot | Out-Null
New-Item -ItemType Directory -Path $StageLibrariesRoot | Out-Null
New-Item -ItemType Directory -Path $StagePresetsRoot | Out-Null
New-Item -ItemType Directory -Path $StageTemplatesRoot | Out-Null
if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

Write-Host ">>> Staging expert payload" -ForegroundColor Yellow
Copy-RequiredFile -Source (Join-Path $ProjectRoot "MultiBotPro.ex5") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "romeo.bmp") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "romeo_panel.bmp") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "romeo.ico") -DestinationDirectory $StageExpertsRoot
Copy-OptionalFile -Source (Join-Path $ProjectRoot "accel.bmp") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "runtime_v3.json") -DestinationDirectory $StageExpertsRoot
Copy-OptionalFile -Source (Join-Path $ProjectRoot "runtime_v3.openai.sample.json") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "sqlite_schema.sql") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "MultiBotPro_v3.db") -DestinationDirectory $StageExpertsRoot
Copy-RequiredFile -Source (Join-Path $ProjectRoot "accel.dll") -DestinationDirectory $StageLibrariesRoot

$workspacePythonRoot = Join-Path $ProjectRoot "PythonApp"
$stagedPythonRoot = Join-Path $StageExpertsRoot "PythonApp"

# WinPython is intentionally EXCLUDED from the staged payload. ShadowMaster.exe
# is now built as a self-contained PyInstaller binary that bundles its own Python
# interpreter and dependencies, so shipping a separate WinPython runtime would
# add ~89 MB of dead weight to the installer for no functional benefit.
# Copy everything in PythonApp EXCEPT the WinPython subdirectory.
if (Test-Path $workspacePythonRoot) {
    if (-not (Test-Path $stagedPythonRoot)) {
        New-Item -ItemType Directory -Path $stagedPythonRoot | Out-Null
    }
    Get-ChildItem -LiteralPath $workspacePythonRoot -Force | Where-Object {
        $_.Name -ne "WinPython" -and
        $_.Name -ne "ShadowMaster.exe" -and
        $_.Name -ne "__pycache__" -and
        $_.Name -ne "logs" -and
        $_.Name -ne "runtime_v3.json" -and
        $_.Name -notlike "*.bak*" -and
        $_.Extension -notin @(".py", ".pyw", ".pyc", ".pyo", ".spec")
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagedPythonRoot -Recurse -Force
    }

    Copy-Item -LiteralPath $RebuiltShadowMasterExe -Destination (Join-Path $stagedPythonRoot "ShadowMaster.exe") -Force
    Copy-Item -LiteralPath (Join-Path $HelperDistRoot "init_database.exe") -Destination (Join-Path $stagedPythonRoot "init_database.exe") -Force
    Copy-Item -LiteralPath (Join-Path $HelperDistRoot "renko_fallback.exe") -Destination (Join-Path $stagedPythonRoot "renko_fallback.exe") -Force
}

$presetPath = Join-Path $Mql5Root "Presets\multibot.set"
$templatePath = Join-Path $Mql5Root "Profiles\Templates\multibot.set"
$fallbackPresetPath = Join-Path $ProjectRoot "S\P\multibot.set"
$fallbackTemplatePath = Join-Path $ProjectRoot "S\T\multibot.set"
if (-not (Test-Path $presetPath) -and (Test-Path $fallbackPresetPath)) {
    $presetPath = $fallbackPresetPath
}
if (-not (Test-Path $templatePath) -and (Test-Path $fallbackTemplatePath)) {
    $templatePath = $fallbackTemplatePath
}
Copy-OptionalFile -Source $presetPath -DestinationDirectory $StagePresetsRoot
Copy-OptionalFile -Source $templatePath -DestinationDirectory $StageTemplatesRoot

if (-not (Test-Path $presetPath)) {
    Write-Warning "Preset not found at $presetPath. Installer will still build without it."
}

if (-not (Test-Path $templatePath)) {
    Write-Warning "Template preset not found at $templatePath. Installer will still build without it."
}

if (-not (Test-Path $InnoCompiler)) {
    throw "Inno Setup Compiler (ISCC.exe) not found at $InnoCompiler"
}

Write-Host ">>> Compiling installer" -ForegroundColor Green
& $InnoCompiler "/DStageRoot=$StageRoot" (Join-Path $ProjectRoot "MultiBotPro_ClientInstaller.iss")
if ($LASTEXITCODE -ne 0) {
    throw "Installer compilation failed with exit code $LASTEXITCODE."
}

Write-Host ">>> Installer build complete" -ForegroundColor Cyan
