# Contributing to AeroPulse

## Quick Start

```bash
git clone https://github.com/inhwa-son/aeropulse-mac.git
cd aeropulse-mac
mise x tuist@4.162.1 -- tuist generate
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
```

## Requirements

- macOS 15.0+
- Xcode 26.3+ (Swift 6.2)
- [mise](https://mise.jdx.dev/) with Tuist 4.162.1

## Development Rules

All rules are enforced by architecture tests (`App/Tests/ArchitectureTests.swift`). Violations fail the build.

- **Colors**: Use `APColor.*` tokens only. No `.red`, `.blue`, `.orange` etc.
- **Localization**: All UI text via `String.tr("key")`. Add keys to both `en.lproj` and `ko.lproj`.
- **Design Tokens**: New colors go in `DesignTokens.swift` with light/dark `isDark` branching.

Run tests before submitting:
```bash
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Pull Requests

1. Fork and create a feature branch
2. Make changes following the rules above
3. Ensure all tests pass (59+ tests)
4. Submit a PR with a clear description

## Private API Disclaimer

This project uses undocumented Apple IOKit APIs for temperature sensor reading and SMC fan control. These APIs are community-documented and used by similar open-source projects, but may change across macOS versions. See `HIDTemperatureService.swift` and `AeroPulseSMCBridge.c`.
