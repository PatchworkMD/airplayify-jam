#!/bin/bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh, then try again."
  /usr/bin/open https://brew.sh
  read -r -p "Press Return to close."
  exit 1
fi

if [ -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]; then
  echo "BlackHole 2ch is already installed."
else
  brew install --cask blackhole-2ch
fi

echo
echo "Restart this Mac once so Core Audio can load BlackHole, then reopen Airplayify Jam Setup."
read -r -p "Press Return to close."
