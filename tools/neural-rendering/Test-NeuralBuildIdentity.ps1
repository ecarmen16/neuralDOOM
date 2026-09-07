[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Resolve-NeuralRepoRoot
$fixture = Join-Path $repo ('captures/neural/build-identity-' + [guid]::NewGuid().ToString('N'))
$tree = Join-Path $fixture 'custom-build'
New-Item -ItemType Directory -Path $tree -Force | Out-Null

# The exact executable is deliberately neither newest nor named neuralDoom.
$exact = Join-Path $tree 'custom-target.exe'
'exact' | Set-Content -LiteralPath $exact
'stale-root' | Set-Content -LiteralPath (Join-Path $fixture 'neuralDoom.exe')
$release = New-Item -ItemType Directory -Path (Join-Path $fixture 'build/Release') -Force
'wrong-config' | Set-Content -LiteralPath (Join-Path $release.FullName 'neuralDoom.exe')
$identity = Join-Path $tree 'neuraldoom-artifact-RelWithDebInfo.txt'
$exact | Set-Content -LiteralPath $identity
if ((Find-NeuralDoomExecutable -RepoRoot $fixture -BuildDirectory $tree) -ne $exact) {
    throw 'Did not select exact CMake target in custom build directory.'
}
(Join-Path $tree 'missing.exe') | Set-Content -LiteralPath $identity
if ($null -ne (Find-NeuralDoomExecutable -RepoRoot $fixture -BuildDirectory $tree)) {
    throw 'Missing exact output silently fell back to a stale executable.'
}
$threw = $false
try { Find-NeuralDoomExecutable -RepoRoot $fixture -BuildDirectory $tree -Configuration Debug } catch { $threw = $true }
if (-not $threw) { throw 'Missing configuration identity was accepted.' }

# Exercise the build script itself: a successful compiler invocation with no
# target must invalidate old success metadata and fail before any staging.
'# fixture cache' | Set-Content -LiteralPath (Join-Path $tree 'CMakeCache.txt')
$oldManifest = Join-Path $tree 'neuraldoom-build-RelWithDebInfo.json'
'{"status":"stale"}' | Set-Content -LiteralPath $oldManifest
function cmake { $global:LASTEXITCODE = 0 }
try {
    $threw = $false
    try {
        & (Join-Path $PSScriptRoot 'Build-RBDOOM.ps1') -RepoRoot $fixture -BuildDirectory $tree
    } catch {
        if ($_.Exception.Message -notlike '*exact configured target executable is missing*') { throw }
        $threw = $true
    }
    if (-not $threw -or (Test-Path -LiteralPath $oldManifest)) { throw 'Build falsely succeeded or retained stale success metadata.' }
} finally {
    Remove-Item Function:\cmake
}

# Cleaning must refuse the repository, source, assets and an unrelated directory.
$source = New-Item -ItemType Directory -Path (Join-Path $fixture 'neo') -Force
$assets = New-Item -ItemType Directory -Path (Join-Path $fixture 'base') -Force
foreach ($unsafePath in @($fixture, $source.FullName, $assets.FullName, $repo)) {
    $threw = $false
    try { Assert-NeuralCleanBuildDirectory -RepoRoot $fixture -BuildDirectory $unsafePath } catch { $threw = $true }
    if (-not $threw) { throw "Unsafe -Clean target accepted: $unsafePath" }
}
@("CMAKE_HOME_DIRECTORY:INTERNAL=$($source.FullName)", "CMAKE_CACHEFILE_DIR:INTERNAL=$tree") |
    Set-Content -LiteralPath (Join-Path $tree 'CMakeCache.txt')
Assert-NeuralCleanBuildDirectory -RepoRoot $fixture -BuildDirectory $tree
# Validation only: never delete even the accepted fixture.

# Parser errors must fail, including inability to invoke the parser itself.
foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "$($script.Name): $parseErrors" }
}
Write-Host 'PASS: exact target, stale-output rejection, configuration isolation, safe clean targets, PowerShell syntax.'
Write-Host "Fixtures retained at $fixture"
