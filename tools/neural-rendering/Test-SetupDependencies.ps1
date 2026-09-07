[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1')
$root = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ('captures/neural/setup-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
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
