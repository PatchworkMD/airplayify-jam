#!/bin/sh
set -eu

# This flag selects Store-compatible media-key policy, not a Store-ready package.
case "${AIRPLAYIFY_APP_STORE_POLICY:-0}" in
  0) set -- ;;
  1) set -- -D APP_STORE ;;
  *) echo "AIRPLAYIFY_APP_STORE_POLICY must be 0 or 1" >&2; exit 64 ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/.build/AirplayifyJamDirectTests"
mkdir -p "$ROOT/.build"

if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
  SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
  export SDKROOT
fi
CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-"$ROOT/.build/ModuleCache"}
SWIFT_MODULE_CACHE_PATH=${SWIFT_MODULE_CACHE_PATH:-"$CLANG_MODULE_CACHE_PATH"}
export CLANG_MODULE_CACHE_PATH SWIFT_MODULE_CACHE_PATH
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swiftc "$@" -O -parse-as-library \
  -framework CryptoKit \
  -framework Combine \
  -framework CoreAudio \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -o "$OUT" \
  "$ROOT/Sources/AirplayifyJam/OutputModels.swift" \
  "$ROOT/Sources/AirplayifyJam/RuntimePaths.swift" \
  "$ROOT/Sources/AirplayifyJam/PartyOutputPlan.swift" \
  "$ROOT/Sources/AirplayifyJam/BridgeLaunchPlan.swift" \
  "$ROOT/Sources/AirplayifyJam/SenderStatusSnapshot.swift" \
  "$ROOT/Sources/AirplayifyJam/LocalOutputSelection.swift" \
  "$ROOT/Sources/AirplayifyJam/AudioDeviceCatalog.swift" \
  "$ROOT/Sources/AirplayifyJam/AirPlayDiscovery.swift" \
  "$ROOT/Sources/AirplayifyJam/AirPlayRuntime.swift" \
  "$ROOT/Sources/AirplayifyJam/DeviceRegistry.swift" \
  "$ROOT/Sources/AirplayifyJam/GroupStore.swift" \
  "$ROOT/Sources/AirplayifyJam/OutputInventory.swift" \
  "$ROOT/Sources/AirplayifyJam/PartyRuntime.swift" \
  "$ROOT/Sources/AirplayifyJam/SpotifyBridge.swift" \
  "$ROOT/Sources/AirplayifyJam/PartySessionController.swift" \
  "$ROOT/Sources/AirplayifyJam/RunningIdentity.swift" \
  "$ROOT/Sources/AirplayifyJam/CaptureAuthorizationService.swift" \
  "$ROOT/Sources/AirplayifyJam/SetupModels.swift" \
  "$ROOT/Sources/AirplayifyJam/VolumeScaling.swift" \
  "$ROOT/Sources/AirplayifyJam/SpotifyPKCE.swift" \
  "$ROOT/Sources/AirplayifyJam/SpotifyProfile.swift" \
  "$ROOT/Sources/AirplayifyJam/SpotifyLaneStore.swift" \
  "$ROOT/Sources/AirplayifyJam/SetupAccess.swift" \
  "$ROOT/Sources/AirplayifyJam/MediaKeyInterceptor.swift" \
  "$ROOT/Tools/DirectTests/main.swift"

"$OUT"
"$ROOT/.venv/bin/python" "$ROOT/Tools/test_live_airplay_sender.py"
"$ROOT/.venv/bin/python" "$ROOT/Tools/test_installer_policy.py"
sh "$ROOT/Tools/test_verify_canonical_install.sh"
