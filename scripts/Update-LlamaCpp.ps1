[CmdletBinding()]
param(
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+$')]
    [string] $Release,
    [ValidatePattern('^b[0-9]+$')]
    [string] $Nightly,
    [switch] $LatestNightly,
    [switch] $LatestBranch,
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\vendor\llama.cpp')
)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceDir)

if (-not (Test-Path (Join-Path $source '.git'))) {
    throw "llama.cpp submodule not found at '$source'. Run: git submodule update --init --recursive"
}

$changes = & git -C $source status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect the llama.cpp submodule.' }
if ($changes) {
    throw 'The llama.cpp submodule has uncommitted changes. Commit or stash them before updating.'
}

$selectorCount = 0
if ($Release) { $selectorCount++ }
if ($Nightly) { $selectorCount++ }
if ($LatestNightly.IsPresent) { $selectorCount++ }
if ($LatestBranch.IsPresent) { $selectorCount++ }

if ($selectorCount -gt 1) {
    throw 'Release, Nightly, LatestNightly, and LatestBranch cannot be specified together.'
}

if ($Release) {
    $targetRelease = $Release
} elseif ($Nightly) {
    $targetRelease = $Nightly
} elseif ($LatestNightly) {
    $remoteTags = & git -C $source ls-remote --tags --refs origin 'refs/tags/b*'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to retrieve llama.cpp nightly tags.' }

    $latestNightlyTag = $remoteTags |
        ForEach-Object {
            if ($_ -match 'refs/tags/(b([0-9]+))$') {
                [pscustomobject]@{ Tag = $Matches[1]; Number = [long]$Matches[2] }
            }
        } |
        Sort-Object Number -Descending |
        Select-Object -First 1

    if (-not $latestNightlyTag) { throw 'No llama.cpp nightly tags were found.' }
    $targetRelease = $latestNightlyTag.Tag
} elseif ($LatestBranch) {
    & git -C $source fetch --depth=1 --prune origin master
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch the latest master branch.' }
    $target = 'origin/master'
    $label = 'the latest origin/master commit'
} else {
    $remoteTags = & git -C $source ls-remote --tags --refs origin 'refs/tags/v*'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to retrieve llama.cpp release tags.' }

    $latestRelease = $remoteTags |
        ForEach-Object {
            if ($_ -match 'refs/tags/(v([0-9]+\.[0-9]+\.[0-9]+))$') {
                [pscustomobject]@{ Tag = $Matches[1]; Version = [version]$Matches[2] }
            }
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $latestRelease) { throw 'No stable llama.cpp release tags were found.' }
    $targetRelease = $latestRelease.Tag
}

if ($targetRelease) {
    & git -C $source fetch --depth=1 origin tag $targetRelease
    if ($LASTEXITCODE -ne 0) {
        throw "Release '$targetRelease' was not found in ggml-org/llama.cpp."
    }
    $target = "refs/tags/$targetRelease"
    $label = "release $targetRelease"
}

& git -C $source checkout --detach $target
if ($LASTEXITCODE -ne 0) { throw "Failed to check out $label." }

$commit = (& git -C $source rev-parse HEAD).Trim()
Write-Host "llama.cpp updated to $label ($commit)."
Write-Host 'To record this version in the parent repository, run:'
Write-Host '  git add vendor/llama.cpp'
Write-Host '  git commit -m "Update llama.cpp submodule"'
