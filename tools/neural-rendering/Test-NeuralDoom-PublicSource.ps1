[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$AllowDirty,
    [switch]$Staged
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

Push-Location $RepoRoot
try {
    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Not a Git worktree: $RepoRoot"
    }

    $failures = @()
    $trackedFiles = @(& git ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw 'git ls-files failed.'
    }

    $forbiddenLeafNames = @(
        'dxgi.dll',
        'neuraldoom-reshade64.dll',
        'renodx-dlss5.addon64',
        'nvngx_dlss.dll',
        'nvngx_dlssnr.dll',
        'sl.common.dll',
        'sl.dlss.dll',
        'sl.interposer.dll'
    )
    foreach ($trackedFile in $trackedFiles) {
        $normalized = $trackedFile -replace '\\', '/'
        $leaf = Split-Path -Leaf $normalized
        if ($forbiddenLeafNames -contains $leaf.ToLowerInvariant()) {
            $failures += "Tracked local runtime: $trackedFile"
        }
        if ($normalized -match '(?i)(^|/)(captures|releases|neural-local|local-proprietary|local-research|\.neuraldoom-cache|settings-snapshots|mod_D3HDP_Lite)(/|$)') {
            $failures += "Tracked local-only path: $trackedFile"
        }
        if ($normalized -match '(?i)\.(resources?|pk4|rdc)$') {
            $failures += "Tracked game data or capture: $trackedFile"
        }
        if ($leaf -match '(?i)^(D3BFGConfig\.cfg|ReShadePreset\.ini|reshade\.ini|imgui\.ini|profile\.bin|\.neuraldoom-snapshot-.*\.tmp)$') {
            $failures += "Tracked personal settings: $trackedFile"
        }
    }

    $machinePaths = @(
        $RepoRoot,
        [Environment]::GetFolderPath('UserProfile')
    )
    $machinePaths = @($machinePaths | ForEach-Object { $_; $_.Replace('\', '/') } | Select-Object -Unique)
    foreach ($machinePath in $machinePaths) {
        $grepArgs = @('grep', '-I', '-n', '-i', '-F')
        if ($Staged) { $grepArgs += '--cached' }
        $personalPathMatches = @(& git @grepArgs -- $machinePath . 2>$null)
        if ($LASTEXITCODE -eq 0) {
            foreach ($match in $personalPathMatches) {
                $location = ($match -split ':', 3)[0..1] -join ':'
                $failures += "Machine-specific path in tracked text: $location"
            }
        } elseif ($LASTEXITCODE -ne 1) {
            throw 'git grep failed.'
        }
    }

    # Catch paths from other machines as well, allowing documented placeholders.
    $grepArgs = @('grep', '-I', '-n', '-i', '-E')
    if ($Staged) { $grepArgs += '--cached' }
    $profilePattern = '[a-z]:[\\/]+Users[\\/]+[[:alnum:]_.-]+'
    $profileMatches = @(& git @grepArgs -- $profilePattern . 2>$null)
    if ($LASTEXITCODE -eq 0) {
        foreach ($match in $profileMatches) {
            $location = ($match -split ':', 3)[0..1] -join ':'
            $failures += "Personal profile path in tracked text: $location"
        }
    } elseif ($LASTEXITCODE -ne 1) { throw 'Profile-path audit failed.' }

    if (-not $AllowDirty) {
        $dirty = @(& git status --porcelain --untracked-files=all)
        if ($LASTEXITCODE -ne 0) {
            throw 'git status failed.'
        }
        if ($dirty.Count -gt 0) {
            $failures += 'Worktree is not clean. Commit intended source changes and remove or ignore local artifacts.'
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host 'neuralDoom public-source audit: FAIL' -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host " - $failure" -ForegroundColor Red
        }
        exit 1
    }

    Write-Host "neuralDoom public-source audit: PASS ($($trackedFiles.Count) tracked files checked)" -ForegroundColor Green
} finally {
    Pop-Location
}
