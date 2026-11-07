[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86', 'arm64')]
    [string] $Architecture = 'x64'
)

# llama.cpp v0.9.0 and later embed an application manifest in every Windows
# executable. When ROCm clang links through lld-link outside a Visual Studio
# developer shell, lld-link needs mt.exe on PATH to merge that manifest.
# This script returns the directory that holds the newest Windows SDK mt.exe.

$ErrorActionPreference = 'Stop'

$existing = Get-Command mt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    return Split-Path -Parent $existing.Source
}

$kitsRoots = @()
foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots')) {
    $value = Get-ItemProperty -LiteralPath $key -Name KitsRoot10 -ErrorAction SilentlyContinue
    if ($value -and $value.KitsRoot10) { $kitsRoots += $value.KitsRoot10 }
}
if (${env:ProgramFiles(x86)}) {
    $kitsRoots += Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
}

$candidates = foreach ($root in ($kitsRoots | Select-Object -Unique)) {
    $bin = Join-Path $root 'bin'
    if (-not (Test-Path -LiteralPath $bin)) { continue }
    Get-ChildItem -LiteralPath $bin -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $version = $null
        if (-not [version]::TryParse($_.Name, [ref] $version)) { return }
        $mt = Join-Path $_.FullName "$Architecture\mt.exe"
        if (Test-Path -LiteralPath $mt) {
            [pscustomobject]@{ Version = $version; Directory = Split-Path -Parent $mt }
        }
    }
}

$selected = $candidates | Sort-Object Version -Descending | Select-Object -First 1
if (-not $selected) {
    throw "mt.exe ($Architecture) was not found. Install the Windows SDK (Visual Studio 'Desktop development with C++' workload)."
}
return $selected.Directory
