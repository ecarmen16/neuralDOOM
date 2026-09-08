[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Install-Lifecycle.ps1')
$fixture = Join-Path $PSScriptRoot ('../../captures/neural/lifecycle-' + [guid]::NewGuid().ToString('N'))
$fixture = [IO.Path]::GetFullPath($fixture)
$stage = Join-Path $fixture 'stage'; $install = Join-Path $fixture 'install'
New-Item -ItemType Directory -Path $stage, $install -Force | Out-Null
function Put([string]$Root, [string]$Name, [string]$Text) {
    $path = Join-Path $Root $Name
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}
function Manifest([string]$Root, [string]$Revision) {
    $files = @(Get-SetupFiles $Root | Where-Object { $_ -ne 'internal-package.json' -and $_ -notlike '.neuraldoom-*' } | ForEach-Object { @{ path = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $Root $_)).Hash } })
    @{ schemaVersion = 2; commit = ($Revision * 40); executable = 'build-rt/Release/neuralDoom.exe'; files = $files } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'internal-package.json')
}
Put $install 'app.txt' 'old application'
Put $install 'obsolete.txt' 'old removed file'
Manifest $install 'a'
Put $install 'captures/dogfood/base/save.dat' 'precious save'
Put $install 'reshade.ini' 'user tuning'
Put $install 'personal.txt' 'leave me alone'
Put $stage 'app.txt' 'new application'
Put $stage 'tools/neural-rendering/Install-InternalTest.ps1' @'
param($RepoRoot,$GamePath,$Profile,$DlssDllPath,$NRDllPath,[switch]$SkipShortcut,[switch]$SkipStartMenu,[switch]$NonInteractive,[switch]$ManagedDeployment)
if ($env:NEURALDOOM_LIFECYCLE_FAIL -eq '1') { throw 'Fixture failure during installation' }
'@
Manifest $stage 'b'
$env:NEURALDOOM_LIFECYCLE_FAIL = '1'
$caught = $false
try { Invoke-SetupDeployment -Stage $stage -Destination $install -Mode Upgrade -Profile Native -SkipShortcut -SkipStartMenu -SkipRegistration }
catch { if ($_.Exception.Message -notlike '*Fixture failure*') { throw }; $caught = $true }
finally { Remove-Item Env:NEURALDOOM_LIFECYCLE_FAIL }
if (-not $caught -or [IO.File]::ReadAllText((Join-Path $install 'app.txt')) -ne 'old application' -or (Get-Content (Join-Path $install 'internal-package.json') -Raw | ConvertFrom-Json).commit -ne ('a' * 40)) { throw 'Rollback failed.' }
Invoke-SetupDeployment -Stage $stage -Destination $install -Mode Upgrade -Profile NR -SkipShortcut -SkipStartMenu -SkipRegistration
if ([IO.File]::ReadAllText((Join-Path $install 'app.txt')) -ne 'new application' -or (Test-Path (Join-Path $install 'obsolete.txt'))) { throw 'Upgrade did not replace/remove old application files.' }
foreach ($name in @('captures/dogfood/base/save.dat', 'reshade.ini', 'personal.txt')) { if (-not (Test-Path -LiteralPath (Join-Path $install $name))) { throw 'Upgrade removed personal data.' } }
$state = Get-Content (Join-Path $install '.neuraldoom-install.json') -Raw | ConvertFrom-Json
if ($state.files.path -contains 'personal.txt' -or $state.files.path -contains 'reshade.ini') { throw 'Unrelated files were claimed by setup.' }
$copy = Join-Path $fixture 'copy'
Invoke-SetupDeployment -Stage $stage -Destination $copy -Mode Copy -ExistingPath $install -Profile DLAA -SkipShortcut -SkipStartMenu -SkipRegistration
if ([IO.File]::ReadAllText((Join-Path $copy 'captures/dogfood/base/save.dat')) -ne 'precious save') { throw 'Copy lost saved game.' }
foreach ($relative in @('../outside', 'C:/outside', 'dir/../../outside', 'file:stream')) {
    $caught = $false; try { $null = Get-SetupSafePath $install $relative } catch { $caught = $true }
    if (-not $caught) { throw 'Unsafe path accepted.' }
}
Put $install 'app.txt' 'modified by tester'
Remove-SetupInstallation $install -SkipRegistration
foreach ($name in @('app.txt','captures/dogfood/base/save.dat','reshade.ini','personal.txt')) { if (-not (Test-Path -LiteralPath (Join-Path $install $name))) { throw 'Uninstall removed changed/user data.' } }
if (Test-Path -LiteralPath (Join-Path $install '.neuraldoom-install.json')) { throw 'Uninstall left the registration marker.' }
Remove-SetupInstallation $copy -SkipRegistration
if (Test-Path -LiteralPath (Join-Path $copy 'app.txt')) { throw 'Uninstall did not remove unchanged program file.' }
Write-Host 'PASS: failed upgrade rollback, successful upgrade, obsolete-file removal, separate copy, save/tuning preservation, ownership-based uninstall and traversal rejection.'
