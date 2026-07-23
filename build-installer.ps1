<#
.SYNOPSIS
    Creates a DasaCloud Setup executable containing a signed MSIX package.

.DESCRIPTION
    IExpress (included with Windows) creates a self-extracting Setup executable.
    The executable extracts the MSIX, optionally trusts a supplied internal
    certificate for the current user, and calls install-dasacloud.ps1.

    Use this only after build-msix.ps1 has created a signed MSIX package. Pass
    TrustCertificatePath for an internal release certificate to include in the
    installer, and SigningCertificatePath to Authenticode-sign the Setup file.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$TrustCertificatePath,
    [string]$SigningCertificatePath,
    [string]$CertificatePassword,
    [string]$DisplayName = "DasaCloud Setup"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$ResolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$ResolvedTrustCertificatePath = $null
$ResolvedSigningCertificatePath = $null

if ([System.IO.Path]::GetExtension($ResolvedPackagePath).ToLowerInvariant() -notin @(".msix", ".msixbundle")) {
    throw "PackagePath must point to an .msix or .msixbundle file."
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

$IExpressPath = Join-Path $env:WINDIR "System32\iexpress.exe"
if (-not (Test-Path $IExpressPath)) {
    throw "IExpress was not found at $IExpressPath. Run this script on Windows."
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

$OutputDirectory = Split-Path -Parent $ResolvedOutputPath
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Test-Path $ResolvedOutputPath) {
    Remove-Item $ResolvedOutputPath -Force
}

$StagingDirectory = Join-Path $env:TEMP ("dasacloud-installer-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null

try {
    $PackageFileName = Split-Path -Leaf $ResolvedPackagePath
    Copy-Item -LiteralPath $ResolvedPackagePath -Destination (Join-Path $StagingDirectory $PackageFileName)
    Copy-Item -LiteralPath (Join-Path $ScriptDir "install-dasacloud.ps1") -Destination (Join-Path $StagingDirectory "install-dasacloud.ps1")

    $Files = @("install-dasacloud.ps1", $PackageFileName)
    $InstallArguments = "-PackagePath `"$PackageFileName`""
    if ($ResolvedTrustCertificatePath) {
        $CertificateFileName = Split-Path -Leaf $ResolvedTrustCertificatePath
        Copy-Item -LiteralPath $ResolvedTrustCertificatePath -Destination (Join-Path $StagingDirectory $CertificateFileName)
        $Files += $CertificateFileName
        $InstallArguments += " -CertificatePath `"$CertificateFileName`""
    }

    $FileDeclarations = for ($Index = 0; $Index -lt $Files.Count; $Index++) {
        "FILE$Index=`"$($Files[$Index])`""
    }
    $SourceEntries = for ($Index = 0; $Index -lt $Files.Count; $Index++) {
        "%FILE$Index%="
    }

    $SedPath = Join-Path $StagingDirectory "DasaCloud-Setup.sed"
    $SedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=DasaCloud was installed successfully.
TargetName=$ResolvedOutputPath
FriendlyName=$DisplayName
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-dasacloud.ps1 $InstallArguments
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
$($FileDeclarations -join "`r`n")
[SourceFiles]
SourceFiles0=$StagingDirectory\
[SourceFiles0]
$($SourceEntries -join "`r`n")
"@

    [System.IO.File]::WriteAllText($SedPath, $SedContent, [System.Text.Encoding]::ASCII)
    & $IExpressPath /N $SedPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ResolvedOutputPath)) {
        throw "IExpress failed to create $ResolvedOutputPath."
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
} finally {
    if (Test-Path $StagingDirectory) {
        Remove-Item $StagingDirectory -Recurse -Force
    }
}
