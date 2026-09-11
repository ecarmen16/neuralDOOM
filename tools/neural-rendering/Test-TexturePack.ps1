# Isolated importer tests: fixture ZIPs are never accepted by the production pin gate.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Setup-TexturePack.ps1')
$fixture = Join-Path $PSScriptRoot ('../../captures/neural/texture-test-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $fixture 'install'
New-Item -ItemType Directory -Path $root -Force | Out-Null
@{ schemaVersion = 2; commit = ('a' * 40); executable = 'build-rt/Release/neuralDoom.exe' } | ConvertTo-Json | Set-Content (Join-Path $root 'internal-package.json')
function Make-Pack([string]$Name, [hashtable]$Files) {
    $path = Join-Path $fixture $Name
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($key in $Files.Keys) {
            $entry = $zip.CreateEntry($key); $stream = $entry.Open()
            $bytes = [Text.Encoding]::UTF8.GetBytes($Files[$key])
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    return $path
}
function Must-Fail([scriptblock]$Action) {
    $failed = $false; try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw 'Expected rejection.' }
}
$pack = Make-Pack 'valid.zip' @{
    'Readme.txt' = 'Original author and contributor credits';
    'mod_D3HDP_Lite/textures/test.txt' = 'fixture asset';
    'mod_D3HDP_Lite/Readme.txt' = 'Additional credits';
    'mod_D3HDP_Lite/autoexec.cfg' = 'DO NOT APPLY';
    'mod_D3HDP_Lite/play.bat' = 'DO NOT EXECUTE'
}
Must-Fail { Test-D3HDPArchive $pack }
# Substitute only download/pin acquisition; run the actual parsing, import and collision code.
function Get-D3HDPArchive { param($RepoRoot, $ArchivePath) return $ArchivePath }
Install-SetupTexturePack -RepoRoot $root -ArchivePath $pack
$installed = Join-Path $root 'base/zzz_neural_d3hdp_loose.pk4'
$hash = (Get-FileHash $installed).Hash
Install-SetupTexturePack -RepoRoot $root -ArchivePath $pack
if ((Get-FileHash $installed).Hash -ne $hash) { throw 'Retry changed content.' }
if ((Get-Content (Join-Path $root 'notices/D3HDP-BFG-Lite/Readme.txt') -Raw).Trim() -ne 'Original author and contributor credits') { throw 'Lost original readme.' }
if (Test-Path (Join-Path $root 'base/autoexec.cfg')) { throw 'Applied mod settings.' }
$zip = [IO.Compression.ZipFile]::OpenRead($installed)
try {
    if ($zip.Entries.Count -ne 1 -or $zip.Entries[0].FullName -ne 'textures/test.txt') { throw 'Incorrect asset overlay.' }
} finally { $zip.Dispose() }
$bad = Make-Pack 'traversal.zip' @{ 'Readme.txt' = 'credits'; 'mod_D3HDP_Lite/../escape.txt' = 'bad' }
Must-Fail { Install-SetupTexturePack -RepoRoot $root -ArchivePath $bad }
$bad = Make-Pack 'nocredits.zip' @{ 'mod_D3HDP_Lite/textures/test.txt' = 'bad' }
Must-Fail { Install-SetupTexturePack -RepoRoot $root -ArchivePath $bad }
$bad = Make-Pack 'binary.zip' @{ 'Readme.txt' = 'credits'; 'mod_D3HDP_Lite/bad.dll' = 'bad' }
Must-Fail { Install-SetupTexturePack -RepoRoot $root -ArchivePath $bad }
$changed = Make-Pack 'changed.zip' @{ 'Readme.txt' = 'credits'; 'mod_D3HDP_Lite/textures/test.txt' = 'different' }
Must-Fail { Install-SetupTexturePack -RepoRoot $root -ArchivePath $changed }
if ((Get-FileHash $installed).Hash -ne $hash) { throw 'Failed import damaged installed content.' }
Write-Host 'PASS: real importer preserves credits and settings, is idempotent, rejects wrong pins, traversal, missing credits, binaries and changed content. Fixture only; publisher archive/gameplay not validated.'
