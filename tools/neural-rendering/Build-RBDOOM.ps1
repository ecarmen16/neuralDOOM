[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [int]$Parallel = 0,
    [switch]$StageExecutable
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
$buildDirectory = Join-Path $RepoRoot 'build'
if (-not (Test-Path (Join-Path $buildDirectory 'CMakeCache.txt'))) {
    throw "The build tree is not configured. Run Configure-RBDOOM-DX12.ps1 first."
}

$args = @('--build', $buildDirectory, '--config', $Configuration)
if ($Parallel -gt 0) {
    $args += @('--parallel', $Parallel.ToString())
} else {
    $args += '--parallel'
}

Write-Step "Building RBDOOM-3-BFG ($Configuration)"
Invoke-NativeChecked 'cmake' $args

$exe = Find-RBDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration
if (-not $exe) {
    Write-Warning 'Build returned success, but RBDoom3BFG.exe was not found automatically. Inspect the build tree.'
    exit 0
}

Write-Host "Executable: $exe" -ForegroundColor Green
if ($StageExecutable) {
    $staged = Join-Path $RepoRoot 'RBDoom3BFG.exe'
    Copy-Item $exe $staged -Force
    Write-Host "Staged:     $staged" -ForegroundColor Green
}

$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
$docs = Join-Path $RepoRoot 'docs\neural-rendering'
if (Test-Path $docs) {
    @(
        "Built: $(Get-Date -Format o)",
        "Configuration: $Configuration",
        "Executable: $exe",
        "SHA256: $hash"
    ) | Set-Content (Join-Path $docs 'LAST_BUILD.txt') -Encoding utf8
}
