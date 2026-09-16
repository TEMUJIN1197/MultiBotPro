param(
    [string]$OutputPath = ".\support_bundle"
)

$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bundleDir = Join-Path (Resolve-Path ".").Path "mbp_support_$timestamp"

New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

function Copy-IfExists {
    param([string]$Source, [string]$Destination)
    if (Test-Path -LiteralPath $Source) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

Push-Location $Root
try {
    Copy-IfExists "REPO_MAP.md" $bundleDir
    Copy-IfExists "Output\build_manifest.json" $bundleDir
    Copy-IfExists "schemas\runtime_v3.sql" $bundleDir

    $runtimeCandidates = @("runtime_v3.json", "runtime_v3.openai.sample.json")
    foreach ($candidate in $runtimeCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $content = Get-Content -LiteralPath $candidate -Raw
            $content = $content -replace '"api_key"\s*:\s*"[^"]*"', '"api_key": "REDACTED"'
            $content = $content -replace '"OPENAI_API_KEY"\s*:\s*"[^"]*"', '"OPENAI_API_KEY": "REDACTED"'
            $outName = [IO.Path]::GetFileNameWithoutExtension($candidate) + ".redacted.json"
            Set-Content -LiteralPath (Join-Path $bundleDir $outName) -Value $content
        }
    }

    $commonFiles = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
    if (Test-Path -LiteralPath $commonFiles) {
        Copy-IfExists (Join-Path $commonFiles "status_snapshot.json") $bundleDir
        Copy-IfExists (Join-Path $commonFiles "ShadowMasterRuntime.json") $bundleDir
        Copy-IfExists (Join-Path $commonFiles "ShadowSync.json") $bundleDir
    }

    Get-ChildItem -Path . -File -Include "*.log", "compile*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Tail 500 -ErrorAction SilentlyContinue |
                Set-Content -LiteralPath (Join-Path $bundleDir ($_.BaseName + ".tail.log"))
        }

    $summary = [ordered]@{
        collected_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        root = $Root
        bridge_active = "hedgeBridge.mqh"
        bridge_canonical_target = "MultiBotPro_HedgeBridge.mqh"
        schema_runtime_truth = "schemas/runtime_v3.sql"
    }
    $summary | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $bundleDir "bundle_summary.json")

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $zipPath = Join-Path (Resolve-Path $OutputPath).Path "mbp_support_$timestamp.zip"
    Compress-Archive -Path (Join-Path $bundleDir "*") -DestinationPath $zipPath -Force
    Remove-Item -LiteralPath $bundleDir -Recurse -Force
    Write-Host "Support bundle: $zipPath" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
