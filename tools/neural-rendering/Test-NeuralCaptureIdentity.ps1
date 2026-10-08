[CmdletBinding()]
param([string]$Case = '*')

. (Join-Path $PSScriptRoot 'Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('neuraldoom-identity-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$failed = [Collections.Generic.List[string]]::new()
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    if ($Name -notlike $Case) { return }
    try { & $Body; Write-Host "PASS: $Name" } catch { $failed.Add($Name); Write-Host "FAIL: ${Name}: $($_.Exception.Message)" }
}
function Expect-Rejection {
    param([scriptblock]$Body, [string]$Pattern)
    try { & $Body | Out-Null } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        return
    }
    throw 'Invalid build identity was accepted.'
}
try {
    Invoke-NativeChecked git @('init', '--quiet', $fixture)
    'initial-source' | Set-Content -LiteralPath (Join-Path $fixture 'source.txt')
    Invoke-NativeChecked git @('-C', $fixture, 'add', 'source.txt')
    Invoke-NativeChecked git @('-C', $fixture, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'initial fixture')
    $builtCommit = (& git -C $fixture rev-parse HEAD).Trim()
    $build = Join-Path $fixture 'build'
    $selectedBuild = Join-Path $fixture 'build-selected'
    $shaderRoot = Join-Path $fixture 'base/renderprogs2/dxil'
    New-Item -ItemType Directory -Path $build, $selectedBuild, $shaderRoot | Out-Null
    '/build*/', '/base/', '/captures/' | Set-Content -LiteralPath (Join-Path $fixture '.git/info/exclude')
    $exe = Join-Path $build 'fixture.exe'
    'old-executable' | Set-Content -LiteralPath $exe
    'compiled-shader' | Set-Content -LiteralPath (Join-Path $shaderRoot 'fixture.cs.dxil')
    $exe | Set-Content -LiteralPath (Join-Path $build 'neuraldoom-artifact-RelWithDebInfo.txt')
    $manifestPath = Join-Path $build 'neuraldoom-build-RelWithDebInfo.json'
    $manifest = [ordered]@{
        schemaVersion = 2; builtAt = '2026-10-07T00:00:00Z'; commit = $builtCommit; dirty = $false
        configuration = 'RelWithDebInfo'; executable = $exe; sha256 = (Get-FileHash -LiteralPath $exe).Hash
        features = @{ dx12 = 'ON'; vulkan = 'OFF'; streamline = 'OFF'; rayTracing = 'OFF' }
        shaders = @(@{ path = 'base/renderprogs2/dxil/fixture.cs.dxil'; sha256 = (Get-FileHash -LiteralPath (Join-Path $shaderRoot 'fixture.cs.dxil')).Hash })
    }
    function Write-Manifest { $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath }
    function Capture-Metadata {
        param([string]$Directory = $build)
        & (Join-Path $PSScriptRoot 'Capture-BaselineMetadata.ps1') -RepoRoot $fixture -BuildDirectory $Directory | Out-Null
        $output = Get-ChildItem -LiteralPath (Join-Path $fixture 'captures/neural') -Filter baseline-metadata.md -Recurse |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        Get-Content -LiteralPath $output.FullName -Raw
    }
    Write-Manifest
    Test-Case 'verified-default-build' {
        $text = Capture-Metadata
        if ($text -notmatch "Build commit: $builtCommit" -or $text -notmatch 'Build dirty: False' -or $text -notmatch 'Revision relationship: same commit') { throw 'Verified build provenance is absent.' }
    }
    'new-checkout-source' | Set-Content -LiteralPath (Join-Path $fixture 'source.txt')
    Invoke-NativeChecked git @('-C', $fixture, 'add', 'source.txt')
    Invoke-NativeChecked git @('-C', $fixture, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'new checkout')
    $checkoutCommit = (& git -C $fixture rev-parse HEAD).Trim()
    Test-Case 'stale-build-does-not-claim-checkout-revision' {
        # Use the default directory so this regression also runs against the old script.
        & (Join-Path $PSScriptRoot 'Capture-BaselineMetadata.ps1') -RepoRoot $fixture | Out-Null
        $output = Get-ChildItem -LiteralPath (Join-Path $fixture 'captures/neural') -Filter baseline-metadata.md -Recurse | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $text = Get-Content -LiteralPath $output.FullName -Raw
        if ($text -notmatch "Build commit: $builtCommit" -or $text -notmatch "Checkout commit: $checkoutCommit" -or $text -notmatch 'Revision relationship: different commit') { throw 'Capture labels the checkout revision as the stale build revision.' }
    }
    Test-Case 'explicit-build-directory' {
        $selectedExe = Join-Path $selectedBuild 'selected.exe'
        'selected-executable' | Set-Content -LiteralPath $selectedExe
        $selectedExe | Set-Content -LiteralPath (Join-Path $selectedBuild 'neuraldoom-artifact-RelWithDebInfo.txt')
        $selected = @{}; foreach ($key in $manifest.Keys) { $selected[$key] = $manifest[$key] }
        $selected.executable = $selectedExe; $selected.sha256 = (Get-FileHash -LiteralPath $selectedExe).Hash
        $selected | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $selectedBuild 'neuraldoom-build-RelWithDebInfo.json')
        if ((Capture-Metadata $selectedBuild) -notmatch [regex]::Escape("Executable: $selectedExe")) { throw 'Wrong build selected.' }
    }
    Test-Case 'dirty-build-and-dirty-checkout-distinguished' {
        $manifest.dirty = $true; Write-Manifest
        'uncommitted-checkout' | Set-Content -LiteralPath (Join-Path $fixture 'source.txt')
        $text = Capture-Metadata
        if ($text -notmatch 'Build dirty: True' -or $text -notmatch 'Checkout dirty: True' -or $text -notmatch 'uncommitted build changes are not identified') { throw 'Dirty provenance was overstated.' }
        $manifest.dirty = $false; Write-Manifest
    }
    Test-Case 'missing-manifest-rejected' {
        Remove-Item -LiteralPath $manifestPath
        Expect-Rejection { Capture-Metadata } '*Missing build manifest*'
        Write-Manifest
    }
    Test-Case 'changed-executable-rejected' {
        'tampered-executable' | Set-Content -LiteralPath $exe
        Expect-Rejection { Capture-Metadata } '*Executable does not match*'
        'old-executable' | Set-Content -LiteralPath $exe
    }
    Test-Case 'changed-shader-rejected' {
        'tampered-shader' | Set-Content -LiteralPath (Join-Path $shaderRoot 'fixture.cs.dxil')
        Expect-Rejection { Capture-Metadata } '*Shader does not match*'
        'compiled-shader' | Set-Content -LiteralPath (Join-Path $shaderRoot 'fixture.cs.dxil')
    }
    Test-Case 'malformed-manifest-rejected' {
        foreach ($field in @('schemaVersion', 'builtAt', 'commit', 'dirty', 'sha256', 'configuration', 'features', 'shaders')) {
            $saved = $manifest[$field]
            $manifest[$field] = 'invalid'; Write-Manifest
            Expect-Rejection { Capture-Metadata } '*Invalid build manifest*'
            $manifest[$field] = $saved
        }
        Write-Manifest
    }
    Test-Case 'incomplete-and-invalid-json-manifest-rejected' {
        '{ broken json' | Set-Content -LiteralPath $manifestPath
        Expect-Rejection { Capture-Metadata } '*Invalid build manifest JSON*'
        '{}' | Set-Content -LiteralPath $manifestPath
        Expect-Rejection { Capture-Metadata } '*Invalid build manifest*'
        Write-Manifest
    }
    Test-Case 'malformed-and-duplicate-shader-identity-rejected' {
        $saved = $manifest.shaders
        $manifest.shaders = @(@{ path = 'base/renderprogs2/dxil/fixture.cs.dxil'; sha256 = 'invalid' }); Write-Manifest
        Expect-Rejection { Capture-Metadata } '*Invalid shader*'
        $manifest.shaders = @($saved[0], $saved[0]); Write-Manifest
        Expect-Rejection { Capture-Metadata } '*Invalid shader*'
        $manifest.shaders = $saved; Write-Manifest
    }
    Test-Case 'shader-path-escape-rejected' {
        $saved = $manifest.shaders
        $manifest.shaders = @(@{ path = '../outside.dxil'; sha256 = ('A' * 64) }); Write-Manifest
        Expect-Rejection { Capture-Metadata } '*Invalid shader*'
        $manifest.shaders = $saved; Write-Manifest
    }
    Test-Case 'rt-manifest-with-incomplete-shaders-rejected' {
        $manifest.features.rayTracing = 'ON'; Write-Manifest
        Expect-Rejection { Capture-Metadata } '*Build manifest lacks RTX shader identity*'
        $manifest.features.rayTracing = 'OFF'; Write-Manifest
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'neuraldoom-identity-*') { throw 'Unsafe fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if ($failed.Count) { throw "Build identity failures: $($failed -join ', ')" }
