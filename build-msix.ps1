<#
.SYNOPSIS
    Build signed MSIX packages and a bundle for DasaCloud.

.DESCRIPTION
    This script cross-compiles the DasaCloud application for x64 and/or ARM64,
    creates MSIX packages using makeappx.exe from Windows SDK, optionally signs
    them, and generates an MSIX bundle containing all architectures.

.PARAMETER Arch
    Target architecture: "x64", "arm64", or "all" (default: "all")

.PARAMETER Version
    Override the version from tauri.conf.json. Format: "X.Y.Z" (will be converted to "X.Y.Z.0")

.PARAMETER SkipBuild
    Skip the cargo build step (use existing binaries)

.PARAMETER OutputDir
    Output directory for MSIX files (default: "dist")

.PARAMETER Publisher
    Publisher subject for the MSIX identity, for example "CN=Proserver S.r.l.".
    It must exactly match the subject of the signing certificate.

.PARAMETER PublisherDisplayName
    Name displayed in Windows as the package publisher.

.PARAMETER CertificatePath
    Optional path to the PFX code-signing certificate. When provided, every
    MSIX package and the final bundle are signed with SHA-256 and timestamped.

.PARAMETER CertificatePassword
    Password protecting CertificatePath, if one is configured.

.EXAMPLE
    .\build-msix.ps1
    # Build MSIX packages for both x64 and ARM64, then create bundle

.EXAMPLE
    .\build-msix.ps1 -Arch x64
    # Build MSIX package for x64 only (no bundle)

.EXAMPLE
    .\build-msix.ps1 -Arch arm64 -Version "1.0.0" -Publisher "CN=Proserver S.r.l."
    # Build ARM64 package with custom version (no bundle)
#>

param(
    [ValidateSet("x64", "arm64", "all")]
    [string]$Arch = "all",
    [string]$Version,
    [switch]$SkipBuild,
    [string]$OutputDir = "dist",
    [string]$Publisher = $env:DASACLOUD_MSIX_PUBLISHER,
    [string]$PublisherDisplayName = $env:DASACLOUD_PUBLISHER_DISPLAY_NAME,
    [string]$CertificatePath = $env:DASACLOUD_SIGNING_CERTIFICATE_PATH,
    [string]$CertificatePassword = $env:DASACLOUD_SIGNING_CERTIFICATE_PASSWORD
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TauriConfigPath = Join-Path $ScriptDir "src-tauri\tauri.conf.json"
$ManifestPath = Join-Path $ScriptDir "package\AppxManifest.xml"
$PackageDir = Join-Path $ScriptDir "package"
$OutputPath = Join-Path $ScriptDir $OutputDir

if ([string]::IsNullOrWhiteSpace($Publisher)) {
    Write-Error "Publisher is required. Use -Publisher 'CN=Your legal publisher' or set DASACLOUD_MSIX_PUBLISHER."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($PublisherDisplayName)) {
    $PublisherDisplayName = "DasaCloud"
}

# Architecture mapping
$ArchMap = @{
    "x64" = @{
        RustTarget = "x86_64-pc-windows-msvc"
        MsixArch = "x64"
    }
    "arm64" = @{
        RustTarget = "aarch64-pc-windows-msvc"
        MsixArch = "arm64"
    }
}

# Find makeappx.exe from Windows SDK
function Find-MakeAppx {
    $SdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    )

    foreach ($SdkPath in $SdkPaths) {
        if (Test-Path $SdkPath) {
            # Find all version directories and sort descending
            $Versions = Get-ChildItem $SdkPath -Directory |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                Sort-Object { [Version]$_.Name } -Descending

            foreach ($Ver in $Versions) {
                $MakeAppx = Join-Path $Ver.FullName "x64\makeappx.exe"
                if (Test-Path $MakeAppx) {
                    return $MakeAppx
                }
            }
        }
    }

    return $null
}

function Find-SignTool {
    $SdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    )

    foreach ($SdkPath in $SdkPaths) {
        if (Test-Path $SdkPath) {
            $Versions = Get-ChildItem $SdkPath -Directory |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                Sort-Object { [Version]$_.Name } -Descending

            foreach ($Ver in $Versions) {
                $SignTool = Join-Path $Ver.FullName "x64\signtool.exe"
                if (Test-Path $SignTool) {
                    return $SignTool
                }
            }
        }
    }

    return $null
}

function Sign-Package {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$SignToolPath
    )

    $SignArgs = @("sign", "/fd", "SHA256", "/f", $CertificatePath)
    if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
        $SignArgs += @("/p", $CertificatePassword)
    }
    $SignArgs += @("/tr", "http://timestamp.digicert.com", "/td", "SHA256", $FilePath)

    & $SignToolPath @SignArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Signing failed for $FilePath with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

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

# Find makeappx.exe
$MakeAppx = Find-MakeAppx
if (-not $MakeAppx) {
    Write-Error "Could not find makeappx.exe. Please install Windows SDK."
    exit 1
}
Write-Host "Found makeappx.exe: $MakeAppx" -ForegroundColor Cyan

$SignTool = $null
if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
    if (-not (Test-Path $CertificatePath)) {
        Write-Error "Signing certificate not found: $CertificatePath"
        exit 1
    }
    $SignTool = Find-SignTool
    if (-not $SignTool) {
        Write-Error "Could not find signtool.exe. Please install Windows SDK."
        exit 1
    }
    Write-Host "Signing packages with: $CertificatePath" -ForegroundColor Cyan
} else {
    Write-Warning "No signing certificate was supplied. The output is for packaging verification only and cannot be distributed for normal installation."
}

# Determine architectures to build
$TargetArchs = if ($Arch -eq "all") { @("x64", "arm64") } else { @($Arch) }

Write-Host "Target architectures: $($TargetArchs -join ', ')" -ForegroundColor Cyan

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Create temp directory for package staging
$TempBaseDir = Join-Path $env:TEMP "dasacloud-msix-build"
if (Test-Path $TempBaseDir) {
    Remove-Item $TempBaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempBaseDir -Force | Out-Null

# Track created MSIX files for bundling
$CreatedMsixFiles = @()

# Build for each architecture
foreach ($TargetArch in $TargetArchs) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Building for $TargetArch" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    $Config = $ArchMap[$TargetArch]
    $RustTarget = $Config.RustTarget
    $MsixArch = $Config.MsixArch

    # Build the application
    if (-not $SkipBuild) {
        Write-Host "`nBuilding Tauri application for $RustTarget..." -ForegroundColor Cyan

        Push-Location $ScriptDir
        try {
            cargo tauri build --target $RustTarget
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Build failed for $TargetArch with exit code $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "`nSkipping build step..." -ForegroundColor Yellow
    }

    # Determine binary path
    $BinaryPath = Join-Path $ScriptDir "target\$RustTarget\release\dasacloud-desktop.exe"
    if (-not (Test-Path $BinaryPath)) {
        Write-Error "Binary not found at: $BinaryPath"
        exit 1
    }

    # Create temp directory for this architecture
    $TempPackageDir = Join-Path $TempBaseDir $MsixArch
    Write-Host "Copying package to temp directory: $TempPackageDir" -ForegroundColor Cyan
    Copy-Item $PackageDir -Destination $TempPackageDir -Recurse -Force

    # Copy binary to temp package directory
    Write-Host "Copying binary..." -ForegroundColor Cyan
    Copy-Item $BinaryPath -Destination $TempPackageDir -Force

    # Update AppxManifest.xml in temp directory
    $TempManifestPath = Join-Path $TempPackageDir "AppxManifest.xml"
    Write-Host "Updating AppxManifest.xml for $MsixArch..." -ForegroundColor Cyan

    $ManifestContent = Get-Content $TempManifestPath -Raw -Encoding UTF8

    # Replace placeholders
    $ManifestContent = $ManifestContent -replace '__ARCH__', $MsixArch
    $ManifestContent = $ManifestContent -replace '__VERSION__', $MsixVersion
    $ManifestContent = $ManifestContent -replace '__PUBLISHER__', $Publisher
    $ManifestContent = $ManifestContent -replace '__PUBLISHER_DISPLAY_NAME__', $PublisherDisplayName

    # Write back with UTF-8 BOM
    $Utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($TempManifestPath, $ManifestContent, $Utf8Bom)

    # Create MSIX package
    $MsixPath = Join-Path $OutputPath "DasaCloud.$MsixArch.msix"
    Write-Host "Creating MSIX package: $MsixPath" -ForegroundColor Cyan

    # Remove existing package if present
    if (Test-Path $MsixPath) {
        Remove-Item $MsixPath -Force
    }

    & $MakeAppx pack /v /p $MsixPath /d $TempPackageDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "makeappx.exe pack failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    Write-Host "Created: $MsixPath" -ForegroundColor Green
    if ($SignTool) {
        Sign-Package -FilePath $MsixPath -SignToolPath $SignTool
    }
    $CreatedMsixFiles += $MsixPath
}

# Create bundle if building for all architectures
if ($Arch -eq "all" -and $CreatedMsixFiles.Count -gt 1) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Creating MSIX Bundle" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    $BundlePath = Join-Path $OutputPath "DasaCloud.msixbundle"

    # Remove existing bundle if present
    if (Test-Path $BundlePath) {
        Remove-Item $BundlePath -Force
    }

    Write-Host "Creating bundle: $BundlePath" -ForegroundColor Cyan
    & $MakeAppx bundle /v /d $OutputPath /p $BundlePath /bv $MsixVersion
    if ($LASTEXITCODE -ne 0) {
        Write-Error "makeappx.exe bundle failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    Write-Host "Created: $BundlePath" -ForegroundColor Green
    if ($SignTool) {
        Sign-Package -FilePath $BundlePath -SignToolPath $SignTool
    }
}

# Cleanup temp directory
Write-Host "`nCleaning up temp directory..." -ForegroundColor Cyan
Remove-Item $TempBaseDir -Recurse -Force

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Output files:" -ForegroundColor Cyan
Get-ChildItem $OutputPath -Filter "*.msix*" | ForEach-Object {
    Write-Host "  $($_.FullName)" -ForegroundColor White
}
