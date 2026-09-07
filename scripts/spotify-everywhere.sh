#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHON="$ROOT/.venv/bin/python"

if [ ! -x "$PYTHON" ]; then
  echo "Missing .venv; run: python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt" >&2
  exit 1
fi

exec ffmpeg -f avfoundation -i ":BlackHole 2ch" \
  -ac 2 -ar 44100 -c:a libmp3lame -f mp3 - | \
  "$PYTHON" "$ROOT/scripts/live_airplay_sender.py" \
    --device "50in Hisense Roku TV" \
    --device "Roku Express 4K "
