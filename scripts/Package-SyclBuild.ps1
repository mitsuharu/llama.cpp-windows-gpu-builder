[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BuildDir,
    [string] $OneApiRoot = $env:ONEAPI_ROOT,
    [string] $LevelZeroSdkRoot = $env:LEVEL_ZERO_V1_SDK_PATH,
    [Parameter(Mandatory)] [string] $Name,
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
if (-not $OneApiRoot) { throw 'OneApiRoot is not set. Pass -OneApiRoot or set ONEAPI_ROOT.' }
$build = [IO.Path]::GetFullPath($BuildDir)
$oneApi = [IO.Path]::GetFullPath($OneApiRoot)
$output = [IO.Path]::GetFullPath($OutputDir)
if ([IO.Path]::GetFileName($Name) -ne $Name) {
    throw 'Name must be a file name without directory components.'
}
$binCandidates = @((Join-Path $build 'bin\Release'), (Join-Path $build 'bin'))
$bin = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bin) { throw "No build output found below '$build'." }
if (-not (Test-Path $oneApi -PathType Container)) { throw "oneAPI root not found: $oneApi" }

$backend = Join-Path $bin 'ggml-sycl.dll'
if (-not (Test-Path $backend -PathType Leaf)) { throw "SYCL backend not found: $backend" }

New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path $output $Name
$archive = Join-Path $output "$Name.zip"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $bin '*') -Destination $stage -Recurse -Force

# ggml-sycl.dll depends on the oneAPI DPC++ runtime, oneMKL, oneDNN, and oneTBB.
# Bundle the same redistributable files as the upstream llama.cpp windows-sycl
# release job so the package runs with only the Intel GPU driver installed.
# Versioned file names (sycl9.dll, mkl_core.3.dll, ...) are matched by pattern
# so that a oneAPI update does not silently drop a renamed DLL.
$runtimeFiles = @(
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_sycl_blas\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_core\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_def\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_avx2\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_tbb_thread\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^mkl_intel_thread\.\d+\.dll$' },
    @{ Dir = 'mkl\latest\bin'; Pattern = '^libimalloc\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^ur_adapter_level_zero\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^ur_adapter_level_zero_v2\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^ur_loader_shared\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^ur_win_proxy_loader\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^sycl\d+\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^svml_dispmd\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^libmmd\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^libiomp5md\.dll$' },
    @{ Dir = 'compiler\latest\bin'; Pattern = '^sycl-ls\.exe$' },
    @{ Dir = 'dnnl\latest\bin'; Pattern = '^dnnl\.dll$' },
    @{ Dir = 'tbb\latest\bin'; Pattern = '^tbb12\.dll$' },
    @{ Dir = 'tcm\latest\bin'; Pattern = '^tcm\.dll$' },
    @{ Dir = 'tcm\latest\bin'; Pattern = '^libhwloc-\d+\.dll$' },
    @{ Dir = 'umf\latest\bin'; Pattern = '^umf\.dll$' }
)
$missing = @()
foreach ($entry in $runtimeFiles) {
    $directory = Join-Path $oneApi $entry.Dir
    $found = Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $entry.Pattern } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($found) {
        Copy-Item -LiteralPath $found.FullName -Destination $stage -Force
        Write-Host "Bundled $($found.Name) from $($found.DirectoryName)"
    } else {
        $missing += "$($entry.Dir)\$($entry.Pattern)"
    }
}
if ($missing) { throw "oneAPI runtime files were not found below '$oneApi': $($missing -join ', ')" }

# The Level Zero loader is normally installed by the Intel GPU driver. Bundle it
# when oneAPI or the Level Zero SDK provides one, matching the upstream package.
$zeSearchRoots = @($oneApi)
if ($LevelZeroSdkRoot -and (Test-Path $LevelZeroSdkRoot -PathType Container)) { $zeSearchRoots += $LevelZeroSdkRoot }
$zeLoader = $zeSearchRoots |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'ze_loader.dll' -File -Recurse -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if ($zeLoader) {
    Copy-Item -LiteralPath $zeLoader.FullName -Destination $stage -Force
    Write-Host "Bundled ze_loader.dll from $($zeLoader.DirectoryName)"
} else {
    Write-Warning 'ze_loader.dll was not found; the package relies on the Level Zero loader installed by the Intel GPU driver.'
}

$licenseDestination = Join-Path $stage 'licenses\oneapi'
New-Item -ItemType Directory -Path $licenseDestination -Force | Out-Null
# oneAPI keeps shared license texts in <root>\licensing and per-component texts in
# <component>\latest\licensing (or share\doc). Copy every one that exists.
$licenseSources = @(
    @{ Source = 'licensing'; Destination = '.' },
    @{ Source = 'compiler\latest\licensing'; Destination = 'compiler' },
    @{ Source = 'compiler\latest\share\doc'; Destination = 'compiler' },
    @{ Source = 'mkl\latest\licensing'; Destination = 'mkl' },
    @{ Source = 'mkl\latest\share\doc'; Destination = 'mkl' },
    @{ Source = 'dnnl\latest\licensing'; Destination = 'dnnl' },
    @{ Source = 'dnnl\latest\share\doc'; Destination = 'dnnl' },
    @{ Source = 'tbb\latest\licensing'; Destination = 'tbb' },
    @{ Source = 'tbb\latest\share\doc'; Destination = 'tbb' },
    @{ Source = 'tcm\latest\licensing'; Destination = 'tcm' },
    @{ Source = 'umf\latest\licensing'; Destination = 'umf' }
)
$licenseCount = 0
foreach ($entry in $licenseSources) {
    $source = Join-Path $oneApi $entry.Source
    if (-not (Test-Path $source -PathType Container)) { continue }
    $files = Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)(licen[cs]e|eula|third-party|notice)' }
    foreach ($file in $files) {
        $destination = Join-Path $licenseDestination $entry.Destination
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination $file.Name) -Force
        $licenseCount++
    }
}
if ($licenseCount -eq 0) { throw "No oneAPI license files were found below '$oneApi'." }
Write-Host "Bundled $licenseCount oneAPI license file(s)."

$projectLicense = Join-Path $PSScriptRoot '..\LICENSE'
$llamaLicense = Join-Path $PSScriptRoot '..\vendor\llama.cpp\LICENSE'
Copy-Item -LiteralPath $projectLicense -Destination (Join-Path $stage 'licenses\builder-LICENSE.txt')
Copy-Item -LiteralPath $llamaLicense -Destination (Join-Path $stage 'licenses\llama.cpp-LICENSE.txt')

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Self-contained SYCL package created: $archive"
