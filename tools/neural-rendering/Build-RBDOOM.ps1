[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [int]$Parallel = 0,
    [switch]$StageExecutable
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $RepoRoot 'build'
}
$BuildDirectory = Resolve-NeuralFullPath $BuildDirectory
if (-not (Test-Path (Join-Path $buildDirectory 'CMakeCache.txt'))) {
    throw "The build tree is not configured. Run Configure-RBDOOM-DX12.ps1 first."
}

$args = @('--build', $buildDirectory, '--config', $Configuration)
if ($Parallel -gt 0) {
    $args += @('--parallel', $Parallel.ToString())
} else {
    $args += '--parallel'
}

Write-Step "Building neuralDoom on RBDOOM-3-BFG ($Configuration)"
$manifestPath = Join-Path $BuildDirectory "neuraldoom-build-$Configuration.json"
if (Test-Path -LiteralPath $manifestPath) {
    Remove-Item -LiteralPath $manifestPath -Force
}
Invoke-NativeChecked 'cmake' $args

$exe = Find-RBDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration -BuildDirectory $BuildDirectory
if (-not $exe) {
    throw 'Build returned success, but the exact configured target executable is missing.'
}

Write-Host "Executable: $exe" -ForegroundColor Green
if ($StageExecutable) {
    $staged = Join-Path $RepoRoot (Split-Path -Leaf $exe)
    Copy-Item $exe $staged -Force
    Write-Host "Staged:     $staged" -ForegroundColor Green
}

$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
$cache = @{}
Get-Content -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt') | ForEach-Object {
    if ($_ -match '^([^/#][^:]*):[^=]+=(.*)$') { $cache[$matches[1]] = $matches[2] }
}
$commit = & git -C $RepoRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot record build commit.' }
$changes = @(& git -C $RepoRoot status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot record build worktree state.' }
$manifest = [ordered]@{
    schemaVersion = 1
    builtAt = (Get-Date -Format o)
    commit = "$commit".Trim()
    dirty = $changes.Count -gt 0
    configuration = $Configuration
    executable = $exe
    sha256 = $hash
    features = [ordered]@{ dx12 = $cache['USE_DX12']; vulkan = $cache['USE_VULKAN']; streamline = $cache['USE_STREAMLINE']; rayTracing = $cache['USE_RAYTRACING'] }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$docs = Join-Path $RepoRoot 'docs\neural-rendering'
if (Test-Path $docs) {
    @(
        "Built: $(Get-Date -Format o)",
        "Configuration: $Configuration",
        "Executable: $exe",
        "SHA256: $hash"
    ) | Set-Content (Join-Path $docs 'LAST_BUILD.txt') -Encoding utf8
}
