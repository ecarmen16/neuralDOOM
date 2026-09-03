Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NeuralScriptRoot = $PSScriptRoot

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-NeuralToolPath {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    $pathEntries = @($env:PATH -split ';')
    if ($pathEntries -notcontains $Directory) {
        $env:PATH = "$Directory;$env:PATH"
    }
}

function Enable-NeuralBuildToolPaths {
    Add-NeuralToolPath (Join-Path $env:ProgramFiles 'Git\usr\bin')

    $git = Get-Command 'git' -ErrorAction SilentlyContinue
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        Add-NeuralToolPath (Join-Path $gitRoot 'usr\bin')
    }

    if (-not (Test-CommandAvailable 'cmake')) {
        $programFilesX86 = ${env:ProgramFiles(x86)}
        $vswhere = if ($programFilesX86) {
            Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
        } else { '' }

        if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
            $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
            if ($vsInstall.Trim()) {
                Add-NeuralToolPath (Join-Path $vsInstall.Trim() 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin')
            }
        }
    }
}

function Resolve-NeuralFullPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissing
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if (-not $AllowMissing) {
        throw "Path does not exist: $Path"
    }

    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    if (-not $parent) {
        $parent = (Get-Location).Path
    }
    $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
    return (Join-Path $resolvedParent $leaf)
}

function Get-NeuralPackRoot {
    $candidate = Split-Path -Parent $script:NeuralScriptRoot
    if (Test-Path (Join-Path $candidate 'START_HERE.md')) {
        return (Resolve-Path $candidate).Path
    }
    return $null
}

function Resolve-NeuralRepoRoot {
    param([string]$RepoRoot)

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $resolved = [System.IO.Path]::GetFullPath($RepoRoot)
        if (-not (Test-Path $resolved)) {
            throw "Repository path does not exist: $resolved"
        }
        return $resolved
    }

    # Installed layout: <repo>\tools\neural-rendering\Common.ps1
    $installedCandidate = Split-Path -Parent (Split-Path -Parent $script:NeuralScriptRoot)
    if (Test-Path (Join-Path $installedCandidate '.git')) {
        return (Resolve-Path $installedCandidate).Path
    }

    # Starter-pack layout: read the path written by Bootstrap-NeuralDoom3.ps1.
    $packRoot = Get-NeuralPackRoot
    if ($packRoot) {
        $pathFile = Join-Path $packRoot '.workspace-path.txt'
        if (Test-Path $pathFile) {
            $saved = (Get-Content $pathFile -Raw).Trim()
            if ($saved -and (Test-Path $saved)) {
                return [System.IO.Path]::GetFullPath($saved)
            }
        }
    }

    $default = Join-Path $HOME 'source\NeuralDoom3\RBDOOM-3-BFG'
    if (Test-Path $default) {
        return [System.IO.Path]::GetFullPath($default)
    }

    throw "Could not locate the RBDOOM repository. Run 00-BOOTSTRAP.cmd or pass -RepoRoot explicitly."
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][int[]]$SuccessExitCodes = @(0)
    )

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Find-NeuralDoomExecutable {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Configuration = 'RelWithDebInfo'
    )

    $preferred = @(
        (Join-Path $RepoRoot "build\$Configuration\neuralDoom.exe"),
        (Join-Path $RepoRoot "build\Release\neuralDoom.exe"),
        (Join-Path $RepoRoot 'neuralDoom.exe'),
        (Join-Path $RepoRoot "build\$Configuration\RBDoom3BFG.exe"),
        (Join-Path $RepoRoot "build\Release\RBDoom3BFG.exe"),
        (Join-Path $RepoRoot 'RBDoom3BFG.exe')
    )

    foreach ($candidate in $preferred) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    $buildRoot = Join-Path $RepoRoot 'build'
    if (Test-Path $buildRoot) {
        $found = Get-ChildItem $buildRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('neuralDoom.exe', 'RBDoom3BFG.exe') } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    return $null
}

function Find-RBDoomExecutable {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Configuration = 'RelWithDebInfo'
    )

    return Find-NeuralDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration
}

Enable-NeuralBuildToolPaths
