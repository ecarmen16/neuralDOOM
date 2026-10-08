# PR compile coverage only. Dependencies remain ignored and no binaries are published.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateRange(1,16)][int]$Parallel = 4
)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
$cache = Join-Path $RepoRoot '.neuraldoom-cache/renderer-validation'
New-Item -ItemType Directory -Path $cache -Force | Out-Null

# Same official ISPC pin as Build-CloudRelease.ps1; SDK identity comes from its manifest.
$ispc = Get-SetupDownload -Uri 'https://github.com/ispc/ispc/releases/download/v1.31.0/ispc-v1.31.0-windows.zip' -Destination (Join-Path $cache 'ispc-v1.31.0-windows.zip') -Sha256 '9A18793800B91D5BE7B851513672CD9A81A985A5A5DFEC5611C2318E8AD4140A'
& (Join-Path $PSScriptRoot 'Install-ISPC.ps1') -RepoRoot $RepoRoot -SourcePath $ispc
& (Join-Path $PSScriptRoot 'Test-RendererContracts.ps1') -RepoRoot $RepoRoot -Suite CPU

$env:MSBUILDDISABLENODEREUSE = '1'
# ShaderMake writes to base/renderprogs2 in the checkout, even with separate build trees.
# Finish each variant and its shader contracts before starting the next configuration.
foreach ($variant in @('baseline', 'ray-tracing', 'streamline')) {
    $build = Join-Path $RepoRoot "build-ci-$variant"
    $rayTracing = if ($variant -eq 'baseline') { 'OFF' } else { 'ON' }
    $streamline = if ($variant -eq 'streamline') { 'ON' } else { 'OFF' }
    $options = @("-DUSE_STREAMLINE=$streamline")
    if ($streamline -eq 'ON') {
        $components = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'neural-components.json') -Raw | ConvertFrom-Json
        $component = @($components.components | Where-Object id -EQ 'streamline')
        if ($component.Count -ne 1) { throw 'Expected one pinned Streamline SDK.' }
        $sdkArchive = Get-SetupDownload -Uri $component[0].url -Destination (Join-Path $cache $component[0].file) -Sha256 $component[0].sha256 -Bytes $component[0].bytes
        $sdk = Join-Path $cache 'streamline-sdk'
        Expand-Archive -LiteralPath $sdkArchive -DestinationPath $sdk -Force
        if (-not (Test-Path -LiteralPath (Join-Path $sdk 'include/sl.h'))) { throw 'Unexpected official SDK archive layout.' }
        $options += "-DSTREAMLINE_SDK_PATH=$sdk"
    }
    Write-Step "RelWithDebInfo compile: $variant (RT=$rayTracing, Streamline=$streamline)"
    & (Join-Path $PSScriptRoot 'Configure-RBDOOM-DX12.ps1') -RepoRoot $RepoRoot -BuildDirectory $build -RayTracing $rayTracing
    Invoke-NativeChecked 'cmake' (@('-S', (Join-Path $RepoRoot 'neo'), '-B', $build) + $options)
    & (Join-Path $PSScriptRoot 'Build-RBDOOM.ps1') -RepoRoot $RepoRoot -BuildDirectory $build -Configuration RelWithDebInfo -Parallel $Parallel
    if ($rayTracing -eq 'ON') {
        $dxcEntry = @(Get-Content -LiteralPath (Join-Path $build 'CMakeCache.txt') | Where-Object { $_ -match '^DXC_PATH:[^=]+=' })
        if ($dxcEntry.Count -ne 1) { throw 'Expected the build DXC path in CMakeCache.txt.' }
        $dxc = $dxcEntry[0].Substring($dxcEntry[0].IndexOf('=') + 1)
        & (Join-Path $PSScriptRoot 'Test-RendererContracts.ps1') -RepoRoot $RepoRoot -Suite Shaders -Dxc $dxc
    }
    if ($env:GITHUB_STEP_SUMMARY) { "- PASS: $variant RelWithDebInfo compile; RT=$rayTracing, Streamline=$streamline." >> $env:GITHUB_STEP_SUMMARY }
}
Write-Host 'PASS: three sequential RelWithDebInfo configurations. GPU rendering and gameplay were not tested.'
