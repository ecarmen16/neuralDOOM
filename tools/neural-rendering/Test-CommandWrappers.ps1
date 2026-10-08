# Exercise the real wrappers without invoking setup or the repository audit.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('neuraldoom-wrappers-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testRoot "O'Brien; Write-Output INJECTED; # & (path)!"
$scripts = New-Item -ItemType Directory -Path (Join-Path $fixture 'tools/neural-rendering') -Force
$stub = 'param([string]$RepoRoot) Write-Output (''ROOT:'' + $RepoRoot); exit 23'
try {
    foreach ($name in @('Setup-NeuralDoom.ps1', 'Test-NeuralDoom-PublicSource.ps1')) {
        Set-Content -LiteralPath (Join-Path $scripts.FullName $name) -Value $stub -Encoding ASCII
    }
    foreach ($name in @('Setup-NeuralDoom.cmd', 'Audit-NeuralDoom-PublicSource.cmd')) {
        $wrapper = Join-Path $fixture $name
        Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $wrapper
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $env:ComSpec
        $start.Arguments = '/d /c ""' + $wrapper + '""'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $errors = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 23 -or -not $output.Contains("ROOT:$fixture\") -or $errors) {
            throw "$name failed path/exit propagation: $output $errors"
        }
        $process.Dispose()
        # Also cover the Windows PowerShell fallback when pwsh is installed.
        $commands = [regex]::Matches((Get-Content -LiteralPath $wrapper -Raw), '(?m)^\s*(powershell.exe|pwsh.exe) .* -Command "([^"]+)"')
        foreach ($command in $commands) {
            $shell = Get-Command $command.Groups[1].Value -ErrorAction SilentlyContinue
            if (-not $shell) { continue }
            $savedRoot = $env:ND_SCRIPT_ROOT
            try {
                $env:ND_SCRIPT_ROOT = "$fixture\"
                $output = @(& $shell.Source -NoProfile -ExecutionPolicy Bypass -Command $command.Groups[2].Value)
                if ($LASTEXITCODE -ne 23 -or $output.Count -ne 1 -or $output[0] -ne "ROOT:$fixture\") {
                    throw "$name failed in $($shell.Name): $output"
                }
            } finally { $env:ND_SCRIPT_ROOT = $savedRoot }
        }
        Write-Host "PASS: $name preserves metacharacter paths and child exit status."
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test cleanup path.' }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
