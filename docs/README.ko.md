# AeroPulse

Apple Silicon Mac용 네이티브 열 관리 및 팬 제어 앱.

외부 앱 없이 독립적으로 동작합니다. 시스템 센서를 직접 읽고, 온도 커브 기반으로 팬 속도를 자동 제어합니다.

## 기능

- 실시간 온도 센서 모니터링 (IOKit HID)
- 온도 커브 기반 자동 팬 제어 (히스테리시스, 최소 유지 시간)
- 5개 프리셋 프로필 + 커스텀 커브
- 메뉴바 온도/RPM 표시
- 다크/라이트 모드 적응형 시맨틱 컬러 시스템
- 한국어/영어 UI

## 설치

[Releases](https://github.com/inhwa-son/aeropulse-mac/releases)에서 최신 DMG를 다운로드하고, 열어서 AeroPulse를 Applications로 드래그하세요.

실행 후 **시스템 설정 → 일반 → 로그인 항목**에서 privileged helper를 승인하세요.

### 시스템 요구사항

- macOS 15.0 이상
- Apple Silicon Mac (M1–M5, 모든 변형)

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

### Release 빌드 + 설치

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
├── UI (SwiftUI + Observation)
├── AeroPulseControlService.xpc    — 내부 XPC 서비스
└── AeroPulsePrivilegedHelper      — LaunchDaemon (AppleSMC 직접 접근)
```

팬 제어는 앱 내장 privileged helper가 AppleSMC에 직접 접근하여 수행합니다. Helper를 사용할 수 없는 경우 자동으로 폴백됩니다.

## 릴리즈

원커맨드 릴리즈:

```bash
./scripts/release.sh patch   # 범프 → 빌드 → 서명 → DMG → GitHub Release
```

개발 참여는 [CONTRIBUTING.md](../CONTRIBUTING.md)를 참고하세요.

## 고지

이 프로젝트는 비공개 Apple IOKit API(온도 센서)와 커뮤니티 문서화된 AppleSMC 인터페이스(팬 제어)를 사용합니다. macOS 버전에 따라 동작이 변경될 수 있습니다. Mac App Store 배포에는 적합하지 않으며, 직접 배포(DMG) 전용입니다.

## 라이선스

[MIT](../LICENSE)
