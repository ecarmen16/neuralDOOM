[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Join-Path $HOME 'source\NeuralDoom3'),
    [string]$RepoUrl = 'https://github.com/RobertBeckebans/RBDOOM-3-BFG.git',
    [string]$Branch = 'feature/neural-rendering-spike',
    [switch]$AllowDirty
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$packRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $packRoot 'START_HERE.md'))) {
    throw 'Bootstrap must be run from the extracted NeuralDoom3 starter pack.'
}

if (-not (Test-CommandAvailable 'git')) {
    throw 'Git is not available on PATH. Install Git for Windows, then rerun.'
}

$WorkspaceRoot = Resolve-NeuralFullPath -Path $WorkspaceRoot -AllowMissing
$repoRoot = Join-Path $WorkspaceRoot 'RBDOOM-3-BFG'
New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null

if (-not (Test-Path $repoRoot)) {
    Write-Step "Cloning RBDOOM-3-BFG recursively into $repoRoot"
    Invoke-NativeChecked 'git' @('clone', '--recursive', $RepoUrl, $repoRoot)
} elseif (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    throw "Destination exists but is not a Git repository: $repoRoot"
} else {
    Write-Step "Using existing repository at $repoRoot"
}

$status = (& git -C $repoRoot status --porcelain) -join "`n"
if ($status -and -not $AllowDirty) {
    throw "The repository is dirty. Commit/stash changes or rerun with -AllowDirty after reviewing them.`n$status"
}

Write-Step 'Initializing/updating checked-out submodules without changing the upstream branch tip'
Invoke-NativeChecked 'git' @('-C', $repoRoot, 'submodule', 'update', '--init', '--recursive')

$branchExists = ((& git -C $repoRoot branch --list $Branch) -join '').Trim()
if ($branchExists) {
    Write-Step "Switching to existing branch $Branch"
    Invoke-NativeChecked 'git' @('-C', $repoRoot, 'switch', $Branch)
} else {
    Write-Step "Creating branch $Branch"
    Invoke-NativeChecked 'git' @('-C', $repoRoot, 'switch', '-c', $Branch)
}

$docsDestination = Join-Path $repoRoot 'docs\neural-rendering'
$toolsDestination = Join-Path $repoRoot 'tools\neural-rendering'
New-Item -ItemType Directory -Path $docsDestination -Force | Out-Null
New-Item -ItemType Directory -Path $toolsDestination -Force | Out-Null

Write-Step 'Installing Codex instructions and development documents into the clone'
$targetAgents = Join-Path $repoRoot 'AGENTS.md'
$starterAgents = Get-Content (Join-Path $packRoot 'AGENTS.md') -Raw
$marker = '# Neural Doom 3 project instructions'
if (Test-Path $targetAgents) {
    $existingAgents = Get-Content $targetAgents -Raw
    if ($existingAgents -notmatch [regex]::Escape($marker)) {
        Copy-Item $targetAgents (Join-Path $repoRoot 'AGENTS.upstream.md') -Force
        Set-Content -Path $targetAgents -Encoding utf8 -Value ($existingAgents.TrimEnd() + "`r`n`r`n---`r`n`r`n" + $starterAgents)
    }
} else {
    Copy-Item (Join-Path $packRoot 'AGENTS.md') $targetAgents -Force
}

Copy-Item (Join-Path $packRoot 'docs\*') $docsDestination -Recurse -Force
Copy-Item (Join-Path $packRoot 'scripts\*') $toolsDestination -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $docsDestination 'prompts') -Force | Out-Null
Copy-Item (Join-Path $packRoot 'prompts\*') (Join-Path $docsDestination 'prompts') -Recurse -Force
Copy-Item (Join-Path $packRoot 'FIRST_SESSION_PROMPT.md') (Join-Path $docsDestination 'FIRST_SESSION_PROMPT.md') -Force
Copy-Item (Join-Path $packRoot 'THIRD_PARTY_AND_LEGAL.md') (Join-Path $docsDestination 'THIRD_PARTY_AND_LEGAL.md') -Force

$upstreamSha = (& git -C $repoRoot rev-parse HEAD).Trim()
@(
    "Recorded: $(Get-Date -Format o)",
    "Repository: $RepoUrl",
    "Commit: $upstreamSha",
    "Feature branch: $Branch"
) | Set-Content (Join-Path $docsDestination 'UPSTREAM_BASE.txt') -Encoding utf8

$excludeFile = Join-Path $repoRoot '.git\info\exclude'
$excludeMarker = '# NeuralDoom3 local-only files'
$existingExclude = if (Test-Path $excludeFile) { Get-Content $excludeFile -Raw } else { '' }
if ($existingExclude -notmatch [regex]::Escape($excludeMarker)) {
    Add-Content -Path $excludeFile -Encoding utf8 -Value @"

$excludeMarker
/local-proprietary/
/captures/neural/
/neural-local/
*.nv-gpudmp
*.rdc
"@
}

Set-Content -Path (Join-Path $packRoot '.workspace-path.txt') -Encoding utf8 -Value $repoRoot

Write-Step 'Bootstrap complete'
Write-Host "Repository: $repoRoot"
Write-Host "Branch:     $Branch"
Write-Host "Upstream:   $upstreamSha"
Write-Host "`nNext: run 01-CHECK-PREREQUISITES.cmd from the starter pack."
