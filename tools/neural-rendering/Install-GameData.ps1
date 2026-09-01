[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceBasePath,
    [string]$RepoRoot,
    [switch]$DoNotUpdateGitExclude
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot

if ([string]::IsNullOrWhiteSpace($SourceBasePath)) {
    $programFilesX86 = ${env:ProgramFiles(x86)}
    $programFiles = $env:ProgramFiles
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    if ($programFilesX86) {
        $candidatePaths.Add((Join-Path $programFilesX86 'Steam\steamapps\common\DOOM 3 BFG Edition\base'))
        $candidatePaths.Add((Join-Path $programFilesX86 'GOG Galaxy\Games\DOOM 3 BFG Edition\base'))
    }
    if ($programFiles) {
        $candidatePaths.Add((Join-Path $programFiles 'Steam\steamapps\common\DOOM 3 BFG Edition\base'))
        $candidatePaths.Add((Join-Path $programFiles 'GOG Games\DOOM 3 BFG Edition\base'))
    }
    $candidates = @($candidatePaths | Where-Object { Test-Path $_ })

    if ($candidates.Count -gt 0) {
        Write-Host 'Detected candidate game-data locations:'
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-Host "[$i] $($candidates[$i])"
        }
        $choice = Read-Host 'Choose an index or paste another full base-folder path'
        if ($choice -match '^\d+$' -and [int]$choice -lt $candidates.Count) {
            $SourceBasePath = $candidates[[int]$choice]
        } else {
            $SourceBasePath = $choice
        }
    } else {
        $SourceBasePath = Read-Host 'Enter the full path to your legally owned Doom 3 BFG Edition base folder'
    }
}

$SourceBasePath = Resolve-NeuralFullPath -Path $SourceBasePath.Trim('"')
if (-not (Test-Path $SourceBasePath -PathType Container)) {
    throw "Source base folder does not exist: $SourceBasePath"
}

$resourceFiles = @(Get-ChildItem $SourceBasePath -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.resources', '.resource') })
if ($resourceFiles.Count -eq 0) {
    $continue = Read-Host 'No .resources files were detected. Type COPY to continue anyway'
    if ($continue -cne 'COPY') {
        throw 'Cancelled because the selected folder does not look like a Doom 3 BFG base folder.'
    }
}

$destination = Join-Path $RepoRoot 'base'
New-Item -ItemType Directory -Path $destination -Force | Out-Null

Write-Step 'Copying only missing files; existing RBDOOM files will not be overwritten'
if ($PSCmdlet.ShouldProcess($destination, "Copy missing files from $SourceBasePath")) {
    & robocopy $SourceBasePath $destination /E /XC /XN /XO /R:2 /W:1 /NFL /NDL /NP
    $robocopyExit = $LASTEXITCODE
    if ($robocopyExit -gt 7) {
        throw "robocopy failed with exit code $robocopyExit"
    }
}

if (-not $DoNotUpdateGitExclude) {
    Write-Step 'Adding newly copied untracked data to the repository-local Git exclude file'
    $untracked = @(& git -C $RepoRoot ls-files --others --exclude-standard -- base)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not enumerate untracked base files.'
    }

    $excludeFile = Join-Path $RepoRoot '.git\info\exclude'
    $existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (Test-Path $excludeFile) {
        foreach ($line in Get-Content $excludeFile) {
            [void]$existing.Add($line)
        }
    }
    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $untracked) {
        $normalized = $path.Replace('\', '/')
        if (-not $existing.Contains($normalized)) {
            $additions.Add($normalized)
            [void]$existing.Add($normalized)
        }
    }
    if ($additions.Count -gt 0) {
        Add-Content -Path $excludeFile -Encoding utf8 -Value "`n# Local Doom 3 BFG data added $(Get-Date -Format s)"
        Add-Content -Path $excludeFile -Encoding utf8 -Value $additions
    }
    Write-Host "Locally excluded $($additions.Count) newly copied file(s)."
}

Write-Step 'Checking repository status'
& git -C $RepoRoot status --short
Write-Host "`nGame data remains local. Review status before every commit or archive." -ForegroundColor Yellow
