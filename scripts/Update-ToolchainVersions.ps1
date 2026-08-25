[CmdletBinding()]
param(
    [string] $WorkflowPath = (Join-Path $PSScriptRoot '..\.github\workflows\build-windows-gpu.yml'),
    [string] $ReadmePath = (Join-Path $PSScriptRoot '..\README.md'),
    [string] $RocmTarget = 'gfx1201'
)

$ErrorActionPreference = 'Stop'

function Get-StableVersionsFromPip {
    param([Parameter(Mandatory)] [string] $Package)

    $output = & python -m pip index versions $Package --index-url https://repo.amd.com/rocm/whl-multi-arch/ 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query ROCm package '$Package': $($output -join "`n")"
    }
    return @($output | Select-String -AllMatches -Pattern '(?<![0-9.])([0-9]+\.[0-9]+\.[0-9]+)(?![0-9.])' |
        ForEach-Object { foreach ($versionMatch in $_.Matches) { $versionMatch.Groups[1].Value } } |
        Sort-Object -Unique)
}

$workflow = [IO.Path]::GetFullPath($WorkflowPath)
$readme = [IO.Path]::GetFullPath($ReadmePath)
$cudaAction = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\vendor\llama.cpp\.github\actions\windows-setup-cuda\action.yml'))
foreach ($path in @($workflow, $readme, $cudaAction)) {
    if (-not (Test-Path $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$workflowText = Get-Content -LiteralPath $workflow -Raw
$current = @{}
foreach ($name in @('CUDA_VERSION', 'ROCM_VERSION', 'VULKAN_VERSION')) {
    $match = [regex]::Match($workflowText, "(?m)^\s*${name}:\s*'([^']+)'\s*$")
    if (-not $match.Success) { throw "$name was not found in $workflow." }
    $current[$name] = $match.Groups[1].Value
}

# Only select CUDA versions that the pinned llama.cpp x64 setup action can install.
$cudaVersions = Get-Content -LiteralPath $cudaAction |
    Where-Object { $_ -match "cuda_version == '([0-9]+\.[0-9]+)'" -and $_ -notmatch "cuda_arch == 'arm64'" } |
    ForEach-Object { [regex]::Match($_, "cuda_version == '([0-9]+\.[0-9]+)'").Groups[1].Value } |
    Sort-Object { [version]$_ } -Unique
if (-not $cudaVersions) { throw 'No Windows x64 CUDA versions were found in the pinned setup action.' }
$latestCuda = $cudaVersions[-1]

$rocmVersions = Get-StableVersionsFromPip -Package 'rocm'
$deviceVersions = Get-StableVersionsFromPip -Package "rocm-sdk-device-$RocmTarget"
$latestRocm = @($rocmVersions | Where-Object { $_ -in $deviceVersions } | Sort-Object { [version]$_ })[-1]
if (-not $latestRocm) { throw "No stable ROCm version with a device wheel for $RocmTarget was found." }

$latestVulkan = ([string](Invoke-RestMethod -Uri 'https://vulkan.lunarg.com/sdk/latest/windows.txt')).Trim()
if ($latestVulkan -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Unexpected Vulkan SDK version: '$latestVulkan'"
}

$latest = @{
    CUDA_VERSION = $latestCuda
    ROCM_VERSION = $latestRocm
    VULKAN_VERSION = $latestVulkan
}
$changed = $false
foreach ($name in $latest.Keys) {
    if ($current[$name] -ne $latest[$name]) {
        $workflowText = [regex]::Replace(
            $workflowText,
            "(?m)^(\s*${name}:\s*')[^']+('(\s*))$",
            "`${1}$($latest[$name])`${2}")
        $changed = $true
    }
}

if ($changed) {
    Set-Content -LiteralPath $workflow -Value $workflowText -Encoding utf8NoBOM -NoNewline
    $readmeText = Get-Content -LiteralPath $readme -Raw
    foreach ($name in $latest.Keys) {
        $readmeText = [regex]::Replace(
            $readmeText,
            "(?m)^(\s*${name}:\s*')[^']+('(\s*))$",
            "`${1}$($latest[$name])`${2}")
    }
    Set-Content -LiteralPath $readme -Value $readmeText -Encoding utf8NoBOM -NoNewline
}

Write-Host "CUDA:  $($current.CUDA_VERSION) -> $latestCuda"
Write-Host "ROCm:  $($current.ROCM_VERSION) -> $latestRocm ($RocmTarget device wheel available)"
Write-Host "Vulkan: $($current.VULKAN_VERSION) -> $latestVulkan"
if ($env:GITHUB_OUTPUT) {
    "changed=$($changed.ToString().ToLowerInvariant())" >> $env:GITHUB_OUTPUT
    "cuda=$latestCuda" >> $env:GITHUB_OUTPUT
    "rocm=$latestRocm" >> $env:GITHUB_OUTPUT
    "vulkan=$latestVulkan" >> $env:GITHUB_OUTPUT
}
