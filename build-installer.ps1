<#
.SYNOPSIS
    Creates a DasaCloud Setup executable containing a signed MSIX package.

.DESCRIPTION
    Compiles the included Windows bootstrapper with the .NET Framework C#
    compiler. The Setup executable embeds the MSIX package and, when supplied,
    an internal test certificate. At install time it extracts the files,
    trusts the test certificate for the current user, and runs Add-AppxPackage.

    When SigningCertificatePath is supplied, the generated Setup executable is
    Authenticode-signed with that same certificate.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$TrustCertificatePath,
    [string]$SigningCertificatePath,
    [string]$CertificatePassword
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$ResolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$ResolvedTrustCertificatePath = $null
$ResolvedSigningCertificatePath = $null
$BootstrapperSourcePath = Join-Path $ScriptDir "installer\Bootstrapper.cs"

if ([System.IO.Path]::GetExtension($ResolvedPackagePath).ToLowerInvariant() -notin @(".msix", ".msixbundle")) {
    throw "PackagePath must point to an .msix or .msixbundle file."
}

if (-not (Test-Path $BootstrapperSourcePath)) {
    throw "Bootstrapper source was not found at $BootstrapperSourcePath."
}

if ($TrustCertificatePath) {
    $ResolvedTrustCertificatePath = (Resolve-Path -LiteralPath $TrustCertificatePath).Path
    if ([System.IO.Path]::GetExtension($ResolvedTrustCertificatePath).ToLowerInvariant() -ne ".cer") {
        throw "TrustCertificatePath must point to a public .cer file."
    }
}

if ($SigningCertificatePath) {
    $ResolvedSigningCertificatePath = (Resolve-Path -LiteralPath $SigningCertificatePath).Path
    if ([System.IO.Path]::GetExtension($ResolvedSigningCertificatePath).ToLowerInvariant() -ne ".pfx") {
        throw "SigningCertificatePath must point to a .pfx file."
    }
}

function Find-CSharpCompiler {
    $Candidates = @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
    )

    return $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Find-SignTool {
    $SdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    )

    foreach ($SdkPath in $SdkPaths) {
        if (-not (Test-Path $SdkPath)) {
            continue
        }

        $Versions = Get-ChildItem $SdkPath -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [Version]$_.Name } -Descending

        foreach ($Version in $Versions) {
            $SignTool = Join-Path $Version.FullName "x64\signtool.exe"
            if (Test-Path $SignTool) {
                return $SignTool
            }
        }
    }

    return $null
}

$CSharpCompiler = Find-CSharpCompiler
if (-not $CSharpCompiler) {
    throw "The .NET Framework C# compiler was not found. Run this script on Windows 10 or later."
}

$OutputDirectory = Split-Path -Parent $ResolvedOutputPath
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Test-Path $ResolvedOutputPath) {
    Remove-Item $ResolvedOutputPath -Force
}

$CompilerArguments = @(
    "/nologo",
    "/target:winexe",
    "/platform:x64",
    "/optimize+",
    "/out:$ResolvedOutputPath",
    "/r:System.Windows.Forms.dll",
    "/resource:$ResolvedPackagePath,DasaCloud.x64.msix"
)
if ($ResolvedTrustCertificatePath) {
    $CompilerArguments += "/resource:$ResolvedTrustCertificatePath,DasaCloud-Test.cer"
}
$CompilerArguments += $BootstrapperSourcePath

& $CSharpCompiler @CompilerArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ResolvedOutputPath)) {
    throw "The DasaCloud Setup bootstrapper could not be compiled."
}

if ($ResolvedSigningCertificatePath) {
    $SignTool = Find-SignTool
    if (-not $SignTool) {
        throw "signtool.exe was not found. Install the Windows SDK before signing the Setup executable."
    }

    $SignArguments = @("sign", "/fd", "SHA256", "/f", $ResolvedSigningCertificatePath)
    if ($CertificatePassword) {
        $SignArguments += @("/p", $CertificatePassword)
    }
    $SignArguments += @("/tr", "http://timestamp.digicert.com", "/td", "SHA256", $ResolvedOutputPath)
    & $SignTool @SignArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Signing failed for $ResolvedOutputPath with exit code $LASTEXITCODE."
    }
}

Write-Host "Created installer: $ResolvedOutputPath" -ForegroundColor Green
