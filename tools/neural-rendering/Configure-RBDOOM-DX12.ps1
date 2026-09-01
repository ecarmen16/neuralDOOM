[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot,
    [string]$BuildDirectory,
    [switch]$Clean,
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$DxcDirectory
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $RepoRoot 'build'
}
$BuildDirectory = Resolve-NeuralFullPath -Path $BuildDirectory -AllowMissing

foreach ($required in @('git', 'cmake')) {
    if (-not (Test-CommandAvailable $required)) {
        throw "$required is not available on PATH."
    }
}

$ispc = Join-Path $RepoRoot 'tools\ispc\bin\ispc.exe'
if (-not (Test-Path $ispc)) {
    throw "ISPC is missing at $ispc. Run Install-ISPC.ps1 first."
}

if ([string]::IsNullOrWhiteSpace($DxcDirectory)) {
    $windowsKitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $dxc = Get-ChildItem -LiteralPath $windowsKitsBin -Filter 'dxc.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '\\x64$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($dxc) {
        $DxcDirectory = $dxc.DirectoryName
    }
}
if (-not $DxcDirectory -or -not (Test-Path -LiteralPath (Join-Path $DxcDirectory 'dxc.exe'))) {
    throw 'DXC with SPIR-V support was not found. Install a current Windows SDK or pass -DxcDirectory.'
}

if ($Clean -and (Test-Path $BuildDirectory)) {
    if ($PSCmdlet.ShouldProcess($BuildDirectory, 'Remove existing build directory')) {
        Remove-Item $BuildDirectory -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $BuildDirectory -Force | Out-Null

$args = @(
    '-S', (Join-Path $RepoRoot 'neo'),
    '-B', $BuildDirectory,
    '-G', $Generator,
    '-A', 'x64',
    '-DFFMPEG=OFF',
    '-DBINKDEC=ON',
    '-DUSE_DX12=ON',
    '-DUSE_VULKAN=OFF',
    '-DCMAKE_CXX_FLAGS=/wd4530',
    "-DDXC_CUSTOM_PATH=$DxcDirectory"
)

Write-Step 'Configuring RBDOOM-3-BFG for VS2022 x64, DX12 only'
Write-Host "cmake $($args -join ' ')"
Invoke-NativeChecked 'cmake' $args

$docs = Join-Path $RepoRoot 'docs\neural-rendering'
if (Test-Path $docs) {
    @(
        "Configured: $(Get-Date -Format o)",
        "Repository: $RepoRoot",
        "Build directory: $BuildDirectory",
        "Command: cmake $($args -join ' ')"
    ) | Set-Content (Join-Path $docs 'LAST_CONFIGURE.txt') -Encoding utf8
}

Write-Host "Configured build tree: $BuildDirectory" -ForegroundColor Green
