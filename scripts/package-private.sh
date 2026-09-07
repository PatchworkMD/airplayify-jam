#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.build/Airplayify Jam.app"
DIST="$ROOT/dist"
DMG="$DIST/Airplayify-Jam-private.dmg"
CHECKSUM="$DMG.sha256"
STAMP=$(date +%Y%m%d-%H%M%S)
INSTALL="$HOME/Applications/Airplayify Jam.app"
SYSTEM_COPY="/Applications/Airplayify Jam.app"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-jam-dmg.XXXXXX")

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT INT TERM

"$ROOT/scripts/build.sh" >/dev/null
codesign --verify --deep --strict "$APP"

mkdir -p "$DIST" "$HOME/Applications"
if [ -d "$SYSTEM_COPY" ]; then
  echo "warning: competing install exists at $SYSTEM_COPY; the interactive installer must archive it with administrator approval" >&2
fi
if [ -e "$DMG" ]; then mv "$DMG" "$DMG.backup-$STAMP"; fi
if [ -e "$CHECKSUM" ]; then mv "$CHECKSUM" "$CHECKSUM.backup-$STAMP"; fi
if [ -e "$INSTALL" ]; then mv "$INSTALL" "$INSTALL.backup-$STAMP"; fi

mkdir -p "$STAGE/Airplayify Jam"
ditto "$APP" "$STAGE/Airplayify Jam/Airplayify Jam.app"
cp "$ROOT/scripts/Install Airplayify Jam.command" "$STAGE/Airplayify Jam/"
chmod +x "$STAGE/Airplayify Jam/Install Airplayify Jam.command"
cp "$ROOT/INSTALL.md" "$STAGE/Airplayify Jam/Start Here.md"
hdiutil create -quiet -volname "Airplayify Jam" -srcfolder "$STAGE" -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$CHECKSUM"
ditto "$APP" "$INSTALL"
codesign --verify --deep --strict "$INSTALL"

printf 'private app: %s\nprivate DMG: %s\nchecksum: %s\n' "$INSTALL" "$DMG" "$CHECKSUM"
