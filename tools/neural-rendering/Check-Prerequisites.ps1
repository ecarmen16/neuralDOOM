[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$RequireGameData
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot

$results = [System.Collections.Generic.List[object]]::new()
$hardMissing = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param([string]$Item, [string]$Status, [string]$Detail, [bool]$Required = $false)
    $results.Add([pscustomobject]@{
        Item = $Item
        Required = if ($Required) { 'yes' } else { 'no' }
        Status = $Status
        Detail = $Detail
    })
    if ($Required -and $Status -eq 'MISSING') {
        $hardMissing.Add($Item)
    }
}

$windows = try {
    Get-CimInstance Win32_OperatingSystem
} catch {
    $windowsVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Caption = $windowsVersion.ProductName
        BuildNumber = $windowsVersion.CurrentBuildNumber
    }
}
Add-Check 'Windows' 'OK' "$($windows.Caption) build $($windows.BuildNumber)" $true

foreach ($command in @('git', 'cmake', 'codex')) {
    $required = $command -ne 'codex'
    if (Test-CommandAvailable $command) {
        $version = switch ($command) {
            'git' { (& git --version) -join ' ' }
            'cmake' { ((& cmake --version) | Select-Object -First 1) }
            'codex' { ((& codex --version) | Select-Object -First 1) }
        }
        Add-Check $command.ToUpperInvariant() 'OK' $version $required
    } else {
        Add-Check $command.ToUpperInvariant() 'MISSING' 'Not found on PATH; not required for configure/build.' $required
    }
}

$programFilesX86 = ${env:ProgramFiles(x86)}
$vswhere = if ($programFilesX86) { Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe' } else { '' }
if (Test-Path $vswhere) {
    $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
    if ($vsInstall.Trim()) {
        Add-Check 'Visual Studio C++' 'OK' $vsInstall.Trim() $true
    } else {
        Add-Check 'Visual Studio C++' 'MISSING' 'VS was found, but the x64/x86 C++ tools workload was not detected.' $true
    }
} else {
    Add-Check 'Visual Studio C++' 'MISSING' 'vswhere.exe not found; install Visual Studio 2022 with Desktop development with C++.' $true
}

$ispc = Join-Path $RepoRoot 'tools\ispc\bin\ispc.exe'
if (Test-Path $ispc) {
    $ispcVersion = ((& $ispc --version) | Select-Object -First 1)
    Add-Check 'ISPC' 'OK' "$ispcVersion ($ispc)" $true
} else {
    Add-Check 'ISPC' 'MISSING' "Expected at $ispc. Run 02-INSTALL-ISPC.cmd." $true
}

if (Test-CommandAvailable 'nvidia-smi') {
    $gpu = (& nvidia-smi --query-gpu=name,driver_version --format=csv,noheader) -join '; '
    Add-Check 'NVIDIA GPU/driver' 'OK' $gpu $false
} else {
    Add-Check 'NVIDIA GPU/driver' 'WARN' 'nvidia-smi was not found. Baseline compilation can continue; neural experiments require a compatible NVIDIA setup.' $false
}

$base = Join-Path $RepoRoot 'base'
$retailCandidates = @()
if (Test-Path $base) {
    $retailCandidates = @(Get-ChildItem $base -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.resources', '.resource') -or $_.Name -match '^(maps|textures|_common).*resources$' })
}
if ($retailCandidates.Count -gt 0) {
    Add-Check 'Doom 3 BFG data' 'OK' "$($retailCandidates.Count) retail resource candidate(s) found locally under base/." ($RequireGameData.IsPresent)
} else {
    Add-Check 'Doom 3 BFG data' 'MISSING' 'No retail resource files detected. Run 03-COPY-GAME-DATA.cmd before launching.' ($RequireGameData.IsPresent)
}

$missingSubmodules = [System.Collections.Generic.List[string]]::new()
$submoduleCount = 0
$gitModuleFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Filter '.gitmodules' -File -Recurse -Force -ErrorAction SilentlyContinue)
foreach ($gitModuleFile in $gitModuleFiles) {
    $declaredPaths = @(& git config --file $gitModuleFile.FullName --get-regexp path 2>$null)
    foreach ($declaredPath in $declaredPaths) {
        $parts = @($declaredPath -split '\s+', 2)
        if ($parts.Count -lt 2) { continue }
        $submoduleCount++
        $submoduleRoot = Join-Path $gitModuleFile.Directory.FullName $parts[1]
        $insideWorkTree = (& git -C $submoduleRoot rev-parse --is-inside-work-tree 2>$null) -join ''
        if ($LASTEXITCODE -ne 0 -or $insideWorkTree.Trim() -ne 'true') {
            $missingSubmodules.Add($parts[1])
        }
    }
}
if ($submoduleCount -gt 0 -and $missingSubmodules.Count -eq 0) {
    Add-Check 'Git submodules' 'OK' "$submoduleCount declared submodule(s) initialized." $true
} else {
    $detail = if ($missingSubmodules.Count -gt 0) {
        "Missing: $($missingSubmodules -join ', '). Run: git submodule update --init --recursive"
    } else {
        'No initialized submodules detected. Run: git submodule update --init --recursive'
    }
    Add-Check 'Git submodules' 'MISSING' $detail $true
}

Write-Host "`nRepository: $RepoRoot`n"
$results | Format-Table -AutoSize -Wrap

if ($hardMissing.Count -gt 0) {
    Write-Error "Missing required prerequisites: $($hardMissing -join ', ')"
    exit 1
}

Write-Host "`nAll required checks passed." -ForegroundColor Green
