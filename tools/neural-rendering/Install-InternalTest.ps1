[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$GamePath,
    [string]$LightingPackPath,
    [switch]$VerifyOnly,
    [switch]$SkipShortcut,
    [switch]$SkipStartMenu,
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
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
Write-SetupStatus 'Checking your Doom 3 BFG installation...'
if (-not $GamePath) { $GamePath = Find-SetupBFG }
if (-not $GamePath -and -not $NonInteractive) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Select your owned Doom 3 BFG Edition installation (containing base)'
    $picker.ShowNewFolderButton = $false
    if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $GamePath = $picker.SelectedPath }
    $picker.Dispose()
}
if (-not $GamePath -or -not (Test-Path -LiteralPath (Join-Path $GamePath 'base/maps/mars_city2.resources'))) {
    throw 'Doom 3 BFG Edition was not found. Rerun setup and select its installation folder, or pass -GamePath.'
}
Write-Host "Using owned BFG installation: $GamePath"
Write-SetupStatus 'Checking Microsoft prerequisites...'
Install-SetupVCRuntime -RepoRoot $RepoRoot
if (-not $LightingPackPath) { $LightingPackPath = Get-SetupLightingPack -RepoRoot $RepoRoot }
Write-SetupStatus 'Copying game data and preparing your installation...'
# Convert portable identity to the existing launcher's local exact-build format.
$package.executable = $exe
$package.PSObject.Properties.Remove('files')
$package | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RepoRoot 'build-rt/neuraldoom-build-Release.json') -Encoding UTF8
$exe | Set-Content -LiteralPath (Join-Path $RepoRoot 'build-rt/neuraldoom-artifact-Release.txt') -Encoding UTF8
& (Join-Path $PSScriptRoot 'Setup-NeuralDoom.ps1') -RepoRoot $RepoRoot -GamePath $GamePath -LightingPackPath $LightingPackPath -Profile Native -Configuration Release -SkipD3HDP -SkipNRRuntime -NonInteractive:$NonInteractive
if (-not $SkipShortcut) {
Write-SetupStatus 'Creating your desktop shortcut...'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'neuralDoom Internal Test.lnk'))
$shortcut.TargetPath = Join-Path $RepoRoot 'Play-InternalTest.cmd'
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.IconLocation = "$exe,0"
$shortcut.Save()
}
if (-not $SkipStartMenu) {
Write-SetupStatus 'Adding neuralDoom to your Start menu...'
$startFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'neuralDoom'
New-Item -ItemType Directory -Path $startFolder -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $startFolder 'neuralDoom Internal Test.lnk'))
$shortcut.TargetPath = Join-Path $RepoRoot 'Play-InternalTest.cmd'
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.IconLocation = "$exe,0"
$shortcut.Save()
}
Write-Host 'READY: use the neuralDoom Internal Test desktop shortcut. Controls: INTERNAL_TESTING.md.'
