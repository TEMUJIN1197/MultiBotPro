param(
    [switch]$SkipMql,
    [switch]$SkipDll,
    [switch]$SkipPython,
    [switch]$SkipInstaller,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogRoot = Join-Path $Root "build\logs"
$OutputRoot = Join-Path $Root "Output"

function Find-FirstExistingPath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

Push-Location $Root
try {
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

    Write-Host "== MultiBotPro build wrapper =="
    & (Join-Path $PSScriptRoot "check.ps1")
    if ($CheckOnly) {
        Write-Host "Check-only mode complete." -ForegroundColor Green
        return
    }

    $compileWarnings = $null
    $compileErrors = $null

    if (-not $SkipDll) {
        $nativeBuild = Join-Path $Root "MultiBotWorker\build_static_worker.ps1"
        if (Test-Path -LiteralPath $nativeBuild) {
            Write-Host "[DLL] Running native build helper..."
            & $nativeBuild
        } else {
            Write-Warning "[DLL] Native build helper not found; skipping."
        }
    }

    if (-not $SkipMql) {
        $metaEditor = Find-FirstExistingPath @(
            "C:\Program Files\MetaTrader 5\metaeditor64.exe",
            "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
        )
        if ($metaEditor) {
            $compileLog = Join-Path $LogRoot "compile_current.log"
            Write-Host "[MQL] Compiling MultiBotPro.mq5..."
            $oldMetaLogStamp = $null
            if (Test-Path -LiteralPath $compileLog) {
                $oldMetaLogStamp = (Get-Item -LiteralPath $compileLog).LastWriteTimeUtc
            }

            # MetaEditor is picky about include resolution. Compile from repo root with
            # the same relative target a developer would use in the IDE.
            & $metaEditor /compile:MultiBotPro.mq5 /log:"build\logs\compile_current.log"

            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $compileLog) {
                    $newMetaLogStamp = (Get-Item -LiteralPath $compileLog).LastWriteTimeUtc
                    if ($null -eq $oldMetaLogStamp -or $newMetaLogStamp -gt $oldMetaLogStamp) {
                        break
                    }
                }
                Start-Sleep -Milliseconds 500
            }
            if (-not (Test-Path -LiteralPath $compileLog)) {
                Write-Warning "[MQL] MetaEditor did not create $compileLog; compile truth could not be established."
                $logText = ""
            } else {
                $logText = Get-Content -LiteralPath $compileLog -Raw -ErrorAction SilentlyContinue
            }
            if ($logText -match "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?") {
                $compileErrors = [int]$Matches[1]
                $compileWarnings = [int]$Matches[2]
                if ($compileErrors -gt 0) {
                    throw "MQL compile failed: $compileErrors error(s), $compileWarnings warning(s). See $compileLog"
                }
                Write-Host "[MQL] Compile OK: $compileWarnings warning(s)."
            } else {
                Write-Warning "[MQL] Compile completed but result line was not found in $compileLog"
            }
        } else {
            Write-Warning "[MQL] MetaEditor not found; skipping compile."
        }
    }

    if (-not $SkipPython) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            Write-Host "[Python] Syntax checking ShadowMaster.py..."
            try {
                & $pythonCmd.Source -m py_compile (Join-Path $Root "PythonApp\ShadowMaster.py") (Join-Path $Root "PythonApp\init_database.py")
            } catch {
                Write-Warning "[Python] Syntax check could not run in this desktop session: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "[Python] Python not found; skipping syntax check."
        }
    }

    if (-not $SkipInstaller) {
        $installerScript = Join-Path $Root "build_installer.ps1"
        if (Test-Path -LiteralPath $installerScript) {
            Write-Host "[Installer] Running existing installer build script..."
            & $installerScript
        } else {
            Write-Warning "[Installer] build_installer.ps1 not found; skipping."
        }
    }

    $gitHash = ""
    try { $gitHash = (& git rev-parse --short HEAD 2>$null) } catch { $gitHash = "" }

    $manifest = [ordered]@{
        name = "MultiBotPro"
        built_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        git_hash = $gitHash
        mql_compile_errors = $compileErrors
        mql_compile_warnings = $compileWarnings
        skipped_mql = [bool]$SkipMql
        skipped_dll = [bool]$SkipDll
        skipped_python = [bool]$SkipPython
        skipped_installer = [bool]$SkipInstaller
        bridge_include_active = "hedgeBridge.mqh"
        bridge_canonical_target = "MultiBotPro_HedgeBridge.mqh"
        schema_runtime_truth = "hedgeBridge.mqh / extras/schema_clean.sql / PythonApp/init_database.py"
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot "build_manifest.json")
    Write-Host "Build wrapper complete." -ForegroundColor Green
}
finally {
    Pop-Location
}
