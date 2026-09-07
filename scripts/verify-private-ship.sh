#!/bin/sh
set -eu

compare_apps() {
  built_app=$1
  canonical_app=$2

  stale() {
    echo "ship gate failed: canonical install is stale; reinstall the private artifact ($1)" >&2
    exit 1
  }

  [ -d "$built_app" ] || stale "built app is missing: $built_app"
  [ -d "$canonical_app" ] || stale "canonical install is missing: $canonical_app"

  built_plist="$built_app/Contents/Info.plist"
  canonical_plist="$canonical_app/Contents/Info.plist"
  [ -f "$built_plist" ] || stale "built Info.plist is missing"
  [ -f "$canonical_plist" ] || stale "canonical Info.plist is missing"

  built_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$built_plist" 2>/dev/null) \
    || stale "built bundle version is unreadable"
  canonical_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$canonical_plist" 2>/dev/null) \
    || stale "canonical bundle version is unreadable"
  [ "$built_build" = "$canonical_build" ] \
    || stale "bundle build differs: built=$built_build installed=$canonical_build"

  built_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$built_plist" 2>/dev/null) \
    || stale "built executable name is unreadable"
  canonical_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$canonical_plist" 2>/dev/null) \
    || stale "canonical executable name is unreadable"
  [ "$built_executable" = "$canonical_executable" ] || stale "main executable name differs"

  compare_binary() {
    label=$1
    built_binary=$2
    canonical_binary=$3
    [ -f "$built_binary" ] || stale "built $label is missing"
    [ -f "$canonical_binary" ] || stale "canonical $label is missing"
    built_copy="$COMPARE_TMP/built-$label"
    canonical_copy="$COMPARE_TMP/canonical-$label"
    cp "$built_binary" "$built_copy"
    cp "$canonical_binary" "$canonical_copy"
    codesign --remove-signature "$built_copy" >/dev/null 2>&1 || true
    codesign --remove-signature "$canonical_copy" >/dev/null 2>&1 || true
    cmp -s "$built_copy" "$canonical_copy" || stale "$label differs"
  }

  built_main="$built_app/Contents/MacOS/$built_executable"
  canonical_main="$canonical_app/Contents/MacOS/$canonical_executable"
  compare_binary "main executable" "$built_main" "$canonical_main"

  [ -f "$built_main" ] || stale "built main executable is missing"
  [ -f "$canonical_main" ] || stale "canonical main executable is missing"

  built_helper="$built_app/Contents/Resources/SpotifyCapture"
  canonical_helper="$canonical_app/Contents/Resources/SpotifyCapture"
  compare_binary "SpotifyCapture helper" "$built_helper" "$canonical_helper"

  echo "canonical install matches build $built_build"
}

if [ "${1:-}" = "--compare-apps" ]; then
  [ "$#" -eq 3 ] || {
    echo "usage: $0 --compare-apps BUILT_APP CANONICAL_APP" >&2
    exit 2
  }
  COMPARE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-install-compare.XXXXXX")
  trap 'rm -rf "$COMPARE_TMP"' EXIT HUP INT TERM
  compare_apps "$2" "$3"
  exit 0
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.build/Airplayify Jam.app"
CANONICAL="$HOME/Applications/Airplayify Jam.app"
SYSTEM_COPY="/Applications/Airplayify Jam.app"
LIVE_EVIDENCE="$ROOT/dist/private-live-verification.md"

cd "$ROOT"

[ -d "$CANONICAL" ] || {
  echo "ship gate failed: canonical install is missing; install the private artifact in ~/Applications" >&2
  exit 1
}
CANONICAL_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CANONICAL/Contents/Info.plist" 2>/dev/null) || {
  echo "ship gate failed: canonical install has no readable bundle version" >&2
  exit 1
}

./scripts/test-direct.sh
AIRPLAYIFY_BUILD_NUMBER="$CANONICAL_BUILD" ./scripts/build.sh >/dev/null
codesign --verify --deep --strict "$APP"
git diff --check
./scripts/secret-scan.sh

if [ -d "$SYSTEM_COPY" ] && [ -d "$CANONICAL" ]; then
  echo "ship gate failed: duplicate Airplayify Jam installs exist in /Applications and ~/Applications" >&2
  exit 1
fi

COMPARE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-install-compare.XXXXXX")
trap 'rm -rf "$COMPARE_TMP"' EXIT HUP INT TERM
compare_apps "$APP" "$CANONICAL"

if find "$APP/Contents" -type f \( -name '.env' -o -name '.env.*' \) -print | grep -q .; then
  echo "ship gate failed: environment file found in app bundle" >&2
  exit 1
fi

if pgrep -f 'SpotifyCapture|airplay_sender.py|spotify-screen-capture.sh|spotify-virtual-capture.sh' >/dev/null 2>&1; then
  echo "ship gate failed: sender or capture helper is still running" >&2
  exit 1
fi

echo "AUTOMATED SHIP GATES PASSED"

if [ -f "$LIVE_EVIDENCE" ] && rg -q '^Status: PASS$' "$LIVE_EVIDENCE"; then
  echo "LIVE AUDIO GATES PASSED"
else
  echo "LIVE AUDIO GATES PENDING"
fi
