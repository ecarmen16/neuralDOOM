[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$PromptFile,
    [string]$OutputFile
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot
if (-not (Test-CommandAvailable 'codex')) {
    throw 'Codex is not available on PATH.'
}

if ([string]::IsNullOrWhiteSpace($PromptFile)) {
    $PromptFile = Join-Path $RepoRoot 'docs\neural-rendering\archive\FIRST_SESSION_PROMPT.md'
}
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $RepoRoot 'docs\neural-rendering\CODEX_SESSION_1_LAST_MESSAGE.md'
}
if (-not (Test-Path $PromptFile)) {
    throw "Prompt file not found: $PromptFile"
}

Write-Step 'Running non-interactive Codex reconnaissance'
Write-Warning 'This mode cannot pause for approvals. It is confined to workspace-write and cannot escalate.'
Get-Content $PromptFile -Raw |
    & codex exec --cd $RepoRoot --ask-for-approval never --sandbox workspace-write --output-last-message $OutputFile -
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "codex exec failed with exit code $exitCode"
}
Write-Host "Last message saved to: $OutputFile" -ForegroundColor Green
