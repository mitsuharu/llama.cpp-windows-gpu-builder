[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^gfx[0-9a-f]+$')]
    [string] $GpuTarget,
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\vendor\llama.cpp'),
    [string] $BuildDir = (Join-Path $PSScriptRoot "..\build-rocm-$GpuTarget"),
    [int] $Jobs = [Environment]::ProcessorCount
)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceDir)
$build = [IO.Path]::GetFullPath($BuildDir)

if (-not (Test-Path (Join-Path $source 'CMakeLists.txt'))) {
    throw "llama.cpp source not found at '$source'. Run: git submodule update --init --recursive"
}
if (-not $env:HIP_PATH) {
    throw 'HIP_PATH is not set. Install the AMD ROCm/HIP SDK or activate the TheRock environment.'
}

$clang = Join-Path $env:HIP_PATH 'lib\llvm\bin\clang.exe'
$clangxx = Join-Path $env:HIP_PATH 'lib\llvm\bin\clang++.exe'
if (-not (Test-Path $clang) -or -not (Test-Path $clangxx)) {
    throw "ROCm clang was not found below HIP_PATH '$env:HIP_PATH'."
}

& cmake -S $source -B $build -G 'Unix Makefiles' `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_PREFIX_PATH=$env:HIP_PATH" `
    "-DCMAKE_C_COMPILER=$clang" `
    "-DCMAKE_CXX_COMPILER=$clangxx" `
    "-DCMAKE_HIP_COMPILER=$clang" `
    "-DHIP_PATH=$env:HIP_PATH" `
    -DGGML_HIP=ON `
    -DGGML_CUDA_NO_PEER_COPY=ON `
    -DGGML_HIP_NO_VMM=ON `
    -DGGML_NATIVE=OFF `
    -DGGML_BACKEND_DL=ON `
    "-DGPU_TARGETS=$GpuTarget"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)." }
& cmake --build $build --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw "CMake build failed ($LASTEXITCODE)." }

Write-Host "ROCm build complete: $build\bin"
