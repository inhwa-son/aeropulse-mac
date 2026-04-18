# Changelog

All notable changes to AeroPulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Apple Silicon M3/M4/M5 fan control** — helper runs a 500 ms re-assertion timer that keeps `F<i>Tg` pegged against the firmware's ~1.5 s reclaim, so manual RPM targets actually drive the motor on M5 Pro and later
- **Ad-hoc signing path** — the project no longer requires a paid Apple Developer Program membership. Build scripts and CI transparently fall back to `codesign -s -` + manual `launchctl bootstrap` when no Developer ID cert is supplied
- Strongly-typed SMC API: `SMCKey`, `SMCType`, `SMCValue`, and `SMCHex` replace the scattered `"F0md"` / `"flt "` / inline-hex magic strings across the C bridge, helper, and CLI
- `PrivilegedHelperConstants` as the single source of truth for the helper Mach-service name, plist name, and reassert interval
- `ContinuationGate.tryResume` / `hasResumed` so the XPC client can distinguish a late timeout from a lost reply (no more tearing down healthy XPC connections)
- Architecture tests guarding the security invariants: diagnostic/raw-SMC symbols must be `#if DEBUG`-gated, reassert timer must clear targets before auto writes, silent failures must surface via `helperDebugLog`
- `ContinuationGateTests` unit suite (race, hasResumed, double-resume) and `paidDeveloperProgramIsOptional` architecture test

### Changed
- Privileged helper XPC validation switched from a single hardcoded Team ID to an allow-list of bundle identifiers + an optional trusted-team allow-list
- Reassert timer state reduced to the single `manualTargets: [Int: Int]` map; the redundant `manualFanIDs` set is gone
- `setAuto` now clears the reassert state before issuing the SMC write so a pending tick cannot re-arm manual mode after auto lands

### Security
- Diagnostic CLI (`--fan-diag`, `--fan-experiment`, `--smc-*`) and the raw-SMC XPC methods (`writeRawKey` / `readRawKey`) are now compiled out of Release builds, eliminating a root-privileged arbitrary-SMC-write escalation surface

### Fixed
- `safeQuitRestoresAllFansToAutoViaFallbackCLI` test now creates its own executable stub instead of depending on `/tmp/fan` existing on the host

## [1.0.6] - 2026-03-25

### Fixed
- Switched the privileged helper LaunchDaemon to `BundleProgram` so helper registration survives app moves between paths and Macs
- Removed absolute helper path rewriting from local release builds and GitHub release packaging
- Tightened helper re-registration so stale launchd/BTM registrations are detected and surfaced instead of reported as healthy

### Added
- Helper diagnostics now report detected fan count and the registered helper program path
- Release doctor now flags registration path mismatch and points users to the reset/reboot recovery path when macOS keeps stale background items
- Architecture tests now guard against reintroducing absolute helper-path packaging in release scripts or workflows

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

[1.0.6]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/inhwa-son/aeropulse-mac/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/inhwa-son/aeropulse-mac/releases/tag/v1.0.0
