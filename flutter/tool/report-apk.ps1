[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ApkPath
)

$ErrorActionPreference = 'Stop'
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$stream = [IO.File]::OpenRead($apk)
try {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $sha = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
} finally {
    $stream.Dispose()
}
$size = (Get-Item -LiteralPath $apk).Length
Write-Host "APK: $apk"
Write-Host "Size: $size bytes"
Write-Host "SHA-256: $sha"

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $abis = @($zip.Entries |
        Where-Object { $_.FullName -match '^lib/([^/]+)/[^/]+\.so$' } |
        ForEach-Object { ([regex]::Match($_.FullName, '^lib/([^/]+)/')).Groups[1].Value } |
        Sort-Object -Unique)
    if ($abis.Count -eq 0) { throw 'No native library ABI directories found in APK.' }
    Write-Host "ABIs: $($abis -join ', ')"
} finally {
    $zip.Dispose()
}

$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $null }
$apksigner = $null
if ($androidHome) {
    $apksigner = Get-ChildItem -Path (Join-Path $androidHome 'build-tools') -Filter 'apksigner*' -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
}
if ($apksigner) {
    Write-Host 'Signing certificate:'
    & $apksigner.FullName verify --print-certs $apk
    if ($LASTEXITCODE -ne 0) { throw "apksigner verification failed ($LASTEXITCODE)" }
} else {
    Write-Warning 'apksigner not found under ANDROID_HOME/ANDROID_SDK_ROOT; signing certificate was not reported.'
}
