[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourcePath,
    [string]$RepoRoot
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Read-Host 'Enter the full path to ispc.exe or the downloaded ISPC Windows ZIP'
}
$SourcePath = Resolve-NeuralFullPath -Path $SourcePath.Trim('"')
if (-not (Test-Path $SourcePath)) {
    throw "Source does not exist: $SourcePath"
}

$temp = $null
try {
    if ([System.IO.Path]::GetExtension($SourcePath) -ieq '.zip') {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("NeuralDoom3-ispc-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Write-Step "Extracting $SourcePath"
        Expand-Archive -Path $SourcePath -DestinationPath $temp -Force
        $candidate = Get-ChildItem $temp -Filter 'ispc.exe' -File -Recurse | Select-Object -First 1
        if (-not $candidate) {
            throw 'The ZIP did not contain ispc.exe.'
        }
        $sourceExe = $candidate.FullName
    } elseif ([System.IO.Path]::GetFileName($SourcePath) -ieq 'ispc.exe') {
        $sourceExe = $SourcePath
    } else {
        throw 'Source must be ispc.exe or a ZIP containing ispc.exe.'
    }

    $destination = Join-Path $RepoRoot 'tools\ispc\bin\ispc.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    if ($PSCmdlet.ShouldProcess($destination, "Copy $sourceExe")) {
        Copy-Item $sourceExe $destination -Force
    }

    Write-Step 'Verifying ISPC'
    & $destination --version
    if ($LASTEXITCODE -ne 0) {
        throw 'Installed ispc.exe did not execute successfully.'
    }
    Write-Host "Installed: $destination" -ForegroundColor Green
} finally {
    if ($temp -and (Test-Path $temp)) {
        Remove-Item $temp -Recurse -Force
    }
}
