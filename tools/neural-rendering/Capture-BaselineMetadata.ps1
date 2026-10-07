[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [string]$Notes = ''
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
$identity = Get-NeuralBuildIdentity -RepoRoot $RepoRoot -BuildDirectory $BuildDirectory -Configuration $Configuration
$exe = $identity.executable
$manifest = $identity.manifest

$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$destination = Join-Path $RepoRoot "captures\neural\$stamp"
New-Item -ItemType Directory -Path $destination -Force | Out-Null

$os = try {
    Get-CimInstance Win32_OperatingSystem
} catch {
    $windowsVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Caption = $windowsVersion.ProductName
        BuildNumber = $windowsVersion.CurrentBuildNumber
    }
}
$gpu = if (Test-CommandAvailable 'nvidia-smi') {
    (& nvidia-smi --query-gpu=name,driver_version,vbios_version --format=csv,noheader) -join '; '
} else { 'nvidia-smi unavailable' }
$cmake = ((& cmake --version) | Select-Object -First 1)

$metadata = @"
# Baseline metadata

- Captured: $(Get-Date -Format o)
- Repository: $RepoRoot
- Build directory: $($identity.buildDirectory)
- Build manifest: $($identity.manifestPath)
- Built: $($manifest.builtAt)
- Build commit: $($manifest.commit)
- Build dirty: $($manifest.dirty)
- Checkout branch: $($identity.checkoutBranch)
- Checkout commit: $($identity.checkoutCommit)
- Checkout dirty: $($identity.checkoutDirty)
- Revision relationship: $($identity.revisionRelationship)
- Configuration: $Configuration
- Executable: $exe
- Executable SHA-256: $($manifest.sha256)
- Shader identity: $(@($manifest.shaders).Count) manifest hashes verified
- Build features: DX12=$($manifest.features.dx12), Vulkan=$($manifest.features.vulkan), Streamline=$($manifest.features.streamline), ray tracing=$($manifest.features.rayTracing)
- OS: $($os.Caption) build $($os.BuildNumber)
- GPU/driver: $gpu
- CMake: $cmake
- Launch: ``+set r_graphicsAPI dx12``
- Notes: $Notes

Add screenshots, GPU captures, logs, and scene/save details to this directory. This directory is locally excluded from Git.
$(if ($manifest.dirty) { 'The build was made with local changes; uncommitted build changes are not identified by its commit. The current checkout cannot reconstruct those changes from this manifest.' })
"@
$metadata | Set-Content (Join-Path $destination 'baseline-metadata.md') -Encoding utf8
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'build-manifest.json') -Encoding utf8

Write-Host "Created: $destination" -ForegroundColor Green
