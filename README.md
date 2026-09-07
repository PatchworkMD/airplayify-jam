# Airplayify Jam

Experimental macOS menu-bar app for grouping visible audio outputs for Spotify playback. It does not modify Tutti.app; Spotify access and refresh tokens are stored only in Keychain.

Desktop OAuth uses Authorization Code with PKCE, so the app needs only a Spotify
client ID. Never paste or ship a Spotify client secret; if one is exposed, revoke
it in the Spotify dashboard and create a replacement only for a server-side
confidential client.

The current sender adapter uses the open-source `pyatv` library to discover and stream to AirPlay receivers independently. This is deliberate: macOS Core Audio exposes the Roku endpoints as one `AirPlay` device, while Bonjour/pyatv can see `50in Hisense Roku TV` and `Roku Express 4K` separately.

## Distribution status

Airplayify Jam is MIT-licensed alpha software, published on GitHub.
A Mac App Store build is planned. The current build uses an external
Python/pyatv runtime and FFmpeg; it is not an App Store package.

Automated checks cover output planning, Party lifecycle, sender behavior, and
installation policy. Audible playback, synchronization, cleanup, and restoration
still need verification on the target devices.

For source releases, use `git archive`. Archive attributes exclude private
investigation notes and historical security reports. The private repository
history is not part of the public source snapshot.

## Run

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
not. macOS owns this permission and keeps it enabled until the user turns it
off. The same window detects BlackHole 2ch as an optional virtual Audio MIDI
loopback output and provides its installer or Homebrew command. Airplayify Jam
does not silently install a system audio driver; its default ScreenCaptureKit
party path works without one.

Two native macOS switches apply immediately and persist between launches:
**Use virtual audio output when available** selects the BlackHole capture path
when that driver is present, while **Automatically refresh available outputs**
controls the five-second output inventory monitor.

The app bundle contains only sender scripts and `requirements.txt`; `.venv`,
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

## Local verification and private shipping

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

Build and package a private local copy for Austin only:

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
