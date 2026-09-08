# Helpers for the already-installed, engine-loaded local compatibility stack.
# Never obtain, copy or package compatibility / NR runtime binaries here.

function Get-NeuralEmbeddedNRState {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$BuildExecutable)
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'dxgi.dll')) {
        throw 'NR requires the engine-loaded compatibility path: a local dxgi.dll proxy is still present.'
    }
    $runtimeFiles = @()
    foreach ($name in @('neuraldoom-reshade64.dll', 'renodx-dlss5.addon64', 'nvngx_dlssnr.dll', 'nvngx_dlss.dll',
        'sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'reshade.ini')) {
        $path = Join-Path $RepoRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "NR local component is missing: $name. This profile only uses an existing installation."
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($name -like 'sl.*.dll') {
            $buildDll = Join-Path (Split-Path $BuildExecutable) $name
            if (-not (Test-Path -LiteralPath $buildDll -PathType Leaf) -or
                $hash -ne (Get-FileHash -LiteralPath $buildDll -Algorithm SHA256).Hash) {
                throw "NR local Streamline component differs from the selected build: $name."
            }
        }
        $runtimeFiles += [pscustomobject]@{ name = $name; sha256 = $hash }
    }
    # Validate the editable configuration during read-only readiness checks too.
    $config = [IO.File]::ReadAllText((Join-Path $RepoRoot 'reshade.ini'))
    $null = Get-NeuralNRFullResolutionConfig -Text $config
    return [pscustomobject]@{
        executable = (Join-Path $RepoRoot 'neuralDoom.exe')
        runtimeFiles = $runtimeFiles
    }
}

function Get-NeuralNRFullResolutionConfig {
    param([Parameter(Mandatory)][string]$Text)
    $sections = [regex]::Matches($Text, '(?ms)^\[RenoDX\.DLSS5\][ \t]*\r?\n.*?(?=^\[|\z)')
    if ($sections.Count -ne 1) { throw 'NR requires one existing [RenoDX.DLSS5] configuration section.' }
    $original = $sections[0].Value
    $section = $original
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    foreach ($entry in @(@('NeuralUplift', '1'), @('NREnableUpscaling', '0'), @('EnableHooks', '1'), @('NRToggleKey', '117'))) {
        $pattern = '(?m)^' + $entry[0] + '[ \t]*=[^\r\n]*'
        $keyMatches = [regex]::Matches($section, $pattern)
        if ($keyMatches.Count -gt 1) { throw "Duplicate NR setting: $($entry[0])" }
        $replacement = $entry[0] + '=' + $entry[1]
        if ($keyMatches.Count -eq 1) { $section = [regex]::Replace($section, $pattern, $replacement) }
        else { $section = $section.TrimEnd("`r", "`n") + $newline + $replacement + $newline }
    }
    return $Text.Substring(0, $sections[0].Index) + $section + $Text.Substring($sections[0].Index + $original.Length)
}

function Initialize-NeuralEmbeddedNRLaunch {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$BuildExecutable,
        [Parameter(Mandatory)][string]$ExpectedHash, [Parameter(Mandatory)][string]$SaveBase)
    $state = Get-NeuralEmbeddedNRState -RepoRoot $RepoRoot -BuildExecutable $BuildExecutable
    if ((Get-FileHash -LiteralPath $BuildExecutable -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'NR source executable changed after build validation.'
    }
    $configPath = Join-Path $RepoRoot 'reshade.ini'
    foreach ($path in @($state.executable, $configPath)) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'NR preparation cannot overwrite a linked executable or configuration.'
        }
    }
    $backup = Join-Path (Split-Path $SaveBase) 'nr-backup'
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $backup 'reshade.ini'))) {
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $backup 'reshade.ini')
    }
    if (-not (Test-Path -LiteralPath $state.executable) -or
        (Get-FileHash -LiteralPath $state.executable -Algorithm SHA256).Hash -ne $ExpectedHash) {
        if ((Test-Path -LiteralPath $state.executable) -and -not (Test-Path -LiteralPath (Join-Path $backup 'neuralDoom.exe'))) {
            Copy-Item -LiteralPath $state.executable -Destination (Join-Path $backup 'neuralDoom.exe')
        }
        # Only our manifest-verified engine executable is staged. Runtime DLLs
        # stay in their existing location beside it, as required by this add-on.
        Copy-Item -LiteralPath $BuildExecutable -Destination $state.executable -Force
    }
    if ((Get-FileHash -LiteralPath $state.executable -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'NR launch executable does not match the selected build.'
    }
    $config = Get-NeuralNRFullResolutionConfig -Text ([IO.File]::ReadAllText($configPath))
    [IO.File]::WriteAllText($configPath, $config, (New-Object System.Text.UTF8Encoding $false))
    ($state.runtimeFiles | Where-Object { $_.name -eq 'reshade.ini' }).sha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    $state.runtimeFiles | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path (Split-Path $SaveBase) 'nr-runtime-inventory.json') -Encoding UTF8
    return $state.executable
}
