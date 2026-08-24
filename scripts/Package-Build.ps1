[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BuildDir,
    [Parameter(Mandatory)] [string] $Name,
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$build = [IO.Path]::GetFullPath($BuildDir)
$output = [IO.Path]::GetFullPath($OutputDir)
$binCandidates = @((Join-Path $build 'bin\Release'), (Join-Path $build 'bin'))
$bin = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bin) { throw "No build output found below '$build'." }

New-Item -ItemType Directory -Path $output -Force | Out-Null
$archive = Join-Path $output "$Name.zip"
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }
Compress-Archive -Path (Join-Path $bin '*') -DestinationPath $archive -CompressionLevel Optimal
Write-Host "Package created: $archive"
