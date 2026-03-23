# Changelog

All notable changes to AeroPulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.5] - 2026-03-22

### Added
- Homebrew Cask distribution (`brew install inhwa-son/tap/aeropulse`)
- Hardened Runtime entitlements for app and privileged helper
- Release doctor validates Hardened Runtime status

### Changed
- Recommended install method is now Homebrew
- Release pipeline signs with inside-out order (helper → XPC → app)
- Improved code signing in `release-build.sh` with Hardened Runtime support

## [1.0.4] - 2026-03-21

### Added
- Adaptive semantic color system with light/dark mode support
- Design tokens for thermal status, chart, and UI components
- Architecture tests enforcing color, localization, and version rules

### Changed
- All colors migrated to `APColor.*` semantic tokens
- All UI text migrated to `String.tr()` localization

## [1.0.3] - 2026-03-20

### Added
- XPC-based `AeroPulseControlService` for sensor reads
- Privileged helper embedded in app bundle

### Changed
- Fan control no longer depends on external CLI tools

## [1.0.2] - 2026-03-19

### Added
- Temperature-curve based automatic fan control with hysteresis
- 5 preset profiles (Silent, Quiet, Balanced, Performance, Max)
- Custom curve editor

## [1.0.1] - 2026-03-18

### Added
- Menu bar temperature and RPM display
- Korean localization

## [1.0.0] - 2026-03-17

### Added
- Initial release
- Real-time temperature sensor monitoring via IOKit HID
- Manual fan speed control via AppleSMC
- Privileged helper LaunchDaemon for root-level SMC access

[1.0.5]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/inhwa-son/aeropulse-mac/releases/tag/v1.0.0
