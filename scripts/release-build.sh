#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/out/release}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.derived/release}"
APP_NAME="AeroPulse.app"
LAUNCHD_PLIST_RELATIVE="Contents/Library/LaunchDaemons/com.dan.aeropulse.helperd2.plist"
HELPER_RELATIVE="Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper"

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-0}"
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-0}"
HELPER_IDENTIFIER="com.dan.aeropulse.helperd2"
XPC_RELATIVE="Contents/XPCServices/AeroPulseControlService.xpc"
APP_ENTITLEMENTS="$ROOT_DIR/App/Support/AeroPulse.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/App/Support/AeroPulsePrivilegedHelper.entitlements"

post_sign_app() {
  local app_path="$1"
  local helper_path="$app_path/$HELPER_RELATIVE"
  local xpc_path="$app_path/$XPC_RELATIVE"

  [[ -n "$CODE_SIGN_IDENTITY" ]] || return 0
  [[ -e "$helper_path" ]] || return 0

  # Determine timestamp flag:
  #  - Secure (online) timestamp for Developer ID production signing
  #  - None for local Development, Apple Distribution, or ad-hoc ("-") signing
  local ts_flag="--timestamp=none"
  if [[ "$CODE_SIGN_IDENTITY" == *"Developer ID"* ]]; then
    ts_flag="--timestamp"
  fi

  # Sign inside-out: helper → XPC → app
  echo "==> Post-signing helper payload (hardened runtime)"
  /usr/bin/codesign \
    --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --identifier "$HELPER_IDENTIFIER" \
    --options runtime \
    --entitlements "$HELPER_ENTITLEMENTS" \
    $ts_flag \
    "$helper_path"

  if [[ -d "$xpc_path" ]]; then
    echo "==> Post-signing XPC service (hardened runtime)"
    /usr/bin/codesign \
      --force \
      --sign "$CODE_SIGN_IDENTITY" \
      --options runtime \
      $ts_flag \
      "$xpc_path"
  fi

  echo "==> Re-signing app bundle (hardened runtime)"
  /usr/bin/codesign \
    --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --options runtime \
    --entitlements "$APP_ENTITLEMENTS" \
    $ts_flag \
    "$app_path"
}

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_DIR"

build_args=(
  -project "$ROOT_DIR/AeroPulse.xcodeproj"
  -scheme AeroPulse
  -configuration Release
  -derivedDataPath "$DERIVED_DATA_DIR"
)

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
  build_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_STYLE="Manual"
fi

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
  build_args+=("CODE_SIGN_STYLE=$CODE_SIGN_STYLE")
fi

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  build_args+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY" "PROVISIONING_PROFILE_SPECIFIER=")
fi

# Ad-hoc signing path: if no identity was supplied, build unsigned and post-sign
# the app + helper + XPC service with `-` so the binaries still carry a code
# signature identifier (required for the helper's XPC client validation).
if [[ -z "$CODE_SIGN_IDENTITY" && -z "$DEVELOPMENT_TEAM" ]]; then
  build_args+=("CODE_SIGNING_ALLOWED=NO")
  CODE_SIGN_IDENTITY="-"
fi

echo "==> Building AeroPulse Release"
/usr/bin/xcodebuild "${build_args[@]}"

APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME"
APP_OUTPUT="$OUTPUT_DIR/$APP_NAME"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Release app bundle not found: $APP_SOURCE" >&2
  exit 1
fi

echo "==> Copying app bundle"
rm -rf "$APP_OUTPUT"
/bin/cp -R "$APP_SOURCE" "$APP_OUTPUT"
post_sign_app "$APP_OUTPUT"

echo "==> Running release doctor"
"$ROOT_DIR/scripts/release-doctor.sh" "$APP_OUTPUT"

if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
  echo "==> Installing into /Applications"
  /bin/rm -rf "/Applications/$APP_NAME"
  /bin/cp -R "$APP_OUTPUT" "/Applications/$APP_NAME"
  post_sign_app "/Applications/$APP_NAME"
  "$ROOT_DIR/scripts/release-doctor.sh" "/Applications/$APP_NAME"
fi

if [[ "$OPEN_AFTER_BUILD" == "1" ]]; then
  APP_TO_OPEN="$APP_OUTPUT"
  if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
    APP_TO_OPEN="/Applications/$APP_NAME"
  fi
  echo "==> Opening $APP_TO_OPEN"
  /usr/bin/open -na "$APP_TO_OPEN"
fi

echo
echo "Build complete:"
echo "  $APP_OUTPUT"
