[CmdletBinding()]
param(
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\vendor\llama.cpp'),
    [string] $BuildDir = (Join-Path $PSScriptRoot '..\build-cuda'),
    [string[]] $CudaArchitectures,
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
if (-not $env:CUDA_PATH) {
    throw 'CUDA_PATH is not set. Install the NVIDIA CUDA Toolkit first.'
}

$configureArgs = @(
    '-S', $source,
    '-B', $build,
    '-G', 'Ninja Multi-Config',
    '-DGGML_CUDA=ON',
    '-DGGML_CUDA_NO_PEER_COPY=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_BACKEND_DL=ON'
)
if ($CudaArchitectures.Count -gt 0) {
    $configureArgs += "-DCMAKE_CUDA_ARCHITECTURES=$($CudaArchitectures -join ';')"
}

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)." }
& cmake --build $build --config Release --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw "CMake build failed ($LASTEXITCODE)." }

Write-Host "CUDA build complete: $build\bin\Release"
