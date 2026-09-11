# Source-only Windows release build. Never install or launch game/runtime content.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidatePattern('^(v[0-9][A-Za-z0-9._-]*|milestone-[0-9][A-Za-z0-9._-]*)$')]
    [Parameter(Mandatory)][string]$Version,
    [ValidateRange(1,16)][int]$Parallel = 4
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '../..' }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')

$changes = @(& git -C $RepoRoot status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count) { throw 'Release builds require a clean Git checkout.' }
Invoke-NativeChecked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Test-NeuralDoom-PublicSource.ps1'), '-RepoRoot', $RepoRoot)
$cache = Join-Path $RepoRoot '.neuraldoom-cache/cloud-release'
New-Item -ItemType Directory -Path $cache -Force | Out-Null

# Existing documented build dependencies, obtained from their official releases.
$ispc = Get-SetupDownload -Uri 'https://github.com/ispc/ispc/releases/download/v1.31.0/ispc-v1.31.0-windows.zip' -Destination (Join-Path $cache 'ispc-v1.31.0-windows.zip') -Sha256 '9A18793800B91D5BE7B851513672CD9A81A985A5A5DFEC5611C2318E8AD4140A'
& (Join-Path $PSScriptRoot 'Install-ISPC.ps1') -RepoRoot $RepoRoot -SourcePath $ispc
$components = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'neural-components.json') -Raw | ConvertFrom-Json
$streamline = @($components.components | Where-Object id -EQ 'streamline')
if ($streamline.Count -ne 1) { throw 'Expected one pinned Streamline SDK.' }
$sdkArchive = Get-SetupDownload -Uri $streamline[0].url -Destination (Join-Path $cache $streamline[0].file) -Sha256 $streamline[0].sha256 -Bytes $streamline[0].bytes
$sdk = Join-Path $cache 'streamline-sdk'
Expand-Archive -LiteralPath $sdkArchive -DestinationPath $sdk -Force
if (-not (Test-Path -LiteralPath (Join-Path $sdk 'include/sl.h'))) { throw 'Unexpected official SDK archive layout.' }

$env:MSBUILDDISABLENODEREUSE = '1'
$native = Join-Path $RepoRoot 'build-ci-native'
$neural = Join-Path $RepoRoot 'build-ci-neural'
# Builds share shader outputs: keep these sequential, not a concurrent matrix.
& (Join-Path $PSScriptRoot 'Configure-RBDOOM-DX12.ps1') -RepoRoot $RepoRoot -BuildDirectory $native -RayTracing ON
Invoke-NativeChecked 'cmake' @('-S', (Join-Path $RepoRoot 'neo'), '-B', $native, '-DUSE_STREAMLINE=OFF')
& (Join-Path $PSScriptRoot 'Build-RBDOOM.ps1') -RepoRoot $RepoRoot -BuildDirectory $native -Configuration Release -Parallel $Parallel
& (Join-Path $PSScriptRoot 'Configure-RBDOOM-DX12.ps1') -RepoRoot $RepoRoot -BuildDirectory $neural -RayTracing ON
Invoke-NativeChecked 'cmake' @('-S', (Join-Path $RepoRoot 'neo'), '-B', $neural, '-DUSE_STREAMLINE=ON', "-DSTREAMLINE_SDK_PATH=$sdk")
& (Join-Path $PSScriptRoot 'Build-RBDOOM.ps1') -RepoRoot $RepoRoot -BuildDirectory $neural -Configuration Release -Parallel $Parallel

# Use the installer's actual Windows PowerShell 5.1 host for offline helper tests.
foreach ($test in @('Test-TexturePack.ps1', 'Test-TexturePackWizard.ps1', 'Test-SetupUpgradeDefault.ps1', 'Test-InstallLifecycle.ps1', 'Test-NeuralSettingsSnapshot.ps1')) {
    Invoke-NativeChecked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $test))
}
$out = Join-Path $RepoRoot "releases/$Version"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$zip = Join-Path $out "neuralDOOM-$Version.zip"
$exe = Join-Path $out "neuralDOOM-Setup-$Version.exe"
Invoke-NativeChecked 'python' @((Join-Path $PSScriptRoot 'Build-InternalPackage.py'), '--source', $RepoRoot, '--game', $RepoRoot, '--build-directory', $native, '--neural-build-directory', $neural, '--output', $zip)
& (Join-Path $PSScriptRoot 'Build-InternalSetup.ps1') -PackagePath $zip -OutputPath $exe
Write-Host "PASS: release assets ready in $out"
