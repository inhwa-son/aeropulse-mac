<!-- AI Agent Instructions — Single Source of Truth. CLAUDE.md → symlink -->

# AeroPulse

> Swift 6.2 · SwiftUI · Observation · Tuist 4.162.1 · IOKit · Charts · macOS 15.0+

## Design Principles

- **No Over-Engineering** — 현재 필요한 최소 복잡도만.
- **Native First** — 외부 의존성 없이 macOS 네이티브 프레임워크로 구현.
- **Semantic Design Tokens** — 하드코딩 컬러 금지. `APColor.*` 시맨틱 토큰만. 테스트가 강제함.
- **Independent Operation** — Privileged Helper 또는 XPC로 독립 동작. CLI Fallback은 레거시 전용.

## Autonomous Default Mode

- 분석만 멈추지 말고 구현까지 완료하는 것이 기본값.
- 기본 목표는 `기존 구현 답습`이 아니라 가장 현대적이고 일관된 구조.
- 변경 후 `xcodebuild test`까지 통과시키는 것이 기본값. 아키텍처 테스트가 규칙 위반을 잡음.
- 되돌릴 수 없는 제품 정책 결정, 외부 비밀값 누락 시에만 질문.

## Autonomous Quality Bar

- `APColor.*` 시맨틱 토큰만 사용 → `.red`, `.blue` 직접 사용 시 테스트 실패.
- UI 텍스트는 `String.tr()` 필수 → 한국어 하드코딩 시 테스트 실패.
- en/ko 로컬라이제이션 키 동기화 필수 → 불일치 시 테스트 실패.
- 동적 컬러는 라이트/다크 분기 필수 → `isDark` 누락 시 테스트 실패.
- 버전은 `Project.swift` 한 곳에서 관리 → 불일치 시 테스트 실패.
- Team ID 3곳(Project.swift, AGENTS.md, release.yml) 일치 → 불일치 시 테스트 실패.

## Commands

```bash
mise x tuist@4.162.1 -- tuist generate                    # 프로젝트 생성
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug CODE_SIGNING_ALLOWED=NO test
DEVELOPMENT_TEAM=Y9TRXFZMR5 CODE_SIGN_IDENTITY="Apple Development" INSTALL_TO_APPLICATIONS=1 OPEN_AFTER_BUILD=1 ./scripts/release-build.sh
./scripts/bump-version.sh patch                            # 버전 범프 → commit → tag → push
```

## Code Rules

| 항목 | 규칙 | 강제 방법 |
|------|------|-----------|
| Color | `APColor.*` only | `noRawSystemColorsInFeatures` 테스트 |
| Localization | `String.tr("key")` 양쪽 필수 | `localizationKeysInSync` 테스트 |
| Design Token | `DesignTokens.swift`에 thermal/status/chart 전부 | `designTokensComplete` 테스트 |
| Adaptive Color | 라이트/다크 isDark 분기 필수 | `designTokensAdaptive` 테스트 |
| Version | `MARKETING_VERSION` = `CFBundleShortVersionString` | `versionConsistency` 테스트 |
| Independence | 기본 설정에 외부 앱 경로 없음 | `independentDefaults` 테스트 |
| View | `Features/`, Model → `Domain/`, Service → `Infrastructure/` | `codePathsClaimed` 테스트 |
| Card Style | `.tintedCard()`, `.panelSection()`, `.cardStyle()` | 문서 규칙 |
| Scripts | 모든 스크립트 실행 권한 필수 | `scriptsExecutable` 테스트 |

## Version

| Key | Value | Location |
|-----|-------|----------|
| `MARKETING_VERSION` | 1.0.6 | `Project.swift` |
| `CURRENT_PROJECT_VERSION` | 7 | `Project.swift` |
| Team ID | `Y9TRXFZMR5` | `Project.swift` |

## CI/CD

- **CI**: `.github/workflows/ci.yml` — PR/push → 빌드 + 테스트 (아키텍처 테스트 포함)
- **Release**: `.github/workflows/release.yml` — 수동 실행(workflow_dispatch) → 서명 + DMG + 공증 + GitHub Release
- **릴리즈**: `./scripts/bump-version.sh patch` → commit → `git tag v<version>` → push

## References

- `README.md` — 빌드/설치/아키텍처 상세
- `App/Tests/ArchitectureTests.swift` — 규칙 강제 테스트 (이 문서의 실행 가능한 버전)
- `scripts/release-build.sh` · `scripts/create-dmg.sh` · `scripts/bump-version.sh` · `scripts/notarize.sh` · `scripts/setup-github-secrets.sh` · `scripts/release-doctor.sh` · `scripts/release-register.sh`
