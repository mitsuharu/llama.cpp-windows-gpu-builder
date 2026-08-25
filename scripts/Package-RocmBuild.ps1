[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BuildDir,
    [Parameter(Mandatory)] [string] $RocmRoot,
    [string] $RuntimeRoot = $RocmRoot,
    [Parameter(Mandatory)] [string] $Name,
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$build = [IO.Path]::GetFullPath($BuildDir)
$rocm = [IO.Path]::GetFullPath($RocmRoot)
$runtime = [IO.Path]::GetFullPath($RuntimeRoot)
$output = [IO.Path]::GetFullPath($OutputDir)
if ([IO.Path]::GetFileName($Name) -ne $Name) {
    throw 'Name must be a file name without directory components.'
}
$binCandidates = @((Join-Path $build 'bin\Release'), (Join-Path $build 'bin'))
$bin = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bin) { throw "No build output found below '$build'." }
if (-not (Test-Path $rocm -PathType Container)) { throw "ROCm root not found: $rocm" }
if (-not (Test-Path $runtime -PathType Container)) { throw "ROCm runtime search root not found: $runtime" }

$backend = Join-Path $bin 'ggml-hip.dll'
if (-not (Test-Path $backend -PathType Leaf)) { throw "ROCm backend not found: $backend" }

New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path $output $Name
$archive = Join-Path $output "$Name.zip"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $bin '*') -Destination $stage -Recurse -Force

$collector = Join-Path $PSScriptRoot 'Collect-RocmRuntime.cmake'
& cmake "-DBACKEND_DLL=$backend" "-DROCM_ROOT=$rocm" "-DRUNTIME_ROOT=$runtime" "-DDESTINATION=$stage" -P $collector
if ($LASTEXITCODE -ne 0) { throw "ROCm dependency collection failed: $LASTEXITCODE" }

$rocblasCandidates = @(
    (Join-Path $rocm 'bin\rocblas'),
    (Join-Path $rocm 'lib\rocblas'),
    (Join-Path $runtime 'bin\rocblas'),
    (Join-Path $runtime 'lib\rocblas')
)
$rocblas = $rocblasCandidates | Where-Object { Test-Path $_ -PathType Container } | Select-Object -First 1
if (-not $rocblas) {
    $rocblas = Get-ChildItem -LiteralPath $runtime -Directory -Filter 'rocblas' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'library') -PathType Container } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $rocblas) { throw "rocBLAS kernel directory was not found below '$rocm' or '$runtime'." }
Copy-Item -LiteralPath $rocblas -Destination (Join-Path $stage 'rocblas') -Recurse -Force

$licenseDestination = Join-Path $stage 'licenses\rocm'
New-Item -ItemType Directory -Path $licenseDestination -Force | Out-Null
$licenseFiles = @($rocm, $runtime) | Select-Object -Unique |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -ErrorAction SilentlyContinue } |
    Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)(\..*)?$' }
if (-not $licenseFiles) { throw "No ROCm license files were found below '$rocm'." }
foreach ($license in $licenseFiles) {
    $licenseRoot = if ($license.FullName.StartsWith($rocm, [StringComparison]::OrdinalIgnoreCase)) { $rocm } else { $runtime }
    $relative = [IO.Path]::GetRelativePath($licenseRoot, $license.FullName)
    $target = Join-Path $licenseDestination $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $license.FullName -Destination $target -Force
}

$projectLicense = Join-Path $PSScriptRoot '..\LICENSE'
$llamaLicense = Join-Path $PSScriptRoot '..\vendor\llama.cpp\LICENSE'
Copy-Item -LiteralPath $projectLicense -Destination (Join-Path $stage 'licenses\builder-LICENSE.txt')
Copy-Item -LiteralPath $llamaLicense -Destination (Join-Path $stage 'licenses\llama.cpp-LICENSE.txt')

$requiredDlls = @('ggml-hip.dll', 'hipblas.dll', 'rocblas.dll', 'rocsolver.dll')
$missing = $requiredDlls | Where-Object { -not (Test-Path (Join-Path $stage $_)) }
$hipRuntime = Get-ChildItem -LiteralPath $stage -Filter 'amdhip64*.dll' -File
$comgrRuntime = Get-ChildItem -LiteralPath $stage -Filter 'amd_comgr*.dll' -File
$kernelFiles = Get-ChildItem -LiteralPath (Join-Path $stage 'rocblas') -Recurse -File
if (-not $hipRuntime) { $missing += 'amdhip64*.dll' }
if (-not $comgrRuntime) { $missing += 'amd_comgr*.dll' }
if (-not $kernelFiles) { $missing += 'rocblas\library contents' }
if ($missing) { throw "ROCm package is incomplete: $($missing -join ', ')" }

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Self-contained ROCm package created: $archive"
