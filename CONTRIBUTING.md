# Contributing to AeroPulse

Thanks for your interest in AeroPulse! This guide covers everything you need to get started.

## Development Setup

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| macOS | 15.0+ | — |
| Xcode | 26.3+ | Mac App Store |
| mise | latest | `brew install mise` |
| Tuist | 4.162.1 | Managed by mise |

### Clone and build

```bash
git clone https://github.com/inhwa-son/aeropulse-mac.git
cd aeropulse-mac
mise install
mise x tuist@4.162.1 -- tuist generate
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
```

### Run tests

```bash
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

All code rules are enforced by architecture tests in `App/Tests/ArchitectureTests.swift`. Violations fail the build — no exceptions.

## Code Rules

| Rule | Requirement | Enforced by |
|------|------------|-------------|
| Colors | `APColor.*` tokens only — no `.red`, `.blue`, etc. | `noRawSystemColorsInFeatures` test |
| Localization | `String.tr("key")` — add keys to both `en.lproj` and `ko.lproj` | `localizationKeysInSync` test |
| Design Tokens | New colors in `DesignTokens.swift` with `isDark` branching | `designTokensAdaptive` test |
| File Structure | Views in `Features/`, models in `Domain/`, services in `Infrastructure/` | `codePathsClaimed` test |
| Card Styling | Use `.tintedCard()`, `.panelSection()`, `.cardStyle()` modifiers | Convention |

## Project Structure

```
App/
├── Sources/
│   ├── App/            Entry point, AppDelegate
│   ├── Features/       SwiftUI views and view models
│   ├── Domain/         Models and business logic
│   ├── Infrastructure/ Services, XPC clients, hardware access
│   ├── Shared/         SMC bridge, protocols shared across targets
│   ├── Daemon/         Privileged helper source
│   └── Service/        XPC service source
├── Resources/          Assets, localizations
├── Support/            Entitlements, LaunchDaemon plists
└── Tests/              Unit + architecture tests
```

## Pull Requests

1. **Fork** the repo and create a feature branch from `main`
2. Follow the code rules above
3. Ensure **all tests pass** before submitting
4. Write a clear PR title and description
5. One focused change per PR — avoid mixing unrelated changes

## Commit Messages

Use clear, descriptive commit messages:

```
feat: add custom curve import/export
fix: prevent fan speed spike on wake from sleep
refactor: extract sensor polling into dedicated service
docs: update Korean installation guide
```

## Private API Disclaimer

This project uses undocumented Apple IOKit APIs (`HIDTemperatureService.swift`) and community-documented AppleSMC interfaces (`AeroPulseSMCBridge.c`) for temperature sensor reading and fan control. These APIs may change across macOS versions. If you discover breakage on a new macOS version, please open an issue.
