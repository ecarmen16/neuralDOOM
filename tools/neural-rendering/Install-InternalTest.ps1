[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$GamePath,
    [string]$LightingPackPath,
    [switch]$VerifyOnly,
    [switch]$NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '../..' }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$packagePath = Join-Path $RepoRoot 'internal-package.json'
if (-not (Test-Path -LiteralPath $packagePath)) { throw 'Use this installer from the extracted internal Release ZIP.' }
$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
if ($package.schemaVersion -ne 2 -or $package.configuration -ne 'Release' -or $package.features.streamline -ne 'OFF' -or $package.features.rayTracing -ne 'ON') {
    throw 'This installer accepts only the native RTX Release package.'
}
$prefix = $RepoRoot.TrimEnd('\') + '\'
$seen = @{}
foreach ($file in $package.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $RepoRoot $file.path))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($path)) { throw 'Invalid/duplicate package path.' }
    $seen[$path] = $true
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) {
        throw "Package file missing or changed: $($file.path). Extract a fresh ZIP; saves can remain in captures/dogfood."
    }
}
$exe = [IO.Path]::GetFullPath((Join-Path $RepoRoot $package.executable))
if (-not $exe.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not $seen.ContainsKey($exe) -or
    (Get-FileHash -LiteralPath $exe).Hash -ne $package.sha256 -or
    -not $seen.ContainsKey((Join-Path $RepoRoot 'LICENSE.md')) -or
    (Get-Content -LiteralPath (Join-Path $RepoRoot 'SOURCE_REVISION.txt') -First 1) -ne $package.commit) { throw 'Invalid package executable/source identity.' }
Write-Host "PASS: package hashes and corresponding source ($($package.commit))."
if ($VerifyOnly) { return }
foreach ($dll in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR "System32/$dll"))) {
        throw 'Install the Microsoft Visual C++ 2015-2022 x64 Redistributable from https://aka.ms/vs/17/release/vc_redist.x64.exe, then rerun Install-InternalTest.cmd.'
    }
}
if (-not $LightingPackPath -and -not $NonInteractive) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = 'Select _rbdoom_global_illumination_data.pk4 from your extracted RBDOOM 1.6.0 release'
    $picker.Filter = 'RBDOOM lighting pack|_rbdoom_global_illumination_data.pk4'
    if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $LightingPackPath = $picker.FileName }
    $picker.Dispose()
}
if (-not $LightingPackPath) { throw 'Select the official RBDOOM lighting pack to test the intended lighting. See INTERNAL_TESTING.md.' }
# Convert portable identity to the existing launcher's local exact-build format.
$package.executable = $exe
$package.PSObject.Properties.Remove('files')
$package | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RepoRoot 'build-rt/neuraldoom-build-Release.json') -Encoding UTF8
$exe | Set-Content -LiteralPath (Join-Path $RepoRoot 'build-rt/neuraldoom-artifact-Release.txt') -Encoding UTF8
& (Join-Path $PSScriptRoot 'Setup-NeuralDoom.ps1') -RepoRoot $RepoRoot -GamePath $GamePath -LightingPackPath $LightingPackPath -Profile Native -Configuration Release -SkipD3HDP -SkipNRRuntime -NonInteractive:$NonInteractive
Write-Host 'READY: double-click Play-InternalTest.cmd. Controls and comparisons: INTERNAL_TESTING.md.'
