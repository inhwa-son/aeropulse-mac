#!/usr/bin/env bash
set -euo pipefail

# AeroPulse Full Release — 원커맨드 릴리즈
#
# 버전 범프 → 빌드 → 서명 → DMG → 커밋 → 태그 → 푸시 → GitHub Release
#
# Usage:
#   ./scripts/release.sh patch     # 1.0.2 → 1.0.3
#   ./scripts/release.sh minor     # 1.0.3 → 1.1.0
#   ./scripts/release.sh major     # 1.1.0 → 2.0.0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP_TYPE="${1:-patch}"
# Signing identity & team are optional — omit to produce an ad-hoc local build.
# Provide DEVELOPMENT_TEAM + CODE_SIGN_IDENTITY only when a Developer ID
# Application cert is available and notarization/Gatekeeper-passing DMGs are wanted.
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

echo "╔══════════════════════════════════════╗"
echo "║     AeroPulse Release Pipeline       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. Dirty check
if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ Working tree is dirty. Commit or stash changes first." >&2
  exit 1
fi

# 2. Bump version
echo "── Step 1: Version Bump ($BUMP_TYPE) ──"
./scripts/bump-version.sh "$BUMP_TYPE"

NEW_VERSION=$(grep 'MARKETING_VERSION' Project.swift | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
NEW_BUILD=$(grep 'CURRENT_PROJECT_VERSION' Project.swift | head -1 | sed 's/.*"\([0-9]*\)".*/\1/')
TAG="v$NEW_VERSION"

echo ""
echo "   Version: $NEW_VERSION (build $NEW_BUILD)"
echo "   Tag: $TAG"
echo ""

# 3. Update AGENTS.md version table
sed -i '' "s/| \`MARKETING_VERSION\` | [0-9.]* /| \`MARKETING_VERSION\` | $NEW_VERSION /" AGENTS.md
sed -i '' "s/| \`CURRENT_PROJECT_VERSION\` | [0-9]* /| \`CURRENT_PROJECT_VERSION\` | $NEW_BUILD /" AGENTS.md

# 4. Regenerate project
echo "── Step 2: Generate Project ──"
mise x tuist@4.162.1 -- tuist generate --no-open

# 5. Test
echo "── Step 3: Test ──"
xcodebuild -workspace AeroPulse.xcworkspace -scheme AeroPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test 2>&1 | \
  grep -E "(Test run|SUCCEEDED|FAILED)" | tail -1

# 6. Release build
echo ""
echo "── Step 4: Release Build + Sign ──"
DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
./scripts/release-build.sh

# 7. Create DMG
echo ""
echo "── Step 5: Create DMG ──"
./scripts/create-dmg.sh

DMG_PATH=$(ls out/release/AeroPulse-*.dmg 2>/dev/null | head -1)
if [[ -z "$DMG_PATH" ]]; then
  echo "✗ DMG not found" >&2
  exit 1
fi
echo "   DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# 8. Commit + Tag + Push
echo ""
echo "── Step 6: Commit + Tag + Push ──"
git add Project.swift AGENTS.md
git commit -m "release: v$NEW_VERSION (build $NEW_BUILD)"
git tag "$TAG"
git push
git push --tags
echo "   Pushed: $TAG"

# 9. Create GitHub Release
echo ""
echo "── Step 7: GitHub Release ──"
DMG_NAME=$(basename "$DMG_PATH")

gh release create "$TAG" \
  --title "AeroPulse $NEW_VERSION" \
  --notes "$(cat <<NOTES
## AeroPulse $NEW_VERSION

### 설치 방법
1. 아래 **$DMG_NAME** 다운로드
2. DMG 열기 → AeroPulse를 Applications로 드래그
3. AeroPulse 실행 → 시스템 설정에서 Login Items 승인

### 시스템 요구사항
- macOS 15.0 이상
- Apple Silicon Mac
NOTES
)" \
  "$DMG_PATH#$DMG_NAME"

RELEASE_URL=$(gh release view "$TAG" --json url -q '.url')

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Release Complete!           ║"
echo "╠══════════════════════════════════════╣"
echo "  Version: $NEW_VERSION (build $NEW_BUILD)"
echo "  Tag:     $TAG"
echo "  DMG:     $DMG_NAME"
echo "  URL:     $RELEASE_URL"
echo "╚══════════════════════════════════════╝"
