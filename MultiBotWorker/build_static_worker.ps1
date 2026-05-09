$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$localCompiler = Join-Path $root ".tools\LLVM-MinGW\bin\clang-22.exe"
$systemCompiler = "C:\Program Files\LLVM-MinGW\bin\g++.exe"
$compiler = if(Test-Path -LiteralPath $localCompiler) { $localCompiler } else { $systemCompiler }
$outDll = Join-Path $root "accel.dll"

& $compiler `
  -target x86_64-w64-mingw32 `
  -rtlib=compiler-rt `
  -unwindlib=libunwind `
  -stdlib=libc++ `
  -fuse-ld=lld `
  -std=gnu++17 `
  -O2 `
  -shared `
  -DMULTIBOTWORKER_EXPORTS `
  -static `
  -o $outDll `
  (Join-Path $PSScriptRoot "dllmain.cpp") `
  (Join-Path $PSScriptRoot "MultiBotWorker.cpp") `
  -lc++ `
  -lc++abi `
  -lunwind

if($LASTEXITCODE -ne 0)
{
  throw "Worker DLL build failed with exit code $LASTEXITCODE"
}

Write-Host "Built static worker DLL:" $outDll
