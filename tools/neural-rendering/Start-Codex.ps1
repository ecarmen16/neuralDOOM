[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$PromptFile
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if (-not (Test-CommandAvailable 'codex')) {
    throw 'Codex is not available on PATH. Install/authenticate the Codex CLI first.'
}

if ([string]::IsNullOrWhiteSpace($PromptFile)) {
    $PromptFile = Join-Path $RepoRoot 'docs\neural-rendering\FIRST_SESSION_PROMPT.md'
}
if (-not (Test-Path $PromptFile)) {
    throw "Prompt file not found: $PromptFile"
}

$prompt = Get-Content $PromptFile -Raw
Write-Step 'Starting interactive Codex reconnaissance session'
Write-Host "Repository: $RepoRoot"
Write-Host "Prompt:     $PromptFile"
Write-Host 'Sandbox:    workspace-write; approvals: on-request'

& codex --cd $RepoRoot --ask-for-approval on-request --sandbox workspace-write $prompt
exit $LASTEXITCODE
