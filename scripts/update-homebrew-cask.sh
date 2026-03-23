#!/usr/bin/env bash
set -euo pipefail

# Update Homebrew Cask in inhwa-son/homebrew-tap
# Usage: ./scripts/update-homebrew-cask.sh <version> <dmg_path>
# Requires: GH_TOKEN env var with repo scope for homebrew-tap

VERSION="${1:?Usage: $0 <version> <dmg_path>}"
DMG_PATH="${2:?Usage: $0 <version> <dmg_path>}"

TAP_REPO="inhwa-son/homebrew-tap"
CASK_PATH="Casks/aeropulse.rb"
DMG_NAME=$(basename "$DMG_PATH")
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

CASK_CONTENT="cask \"aeropulse\" do
  version \"${VERSION}\"
  sha256 \"${SHA256}\"

  url \"https://github.com/inhwa-son/aeropulse-mac/releases/download/v#{version}/${DMG_NAME}\"
  name \"AeroPulse\"
  desc \"Fan control and thermal monitoring for Apple Silicon Macs\"
  homepage \"https://github.com/inhwa-son/aeropulse-mac\"

  depends_on macos: \">= :sequoia\"

  app \"AeroPulse.app\"

  postflight do
    system_command \"/usr/bin/xattr\",
                   args: [\"-cr\", \"#{appdir}/AeroPulse.app\"],
                   sudo: false
  end

  zap trash: [
    \"~/Library/Preferences/com.dan.aeropulse.plist\",
    \"~/Library/Caches/com.dan.aeropulse\",
  ]
end
"

# Get current file SHA for update
CURRENT_SHA=$(gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" --jq '.sha' 2>/dev/null || true)

TMPFILE=$(mktemp)
echo "$CASK_CONTENT" > "$TMPFILE"
ENCODED=$(base64 < "$TMPFILE")
rm -f "$TMPFILE"

if [[ -n "$CURRENT_SHA" ]]; then
  gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" \
    --method PUT \
    -f message="chore: bump aeropulse to ${VERSION}" \
    -f branch=main \
    -f content="$ENCODED" \
    -f sha="$CURRENT_SHA" \
    --silent
else
  gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" \
    --method PUT \
    -f message="feat: add aeropulse cask ${VERSION}" \
    -f branch=main \
    -f content="$ENCODED" \
    --silent
fi

echo "==> Homebrew cask updated to ${VERSION} (sha256: ${SHA256})"
