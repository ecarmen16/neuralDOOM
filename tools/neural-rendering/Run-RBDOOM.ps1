[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [string[]]$AdditionalArguments = @()
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
$exe = Find-RBDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration
if (-not $exe) {
    throw 'RBDoom3BFG.exe was not found. Configure and build first.'
}

$args = @('+set', 'r_graphicsAPI', 'dx12') + $AdditionalArguments
Write-Step 'Launching RBDOOM-3-BFG through DX12'
Write-Host "Working directory: $RepoRoot"
Write-Host "Executable:        $exe"
Write-Host "Arguments:         $($args -join ' ')"

Push-Location $RepoRoot
try {
    & $exe @args
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

Write-Host "RBDOOM exited with code $exitCode"
exit $exitCode
