$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    & (Join-Path $scriptDir "build_installer.ps1")
}
finally {
    Pop-Location
}
