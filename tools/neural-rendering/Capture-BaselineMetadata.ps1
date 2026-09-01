[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo',
    [string]$Notes = ''
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
$exe = Find-RBDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration
if (-not $exe) { throw 'Executable not found.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
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
$gitSha = (& git -C $RepoRoot rev-parse HEAD).Trim()
$branch = (& git -C $RepoRoot branch --show-current).Trim()
$cmake = ((& cmake --version) | Select-Object -First 1)
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash

$metadata = @"
# Baseline metadata

- Captured: $(Get-Date -Format o)
- Repository: $RepoRoot
- Branch: $branch
- Commit: $gitSha
- Configuration: $Configuration
- Executable: $exe
- Executable SHA-256: $hash
- OS: $($os.Caption) build $($os.BuildNumber)
- GPU/driver: $gpu
- CMake: $cmake
- Launch: ``+set r_graphicsAPI dx12``
- Notes: $Notes

Add screenshots, GPU captures, logs, and scene/save details to this directory. This directory is locally excluded from Git.
"@
$metadata | Set-Content (Join-Path $destination 'baseline-metadata.md') -Encoding utf8

Write-Host "Created: $destination" -ForegroundColor Green
