[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$ExpectedSamples,
    [Parameter(Mandatory)][int]$Width,
    [Parameter(Mandatory)][int]$Height
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$rows = @(Import-Csv -LiteralPath $Path)
if ($rows.Count -ne $ExpectedSamples) { throw "GPU profile has $($rows.Count) samples; expected $ExpectedSamples." }
$columns = @($rows[0].PSObject.Properties.Name | Where-Object { $_ -like 'MRB_*_us' })
if ($columns -notcontains 'MRB_GPU_TIME_us') { throw 'GPU profile is missing total GPU time.' }
$lastFrame = -1L
foreach ($row in $rows) {
    if ([int]$row.width -ne $Width -or [int]$row.height -ne $Height) { throw 'GPU profile resolution changed.' }
    $frame = [long]::Parse($row.query_frame, $culture)
    if ($frame -le $lastFrame) { throw 'GPU profile contains repeated or unordered frames.' }
    $lastFrame = $frame
}
$passes = [ordered]@{}
foreach ($column in $columns) {
    $values = @(
        foreach ($row in $rows) {
            if ([string]::IsNullOrWhiteSpace($row.$column)) {
                if ($column -eq 'MRB_GPU_TIME_us') { throw 'GPU profile is missing a total GPU sample.' }
                continue
            }
            $value = [double]::Parse($row.$column, $culture)
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or ($column -eq 'MRB_GPU_TIME_us' -and $value -eq 0)) { throw "Invalid GPU timing in $column." }
            $value / 1000.0
        }
    ) | Sort-Object
    $values = @($values)
    $median = $null; $p95 = $null
    if ($values.Count -gt 0) {
        $middle = [int][math]::Floor($values.Count / 2)
        $median = if ($values.Count % 2 -eq 0) { ($values[$middle - 1] + $values[$middle]) / 2 } else { $values[$middle] }
        $p95 = $values[[int][math]::Ceiling(0.95 * $values.Count) - 1]
    }
    $passes[$column] = [ordered]@{ measuredSamples = $values.Count; missingSamples = $rows.Count - $values.Count; medianMs = $median; p95Ms = $p95 }
}
[pscustomobject]@{
    samples = $rows.Count; csv = (Resolve-Path -LiteralPath $Path).Path
    firstQueryFrame = [long]$rows[0].query_frame; lastQueryFrame = $lastFrame
    passes = $passes
    scope = 'Graphics queue GPU timers; first occurrence per named block per frame. Passes may overlap; do not sum. SSR shading is integrated and has no standalone timer. This is not end-to-end frame latency or FPS.'
}
