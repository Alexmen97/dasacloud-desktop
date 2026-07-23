<#
.SYNOPSIS
    Installs or updates a signed DasaCloud MSIX package.

.DESCRIPTION
    Installs an MSIX or MSIX bundle for the current Windows user. Publicly
    trusted code-signing certificates need no extra steps. For an internal
    self-signed build, pass the matching .cer file once to trust it for the
    current user before the package is installed.

.PARAMETER PackagePath
    Path to DasaCloud.x64.msix, DasaCloud.arm64.msix, or DasaCloud.msixbundle.

.PARAMETER CertificatePath
    Optional public certificate (.cer) for an internal self-signed release.

.EXAMPLE
    .\install-dasacloud.ps1 -PackagePath .\DasaCloud.msixbundle
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [string]$CertificatePath
)

$ErrorActionPreference = "Stop"

$ResolvedPackagePath = Resolve-Path -LiteralPath $PackagePath
$Extension = [System.IO.Path]::GetExtension($ResolvedPackagePath).ToLowerInvariant()
if ($Extension -notin @(".msix", ".msixbundle")) {
    throw "PackagePath must point to an .msix or .msixbundle file."
}

if ($CertificatePath) {
    $ResolvedCertificatePath = Resolve-Path -LiteralPath $CertificatePath
    if ([System.IO.Path]::GetExtension($ResolvedCertificatePath).ToLowerInvariant() -ne ".cer") {
        throw "CertificatePath must point to a .cer file."
    }

    Write-Host "Trusting the DasaCloud release certificate for the current user..." -ForegroundColor Cyan
    Import-Certificate -FilePath $ResolvedCertificatePath -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" | Out-Null
}

Write-Host "Installing DasaCloud..." -ForegroundColor Cyan
Add-AppxPackage -Path $ResolvedPackagePath
Write-Host "DasaCloud is installed and ready to use." -ForegroundColor Green
