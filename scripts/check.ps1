$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $Root

try {
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    function Test-RequiredFile {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) {
            $errors.Add("Missing required file: $Path")
        }
    }

    Write-Host "== MultiBotPro repository check =="
    Write-Host "Root: $Root"

    $required = @(
        "MultiBotPro.mq5",
        "hedgeBridge.mqh",
        "MultiBotPro_HedgeBridge.mqh",
        "PythonApp\ShadowMaster.py",
        "PythonApp\init_database.py",
        "MultiBotWorker\MultiBotWorker.cpp",
        "extras\schema_clean.sql"
    )
    foreach ($file in $required) { Test-RequiredFile $file }

    $tools = [ordered]@{
        MetaEditor = @(
            "C:\Program Files\MetaTrader 5\metaeditor64.exe",
            "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
        )
        MSBuild = @(
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
        )
        InnoSetup = @(
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Antigravity\resources\app\node_modules\innosetup\bin\ISCC.exe"
        )
    }

    foreach ($tool in $tools.GetEnumerator()) {
        $found = $tool.Value | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($found) {
            Write-Host ("Tool {0}: {1}" -f $tool.Key, $found)
        } else {
            $warnings.Add("Tool not found: $($tool.Key)")
        }
    }

    $generatedPaths = @("Output", "PackageStage", "build", "PythonApp\WinPython")
    foreach ($path in $generatedPaths) {
        if (Test-Path -LiteralPath $path) {
            $warnings.Add("Generated/runtime path present: $path")
        }
    }

    $artifactPatterns = @("*.ex5", "*.dll", "*.db", "*.db-wal", "*.db-shm", "*.log", "compile*.txt")
    foreach ($pattern in $artifactPatterns) {
        $hits = Get-ChildItem -Path . -Filter $pattern -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
        if ($hits) {
            $warnings.Add("Generated artifacts present for '$pattern': $($hits -join ', ')")
        }
    }

    $compileLogCandidates = @()
    $currentCompileLog = Join-Path $Root "build\logs\compile_current.log"
    if (Test-Path -LiteralPath $currentCompileLog) {
        $compileLogCandidates += Get-Item -LiteralPath $currentCompileLog
    }
    $compileLogCandidates += Get-ChildItem -Path . -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.log" -or $_.Name -like "compile*.txt" } |
        Sort-Object LastWriteTime -Descending

    $latestCompileLog = $compileLogCandidates | Select-Object -First 1
    if ($latestCompileLog) {
        Write-Host "Latest compile/runtime log candidate: $($latestCompileLog.FullName)"
        $logText = Get-Content -LiteralPath $latestCompileLog.FullName -Raw -ErrorAction SilentlyContinue
        if ($logText -match "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?") {
            Write-Host "Log result: $($Matches[1]) errors, $($Matches[2]) warnings"
            if ([int]$Matches[1] -gt 0) {
                $warnings.Add("Latest log reports compile errors: $($latestCompileLog.Name)")
            }
        } else {
            $warnings.Add("Latest compile log has no Result line yet: $($latestCompileLog.FullName)")
        }
    } else {
        $warnings.Add("No compile log found.")
    }

    if ((Test-Path "hedgeBridge.mqh") -and (Test-Path "MultiBotPro_HedgeBridge.mqh")) {
        $legacyHash = (Get-FileHash "hedgeBridge.mqh" -Algorithm SHA256).Hash
        $canonicalHash = (Get-FileHash "MultiBotPro_HedgeBridge.mqh" -Algorithm SHA256).Hash
        if ($legacyHash -ne $canonicalHash) {
            $warnings.Add("Bridge files differ; keep active include unchanged until reconciled.")
        } else {
            Write-Host "Bridge files are byte-identical."
        }
    }

    if ((Test-Path "sqlite_schema.sql") -and (Test-Path "extras\schema_clean.sql")) {
        $rootSchema = Get-Content "sqlite_schema.sql" -Raw
        $v3Schema = Get-Content "extras\schema_clean.sql" -Raw
        if ($rootSchema -notmatch "CREATE TABLE IF NOT EXISTS signals" -or
            $rootSchema -match "signal_queue") {
            $warnings.Add("Root sqlite_schema.sql appears legacy; runtime v3 schema is extras/schema_clean.sql and hedgeBridge.mqh.")
        }
        if ($v3Schema -notmatch "shadow_params") {
            $warnings.Add("extras/schema_clean.sql does not expose shadow_params.")
        }
    }

    foreach ($warning in $warnings) { Write-Warning $warning }
    foreach ($err in $errors) { Write-Error $err }

    if ($errors.Count -gt 0) {
        Write-Host "CHECK FAILED" -ForegroundColor Red
        exit 1
    }

    Write-Host "CHECK COMPLETE: $($warnings.Count) warning(s), 0 error(s)." -ForegroundColor Green
}
finally {
    Pop-Location
}
