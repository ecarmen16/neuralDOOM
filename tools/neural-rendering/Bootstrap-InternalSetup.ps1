[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$Sha256,
    [string]$Destination,
    [string]$GamePath,
    [switch]$NonInteractive,
    [switch]$ExtractOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-FileHash -LiteralPath $PackagePath).Hash -ne $Sha256) { throw 'Setup payload checksum failed. Download setup again.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
try {
    $reader = New-Object IO.StreamReader($archive.GetEntry('internal-package.json').Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($manifest.commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid payload version.' }
    if (-not $Destination) { $Destination = Join-Path $env:LOCALAPPDATA ("neuralDoom/Internal/" + $manifest.commit.Substring(0, 8)) }
    $Destination = [IO.Path]::GetFullPath($Destination)
    $prefix = $Destination.TrimEnd('\') + '\'
    foreach ($entry in $archive.Entries) {
        $path = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe setup archive path.' }
    }
} finally { $archive.Dispose() }
if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) {
    $marker = Join-Path $Destination 'internal-package.json'
    if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).commit -ne $manifest.commit) {
        throw 'Choose an empty destination. Setup preserves other installations and their saves.'
    }
}
Write-Host "Installing neuralDoom to $Destination"
Expand-Archive -LiteralPath $PackagePath -DestinationPath $Destination -Force
if ($ExtractOnly) { return }
& (Join-Path $Destination 'tools/neural-rendering/Install-InternalTest.ps1') -RepoRoot $Destination -GamePath $GamePath -NonInteractive:$NonInteractive
