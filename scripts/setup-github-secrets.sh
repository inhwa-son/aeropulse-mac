#!/usr/bin/env bash
set -euo pipefail

# AeroPulse GitHub Secrets Setup
# Exports local signing certificate and sets GitHub secrets for CI/CD.
#
# Prerequisites:
#   - gh CLI authenticated
#   - Signing certificate in local keychain
#   - Apple ID with app-specific password (https://appleid.apple.com/account/manage)
#
# Usage: ./scripts/setup-github-secrets.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
echo "==> Setting up GitHub secrets for: $REPO"
echo ""

# Step 1: Export signing certificate
echo "==> Step 1: Export signing certificate"
echo "    Finding your Apple Distribution certificate..."

CERT_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Distribution" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "Apple Distribution")
P12_PATH="$RUNNER_TEMP_DIR/aeropulse-cert.p12"
P12_PATH="${P12_PATH:-/tmp/aeropulse-cert.p12}"

read -rsp "Enter a password for the .p12 export (remember this): " P12_PASSWORD
echo ""

security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -o "$P12_PATH" 2>/dev/null || {
    echo ""
    echo "Auto-export failed. Please export manually:"
    echo "  1. Open Keychain Access"
    echo "  2. Find '$CERT_IDENTITY'"
    echo "  3. Right-click → Export → Save as .p12"
    echo "  4. Save to: $P12_PATH"
    echo ""
    read -rp "Press Enter when done..."
  }

if [[ ! -f "$P12_PATH" ]]; then
  echo "Error: .p12 file not found at $P12_PATH" >&2
  exit 1
fi

echo "==> Setting CERTIFICATES_P12 secret..."
base64 < "$P12_PATH" | gh secret set CERTIFICATES_P12

echo "==> Setting CERTIFICATES_P12_PASSWORD secret..."
echo "$P12_PASSWORD" | gh secret set CERTIFICATES_P12_PASSWORD

rm -f "$P12_PATH"
echo "    Certificate exported and set. Local .p12 deleted."

# Step 2: Apple ID for notarization
echo ""
echo "==> Step 2: Apple ID for notarization"
echo "    Generate an app-specific password at: https://appleid.apple.com/account/manage"
echo ""

read -rp "Apple ID (email): " APPLE_ID
read -rsp "App-Specific Password: " APPLE_APP_PASSWORD
echo ""

echo "$APPLE_ID" | gh secret set APPLE_ID
echo "$APPLE_APP_PASSWORD" | gh secret set APPLE_APP_SPECIFIC_PASSWORD

echo ""
echo "==> All secrets configured!"
echo ""
echo "Secrets set:"
echo "  CERTIFICATES_P12              ✓"
echo "  CERTIFICATES_P12_PASSWORD     ✓"
echo "  APPLE_ID                      ✓"
echo "  APPLE_APP_SPECIFIC_PASSWORD   ✓"
echo ""
echo "To trigger a release:"
echo "  ./scripts/bump-version.sh patch"
echo "  git add -A && git commit -m 'Bump version'"
echo "  git tag v\$(grep MARKETING_VERSION Project.swift | sed 's/.*\"\\([0-9.]*\\)\".*/\\1/')"
echo "  git push && git push --tags"
