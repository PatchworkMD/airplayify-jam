#!/bin/bash
set -euo pipefail

SUPPORT_DIR=${1:?missing support directory}
REQUIREMENTS=${2:?missing requirements file}
RUNTIME="$SUPPORT_DIR/runtime"

PYTHON=""
for candidate in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.13 /usr/bin/python3; do
  if [ -x "$candidate" ]; then
    PYTHON="$candidate"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  echo "Python 3.11–3.13 is required for the AirPlay sender runtime." >&2
  exit 78
fi

mkdir -p "$SUPPORT_DIR"
if [ ! -x "$RUNTIME/bin/python" ]; then
  "$PYTHON" -m venv "$RUNTIME"
fi
"$RUNTIME/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip
"$RUNTIME/bin/python" -m pip install --disable-pip-version-check --quiet -r "$REQUIREMENTS"
"$RUNTIME/bin/python" -c 'import pyatv; print("AirPlay sender runtime ready")'
