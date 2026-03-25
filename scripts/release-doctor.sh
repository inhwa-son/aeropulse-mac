#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-$(dirname "${BASH_SOURCE[0]}")/../out/release/AeroPulse.app}"
HELPER_PATH="$APP_PATH/Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper"
PLIST_PATH="$APP_PATH/Contents/Library/LaunchDaemons/com.dan.aeropulse.helperd2.plist"

print_line() {
  printf '%-22s %s\n' "$1" "$2"
}

echo "AeroPulse Release Doctor"
echo "App Path: $APP_PATH"
echo

if [[ ! -d "$APP_PATH" ]]; then
  print_line "App Bundle" "missing"
  exit 1
fi

print_line "App Bundle" "present"

if [[ "$APP_PATH" == /Applications/* ]]; then
  print_line "Install Location" "/Applications"
else
  print_line "Install Location" "outside /Applications"
fi

if [[ -x "$HELPER_PATH" ]]; then
  print_line "Helper Tool" "embedded"
else
  print_line "Helper Tool" "missing"
fi

if [[ -f "$PLIST_PATH" ]]; then
  print_line "LaunchDaemon Plist" "embedded"
else
  print_line "LaunchDaemon Plist" "missing"
fi

CODESIGN_INFO="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 || true)"
TEAM_ID="$(printf '%s\n' "$CODESIGN_INFO" | awk -F= '/^TeamIdentifier=/{print $2}')"
SIGNATURE="$(printf '%s\n' "$CODESIGN_INFO" | awk -F= '/^Signature=/{print $2}')"
AUTHORITY="$(printf '%s\n' "$CODESIGN_INFO" | awk -F= '/^Authority=/{print $2; exit}')"

if [[ -z "$SIGNATURE" ]]; then
  if [[ -n "$AUTHORITY" ]]; then
    SIGNATURE="signed"
  else
    SIGNATURE="unknown"
  fi
fi

FLAGS="$(printf '%s\n' "$CODESIGN_INFO" | awk -F= '/^CodeDirectory/{print $0}')"
RUNTIME="no"
if printf '%s\n' "$CODESIGN_INFO" | grep -q 'runtime'; then
  RUNTIME="yes"
fi

print_line "Signature" "${SIGNATURE:-unknown}"
print_line "Authority" "${AUTHORITY:-missing}"
print_line "Team ID" "${TEAM_ID:-missing}"
print_line "Hardened Runtime" "$RUNTIME"

if [[ -f "$PLIST_PATH" ]]; then
  BUNDLE_PROGRAM="$(/usr/bin/plutil -extract BundleProgram raw -o - "$PLIST_PATH" 2>/dev/null || true)"
  PROGRAM_ARGUMENTS="$(/usr/bin/plutil -extract ProgramArguments xml1 -o - "$PLIST_PATH" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g' || true)"
  MACH_SERVICE="$(/usr/libexec/PlistBuddy -c 'Print :MachServices:com.dan.aeropulse.helperd2' "$PLIST_PATH" 2>/dev/null || true)"
  PATH_MODE="missing"
  if [[ -n "$BUNDLE_PROGRAM" ]]; then
    print_line "BundleProgram" "$BUNDLE_PROGRAM"
    PATH_MODE="bundle-relative"
  elif [[ -n "$PROGRAM_ARGUMENTS" ]]; then
    print_line "ProgramArguments" "${PROGRAM_ARGUMENTS:-missing}"
    PATH_MODE="absolute-path"
  fi
  print_line "Launch Path Mode" "$PATH_MODE"
  print_line "Mach Service" "${MACH_SERVICE:-missing}"
fi

echo
echo "Suggested next step:"
if [[ "$APP_PATH" != /Applications/* ]]; then
  echo "- Move AeroPulse.app into /Applications and rebuild or copy the signed release there."
elif [[ -z "${TEAM_ID:-}" ]]; then
  echo "- Produce a team-signed release build before registering the privileged helper."
elif [[ ! -x "$HELPER_PATH" || ! -f "$PLIST_PATH" ]]; then
  echo "- Rebuild the app so the helper payload is embedded correctly."
elif [[ -z "${BUNDLE_PROGRAM:-}" ]]; then
  echo "- Rebuild the app. The LaunchDaemon uses an absolute helper path, so moving the app can break helper registration."
else
  echo "- Register the helper from Settings and approve it in Login Items if macOS asks."
fi
