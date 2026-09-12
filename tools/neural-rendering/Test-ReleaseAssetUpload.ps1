# Offline regression coverage: the real uploader runs against a fake GitHub CLI.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('release-upload-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
$commit = '0123456789012345678901234567890123456789'
$global:releaseUploadTestState = @{ remoteCommit = $commit; release = $null; uploads = @(); creates = 0 }
function gh {
    $commandArgs = @($args)
    $global:LASTEXITCODE = 0
    if ($commandArgs[0] -eq 'api') {
        if ($commandArgs[1] -like '*/commits/*') { return $global:releaseUploadTestState.remoteCommit }
        if ($null -eq $global:releaseUploadTestState.release) { $global:LASTEXITCODE = 1; return }
        return ($global:releaseUploadTestState.release | ConvertTo-Json -Depth 10)
    }
    if ($commandArgs[1] -eq 'create') {
        if ('--draft' -notin $commandArgs -or '--verify-tag' -notin $commandArgs) { throw 'Missing draft/tag safeguard.' }
        $global:releaseUploadTestState.creates++
        $global:releaseUploadTestState.release = @{ draft = $true; immutable = $false; assets = @() }
        return
    }
    if ($commandArgs[1] -eq 'upload') {
        if ('--clobber' -in $commandArgs) { throw 'Must never overwrite assets.' }
        foreach ($path in $commandArgs[5..($commandArgs.Count - 1)]) {
            $global:releaseUploadTestState.uploads += $path
            $global:releaseUploadTestState.release.assets += @{ name = [IO.Path]::GetFileName($path); state = 'uploaded'; digest = 'sha256:' + (Get-FileHash -LiteralPath $path).Hash }
        }
        return
    }
    throw 'Unexpected CLI command.'
}
function Invoke-Case([string]$Name, [int]$Count, [string]$ErrorPattern = '') {
    $global:releaseUploadTestState.uploads = @()
    $caught = ''
    try {
        & "$PSScriptRoot/Publish-ReleaseAssets.ps1" -Repository fixture/repo -Tag v1.0.0 -SourceCommit $commit -ArtifactDirectory $fixture
    } catch { $caught = $_.Exception.Message }
    if ($ErrorPattern) {
        if ($caught -notlike $ErrorPattern) { throw "${Name}: wrong failure: $caught" }
    } elseif ($caught) { throw "${Name}: $caught" }
    if ($global:releaseUploadTestState.uploads.Count -ne $Count) { throw "${Name}: expected $Count uploads, got $($global:releaseUploadTestState.uploads.Count)" }
    Write-Host "PASS: $Name"
}
try {
    foreach ($name in @('neuralDOOM-v1.0.0.zip', 'neuralDOOM-Setup-v1.0.0.exe')) {
        $path = Join-Path $fixture $name
        [IO.File]::WriteAllText($path, 'fixture payload')
        [IO.File]::WriteAllText(($path + '.sha256'), ((Get-FileHash -LiteralPath $path).Hash + '  ' + $name))
    }
    Invoke-Case 'Create missing draft' 4
    if ($global:releaseUploadTestState.creates -ne 1) { throw 'Expected one draft creation.' }
    Invoke-Case 'Retry complete draft without extra local files' 0
    $global:releaseUploadTestState.release.draft = $false
    Invoke-Case 'Complete published release' 0
    $global:releaseUploadTestState.release.assets = @($global:releaseUploadTestState.release.assets[0])
    Invoke-Case 'Resume partial published release' 3
    $global:releaseUploadTestState.release.assets = @()
    Invoke-Case 'Empty published release' 4
    $global:releaseUploadTestState.release.immutable = $true
    Invoke-Case 'Complete immutable release' 0
    $global:releaseUploadTestState.release.assets = @($global:releaseUploadTestState.release.assets[0])
    Invoke-Case 'Incomplete immutable release' 0 '*immutable*'
    $global:releaseUploadTestState.release.immutable = $false
    $global:releaseUploadTestState.release.assets[0].digest = 'sha256:different'
    Invoke-Case 'Conflicting asset prevents all uploads' 0 '*differs or cannot be verified*'
    $global:releaseUploadTestState.release.assets[0].Remove('digest')
    Invoke-Case 'Missing remote digest' 0 '*differs or cannot be verified*'
    $global:releaseUploadTestState.remoteCommit = 'changed'
    Invoke-Case 'Moved tag' 0 '*tag changed*'
    $global:releaseUploadTestState.remoteCommit = $commit
    [IO.File]::WriteAllText((Join-Path $fixture 'extra.txt'), 'unexpected')
    Invoke-Case 'Extra artifact' 0 '*Expected only*'
    Remove-Item -LiteralPath (Join-Path $fixture 'extra.txt')
    [IO.File]::WriteAllText((Join-Path $fixture 'neuralDOOM-v1.0.0.zip.sha256'), 'bad checksum')
    Invoke-Case 'Bad checksum' 0 '*Checksum mismatch*'
} finally {
    # Only remove the uniquely created fixture directory under the temp root.
    if ((Split-Path $fixture -Parent) -ne ([IO.Path]::GetTempPath()).TrimEnd('\') -or
        (Split-Path $fixture -Leaf) -notlike 'release-upload-*') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
    Remove-Variable -Name releaseUploadTestState -Scope Global
}
