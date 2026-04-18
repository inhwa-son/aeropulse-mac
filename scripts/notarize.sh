#!/usr/bin/env bash
set -euo pipefail

# AeroPulse Notarization Script
# Requires: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${1:-}"

if [[ -z "$INPUT_PATH" ]]; then
  echo "Usage: $0 <app_or_dmg_path>" >&2
  exit 1
fi

APPLE_ID="${APPLE_ID:?Set APPLE_ID env var (your Apple ID email)}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID env var (required only when notarizing — paid Apple Developer Program membership needed)}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD env var}"

echo "==> Submitting for notarization: $INPUT_PATH"

xcrun notarytool submit "$INPUT_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

if [[ "$INPUT_PATH" == *.dmg ]]; then
  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$INPUT_PATH"
elif [[ -d "$INPUT_PATH" ]]; then
  echo "==> Stapling notarization ticket to app"
  xcrun stapler staple "$INPUT_PATH"
fi

echo "==> Notarization complete: $INPUT_PATH"
