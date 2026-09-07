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
        [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
        [string]$Configuration = 'RelWithDebInfo',
        [string]$BuildDirectory
    )
    if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
        $BuildDirectory = Join-Path $RepoRoot 'build'
    }
    $artifactFile = Join-Path $BuildDirectory "neuraldoom-artifact-$Configuration.txt"
    if (-not (Test-Path -LiteralPath $artifactFile -PathType Leaf)) {
        throw "Missing CMake artifact identity: $artifactFile. Reconfigure this build tree first."
    }
    $candidate = (Get-Content -LiteralPath $artifactFile -Raw).Trim()
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    return $null
}

function Find-RBDoomExecutable {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Configuration = 'RelWithDebInfo',
        [string]$BuildDirectory
    )
    return Find-NeuralDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration -BuildDirectory $BuildDirectory
}

function Get-NeuralShaderManifest {
    param([Parameter(Mandatory)][string]$RepoRoot, [bool]$RayTracing = $false,
        [string[]]$Formats = @('dxil'), [string]$ContentDirectory = 'base')
    foreach ($format in $Formats) {
        $relativeRoot = "$ContentDirectory/renderprogs2/$format"
        $shaderRoot = Join-Path $RepoRoot $relativeRoot
        $files = @(Get-ChildItem -LiteralPath $shaderRoot -File -Recurse | Where-Object {
            $_.Extension -in @('.bin', '.dxil') -and ($RayTracing -or $_.Directory.Name -ne 'rt')
        } | Sort-Object FullName)
        if ($files.Count -eq 0) { throw "Missing compiled shaders: $relativeRoot" }
        foreach ($file in $files) {
            if ($file.Length -eq 0) { throw "Empty compiled shader: $($file.FullName)" }
            [pscustomobject]@{
                path = $relativeRoot + '/' + $file.FullName.Substring($shaderRoot.Length + 1).Replace('\', '/')
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            }
        }
    }
}

function Assert-NeuralCleanBuildDirectory {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$BuildDirectory)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($BuildDirectory).TrimEnd('\', '/')
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $target -eq (Join-Path $root 'neo')) {
        throw '-Clean requires a dedicated build directory inside the repository.'
    }
    # Do not follow redirected directories or remove an arbitrary asset/source folder.
    for ($entry = Get-Item -LiteralPath $target; $entry.FullName -ne $root; $entry = $entry.Parent) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '-Clean refuses redirected directories.' }
    }
    $cachePath = Join-Path $target 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { throw '-Clean requires an existing CMake build cache.' }
    $cacheText = Get-Content -LiteralPath $cachePath -Raw
    $source = [regex]::Match($cacheText, '(?m)^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)\r?$')
    $directory = [regex]::Match($cacheText, '(?m)^CMAKE_CACHEFILE_DIR:INTERNAL=(.+)\r?$')
    if (-not $source.Success -or -not $directory.Success -or
        [IO.Path]::GetFullPath($source.Groups[1].Value.Trim()) -ne (Join-Path $root 'neo') -or
        [IO.Path]::GetFullPath($directory.Groups[1].Value.Trim()) -ne $target) {
        throw "-Clean requires this repository's CMake cache in its original build directory."
    }
}

function Assert-NeuralShaderManifest {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Manifest)
    # A matching EXE alone cannot establish the ABI of shared loose shader files.
    if (-not $Manifest.PSObject.Properties['schemaVersion'] -or $Manifest.schemaVersion -ne 2 -or
        -not $Manifest.PSObject.Properties['shaders'] -or @($Manifest.shaders).Count -eq 0) {
        throw 'Build manifest lacks shader identity. Rebuild with Build-RBDOOM.ps1 before playtesting.'
    }
    $rootPrefix = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $recorded = @{}
    foreach ($shader in $Manifest.shaders) {
        $path = [IO.Path]::GetFullPath((Join-Path $RepoRoot $shader.path))
        if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or $recorded.ContainsKey($shader.path)) {
            throw 'Invalid shader path in build manifest. Rebuild before playtesting.'
        }
        $recorded[$shader.path] = $true
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $shader.sha256) {
            throw "Shader does not match its build manifest: $($shader.path). Rebuild the selected profile before playtesting."
        }
    }
    if ($Manifest.features.rayTracing -eq 'ON') {
        foreach ($shader in @('ray_query', 'ambient_occlusion', 'contact_shadows', 'visibility_debug', 'material_atlas', 'diffuse_bounce', 'bounce_composite')) {
            if (-not $recorded.ContainsKey("base/renderprogs2/dxil/rt/$shader.cs.dxil") -and
                -not $recorded.ContainsKey("content/renderprogs2/dxil/rt/$shader.cs.dxil")) {
                throw "Build manifest lacks RTX shader identity: $shader. Rebuild before playtesting."
            }
        }
    }
}

Enable-NeuralBuildToolPaths
