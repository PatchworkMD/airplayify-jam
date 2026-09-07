#!/bin/bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_APP="$HERE/Airplayify Jam.app"
INSTALL_ROOT="$HOME/Applications"
INSTALL_APP="$INSTALL_ROOT/Airplayify Jam.app"
SYSTEM_APP="/Applications/Airplayify Jam.app"
STAMP=$(date +%Y%m%d-%H%M%S)

echo "Airplayify Jam private installer"
echo "================================"

if [ ! -d "$SOURCE_APP" ]; then
  echo "Airplayify Jam.app must remain beside this installer in the mounted DMG." >&2
  read -r -p "Press Return to close."
  exit 1
fi

mkdir -p "$INSTALL_ROOT"
/usr/bin/pkill -x AirplayifyJam >/dev/null 2>&1 || true

if [ -d "$SYSTEM_APP" ]; then
  SYSTEM_ARCHIVE="$INSTALL_ROOT/Airplayify Jam.system-copy-$STAMP.app"
  echo
  echo "A competing copy exists at $SYSTEM_APP."
  read -r -p "Archive it to $SYSTEM_ARCHIVE using administrator approval? [y/N] " ARCHIVE_SYSTEM
  case "$ARCHIVE_SYSTEM" in
    y|Y|yes|YES)
      /usr/bin/sudo /bin/mv "$SYSTEM_APP" "$SYSTEM_ARCHIVE"
      ;;
    *)
      echo "Installation stopped. Archive the competing /Applications copy, then run this installer again." >&2
      read -r -p "Press Return to close."
      exit 1
      ;;
  esac
fi

if [ -e "$INSTALL_APP" ]; then
  mv "$INSTALL_APP" "$INSTALL_APP.backup-$STAMP"
fi
/usr/bin/ditto "$SOURCE_APP" "$INSTALL_APP"

if ! command -v brew >/dev/null 2>&1; then
  echo
  echo "Homebrew is required to install the AirPlay sender dependencies."
  echo "Install it from https://brew.sh, then run this installer again."
  /usr/bin/open https://brew.sh
  read -r -p "Press Return to close."
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Installing FFmpeg…"
  brew install ffmpeg
else
  echo "FFmpeg is already installed."
fi

BLACKHOLE_INSTALLED=0
if [ ! -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]; then
  echo
  echo "BlackHole is an optional capture fallback. Default capture does not need it."
  read -r -p "Install BlackHole 2ch? macOS may request administrator approval. [y/N] " INSTALL_BLACKHOLE
  case "$INSTALL_BLACKHOLE" in
    y|Y|yes|YES)
      brew install --cask blackhole-2ch
      BLACKHOLE_INSTALLED=1
      ;;
    *)
      echo "Skipping BlackHole. Airplayify Jam will use ScreenCaptureKit."
      ;;
  esac
else
  echo "BlackHole 2ch is already installed."
fi

PYTHON_FOUND=0
for candidate in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.13 /usr/bin/python3; do
  if [ -x "$candidate" ]; then PYTHON_FOUND=1; break; fi
done
if [ "$PYTHON_FOUND" -eq 0 ]; then
  echo "Installing Python 3.13…"
  brew install python@3.13
fi

echo "Installing the private AirPlay sender runtime…"
/bin/bash "$INSTALL_APP/Contents/Resources/scripts/setup-runtime.sh" \
  "$HOME/Library/Application Support/Airplayify Jam" \
  "$INSTALL_APP/Contents/Resources/requirements.txt"

/usr/bin/codesign --verify --deep --strict "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP"
/usr/bin/open "$INSTALL_APP"

echo
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_APP/Contents/Info.plist")
echo "Airplayify Jam is installed in $INSTALL_APP"
echo "Version $VERSION ($BUILD)"
if [ "$BLACKHOLE_INSTALLED" -eq 1 ]; then
  echo "IMPORTANT: restart this Mac once before selecting BlackHole in Airplayify Jam."
fi
echo "Open Airplayify Jam Setup and complete Screen Recording and Accessibility approval."
read -r -p "Press Return to close."
