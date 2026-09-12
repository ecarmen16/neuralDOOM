# Upload verified build output without replacing an existing asset.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('^(v[0-9][A-Za-z0-9._-]*|milestone-[0-9][A-Za-z0-9._-]*)$')][string]$Tag,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$ArtifactDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expected = @("neuralDOOM-$Tag.zip", "neuralDOOM-Setup-$Tag.exe")
$names = @($expected + @($expected | ForEach-Object { $_ + '.sha256' }))
$files = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File)
if ($files.Count -ne 4 -or @($files | Where-Object { $_.Name -cnotin $names }).Count) { throw 'Expected only installer, portable ZIP and their checksums.' }
$digests = @{}
foreach ($file in $files) { $digests[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
foreach ($name in $expected) {
    $checksum = (Get-Content -LiteralPath (Join-Path $ArtifactDirectory ($name + '.sha256')) -Raw).Trim()
    if ($checksum -cne ($digests[$name] + '  ' + $name)) { throw "Checksum mismatch: $name" }
}
$remoteCommit = & gh api "repos/$Repository/commits/$Tag" --jq .sha
if ($LASTEXITCODE -ne 0 -or $remoteCommit -ne $SourceCommit) { throw 'Release tag changed during the build.' }
function Find-Release {
    # The tag endpoint returns only published releases. List releases to include
    # drafts visible to this token, and fail closed on lookup errors/duplicates.
    $json = & gh api "repos/$Repository/releases" --paginate --slurp
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect releases; no draft will be created.' }
    $pages = $json | ConvertFrom-Json
    $matchingReleases = @(foreach ($page in $pages) {
        foreach ($item in $page) {
            if ($item.tag_name -ceq $Tag) { $item }
        }
    })
    if ($matchingReleases.Count -gt 1) { throw 'Multiple releases use this tag. Resolve duplicate drafts before uploading.' }
    if ($matchingReleases.Count -eq 1) { return $matchingReleases[0] }
    return $null
}
$release = Find-Release
if ($null -eq $release) {
    $notes = "Source: $SourceCommit. Built on GitHub-hosted Windows from tagged source. Includes native RTX and SDK-enabled engines with corresponding source. Game data, textures and optional runtimes are acquired during installation."
    $notesFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($notesFile, $notes)
        & gh release create $Tag --repo $Repository --draft --verify-tag --title "neuralDOOM $Tag" --notes-file $notesFile
        if ($LASTEXITCODE -ne 0) { throw 'Could not create draft release.' }
    } finally { Remove-Item -LiteralPath $notesFile -Force }
    $release = Find-Release
    if ($null -eq $release) { throw 'Cannot inspect created release.' }
}
$missing = @()
foreach ($file in $files) {
    $existing = @($release.assets | Where-Object { $_.name -ceq $file.Name })
    if ($existing.Count -eq 0) { $missing += $file.FullName; continue }
    if ($existing.Count -ne 1 -or $existing[0].state -ne 'uploaded' -or
        -not $existing[0].PSObject.Properties['digest'] -or
        $existing[0].digest -ine ('sha256:' + $digests[$file.Name])) {
        throw "Existing release asset differs or cannot be verified: $($file.Name). Nothing will be replaced."
    }
}
if ($missing.Count) {
    if ($release.PSObject.Properties['immutable'] -and $release.immutable) { throw 'GitHub has locked this release as immutable; missing assets cannot be attached.' }
    # No --clobber: concurrent uploads or conflicting names must fail safely.
    & gh release upload $Tag --repo $Repository @missing
    if ($LASTEXITCODE -ne 0) { throw 'Could not upload release assets. Retry to verify existing files and upload only missing files.' }
    $verified = Find-Release
    if ($null -eq $verified) { throw 'Could not verify uploaded release assets.' }
    foreach ($file in $files) {
        $asset = @($verified.assets | Where-Object { $_.name -ceq $file.Name })
        if ($asset.Count -ne 1 -or $asset[0].state -ne 'uploaded' -or
            -not $asset[0].PSObject.Properties['digest'] -or
            $asset[0].digest -ine ('sha256:' + $digests[$file.Name])) {
            throw "Uploaded asset verification failed: $($file.Name)"
        }
    }
}
Write-Host "Release assets ready: https://github.com/$Repository/releases/tag/$Tag"
