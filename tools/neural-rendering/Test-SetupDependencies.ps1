[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
$root = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ('captures/neural/setup-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$previousCancel = $env:NEURALDOOM_SETUP_CANCEL_FILE
try {
    $env:NEURALDOOM_SETUP_CANCEL_FILE = Join-Path $root 'cancel'
    'cancel' | Set-Content -LiteralPath $env:NEURALDOOM_SETUP_CANCEL_FILE
    $cancelled = $false
    try { Write-SetupStatus 'Must not continue' } catch { $cancelled = $_.Exception.Message -match 'Setup cancelled' }
    if (-not $cancelled) { throw 'Cancellation was ignored at the stage boundary.' }
    Remove-Item -LiteralPath $env:NEURALDOOM_SETUP_CANCEL_FILE
    Write-SetupStatus 'Retry can continue'
} finally { $env:NEURALDOOM_SETUP_CANCEL_FILE = $previousCancel }
Write-Host 'PASS: cooperative cancellation and retry at a setup stage boundary.'
$payload = Join-Path $root 'expected.txt'
'verified payload' | Set-Content -LiteralPath $payload
$hash = (Get-FileHash -LiteralPath $payload).Hash
$script:downloads = 0
function Start-BitsTransfer { throw 'Fixture exercises web fallback' }
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $ErrorAction)
    $script:downloads++
    if ($script:downloads -lt 3) { throw 'Fixture transient connection failure' }
    Copy-Item -LiteralPath $payload -Destination $OutFile
}
$destination = Join-Path $root 'cache/file.txt'
Get-SetupDownload -Uri 'https://example.invalid/pinned' -Destination $destination -Sha256 $hash | Out-Null
if ($script:downloads -ne 3) { throw 'Download retries not exercised' }
Get-SetupDownload -Uri 'https://example.invalid/pinned' -Destination $destination -Sha256 $hash | Out-Null
if ($script:downloads -ne 3) { throw 'Valid cache was downloaded again' }
$rejected = $false
try { Get-SetupDownload -Uri 'http://example.invalid/pinned' -Destination $destination -Sha256 $hash } catch { $rejected = $true }
if (-not $rejected) { throw 'HTTP was accepted' }
$rejected = $false
try { Get-SetupDownload -Uri 'https://example.invalid/pinned' -Destination $destination -Sha256 ('0' * 64) } catch { $rejected = $true }
if (-not $rejected -or (Test-Path -LiteralPath $destination)) { throw 'Bad hash reached the completed cache' }
Write-Host 'PASS: retry, fallback, cached reuse, HTTPS requirement and corrupt download rejection.'

# Missing-runtime path: no real registry, download or process changes.
function Test-Path {
    param($LiteralPath)
    if ($LiteralPath -match 'System32[\\/](?:vcruntime140(?:_1)?|msvcp140)\.dll$') { return $false }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
}
function Get-SetupDownload { return $payload }
$script:publisher = 'O=Untrusted Publisher'
function Get-AuthenticodeSignature { return [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Subject=$script:publisher } } }
$script:processes = 0
function Start-Process { $script:processes++; return [pscustomobject]@{ ExitCode=3010 } }
$rejected = $false
try { Install-SetupVCRuntime -RepoRoot $root } catch { $rejected = $true }
if (-not $rejected -or $script:processes -ne 0) { throw 'Untrusted runtime installer executed' }
$script:publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
Install-SetupVCRuntime -RepoRoot $root
if ($script:processes -ne 1) { throw 'Verified missing-runtime path not executed' }
Write-Host 'PASS: publisher verification before execution and restart-required handling (mock process only).'

$gameFixture = Join-Path $root 'Steam BFG'
New-Item -ItemType Directory -Path (Join-Path $gameFixture 'base/maps') -Force | Out-Null
'owned-data-path-fixture' | Set-Content -LiteralPath (Join-Path $gameFixture 'base/maps/mars_city2.resources')
function Get-ItemProperty {
    param($LiteralPath, $ErrorAction)
    if ($LiteralPath -like '*Steam App 208200') { return [pscustomobject]@{ InstallLocation=$gameFixture } }
    return $null
}
if ((Find-SetupBFG) -ne $gameFixture) { throw 'Steam installation detection failed.' }
Write-Host 'PASS: Steam BFG detection with a registry/path fixture.'
