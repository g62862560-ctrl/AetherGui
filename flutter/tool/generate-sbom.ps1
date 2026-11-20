[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $root 'build\reports\sbom.cdx.json'
}
$lockPath = Join-Path $root 'pubspec.lock'
$pubspecPath = Join-Path $root 'pubspec.yaml'
$nativeScript = Join-Path $root 'fetch_aether.sh'

$pubspec = Get-Content -Raw $pubspecPath
$appVersion = [regex]::Match($pubspec, '(?m)^version:\s*([^\s]+)').Groups[1].Value
$lock = Get-Content -Raw $lockPath
$blocks = [regex]::Matches($lock, '(?ms)^  ([a-zA-Z0-9_]+):\r?\n(.*?)(?=^  [a-zA-Z0-9_]+:|^sdks:)')
$components = [Collections.Generic.List[object]]::new()
foreach ($block in $blocks) {
    $name = $block.Groups[1].Value
    $body = $block.Groups[2].Value
    $source = [regex]::Match($body, '(?m)^    source:\s*([^\r\n]+)').Groups[1].Value.Trim(' "')
    $version = [regex]::Match($body, '(?m)^    version:\s*"?([^"\r\n]+)').Groups[1].Value
    if ($source -eq 'hosted' -and $version) {
        $sha = [regex]::Match($body, '(?m)^      sha256:\s*"?([a-f0-9]{64})').Groups[1].Value
        $component = [ordered]@{
            type = 'library'; name = $name; version = $version
            purl = "pkg:pub/$name@$version"
        }
        if ($sha) { $component.hashes = @([ordered]@{ alg = 'SHA-256'; content = $sha }) }
        $components.Add($component)
    }
}

$native = Get-Content -Raw $nativeScript
$aetherVersion = [regex]::Match($native, '(?m)^readonly AETHER_VERSION=([^\s]+)').Groups[1].Value
$hevVersion = [regex]::Match($native, '--branch ([^\s]+)').Groups[1].Value
if ($aetherVersion) { $components.Add([ordered]@{ type='application'; name='aether'; version=$aetherVersion; purl="pkg:github/CluvexStudio/Aether@$aetherVersion" }) }
if ($hevVersion) { $components.Add([ordered]@{ type='library'; name='hev-socks5-tunnel'; version=$hevVersion; purl="pkg:github/heiher/hev-socks5-tunnel@$hevVersion" }) }

$document = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    serialNumber = "urn:uuid:$([guid]::NewGuid())"
    version = 1
    metadata = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        tools = @([ordered]@{ vendor='AetherGui'; name='generate-sbom.ps1' })
        component = [ordered]@{ type='application'; name='aether_gui'; version=$appVersion }
    }
    components = $components
}
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($output)) | Out-Null
$document | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $output
Write-Host "SBOM: $output ($($components.Count) components)"
