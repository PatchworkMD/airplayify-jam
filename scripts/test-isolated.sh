#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/airplayify-isolated.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT HUP INT TERM
SOURCE_STATE=$(git -C "$ROOT" status --porcelain=v1)

git clone --shared --quiet "$ROOT" "$SANDBOX"
PATCH="$SANDBOX/.worktree.patch"
git -C "$ROOT" diff --binary HEAD >"$PATCH"
if [ -s "$PATCH" ]; then
  git -C "$SANDBOX" apply "$PATCH"
fi
rm "$PATCH"
UNTRACKED="$SANDBOX/.untracked"
git -C "$ROOT" ls-files --others --exclude-standard -z >"$UNTRACKED"
if [ -s "$UNTRACKED" ]; then
  tar --null -T "$UNTRACKED" -C "$ROOT" -cf - | tar -xf - -C "$SANDBOX"
fi
rm "$UNTRACKED"
ln -s "$ROOT/.venv" "$SANDBOX/.venv"

HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmp" \
  CLANG_MODULE_CACHE_PATH="$SANDBOX/cache" \
  SWIFT_MODULE_CACHE_PATH="$SANDBOX/cache" \
  AIRPLAYIFY_SIGNING_IDENTITY=- \
  sh -c '
    mkdir -p "$HOME" "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"
    cd "$1"
    ./scripts/test-direct.sh
    ./scripts/build.sh >/dev/null
    codesign --verify --deep --strict ".build/Airplayify Jam.app"
    if [ "${AIRPLAYIFY_APP_STORE_POLICY:-0}" = 1 ]; then
      symbols=$(nm -u ".build/Airplayify Jam.app/Contents/MacOS/AirplayifyJam")
      if printf "%s\n" "$symbols" | grep -Eq "_(CGEventTapCreate|AXIsProcessTrustedWithOptions|AXIsProcessTrusted)$"; then
        echo "Store policy build still links global accessibility or event-tap APIs" >&2
        exit 1
      fi
      echo "Store media-key symbol check passed"
    fi
    ./scripts/package-private.sh >/dev/null
    codesign --verify --deep --strict "$HOME/Applications/Airplayify Jam.app"
    recorded=$(awk "{print \$1}" dist/Airplayify-Jam-private.dmg.sha256)
    actual=$(shasum -a 256 dist/Airplayify-Jam-private.dmg | awk "{print \$1}")
    test "$recorded" = "$actual"
    hdiutil verify dist/Airplayify-Jam-private.dmg >/dev/null
    for script in scripts/*.sh; do
      case $(head -n 1 "$script") in
        *bash*) bash -n "$script" ;;
        *) sh -n "$script" ;;
      esac
    done
    ./scripts/secret-scan.sh
    git diff --check
  ' sh "$SANDBOX"

test "$SOURCE_STATE" = "$(git -C "$ROOT" status --porcelain=v1)"
echo "isolated source/test gates passed"
