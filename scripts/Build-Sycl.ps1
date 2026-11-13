[CmdletBinding()]
param(
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\vendor\llama.cpp'),
    [string] $BuildDir = (Join-Path $PSScriptRoot '..\build-sycl'),
    [ValidateSet('fp32', 'fp16')]
    [string] $Precision = 'fp32',
    [int] $Jobs = [Environment]::ProcessorCount
)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceDir)
$build = [IO.Path]::GetFullPath($BuildDir)

if (-not (Test-Path (Join-Path $source 'CMakeLists.txt'))) {
    throw "llama.cpp source not found at '$source'. Run: git submodule update --init --recursive"
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'cmake was not found. Install Visual Studio 2022 Build Tools and CMake.'
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    throw 'ninja was not found. Install Ninja.'
}
if (-not (Get-Command icx -ErrorAction SilentlyContinue)) {
    throw 'icx was not found. Run this script from a oneAPI command prompt, or call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" first.'
}

# The SYCL backend must be compiled by the Intel oneAPI DPC++ compiler (icx).
# Single-config Ninja matches the upstream llama.cpp Windows SYCL build.
$configureArgs = @(
    '-S', $source,
    '-B', $build,
    '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_C_COMPILER=cl',
    '-DCMAKE_CXX_COMPILER=icx',
    '-DGGML_SYCL=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_BACKEND_DL=ON'
)
if ($Precision -eq 'fp16') {
    $configureArgs += '-DGGML_SYCL_F16=ON'
}

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)." }
& cmake --build $build --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw "CMake build failed ($LASTEXITCODE)." }

$syclDll = Join-Path $build 'bin\ggml-sycl.dll'
if (-not (Test-Path $syclDll)) {
    throw "SYCL backend was not produced: $syclDll"
}

Write-Host "SYCL ($Precision) build complete: $build\bin"
