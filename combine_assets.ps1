$cwd = Get-Location
$headerPath = "$cwd\header.bin"
$dllSrc = "$cwd\..\..\Libraries\accel.dll"
$dllDst = "$cwd\accel.bmp"
$aiSrc = "$cwd\PythonApp\ShadowMaster.exe"
$aiDst = "$cwd\PythonApp\ShadowMaster.bmp"
$renkoSrc = "$cwd\PythonApp\renko_fallback.exe"
$renkoDst = "$cwd\PythonApp\renko_fallback.bmp"

if (!(Test-Path $headerPath)) { Write-Error "Missing header.bin"; exit }
$header = [System.IO.File]::ReadAllBytes($headerPath)

function Combine($src, $dst) {
    if (Test-Path $src) {
        Write-Output "Combining $src -> $dst"
        $out = [System.IO.File]::Create($dst)
        $out.Write($header, 0, $header.Length)
        $in = [System.IO.File]::OpenRead($src)
        $in.CopyTo($out)
        $in.Close(); $in.Dispose()
        $out.Close(); $out.Dispose()
    } else {
        Write-Warning "Source not found: $src"
    }
}

Combine $dllSrc $dllDst
Combine $aiSrc $aiDst
Combine $renkoSrc $renkoDst
