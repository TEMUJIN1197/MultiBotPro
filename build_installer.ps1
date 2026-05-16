$ErrorActionPreference = "Stop"

$ProjectRoot = (Get-Location).Path
$Mql5Root = (Resolve-Path (Join-Path $ProjectRoot "..\..")).Path
$StageRoot = Join-Path $ProjectRoot "PackageStage"
$StageExpertsRoot = Join-Path $StageRoot "E"
$StageLibrariesRoot = Join-Path $StageRoot "L"
$StagePresetsRoot = Join-Path $StageRoot "P"
$StageTemplatesRoot = Join-Path $StageRoot "T"
$OutputRoot = Join-Path $ProjectRoot "Output"
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
$SystemPythonRoot = "C:\Program Files\Python312"

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

function Stage-TrimmedPythonRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (-not (Test-Path $SourceRoot)) {
        throw "Fallback Python runtime '$SourceRoot' was not found."
    }

    New-CleanDirectory -Path $DestinationRoot

    $topLevelFiles = @(
        "python.exe",
        "pythonw.exe",
        "python3.dll",
        "python312.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll",
        "LICENSE.txt"
    )

    foreach ($file in $topLevelFiles) {
        $src = Join-Path $SourceRoot $file
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination $DestinationRoot -Force
        }
    }

    Copy-TreeContent -Source (Join-Path $SourceRoot "DLLs") -Destination (Join-Path $DestinationRoot "DLLs")

    $stdlibSrc = Join-Path $SourceRoot "Lib"
    $stdlibDst = Join-Path $DestinationRoot "Lib"
    New-Item -ItemType Directory -Path $stdlibDst | Out-Null
    $excludeLibDirs = @("site-packages", "test", "tests", "tkinter", "turtledemo", "idlelib", "ensurepip", "venv", "__pycache__")
    Get-ChildItem -LiteralPath $stdlibSrc -Force |
        Where-Object { $excludeLibDirs -notcontains $_.Name } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $stdlibDst -Recurse -Force
        }

    $sitePackagesSrc = Join-Path $stdlibSrc "site-packages"
    $sitePackagesDst = Join-Path $stdlibDst "site-packages"
    New-Item -ItemType Directory -Path $sitePackagesDst | Out-Null
    $sitePackagePatterns = @(
        "MetaTrader5*",
        "numpy*",
        "pandas*",
        "pandas_ta*",
        "pytz*",
        "schedule*",
        "dateutil*",
        "python_dateutil*",
        "six*",
        "tzdata*",
        "packaging*",
        "typing_extensions*"
    )

    foreach ($pattern in $sitePackagePatterns) {
        Get-ChildItem -LiteralPath $sitePackagesSrc -Filter $pattern -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $sitePackagesDst -Recurse -Force
            }
    }

    $pruneDirNames = @("test", "tests", "testing", "__pycache__", "docs", "doc", "examples", "example", "_examples", "include")
    Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { ($pruneDirNames -contains $_.Name) -or $_.Name.EndsWith(".dist-info") } |
        Sort-Object FullName -Descending |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }

    Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".pyc", ".pyo", ".lib", ".pxd", ".pyi", ".pyx", ".h") } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
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
    "PythonApp\ShadowMaster.exe",
    # init_database.exe removed: EA's V3_EnsureRuntimeSchema() (hedgeBridge.mqh:359)
    # creates every table/index/PRAGMA on first launch, making the standalone .exe
    # redundant. Schema source of truth is sqlite_schema.sql plus the EA's runtime
    # CREATE TABLE IF NOT EXISTS statements.
    # renko_fallback.exe removed: never invoked from MQL5 code. Renko goes through
    # accel.dll (MBP_RenkoOpenSessionW etc.) or MultiBotPro_Renko.mqh natively.
    "PythonApp\README.txt"
)

foreach ($relativePath in $requiredWorkspaceFiles) {
    $fullPath = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path $fullPath)) {
        throw "Missing required file: $relativePath"
    }
}

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
        $_.Name -notlike "*.bak*" -and
        $_.Extension -notin @(".py", ".pyw", ".spec")
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagedPythonRoot -Recurse -Force
    }
}

$presetPath = Join-Path $Mql5Root "Presets\multibot.set"
$templatePath = Join-Path $Mql5Root "Profiles\Templates\multibot.set"
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
