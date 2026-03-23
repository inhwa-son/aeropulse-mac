<p align="center">
  <img src="../App/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="AeroPulse 아이콘" />
</p>

<h1 align="center">AeroPulse</h1>

<p align="center">
  Apple Silicon Mac을 위한 네이티브 열 관리 및 팬 제어 앱.
</p>

<p align="center">
  <a href="https://github.com/inhwa-son/aeropulse-mac/releases/latest"><img src="https://img.shields.io/github/v/release/inhwa-son/aeropulse-mac?style=flat-square" alt="최신 릴리즈" /></a>
  <a href="../LICENSE"><img src="https://img.shields.io/github/license/inhwa-son/aeropulse-mac?style=flat-square" alt="MIT 라이선스" /></a>
  <img src="https://img.shields.io/badge/platform-macOS_15.0%2B-blue?style=flat-square" alt="macOS 15.0+" />
  <img src="https://img.shields.io/badge/swift-6.2-F05138?style=flat-square" alt="Swift 6.2" />
</p>

<p align="center">
  <a href="../README.md">English</a>
</p>

---

외부 앱 없이 독립적으로 동작합니다. IOKit으로 시스템 센서를 직접 읽고, 온도 커브 기반으로 팬 속도를 자동 제어합니다.

## 기능

- **실시간 모니터링** — IOKit HID 온도 센서, AppleSMC 팬 RPM
- **커브 기반 팬 제어** — 히스테리시스와 최소 유지 시간을 적용한 자동 속도 조절
- **5개 프리셋 프로필** + 커스텀 커브
- **메뉴바 통합** — 온도와 RPM을 한눈에
- **적응형 UI** — 라이트/다크 모드 시맨틱 컬러 시스템
- **한국어/영어** 지원

## 설치

### Homebrew (권장)

```bash
brew install inhwa-son/tap/aeropulse
```

### 수동 설치

[Releases](https://github.com/inhwa-son/aeropulse-mac/releases)에서 최신 `.dmg`를 다운로드하세요.

> **참고:** 수동 다운로드 시 macOS Gatekeeper 경고가 표시될 수 있습니다.
> 앱을 우클릭 → **열기**를 선택하거나, 터미널에서: `xattr -cr /Applications/AeroPulse.app`

### 설치 후

실행 후 **시스템 설정 → 일반 → 로그인 항목**에서 privileged helper를 승인하세요.

### 시스템 요구사항

- macOS 15.0 이상
- Apple Silicon Mac (M1 이후)

## 소스에서 빌드

### 필수 도구

- Xcode 26.3+ (Swift 6.2)
- [mise](https://mise.jdx.dev/) + Tuist 4.162.1

### 빠른 시작

```bash
git clone https://github.com/inhwa-son/aeropulse-mac.git
cd aeropulse-mac
mise x tuist@4.162.1 -- tuist generate
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse -configuration Debug build
```

### 테스트

```bash
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

### 릴리즈 빌드

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
CODE_SIGN_IDENTITY="Apple Development" \
INSTALL_TO_APPLICATIONS=1 \
OPEN_AFTER_BUILD=1 \
./scripts/release-build.sh
```

## 아키텍처

```
AeroPulse.app
├── UI Layer (SwiftUI + Observation)
├── AeroPulseControlService.xpc      센서 읽기용 XPC 서비스
└── Contents/Library/
    ├── PrivilegedHelperTools/
    │   └── AeroPulsePrivilegedHelper LaunchDaemon — AppleSMC 직접 팬 제어
    └── LaunchDaemons/
        └── com.dan.aeropulse.helperd2.plist
```

Privileged helper는 LaunchDaemon으로 실행되며 하드웨어에 직접 접근합니다. 모든 XPC 연결은 코드 서명 검증 후 명령을 수락합니다. Helper를 사용할 수 없는 경우 자동으로 폴백됩니다.

## 기여

개발 환경, 코드 규칙, PR 프로세스는 [CONTRIBUTING.md](../CONTRIBUTING.md)를 참고하세요.

## 보안

취약점 보고와 privileged helper의 보안 모델은 [SECURITY.md](../SECURITY.md)를 참고하세요.

## 고지

이 프로젝트는 비공개 Apple IOKit API(온도 센서)와 커뮤니티 문서화된 AppleSMC 인터페이스(팬 제어)를 사용합니다. macOS 버전에 따라 동작이 변경될 수 있으며, Mac App Store 배포에는 적합하지 않습니다.

## 라이선스

[MIT](../LICENSE) &copy; 2026 AeroPulse Contributors
