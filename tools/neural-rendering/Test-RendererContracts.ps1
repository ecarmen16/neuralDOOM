# CPU/source and compiled-shader checks; never launch the engine or create a GPU device.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('Offline', 'CPU', 'Shaders')][string]$Suite,
    [string]$Dxc
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$RepoRoot = Resolve-NeuralRepoRoot $RepoRoot

if ($Suite -in @('CPU', 'Shaders')) {
    # The extracted-source tests call cl directly and need INCLUDE/LIB as well as PATH.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = (& $vswhere -latest -version '[17.0,18.0)' -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
    if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'VS2022 C++ tools were not found.' }
    Import-Module (Join-Path $installation 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue) -or -not $env:INCLUDE -or -not $env:LIB) {
        throw 'MSVC compiler environment was not initialized.'
    }
}
if ($Suite -eq 'Shaders' -and (-not $Dxc -or -not (Test-Path -LiteralPath $Dxc -PathType Leaf))) {
    throw 'Shaders suite requires the DXC executable used for the build (-Dxc).'
}

Push-Location -LiteralPath $RepoRoot
try {
    if ($Suite -eq 'Offline') {
        foreach ($test in @('Test-CommandWrappers.ps1', 'Test-PublicSourceAudit.ps1', 'Test-ReleaseAssetUpload.ps1', 'Test-NeuralBuildIdentity.ps1', 'Test-NeuralSubmodules.ps1')) {
            Write-Step $test
            Invoke-NativeChecked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $test))
        }
        Invoke-NativeChecked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Test-NeuralDoom-PublicSource.ps1'), '-RepoRoot', $RepoRoot)
    } elseif ($Suite -eq 'CPU') {
        foreach ($test in @('Test-NeuralReconstruction.py', 'Test-NeuralJitter.py', 'Test-DynamicRayGeometry.py', 'Test-ReconstructionDefaults.py', 'Test-ReflectionHistory.py', 'Test-SSRCoordinates.py', 'Test-RayLightingComposition.py')) {
            Write-Step $test
            Invoke-NativeChecked 'python' @((Join-Path $PSScriptRoot $test))
        }
    } else {
        foreach ($test in @('Test-ReflectionShaderContract.py', 'Test-PlayerShadowContract.py')) {
            Write-Step $test
            Invoke-NativeChecked 'python' @((Join-Path $PSScriptRoot $test), '--repo-root', $RepoRoot, '--dxc', $Dxc)
        }
        Write-Step 'Test-ReflectionMaterials.py'
        Invoke-NativeChecked 'python' @((Join-Path $PSScriptRoot 'Test-ReflectionMaterials.py'), '--source-root', $RepoRoot, '--dxc', $Dxc)
    }
} finally { Pop-Location }
Write-Host "PASS: $Suite renderer checks. GPU rendering and gameplay were not tested."
