#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -x "$SCRIPT_DIR/../../../.venv/bin/python" ]; then
  PYTHON="${AIRPLAYIFY_PYTHON:-$SCRIPT_DIR/../../../.venv/bin/python}"
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
  PYTHON="${AIRPLAYIFY_PYTHON:-$ROOT/.venv/bin/python}"
fi

if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
  echo "Airplayify Jam setup incomplete: pyatv runtime missing." >&2
  exit 78
fi

FFMPEG=${AIRPLAYIFY_FFMPEG:-}
if [ -z "$FFMPEG" ]; then
  for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
    if [ -x "$candidate" ]; then FFMPEG="$candidate"; break; fi
  done
fi
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  echo "Airplayify Jam setup incomplete: FFmpeg is missing." >&2
  exit 78
fi

sender_args=()
for device in "$@"; do
  sender_args+=(--device "$device")
done

PIPE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-virtual-pipe.XXXXXX")
ENCODED_PIPE="$PIPE_DIR/encoded"
mkfifo "$ENCODED_PIPE"
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

"$FFMPEG" -hide_banner -loglevel error \
  -f avfoundation -i ":BlackHole 2ch" \
  -ac 2 -ar 44100 -c:a libmp3lame -f mp3 "$ENCODED_PIPE" &
pids+=("$!")
"$PYTHON" "$SCRIPT_DIR/live_airplay_sender.py" "${sender_args[@]}" <"$ENCODED_PIPE" &
pids+=("$!")

wait "${pids[1]}"
