# AeroPulse

Native thermal management and fan control for Apple Silicon Macs.

Reads system sensors directly via IOKit and drives fan speed from your own temperature curves — no external apps required.

[한국어 문서](docs/README.ko.md)

## Features

- Real-time temperature sensor monitoring (IOKit HID)
- Temperature-curve based automatic fan control with hysteresis and hold intervals
- 5 preset profiles + custom curves
- Menu bar temperature and RPM display
- Adaptive semantic color system with light/dark mode
- English and Korean UI

## Install

Download the latest DMG from [Releases](https://github.com/inhwa-son/aeropulse-mac/releases), open it, and drag AeroPulse to Applications.

After launch, approve the privileged helper in **System Settings → General → Login Items**.

### System Requirements

- macOS 15.0+
- Apple Silicon Mac (M1–M5, all variants)

## Build from Source

### Prerequisites

- Xcode 26.3+ (Swift 6.2)
- [mise](https://mise.jdx.dev/) with Tuist 4.162.1

### Quick Start

```bash
git clone https://github.com/inhwa-son/aeropulse-mac.git
cd aeropulse-mac
mise x tuist@4.162.1 -- tuist generate
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
```

### Run Tests

```bash
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

### Release Build + Install

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
├── UI (SwiftUI + Observation)
├── AeroPulseControlService.xpc    — Internal XPC service
└── AeroPulsePrivilegedHelper      — LaunchDaemon (direct AppleSMC access)
```

The preferred backend for fan writes is the embedded privileged helper, which communicates with AppleSMC directly. If the helper is unavailable, the app falls back gracefully.

## Release

One-command release pipeline:

```bash
./scripts/release.sh patch   # bump → build → sign → DMG → GitHub Release
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development details.

## Disclaimer

This project uses undocumented Apple IOKit APIs for temperature sensor reading and community-documented AppleSMC interfaces for fan control. These may change across macOS versions. Not suitable for Mac App Store distribution — direct distribution (DMG) only.

## License

[MIT](LICENSE)
