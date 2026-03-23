<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="AeroPulse icon" />
</p>

<h1 align="center">AeroPulse</h1>

<p align="center">
  Native thermal management and fan control for Apple Silicon Macs.
</p>

<p align="center">
  <a href="https://github.com/inhwa-son/aeropulse-mac/releases/latest"><img src="https://img.shields.io/github/v/release/inhwa-son/aeropulse-mac?style=flat-square" alt="Latest Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/inhwa-son/aeropulse-mac?style=flat-square" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/platform-macOS_15.0%2B-blue?style=flat-square" alt="macOS 15.0+" />
  <img src="https://img.shields.io/badge/swift-6.2-F05138?style=flat-square" alt="Swift 6.2" />
</p>

<p align="center">
  <a href="docs/README.ko.md">한국어</a>
</p>

---

Reads system sensors directly via IOKit and drives fan speed from your own temperature curves — no external apps required.

## Features

- **Real-time monitoring** — Temperature sensors via IOKit HID, fan RPM via AppleSMC
- **Curve-based fan control** — Automatic speed with hysteresis and hold intervals
- **5 preset profiles** + fully custom curves
- **Menu bar integration** — Live temperature and RPM at a glance
- **Adaptive UI** — Semantic color system with light/dark mode
- **Bilingual** — English and Korean

## Install

### Homebrew (recommended)

```bash
brew install inhwa-son/tap/aeropulse
```

### Manual download

Download the latest `.dmg` from [Releases](https://github.com/inhwa-son/aeropulse-mac/releases).

> **Note:** Manual downloads may trigger a macOS Gatekeeper warning since the app is not notarized.
> Right-click the app → **Open**, or run: `xattr -cr /Applications/AeroPulse.app`

### Post-install

After launch, approve the privileged helper in **System Settings → General → Login Items**.

### Requirements

- macOS 15.0+
- Apple Silicon Mac (M1 and later)

## Build from Source

### Prerequisites

- Xcode 26.3+ (Swift 6.2)
- [mise](https://mise.jdx.dev/) with Tuist 4.162.1

### Quick start

```bash
git clone https://github.com/inhwa-son/aeropulse-mac.git
cd aeropulse-mac
mise x tuist@4.162.1 -- tuist generate
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
```

### Run tests

```bash
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

### Release build

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
CODE_SIGN_IDENTITY="Apple Development" \
INSTALL_TO_APPLICATIONS=1 \
OPEN_AFTER_BUILD=1 \
./scripts/release-build.sh
```

## Architecture

```
AeroPulse.app
├── UI Layer (SwiftUI + Observation)
├── AeroPulseControlService.xpc      XPC service for sensor reads
└── Contents/Library/
    ├── PrivilegedHelperTools/
    │   └── AeroPulsePrivilegedHelper LaunchDaemon — direct AppleSMC fan control
    └── LaunchDaemons/
        └── com.dan.aeropulse.helperd2.plist
```

The privileged helper runs as a LaunchDaemon for direct hardware access. All XPC connections are validated via code signature before accepting commands. If the helper is unavailable, the app falls back gracefully.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code rules, and PR process.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting and the privileged helper's security model.

## Disclaimer

This project uses undocumented Apple IOKit APIs for temperature sensor reading and community-documented AppleSMC interfaces for fan control. These interfaces may change across macOS versions. Not suitable for Mac App Store distribution.

## License

[MIT](LICENSE) &copy; 2026 AeroPulse Contributors
