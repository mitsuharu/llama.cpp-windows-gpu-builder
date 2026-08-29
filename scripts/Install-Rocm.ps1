param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [uri]$IndexUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^gfx[0-9a-f]+$')]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$venvRoot = 'C:\TheRock\build\.venv'

New-Item -Path (Split-Path $venvRoot) -ItemType Directory -Force | Out-Null
python -m venv $venvRoot
if ($LASTEXITCODE -ne 0) { throw "Python virtual environment creation failed: $LASTEXITCODE" }

& (Join-Path $venvRoot 'Scripts\Activate.ps1')
python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed: $LASTEXITCODE" }

$package = "rocm[libraries,devel,device-$Target]==$Version"
Write-Host "Installing $package from $IndexUrl"
python -m pip install --index-url $IndexUrl.AbsoluteUri $package
if ($LASTEXITCODE -ne 0) {
    throw "ROCm wheel installation failed for version '$Version' and target '$Target' from '$IndexUrl'."
}

rocm-sdk init
if ($LASTEXITCODE -ne 0) { throw "rocm-sdk init failed: $LASTEXITCODE" }
