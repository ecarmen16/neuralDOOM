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
        foreach ($shader in @('ray_query', 'ambient_occlusion', 'contact_shadows', 'visibility_debug', 'material_atlas', 'diffuse_bounce', 'bounce_composite', 'reflections', 'reflection_filter', 'reflection_composite')) {
            if (-not $recorded.ContainsKey("base/renderprogs2/dxil/rt/$shader.cs.dxil") -and
                -not $recorded.ContainsKey("content/renderprogs2/dxil/rt/$shader.cs.dxil")) {
                throw "Build manifest lacks RTX shader identity: $shader. Rebuild before playtesting."
            }
        }
    }
}

function Get-NeuralBuildIdentity {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$BuildDirectory,
        [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
        [string]$Configuration = 'RelWithDebInfo'
    )
    if ([string]::IsNullOrWhiteSpace($BuildDirectory)) { $BuildDirectory = Join-Path $RepoRoot 'build' }
    $BuildDirectory = Resolve-NeuralFullPath $BuildDirectory
    $manifestPath = Join-Path $BuildDirectory "neuraldoom-build-$Configuration.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Missing build manifest. Rebuild with Build-RBDOOM.ps1 before capturing metadata.'
    }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch {
        throw 'Invalid build manifest JSON. Rebuild before capturing metadata.'
    }
    foreach ($field in @('schemaVersion', 'builtAt', 'commit', 'dirty', 'configuration', 'executable', 'sha256', 'features', 'shaders')) {
        if (-not $manifest -or -not $manifest.PSObject.Properties[$field]) { throw "Invalid build manifest: missing $field." }
    }
    $builtAt = [DateTimeOffset]::MinValue
    if (($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long]) -or $manifest.schemaVersion -ne 2 -or
        $manifest.commit -isnot [string] -or $manifest.commit -notmatch '^[0-9a-fA-F]{40}$' -or
        $manifest.dirty -isnot [bool] -or $manifest.configuration -cne $Configuration -or
        $manifest.executable -isnot [string] -or -not [IO.Path]::IsPathRooted($manifest.executable) -or
        $manifest.sha256 -isnot [string] -or $manifest.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        ($manifest.builtAt -isnot [string] -and $manifest.builtAt -isnot [DateTime]) -or
        -not [DateTimeOffset]::TryParse([string]$manifest.builtAt, [ref]$builtAt) -or
        $manifest.features -isnot [pscustomobject] -or $manifest.shaders -isnot [array] -or $manifest.shaders.Count -eq 0) {
        throw 'Invalid build manifest identity. Rebuild before capturing metadata.'
    }
    foreach ($feature in @('dx12', 'vulkan', 'streamline', 'rayTracing')) {
        if (-not $manifest.features.PSObject.Properties[$feature] -or $manifest.features.$feature -cnotin @('ON', 'OFF')) {
            throw "Invalid build manifest feature: $feature."
        }
    }
    $exe = Find-NeuralDoomExecutable -RepoRoot $RepoRoot -Configuration $Configuration -BuildDirectory $BuildDirectory
    if (-not $exe -or [IO.Path]::GetFullPath($manifest.executable) -ne $exe -or
        (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $manifest.sha256) {
        throw 'Executable does not match the selected build manifest. Rebuild before capturing metadata.'
    }
    $paths = @{}
    foreach ($shader in $manifest.shaders) {
        if (-not $shader -or -not $shader.PSObject.Properties['path'] -or -not $shader.PSObject.Properties['sha256'] -or
            $shader.path -isnot [string] -or $shader.path -notmatch '^(base|content)/renderprogs2/(dxil|dxbc|spirv)/[^\\:]+\.(bin|dxil)$' -or
            @($shader.path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or
            $paths.ContainsKey($shader.path) -or $shader.sha256 -isnot [string] -or $shader.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw 'Invalid shader identity in build manifest.'
        }
        $paths[$shader.path] = $true
    }
    Assert-NeuralShaderManifest -RepoRoot $RepoRoot -Manifest $manifest
    $checkoutCommit = (& git -C $RepoRoot rev-parse HEAD 2>$null) -join ''
    if ($LASTEXITCODE -ne 0 -or $checkoutCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Cannot determine checkout revision.' }
    $changes = @(& git -C $RepoRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine checkout worktree state.' }
    $branch = (& git -C $RepoRoot branch --show-current 2>$null) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine checkout branch.' }
    [pscustomobject]@{
        manifest = $manifest; manifestPath = $manifestPath; buildDirectory = $BuildDirectory; executable = $exe
        checkoutCommit = $checkoutCommit.Trim(); checkoutDirty = $changes.Count -gt 0; checkoutBranch = $branch.Trim()
        revisionRelationship = if ($manifest.commit -eq $checkoutCommit.Trim()) { 'same commit' } else { 'different commit (build does not match checkout)' }
    }
}

function Get-NeuralSubmoduleStatus {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $problems = [Collections.Generic.List[string]]::new()
    $state = @{ count = 0 }
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    if (-not (Test-CommandAvailable 'git')) {
        return [pscustomobject]@{ count = 0; problems = @('Git is required to verify submodule repositories.') }
    }
    function Invoke-NeuralSubmoduleGit {
        param([string[]]$ArgumentList)
        # Windows PowerShell 5.1 promotes native stderr to an error even when
        # redirected. Corrupt Git metadata is a failed check, not an early abort.
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $output = @(& git @ArgumentList 2>$null)
        [pscustomobject]@{ output = $output; exitCode = $LASTEXITCODE }
    }
    $query = Invoke-NeuralSubmoduleGit @('-C', $root, 'rev-parse', '--show-toplevel')
    $top = $query.output -join ''
    if ($query.exitCode -ne 0 -or -not $top -or [IO.Path]::GetFullPath($top.Trim()).TrimEnd('\', '/') -ne $root) {
        return [pscustomobject]@{ count = 0; problems = @('Invalid repository root: select the actual project checkout.') }
    }
    function Visit-NeuralSubmodules {
        param([string]$Directory, [string]$Prefix)
        $query = Invoke-NeuralSubmoduleGit @('-C', $Directory, 'ls-files', '--stage')
        if ($query.exitCode -ne 0) { $problems.Add("${Prefix}: cannot read Git index"); return }
        $gitlinks = @{}
        foreach ($entry in $query.output) {
            if ($entry -match '^160000 [0-9a-f]{40} [0-3]\t(.+)$') { $gitlinks[$matches[1]] = $true }
        }
        $modulesFile = Join-Path $Directory '.gitmodules'
        $declarations = @()
        if (Test-Path -LiteralPath $modulesFile -PathType Leaf) {
            $query = Invoke-NeuralSubmoduleGit @('config', '--file', $modulesFile, '--get-regexp', '^submodule\..*\.path$')
            $declarations = @($query.output)
            if ($query.exitCode -notin @(0, 1)) { $problems.Add("${Prefix}: invalid .gitmodules"); return }
        }
        $seen = @{}
        foreach ($declaration in $declarations) {
            $parts = @($declaration -split '\s+', 2)
            $relative = if ($parts.Count -eq 2) { $parts[1].Replace('\', '/') } else { '' }
            $label = $Prefix + $relative
            $state.count++
            if (-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or
                @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or $seen.ContainsKey($relative)) {
                $problems.Add("${label}: invalid declared path"); continue
            }
            $seen[$relative] = $true
            $query = Invoke-NeuralSubmoduleGit @('-C', $Directory, 'ls-files', '--stage', '--', $relative)
            $index = @($query.output)
            if ($query.exitCode -ne 0 -or $index.Count -ne 1 -or $index[0] -notmatch '^160000 ([0-9a-f]{40}) 0\t(.+)$' -or $matches[2] -ne $relative) {
                $problems.Add("${label}: missing pinned gitlink"); continue
            }
            $expected = $matches[1]
            $moduleRoot = Join-Path $Directory $relative
            if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot '.git'))) {
                $problems.Add("${label}: uninitialized or missing"); continue
            }
            $query = Invoke-NeuralSubmoduleGit @('-C', $moduleRoot, 'rev-parse', '--show-toplevel')
            $moduleTop = $query.output -join ''
            if ($query.exitCode -ne 0 -or -not $moduleTop -or
                [IO.Path]::GetFullPath($moduleTop.Trim()).TrimEnd('\', '/') -ne [IO.Path]::GetFullPath($moduleRoot).TrimEnd('\', '/')) {
                $problems.Add("${label}: foreign repository or uninitialized"); continue
            }
            $query = Invoke-NeuralSubmoduleGit @('-C', $moduleRoot, 'rev-parse', 'HEAD')
            $revision = $query.output -join ''
            if ($query.exitCode -ne 0 -or $revision.Trim() -ne $expected) {
                $problems.Add("${label}: revision mismatch (expected $expected)"); continue
            }
            Visit-NeuralSubmodules -Directory $moduleRoot -Prefix ($label + '/')
        }
        foreach ($path in $gitlinks.Keys) {
            if (-not $seen.ContainsKey($path)) { $problems.Add("${Prefix}${path}: missing .gitmodules path declaration") }
        }
    }
    Visit-NeuralSubmodules -Directory $root -Prefix ''
    [pscustomobject]@{ count = $state.count; problems = @($problems.ToArray()) }
}

Enable-NeuralBuildToolPaths
