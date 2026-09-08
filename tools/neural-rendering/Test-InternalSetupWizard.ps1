[CmdletBinding()]
param([Parameter(Mandatory)][string]$AssemblyPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class WizardMenuProbe {
    delegate bool EnumWindow(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumThreadWindows(uint thread, EnumWindow callback, IntPtr parameter);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    public static ContextMenuStrip FindOpenMenu() {
        ContextMenuStrip found = null;
        EnumThreadWindows(GetCurrentThreadId(), delegate(IntPtr window, IntPtr parameter) {
            ContextMenuStrip menu = Control.FromHandle(window) as ContextMenuStrip;
            if (menu != null && menu.Visible) found = menu;
            return true;
        }, IntPtr.Zero);
        if (found == null) throw new Exception("Choice button did not open a menu.");
        return found;
    }
}
'@
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $AssemblyPath).Path)
$entry = $assembly.GetType('InternalSetup')
$windowType = $assembly.GetType('SetupWindow')
$flags = [Reflection.BindingFlags]'NonPublic,Public,Instance,Static'
$choices = [Activator]::CreateInstance($windowType)
try {
    $choices.Opacity = 0
    $choices.Show()
    foreach ($pageNumber in @(7, 6, 7)) {
        $null = $windowType.GetMethod('ShowPage', $flags).Invoke($choices, @($pageNumber))
        $names = if ($pageNumber -eq 7) { @('operation', 'existing') } else { @('renderer') }
        foreach ($name in $names) {
            $button = $windowType.GetField($name, $flags).GetValue($choices)
            $type = $button.GetType()
            $items = $type.GetField('Items', $flags).GetValue($button)
            # Exercise a populated existing-install selector even on clean machines.
            if ($items.Count -lt 2) { $items.Add('Fixture installation A'); $items.Add('Fixture installation B') }
            foreach ($index in @(0..($items.Count - 1)) + @(0, 1, 0)) {
                $button.PerformClick()
                $menu = [WizardMenuProbe]::FindOpenMenu()
                # PerformClick traverses WinForms' real item-click/auto-close path.
                # This reproduced the disposed ContextMenuStrip exception in 82adc605.
                $menu.Items[$index].PerformClick()
                [Windows.Forms.Application]::DoEvents()
                if ($type.GetProperty('SelectedIndex', $flags).GetValue($button, $null) -ne $index -or $menu.Visible) { throw 'Choice selection did not update and close.' }
            }
            $button.PerformClick()
            $menu = [WizardMenuProbe]::FindOpenMenu()
            $menu.Close([Windows.Forms.ToolStripDropDownCloseReason]::Keyboard)
            [Windows.Forms.Application]::DoEvents()
            if ($menu.Visible) { throw 'Choice menu did not dismiss.' }
        }
    }
    Write-Host 'PASS: repeated action, existing-install and renderer choices, dismissal and page recreation.'
} finally { $choices.Dispose() }
$root = Join-Path ([IO.Path]::GetTempPath()) ('neuralDoom-wizard-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$worker = Join-Path $root 'fixture-worker.ps1'
@'
param($PackagePath, $Sha256, $Destination, $GamePath, $Profile, $Mode, $ExistingPath, $DlssDllPath, $NRDllPath, [switch]$NonInteractive, [switch]$SkipShortcut)
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
