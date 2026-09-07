# Airplayify Jam

An experimental macOS menu-bar app for grouping audio outputs for Spotify playback.

[Website](https://patchworkmd.dev/airplayify/) · [Download alpha.2](https://github.com/PatchworkMD/airplayify-jam/releases/tag/v0.1.0-alpha.2) · [Installation guide](INSTALL.md) · [Report a bug](https://github.com/PatchworkMD/airplayify-jam/issues)

## Try the alpha

The current download is **0.1.0-alpha.2** for **Apple Silicon Macs running macOS 14 or later**. It includes the app, installer, and setup instructions. Python/pyatv and FFmpeg are installed separately by the setup workflow; BlackHole is optional.

**Experimental release:** the app is ad-hoc signed and not notarized, so Gatekeeper may block it. Automated checks cover output planning, Party lifecycle, sender behavior, and installation policy. Real-device playback, synchronization, output restoration, and visual interaction checks remain pending. This is not a Mac App Store build.

## What it does

- Save an Output group and manage a Party from the menu bar.
- Discover local audio outputs and AirPlay receivers.
- Use in-app volume controls, with optional global volume keys in the direct build.
- Configure optional Spotify Connect lanes. Separate lanes do not promise synchronized playback.

AirPlay streaming uses the open-source `pyatv` library. Spotify Connect uses Authorization Code with PKCE; access and refresh tokens are stored in Keychain. The app needs a Spotify client ID, never a client secret.

## Build from source

```sh
./scripts/build.sh
open ".build/Airplayify Jam.app"
```

Install the Python sender environment:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Verify both Roku receivers:

```sh
.venv/bin/python scripts/airplay_sender.py \
  --test-tone \
  --device '50in Hisense Roku TV' \
  --device 'Roku Express 4K ' \
  --timeout 5
```

For a manual live capture source, encode the source as MP3 and pipe it into the
multi-receiver adapter. BlackHole is an optional debugging path only; it is not
required by the app's default Spotify workflow:

```sh
ffmpeg -f avfoundation -i ":BlackHole 2ch" \
  -ac 2 -ar 44100 -c:a libmp3lame -f mp3 - | \
  .venv/bin/python scripts/live_airplay_sender.py \
    --device '50in Hisense Roku TV' \
    --device 'Roku Express 4K '
```

Use `ffmpeg -f avfoundation -list_devices true -i ""` to confirm the exact
loopback input name if you intentionally use BlackHole. The sender duplicates
one stream into separate receiver queues; it does not create nested Audio MIDI
devices.

The menu-bar app uses the bundled ScreenCaptureKit helper by default, which
captures Spotify app audio through macOS's Screen Recording permission. A
BlackHole loopback path remains available for manual lower-level capture, but
it is optional and is not required to start an AirPlay Party. Install it only
for that debugging workflow:

```sh
brew install --cask blackhole-2ch
```

The fallback helper is built at `.build/SpotifyCapture` and copied into the
app bundle at `Contents/Resources/SpotifyCapture`. The bundled launcher resolves
that helper explicitly. `pyatv` is intentionally not copied from a virtualenv:
source-tree development uses `.venv/bin/python`. The private installer creates
a managed runtime at `~/Library/Application Support/Airplayify Jam/runtime`,
which the app selects automatically. `AIRPLAYIFY_PYTHON` is an optional override
for development. If no usable runtime is available, complete sender setup
before starting a Party.

Use **Start AirPlay Party** in the menu-bar app to activate the selected direct
local outputs and AirPlay receivers as one party. Stop it from the same button.
The status reports local, AirPlay, and unavailable members; it never modifies
Tutti.app.

## Spotify Connect lanes

Create a Spotify Developer app, then choose **Permissions & Setup…** from
the menu bar. The native setup window accepts the client ID and shows the exact
`airplayifyjam://spotify/callback` redirect URI to register. Select
**Allow/Reconnect Spotify Access** to complete the user-initiated Authorization Code with PKCE
flow in the system browser. Access and refresh tokens are stored only in
Keychain; profiles store only label, client ID, and assigned device metadata.
Refresh devices and choose one device per account, then use Transfer. Spotify
Connect lanes are independent and do not promise synchronized playback. A Spotify account may also impose plan/device
restrictions.

The persistent **Permissions & Setup** window reports whether Screen & System
Audio Recording is allowed and opens the exact macOS privacy pane when it is
not. macOS owns this permission; a changed app signature or rebuild may require
renewed approval or an app restart. The same window detects BlackHole 2ch as an optional virtual Audio MIDI
loopback output and provides its installer or Homebrew command. Airplayify Jam
does not silently install a system audio driver; its default ScreenCaptureKit
party path works without one.

Two native macOS switches apply immediately and persist between launches:
**Use virtual audio output when available** selects the BlackHole capture path
when that driver is present, while **Automatically refresh available outputs**
controls the five-second output inventory monitor.

The app bundle includes the capture helper, sender scripts, and `requirements.txt`; `.venv`,
`.env`, tokens, and credentials are excluded.

The app discovers Core Audio outputs and saves an `Everywhere` group. Output
inventory keeps stale group members visible as offline. AirPlay workers
reconnect after transient receiver loss, but do not claim perfect sync until
delay and drift are measured on the target Roku firmware.

The menu is organized into three projections: Outputs for discovery and health,
Party for one selected group and one Start/Stop action, and Spotify Connect for
separate authenticated account lanes. Playback lifecycle, output reconciliation,
and Spotify lane policy live behind their respective modules rather than in the
menu view.

## Development checks and local packaging

The Store policy build uses in-app volume sliders and excludes global volume-key
takeover and its Accessibility prompt. Verify this policy with:

```sh
AIRPLAYIFY_APP_STORE_POLICY=1 ./scripts/test-isolated.sh
```

This selects the `APP_STORE` compilation condition. It does not add sandboxing,
bundle the sender dependencies, or create a submission-ready App Store archive.
The normal build retains global volume-key control.


Run the direct pure-Swift checks when the local SwiftPM manifest linker is
unavailable:

```sh
./scripts/test-direct.sh
```

Run the same source, build, signature, and static checks in a disposable local
snapshot without launching or installing the app:

```sh
./scripts/test-isolated.sh
```

Build and package a local development copy:

```sh
./scripts/package-private.sh
```

This creates `dist/Airplayify-Jam-private.dmg`, a SHA-256 checksum, and an
installed copy at `~/Applications/Airplayify Jam.app`. Existing private copies
are moved to timestamped backups. Nothing is published or uploaded.

Private builds use the first available Apple Development signing identity so
macOS can preserve Screen & System Audio Recording approval across rebuilds.
Set `AIRPLAYIFY_SIGNING_IDENTITY` to choose a different identity. The build
falls back to ad-hoc signing only when no development identity is installed;
that fallback can make macOS request permission again after each changed build.

## Support

Contact [hello@patchworkmd.dev](mailto:hello@patchworkmd.dev) or visit [PatchworkMD](https://patchworkmd.dev). For reproducible bugs, use this repository’s GitHub Issues and omit tokens and private logs.
