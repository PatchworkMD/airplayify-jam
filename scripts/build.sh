#!/bin/sh
set -eu

# This flag selects Store-compatible media-key policy, not a Store-ready package.
case "${AIRPLAYIFY_APP_STORE_POLICY:-0}" in
  0) set -- ;;
  1) set -- -D APP_STORE ;;
  *) echo "AIRPLAYIFY_APP_STORE_POLICY must be 0 or 1" >&2; exit 64 ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.build/Airplayify Jam.app"
OUT="$APP/Contents/MacOS/AirplayifyJam"
mkdir -p "$APP/Contents/MacOS"

# Keep Swift's SDK and module cache deterministic. A partially updated Command
# Line Tools install can point MacOSX.sdk at a newer SDK than swiftc supports.
if [ -z "${SDKROOT:-}" ]; then
  for candidate in \
    /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
  do
    if [ -d "$candidate" ]; then
      SDKROOT="$candidate"
      export SDKROOT
      break
    fi
  done
fi
CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-"$ROOT/.build/ModuleCache"}
SWIFT_MODULE_CACHE_PATH=${SWIFT_MODULE_CACHE_PATH:-"$CLANG_MODULE_CACHE_PATH"}
export CLANG_MODULE_CACHE_PATH SWIFT_MODULE_CACHE_PATH
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swiftc "$@" -O \
  -framework CryptoKit \
  -framework Security \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreAudio \
  -framework CoreGraphics \
  -o "$OUT" \
  "$ROOT"/Sources/AirplayifyJam/*.swift
swiftc -O -parse-as-library \
  -framework Foundation \
  -framework CoreMedia \
  -framework ScreenCaptureKit \
  -o "$ROOT/.build/SpotifyCapture" \
  "$ROOT"/Tools/SpotifyCapture/main.swift
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
BUILD_NUMBER=${AIRPLAYIFY_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/scripts"
cp "$ROOT"/scripts/*.sh "$APP/Contents/Resources/scripts/"
cp "$ROOT"/scripts/*.py "$APP/Contents/Resources/scripts/"
cp "$ROOT"/scripts/install-blackhole.command "$APP/Contents/Resources/scripts/"
chmod +x "$APP/Contents/Resources/scripts/install-blackhole.command"
cp "$ROOT/.build/SpotifyCapture" "$APP/Contents/Resources/SpotifyCapture"
chmod +x "$APP/Contents/Resources/SpotifyCapture"
cp "$ROOT/requirements.txt" "$APP/Contents/Resources/"
SIGNING_IDENTITY=${AIRPLAYIFY_SIGNING_IDENTITY:-}
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }')
fi
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=-
  echo "warning: no Apple Development identity found; macOS permissions may reset after rebuilds" >&2
fi
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.austinwise.airplayifyjam "$APP/Contents/Resources/SpotifyCapture" >/dev/null
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" >/dev/null
echo "$APP"
