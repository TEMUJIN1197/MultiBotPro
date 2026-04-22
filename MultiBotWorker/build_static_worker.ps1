$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$compiler = "C:\Program Files\LLVM-MinGW\bin\g++.exe"
$outDll = Join-Path $root "accel.dll"

& $compiler `
  -std=gnu++17 `
  -O2 `
  -shared `
  -DMULTIBOTWORKER_EXPORTS `
  -static `
  -static-libgcc `
  -static-libstdc++ `
  -o $outDll `
  (Join-Path $PSScriptRoot "dllmain.cpp") `
  (Join-Path $PSScriptRoot "MultiBotWorker.cpp")

Write-Host "Built static worker DLL:" $outDll
