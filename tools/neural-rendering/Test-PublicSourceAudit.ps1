# Exercise the real audit under ordinary and neutral drive-root checkouts.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$audit = Join-Path $PSScriptRoot 'Test-NeuralDoom-PublicSource.ps1'
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../../captures/neural/public-audit-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
& git -C $fixture init --quiet
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize audit fixture.' }
$drive = @('R:', 'S:', 'T:', 'U:', 'V:', 'W:') | Where-Object { -not (Test-Path ($_ + '\')) } | Select-Object -First 1
if (-not $drive) { throw 'No free drive for neutral-root audit regression.' }
$sample = Join-Path $fixture 'sample.txt'
function Put-Sample([string]$Text) {
    [IO.File]::WriteAllText($sample, $Text)
    & git -C $fixture add -- sample.txt
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage fixture.' }
}
function Assert-Audit([string]$Root, [int]$Expected, [string]$Reason, [switch]$Staged) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $audit, '-RepoRoot', $Root, '-AllowDirty')
    if ($Staged) { $arguments += '-Staged' }
    $output = @(& powershell.exe @arguments 2>&1)
    if ($LASTEXITCODE -ne $Expected -or ($Expected -ne 0 -and ($output -join "`n") -notmatch $Reason)) {
        throw "Unexpected audit result for $Reason`: $($output -join "`n")"
    }
}
$mapped = $false
try {
    & subst $drive $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Cannot map audit fixture.' }
    $mapped = $true
    $neutralRoot = $drive + '\'
    Put-Sample ('neutral build ' + $neutralRoot + 'tools/build.ps1' + "`n" + 'buffer:\n')
    Assert-Audit $fixture 0 'ordinary clean text'
    Assert-Audit $neutralRoot 0 'neutral drive root'
    Assert-Audit $neutralRoot 0 'neutral drive root staged' -Staged

    Put-Sample (Join-Path $fixture 'private.txt')
    Assert-Audit $fixture 1 'Machine-specific path'
    Put-Sample ($fixture.Replace('\', '/') + '/private.txt')
    Assert-Audit $fixture 1 'Machine-specific path' -Staged

    Put-Sample (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'private.txt')
    Assert-Audit $neutralRoot 1 'Machine-specific path'
    Assert-Audit $neutralRoot 1 'Machine-specific path' -Staged
    # Build the fake foreign profile at runtime so the test source has no
    # literal profile path for the repository's own audit to reject.
    Put-Sample ('C:' + '/' + 'Users' + '/' + 'audit-fixture-person' + '/private.txt')
    Assert-Audit $neutralRoot 1 'Personal profile path'

    Put-Sample 'clean staged content'
    [IO.File]::WriteAllText($sample, (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'private.txt'))
    Assert-Audit $neutralRoot 0 'staged audit ignores unstaged text' -Staged
    Assert-Audit $neutralRoot 1 'Machine-specific path'

    Put-Sample 'clean content'
    [IO.File]::WriteAllText((Join-Path $fixture 'dxgi.dll'), 'text fixture, not a runtime')
    & git -C $fixture add -- dxgi.dll
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage forbidden-name fixture.' }
    Assert-Audit $neutralRoot 1 'Tracked local runtime'
    Write-Host 'PASS: neutral-root and ordinary audits, private/foreign paths, staged isolation and runtime-name rejection.'
} finally {
    if ($mapped) { & subst $drive /D }
}
