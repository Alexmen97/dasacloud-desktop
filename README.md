# DasaCloud

Windows desktop client for [DasaCloud](https://dasacloud.proserver.cc), with real-time file sync and Windows Explorer integration. It is a branded distribution of [Cloudreve Desktop](https://github.com/cloudreve/desktop), built with Tauri and React.

## Downloads

Official downloads are published on the repository's [Releases](https://github.com/Alexmen97/dasacloud-desktop/releases) page.

- `DasaCloud-Setup-x64.exe` is the installer for 64-bit Intel and AMD Windows PCs.
- `DasaCloud.x64.msix` is available for managed deployments that install MSIX directly.

The first test build uses an included development certificate, so Windows will display a trust warning. This is expected for a test build. Public releases will use a publicly trusted code-signing certificate before being advertised as production downloads.

## Features

- Real-time bidirectional file synchronization
- On-demand file hydration (files download only when accessed)
- Windows Explorer integration (context menus, thumbnails, custom states)
- DasaCloud sign-in preconfigured at `https://dasacloud.proserver.cc`
- System tray application

## Prerequisites

### For Users

- Windows 10 version 1903 (build 18362) or later
- A DasaCloud account

### For Developers

- **Windows 10/11** with [Developer Mode enabled](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development)
- **Rust** toolchain (install via [rustup](https://rustup.rs/))
- **Node.js** 18+ and **Yarn**
- **Windows SDK** (for MSIX packaging)

Enable Developer Mode:
```
Settings → Privacy & security → For developers → Developer Mode → On
```

Install Rust targets for cross-compilation:
```powershell
rustup target add x86_64-pc-windows-msvc
rustup target add aarch64-pc-windows-msvc
```

## Build & Run

### Quick Start (Development)

```powershell
# Install frontend dependencies
cd ui
yarn install
cd ..

# Run in development mode with hot reload
cargo tauri dev
```

### Release Build

```powershell
cargo tauri build
```

The built binary will be at `target/release/dasacloud-desktop.exe`.

## Development Installation (Full Feature Testing)

The basic `cargo tauri dev/build` only produces the binary. For testing **shell integration features** (context menus, thumbnails, cloud file states), you need to register the app as an MSIX package.

### Using dev-install.ps1

```powershell
# Build and register for development
.\dev-install.ps1

# Skip build if binary already exists
.\dev-install.ps1 -SkipBuild

# Use custom version
.\dev-install.ps1 -Version "1.0.0"
```

This script will:
1. Builds the Tauri application in release mode.
2. Stages a local package without modifying the source manifest.
3. Registers it with `Add-AppxPackage -Register` for full Explorer integration.

### Unregister Development Package

```powershell
Get-AppxPackage -Name "Proserver.DasaCloud" | Remove-AppxPackage
```

## Building MSIX Packages

For distribution, use `build-msix.ps1` to create signed MSIX packages. The MSIX publisher must exactly match the subject of the signing certificate: do not invent or change it after publishing the first release, otherwise Windows will treat it as a different application.

```powershell
# Build x64 and ARM64 packages and a signed bundle
.\build-msix.ps1 `
  -Publisher "CN=Your legal publisher" `
  -PublisherDisplayName "DasaCloud" `
  -CertificatePath "C:\secure\dasacloud-signing.pfx"

# Build for specific architecture
.\build-msix.ps1 -Arch x64 -Publisher "CN=Your legal publisher"
.\build-msix.ps1 -Arch arm64 -Publisher "CN=Your legal publisher"

# Skip build (use existing binaries)
.\build-msix.ps1 -SkipBuild -Publisher "CN=Your legal publisher"

# Custom version
.\build-msix.ps1 -Version "1.0.1" -Publisher "CN=Your legal publisher"
```

Output files:
```
dist/
├── DasaCloud.x64.msix
├── DasaCloud.arm64.msix
└── DasaCloud.msixbundle
```

### Requirements for MSIX Building

- Windows SDK with `makeappx.exe` and `signtool.exe` (automatically detected)
- A code-signing certificate in PFX format for releases outside Developer Mode
- The certificate subject must match `-Publisher`

## Installing a release

Distribute the signed `.msixbundle` with `install-dasacloud.ps1`. On a customer machine:

```powershell
.\install-dasacloud.ps1 -PackagePath .\DasaCloud.msixbundle
```

Publicly trusted code-signing certificates install normally. For an internal self-signed release, include the matching `.cer` certificate and run:

```powershell
.\install-dasacloud.ps1 `
  -PackagePath .\DasaCloud.msixbundle `
  -CertificatePath .\DasaCloud-signing.cer
```

## Project Structure

```
├── src-tauri/           # Tauri application shell
├── crates/
│   ├── cloudreve-sync/  # Core sync service
│   ├── cloudreve-api/   # REST client for Cloudreve server
│   └── win32_notif/     # Windows notification utilities
├── ui/                  # React frontend (Vite + MUI)
├── package/             # MSIX packaging assets
├── dev-install.ps1      # Dev build + register script
├── build-msix.ps1       # Signed production MSIX builder
├── build-installer.ps1  # Compiles the signed MSIX Setup .exe
├── install-dasacloud.ps1 # End-user MSIX installer
└── .github/workflows/   # Test and production Windows builds
```

## License

The DasaCloud distribution and its upstream components are licensed under [MIT](LICENSE). The original Cloudreve Desktop copyright and license notices are retained.
