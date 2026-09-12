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
$releaseJson = & gh api "repos/$Repository/releases/tags/$Tag" 2>$null
if ($LASTEXITCODE -ne 0) {
    $notes = "Source: $SourceCommit. Built on GitHub-hosted Windows from tagged source. Includes native RTX and SDK-enabled engines with corresponding source. Game data, textures and optional runtimes are acquired during installation."
    $notesFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($notesFile, $notes)
        & gh release create $Tag --repo $Repository --draft --verify-tag --title "neuralDOOM $Tag" --notes-file $notesFile
        if ($LASTEXITCODE -ne 0) { throw 'Could not create draft release.' }
    } finally { Remove-Item -LiteralPath $notesFile -Force }
    $releaseJson = & gh api "repos/$Repository/releases/tags/$Tag"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect created release.' }
}
$release = $releaseJson | ConvertFrom-Json
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
    $verifiedJson = & gh api "repos/$Repository/releases/tags/$Tag"
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify uploaded release assets.' }
    $verified = $verifiedJson | ConvertFrom-Json
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
