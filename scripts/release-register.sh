#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-/Applications/AeroPulse.app}"
OPEN_LOGIN_ITEMS_ON_APPROVAL="${OPEN_LOGIN_ITEMS_ON_APPROVAL:-0}"

: "${DEVELOPMENT_TEAM:=}"
: "${CODE_SIGN_IDENTITY:=}"

INSTALL_TO_APPLICATIONS=1 "$ROOT_DIR/scripts/release-build.sh"

APP_BINARY="$APP_PATH/Contents/MacOS/AeroPulse"
if [[ ! -x "$APP_BINARY" ]]; then
  echo "App binary not found: $APP_BINARY" >&2
  exit 1
fi

echo
echo "==> Unregistering existing privileged helper (best effort)"
"$APP_BINARY" --helper-unregister || true

echo
echo "==> Registering privileged helper"
REGISTER_OUTPUT="$("$APP_BINARY" --helper-register || true)"
printf '%s\n' "$REGISTER_OUTPUT"

echo
echo "==> Current helper status"
STATUS_OUTPUT="$("$APP_BINARY" --helper-status || true)"
printf '%s\n' "$STATUS_OUTPUT"

if [[ "$STATUS_OUTPUT" == *"helper_status=requires_approval"* && "$OPEN_LOGIN_ITEMS_ON_APPROVAL" == "1" ]]; then
  echo
  echo "==> Opening Login Items"
  "$APP_BINARY" --open-login-items || true
fi

echo
echo "==> Helper doctor"
"$APP_BINARY" --helper-doctor || true
