[CmdletBinding()]
param([Parameter(Mandatory)][string]$AssemblyPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $AssemblyPath).Path)
$entry = $assembly.GetType('InternalSetup')
$windowType = $assembly.GetType('SetupWindow')
$flags = [Reflection.BindingFlags]'NonPublic,Public,Instance,Static'
$root = Join-Path ([IO.Path]::GetTempPath()) ('neuralDoom-wizard-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$worker = Join-Path $root 'fixture-worker.ps1'
@'
param($PackagePath, $Sha256, $Destination, $GamePath, [switch]$NonInteractive, [switch]$SkipShortcut)
Write-Host '@@SETUP|Fixture installation stage'
if ($env:NEURALDOOM_WIZARD_TEST_EXIT -eq '1') { Write-Error 'Fixture installation failure'; exit 1 }
exit 0
'@ | Set-Content -LiteralPath $worker
foreach ($pair in @(@('Scratch', $root), @('Payload', (Join-Path $root 'fixture.zip')), @('Bootstrap', $worker), @('Hash', ('A' * 64)), @('Prepared', $true))) {
    $entry.GetField($pair[0], $flags).SetValue($null, $pair[1])
}
$previous = $env:NEURALDOOM_WIZARD_TEST_EXIT
try {
    foreach ($exitCode in @(0, 1)) {
        $env:NEURALDOOM_WIZARD_TEST_EXIT = "$exitCode"
        $window = [Activator]::CreateInstance($windowType)
        try {
            $window.Opacity = 0
            $window.Show()
            $task = $windowType.GetMethod('Install', $flags).Invoke($window, @())
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (-not $task.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
                [Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 10
            }
            if (-not $task.IsCompleted -or $task.IsFaulted) { throw 'Wizard worker failed to return to UI.' }
            [Windows.Forms.Application]::DoEvents()
            $page = $windowType.GetField('page', $flags).GetValue($window)
            if ($page -ne $(if ($exitCode -eq 0) { 4 } else { 5 })) { throw 'Incorrect completion/failure page.' }
            $log = $windowType.GetField('logPath', $flags).GetValue($window)
            if (-not (Test-Path -LiteralPath $log) -or (Get-Content -LiteralPath $log -Raw) -notmatch 'Fixture installation stage') { throw 'Worker output was not persisted.' }
            Write-Host "PASS: redirected worker exit $exitCode, UI page $page, persisted log."
        } finally { $window.Dispose() }
    }
} finally { $env:NEURALDOOM_WIZARD_TEST_EXIT = $previous }
