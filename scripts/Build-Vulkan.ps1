[CmdletBinding()]
param(
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\vendor\llama.cpp'),
    [string] $BuildDir = (Join-Path $PSScriptRoot '..\build-vulkan'),
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
    throw 'ninja was not found. Install Ninja and run this script from Developer PowerShell for Visual Studio.'
}
if (-not $env:VULKAN_SDK) {
    throw 'VULKAN_SDK is not set. Install the LunarG Vulkan SDK and open a new Developer PowerShell.'
}
if (-not (Test-Path (Join-Path $env:VULKAN_SDK 'Bin\glslc.exe'))) {
    throw "glslc.exe was not found below VULKAN_SDK '$env:VULKAN_SDK'."
}

$configureArgs = @(
    '-S', $source,
    '-B', $build,
    '-G', 'Ninja Multi-Config',
    '-DGGML_VULKAN=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_BACKEND_DL=ON'
)

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)." }
& cmake --build $build --config Release --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw "CMake build failed ($LASTEXITCODE)." }

$vulkanDll = Join-Path $build 'bin\Release\ggml-vulkan.dll'
if (-not (Test-Path $vulkanDll)) {
    throw "Vulkan backend was not produced: $vulkanDll"
}

Write-Host "Vulkan build complete: $build\bin\Release"
