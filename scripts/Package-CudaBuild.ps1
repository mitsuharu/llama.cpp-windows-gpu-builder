[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BuildDir,
    [string] $CudaRoot = $env:CUDA_PATH,
    [Parameter(Mandatory)] [string] $Name,
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
if (-not $CudaRoot) { throw 'CudaRoot is not set. Pass -CudaRoot or set CUDA_PATH.' }
$build = [IO.Path]::GetFullPath($BuildDir)
$cuda = [IO.Path]::GetFullPath($CudaRoot)
$output = [IO.Path]::GetFullPath($OutputDir)
if ([IO.Path]::GetFileName($Name) -ne $Name) {
    throw 'Name must be a file name without directory components.'
}
$binCandidates = @((Join-Path $build 'bin\Release'), (Join-Path $build 'bin'))
$bin = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bin) { throw "No build output found below '$build'." }
if (-not (Test-Path $cuda -PathType Container)) { throw "CUDA root not found: $cuda" }

$backend = Join-Path $bin 'ggml-cuda.dll'
if (-not (Test-Path $backend -PathType Leaf)) { throw "CUDA backend not found: $backend" }

New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path $output $Name
$archive = Join-Path $output "$Name.zip"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $bin '*') -Destination $stage -Recurse -Force

# ggml-cuda.dll links against the CUDA runtime and cuBLAS. Place the redistributable
# DLLs next to the executables so the package runs without a CUDA Toolkit installation.
# Depending on the CUDA version and installer, they are in bin, bin\x64, or lib.
$runtimeDirectories = @(
    (Join-Path $cuda 'bin\x64'),
    (Join-Path $cuda 'bin'),
    (Join-Path $cuda 'lib')
) | Where-Object { Test-Path $_ -PathType Container }
$runtimePatterns = @('cudart64_*.dll', 'cublas64_*.dll', 'cublasLt64_*.dll')
$missing = @()
foreach ($pattern in $runtimePatterns) {
    $found = $runtimeDirectories |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter $pattern -File -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if ($found) {
        Copy-Item -LiteralPath $found.FullName -Destination $stage -Force
        Write-Host "Bundled $($found.Name) from $($found.DirectoryName)"
    } else {
        $missing += $pattern
    }
}
if ($missing) { throw "CUDA runtime DLLs were not found below '$cuda': $($missing -join ', ')" }

$licenseDestination = Join-Path $stage 'licenses\cuda'
New-Item -ItemType Directory -Path $licenseDestination -Force | Out-Null
$licenseFiles = Get-ChildItem -LiteralPath $cuda -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(LICENSE|LICENCE|EULA|NOTICE)(\..*)?$' }
if (-not $licenseFiles) { throw "No CUDA license files (LICENSE or EULA) were found in '$cuda'." }
foreach ($license in $licenseFiles) {
    Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $licenseDestination $license.Name) -Force
}

$projectLicense = Join-Path $PSScriptRoot '..\LICENSE'
$llamaLicense = Join-Path $PSScriptRoot '..\vendor\llama.cpp\LICENSE'
Copy-Item -LiteralPath $projectLicense -Destination (Join-Path $stage 'licenses\builder-LICENSE.txt')
Copy-Item -LiteralPath $llamaLicense -Destination (Join-Path $stage 'licenses\llama.cpp-LICENSE.txt')

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Self-contained CUDA package created: $archive"
