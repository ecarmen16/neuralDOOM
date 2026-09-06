[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = Join-Path (Resolve-Path -LiteralPath $RepoRoot).Path 'base'
$packPath = Join-Path $base '_rbdoom_global_illumination_data.pk4'
$packBytes = if (Test-Path -LiteralPath $packPath -PathType Leaf) { (Get-Item -LiteralPath $packPath).Length } else { 0 }
$looseImages = @(
    foreach ($relative in @('env', 'generated/images/env')) {
        $directory = Join-Path $base $relative
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Get-ChildItem -LiteralPath $directory -File -Recurse |
                Where-Object { $_.Extension -in @('.exr', '.bimage') }
        }
    }
)
$hasCandidates = $packBytes -gt 0 -or $looseImages.Count -gt 0
$detail = if ($hasCandidates) {
    "Lighting candidates: official-name pack $packBytes bytes; $($looseImages.Count) loose image(s). Run probeLightingStatus in a loaded map to verify coverage."
} else {
    'No map-lighting candidates found. The engine can use its built-in lobby probe. See docs/neural-rendering/PROBE_LIGHTING.md for the optional RBDOOM lighting pack.'
}
[pscustomobject]@{
    hasCandidates = $hasCandidates; packPath = $packPath; packBytes = $packBytes
    looseImages = $looseImages.Count; detail = $detail
}
