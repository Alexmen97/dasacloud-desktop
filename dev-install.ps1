<#
.SYNOPSIS
    Build and register the DasaCloud app for development testing.

.DESCRIPTION
    This script builds the DasaCloud application, stages a development package with the
    correct version and architecture, and registers it for shell-integration testing.

.PARAMETER Version
    Override the version from tauri.conf.json. Format: "X.Y.Z" (will be converted to "X.Y.Z.0")

.PARAMETER SkipBuild
    Skip the cargo build step (useful if binary is already built)

.PARAMETER Publisher
    Development MSIX publisher. This is only for local Developer Mode testing and
    is not the identity to use for a public release.

.EXAMPLE
    .\dev-install.ps1
    # Build and register with version from tauri.conf.json

.EXAMPLE
    .\dev-install.ps1 -Version "1.0.0"
    # Build and register with custom version

.EXAMPLE
    .\dev-install.ps1 -SkipBuild
    # Register without rebuilding (use existing binary)
#>

param(
    [string]$Version,
    [switch]$SkipBuild,
    [string]$Publisher = "CN=DasaCloud Development",
    [string]$PublisherDisplayName = "DasaCloud Development"
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TauriConfigPath = Join-Path $ScriptDir "src-tauri\tauri.conf.json"
$ManifestPath = Join-Path $ScriptDir "package\AppxManifest.xml"
$PackageDir = Join-Path $ScriptDir "package"
$TempPackageDir = Join-Path $env:TEMP "dasacloud-dev-package"

# Detect architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
        "arm64"
    } else {
        "x64"
    }
} else {
    Write-Error "32-bit Windows is not supported"
    exit 1
}

Write-Host "Detected architecture: $Arch" -ForegroundColor Cyan

# Get version from tauri.conf.json if not provided
if (-not $Version) {
    Write-Host "Reading version from tauri.conf.json..." -ForegroundColor Cyan
    $TauriConfig = Get-Content $TauriConfigPath -Raw | ConvertFrom-Json
    $Version = $TauriConfig.version
}

# Convert to 4-part version for MSIX
$MsixVersion = if ($Version -match '^\d+\.\d+\.\d+$') {
    "$Version.0"
} elseif ($Version -match '^\d+\.\d+\.\d+\.\d+$') {
    $Version
} else {
    Write-Error "Invalid version format: $Version. Expected X.Y.Z or X.Y.Z.W"
    exit 1
}

Write-Host "Version: $MsixVersion" -ForegroundColor Cyan

# Build the application
if (-not $SkipBuild) {
    Write-Host "`nBuilding Tauri application (release)..." -ForegroundColor Green

    Push-Location $ScriptDir
    try {
        cargo tauri build
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Build failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`nSkipping build step..." -ForegroundColor Yellow
}

# Determine binary path
$BinaryPath = Join-Path $ScriptDir "target\release\dasacloud-desktop.exe"
if (-not (Test-Path $BinaryPath)) {
    Write-Error "Binary not found at: $BinaryPath"
    exit 1
}

# Stage package without mutating the source manifest.
Write-Host "`nStaging development package..." -ForegroundColor Green
if (Test-Path $TempPackageDir) {
    Remove-Item $TempPackageDir -Recurse -Force
}
Copy-Item $PackageDir -Destination $TempPackageDir -Recurse -Force
Copy-Item $BinaryPath -Destination $TempPackageDir -Force

# Update AppxManifest.xml
Write-Host "Updating AppxManifest.xml..." -ForegroundColor Green

$TempManifestPath = Join-Path $TempPackageDir "AppxManifest.xml"
$ManifestContent = Get-Content $TempManifestPath -Raw -Encoding UTF8

# Replace placeholders
$ManifestContent = $ManifestContent -replace '__ARCH__', $Arch
$ManifestContent = $ManifestContent -replace '__VERSION__', $MsixVersion
$ManifestContent = $ManifestContent -replace '__PUBLISHER__', $Publisher
$ManifestContent = $ManifestContent -replace '__PUBLISHER_DISPLAY_NAME__', $PublisherDisplayName

# Write back with UTF-8 BOM (required for AppxManifest.xml)
$Utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($TempManifestPath, $ManifestContent, $Utf8Bom)

# Register the package
Write-Host "`nRegistering package..." -ForegroundColor Green
Write-Host "Running: Add-AppxPackage -Register `"$TempManifestPath`"" -ForegroundColor DarkGray

Add-AppxPackage -Register $TempManifestPath

Write-Host "`nDone! Package registered successfully." -ForegroundColor Green
Write-Host "You can now test shell integration features." -ForegroundColor Cyan
