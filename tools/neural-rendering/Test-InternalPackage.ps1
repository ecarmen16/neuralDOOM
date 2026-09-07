[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$installer = Join-Path $PackageRoot 'tools/neural-rendering/Install-InternalTest.ps1'
$manifestPath = Join-Path $PackageRoot 'internal-package.json'
$original = [IO.File]::ReadAllBytes($manifestPath)
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
& $installer -RepoRoot $PackageRoot -VerifyOnly
function Expect-Rejection {
    param([string]$Pattern)
    $rejected = $false
    try { & $installer -RepoRoot $PackageRoot -VerifyOnly }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw }; $rejected = $true }
    if (-not $rejected) { throw "Expected installer rejection: $Pattern" }
}
$shader = [IO.Path]::GetFullPath((Join-Path $PackageRoot $manifest.shaders[0].path))
$prefix = $PackageRoot.TrimEnd('\') + '\'
if (-not $shader.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test fixture shader path.' }
$shaderBytes = [IO.File]::ReadAllBytes($shader)
try {
    [IO.File]::WriteAllBytes($shader, [byte[]]@(1, 2, 3))
    Expect-Rejection '*Package file missing or changed*'
} finally { [IO.File]::WriteAllBytes($shader, $shaderBytes) }
try {
    $manifest.files[0].path = '../outside-package'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Expect-Rejection '*Invalid/duplicate package path*'
} finally { [IO.File]::WriteAllBytes($manifestPath, $original) }
& $installer -RepoRoot $PackageRoot -VerifyOnly
Write-Host 'PASS: portable verification, shader tamper rejection, path escape rejection and exact fixture restoration.'
