#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERIFY="$ROOT/scripts/verify-private-ship.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-install-check.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

make_app() {
  app=$1
  build=$2
  main_payload=$3
  helper_payload=$4

  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict>' \
    '<key>CFBundleExecutable</key><string>AirplayifyJam</string>' \
    "<key>CFBundleVersion</key><string>$build</string>" \
    '</dict></plist>' >"$app/Contents/Info.plist"
  printf '%s\n' "$main_payload" >"$app/Contents/MacOS/AirplayifyJam"
  printf '%s\n' "$helper_payload" >"$app/Contents/Resources/SpotifyCapture"
}

expect_failure() {
  expected=$1
  shift
  output=$("$@" 2>&1) && {
    echo "expected failure containing: $expected" >&2
    exit 1
  }
  printf '%s\n' "$output" | grep -Fq "$expected" || {
    echo "missing expected failure: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  }
}

BUILT="$TMP/built/Airplayify Jam.app"
INSTALLED="$TMP/installed/Airplayify Jam.app"

make_app "$BUILT" "100" "main-v1" "helper-v1"
make_app "$INSTALLED" "100" "main-v1" "helper-v1"
"$VERIFY" --compare-apps "$BUILT" "$INSTALLED"

rm -rf "$INSTALLED"
expect_failure "canonical install is missing" "$VERIFY" --compare-apps "$BUILT" "$INSTALLED"

make_app "$INSTALLED" "99" "main-v1" "helper-v1"
expect_failure "bundle build differs" "$VERIFY" --compare-apps "$BUILT" "$INSTALLED"

make_app "$INSTALLED" "100" "main-v0" "helper-v1"
expect_failure "main executable differs" "$VERIFY" --compare-apps "$BUILT" "$INSTALLED"

make_app "$INSTALLED" "100" "main-v1" "helper-v0"
expect_failure "SpotifyCapture helper differs" "$VERIFY" --compare-apps "$BUILT" "$INSTALLED"

echo "canonical install verifier: 5 cases passed"
