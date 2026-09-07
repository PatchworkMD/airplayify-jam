#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -x "$SCRIPT_DIR/../SpotifyCapture" ]; then
  CAPTURE="$SCRIPT_DIR/../SpotifyCapture"
  PYTHON="${AIRPLAYIFY_PYTHON:-}"
  if [ -z "$PYTHON" ] && [ -x "$SCRIPT_DIR/../../../.venv/bin/python" ]; then
    PYTHON="$SCRIPT_DIR/../../../.venv/bin/python"
  fi
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
  CAPTURE="$ROOT/.build/SpotifyCapture"
  PYTHON="${AIRPLAYIFY_PYTHON:-$ROOT/.venv/bin/python}"
  if [ ! -x "$CAPTURE" ]; then
    "$ROOT/scripts/build.sh" >/dev/null
  fi
fi

FFMPEG=${AIRPLAYIFY_FFMPEG:-}
if [ -z "$FFMPEG" ]; then
  for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
    if [ -x "$candidate" ]; then FFMPEG="$candidate"; break; fi
  done
fi

if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
  echo "AirPlayify Jam setup incomplete: pyatv runtime missing. Install requirements.txt in the source-tree .venv or set AIRPLAYIFY_PYTHON to a Python environment containing pyatv." >&2
  exit 78
fi
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  echo "Airplayify Jam setup incomplete: FFmpeg is missing." >&2
  exit 78
fi

devices=("$@")
if [ "${#devices[@]}" -eq 0 ]; then
  devices=("50in Hisense Roku TV" "Roku Express 4K ")
fi
sender_args=()
for device in "${devices[@]}"; do
  sender_args+=(--device "$device")
done

PIPE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-screen-pipe.XXXXXX")
RAW_PIPE="$PIPE_DIR/raw"
ENCODED_PIPE="$PIPE_DIR/encoded"
mkfifo "$RAW_PIPE" "$ENCODED_PIPE"
pids=()

cleanup() {
  code=$?
  trap - EXIT
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$PIPE_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

"$CAPTURE" >"$RAW_PIPE" &
pids+=("$!")
"$FFMPEG" -hide_banner -loglevel error -f f32le -ar 48000 -ac 2 -i "$RAW_PIPE" \
  -ar 44100 -c:a libmp3lame -f mp3 "$ENCODED_PIPE" &
pids+=("$!")
"$PYTHON" "$SCRIPT_DIR/live_airplay_sender.py" "${sender_args[@]}" <"$ENCODED_PIPE" &
pids+=("$!")

wait "${pids[2]}"
