[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Executable = 'llama-cli.exe',
    [string] $RocmRoot,
    [switch] $SkipDeviceCheck,
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $LlamaArguments
)

$ErrorActionPreference = 'Stop'
$bundledRuntime = $PSScriptRoot
if (-not $RocmRoot) {
    if (Test-Path (Join-Path $bundledRuntime 'hipblas.dll')) {
        $RocmRoot = $bundledRuntime
    } elseif ($env:HIP_PATH) {
        $RocmRoot = $env:HIP_PATH
    } else {
        $RocmRoot = 'C:\TheRock\build'
    }
}
$rocm = [IO.Path]::GetFullPath($RocmRoot)
$rocmBin = if (Test-Path (Join-Path $rocm 'hipblas.dll')) { $rocm } else { Join-Path $rocm 'bin' }
$exe = Join-Path $PSScriptRoot $Executable

if (-not (Test-Path $exe)) {
    throw "llama.cpp executable not found: $exe"
}
if (-not (Test-Path $rocmBin)) {
    throw "ROCm runtime directory not found: $rocmBin. Use the bundled runtime or specify -RocmRoot."
}

$requiredDlls = @('hipblas.dll', 'rocblas.dll', 'rocsolver.dll')
$missingDlls = $requiredDlls | Where-Object { -not (Test-Path (Join-Path $rocmBin $_)) }
$hipRuntimeDlls = @('amdhip64.dll', 'amdhip64_7.dll')
if (-not ($hipRuntimeDlls | Where-Object { Test-Path (Join-Path $rocmBin $_) })) {
    $missingDlls = @($missingDlls) + ($hipRuntimeDlls -join ' or ')
}
if ($missingDlls) {
    throw "Required ROCm runtime DLLs are missing from '$rocmBin': $($missingDlls -join ', ')"
}

$env:HIP_PATH = $rocm
$env:PATH = "$rocmBin;$PSScriptRoot;$env:PATH"

Write-Host "ROCm runtime: $rocm"
Write-Host "Executable: $exe"

if (-not $SkipDeviceCheck) {
    $deviceProbe = Join-Path $PSScriptRoot 'llama-cli.exe'
    if (-not (Test-Path $deviceProbe)) { throw "Device probe executable not found: $deviceProbe" }
    $deviceOutput = & $deviceProbe --list-devices 2>&1
    $deviceOutput | ForEach-Object { Write-Host $_ }
    if (($deviceOutput -join "`n") -notmatch '(?i)ROCm') {
        throw 'No ROCm device was detected. CPU-only inference was prevented. Check the AMD driver, ROCm runtime, PATH, and the gfx target of this package.'
    }
}

& $exe @LlamaArguments
exit $LASTEXITCODE
