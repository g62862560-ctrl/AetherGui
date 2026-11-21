[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ApkPath,
    [string]$ExpectedCertificateSha256
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

$localProperties = Join-Path $PSScriptRoot '..\android\local.properties'
$localSdk = if (Test-Path -LiteralPath $localProperties) {
    $line = Get-Content -LiteralPath $localProperties | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
    if ($line) { ($line -replace '^sdk\.dir=', '') -replace '\\\\', '\' } else { $null }
} else { $null }
$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $localSdk }
$apksigner = $null
if ($androidHome) {
    $apksigner = Get-ChildItem -Path (Join-Path $androidHome 'build-tools') -Filter 'apksigner*' -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
}
if ($apksigner) {
    Write-Host 'Signing certificate:'
    $certificate = (& $apksigner.FullName verify --print-certs $apk 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "apksigner verification failed ($LASTEXITCODE): $certificate" }
    Write-Host $certificate.Trim()
    if ($ExpectedCertificateSha256) {
        $actual = [regex]::Match($certificate, '(?im)^Signer #1 certificate SHA-256 digest:\s*([0-9a-f:]+)\s*$').Groups[1].Value.Replace(':', '').ToLowerInvariant()
        $expected = $ExpectedCertificateSha256.Replace(':', '').ToLowerInvariant()
        if (-not $actual -or $actual -ne $expected) {
            throw "APK certificate SHA-256 mismatch: expected $expected, got $actual"
        }
    }
} elseif ($ExpectedCertificateSha256) {
    throw 'apksigner is required when an expected certificate fingerprint is supplied.'
} else {
    Write-Warning 'apksigner not found under ANDROID_HOME/ANDROID_SDK_ROOT; signing certificate was not reported.'
}
