# Airplayify Jam architecture

Airplayify Jam is a clean-room, open-source companion/replacement for the
installed Tutti app. The installed binary is signed and contains no source
tree or public repository reference; this repository therefore does not copy,
patch, or redistribute Tutti code.

## Runtime path

Runtime helpers resolve from `Bundle.main.resourceURL` first and fall back to
the source tree for development launches. `scripts/build.sh` copies only the
sender shell/Python scripts and `requirements.txt` into the app bundle.

```text
Spotify
  -> selected local Core Audio group (optional HDMI/USB/built-in outputs)
  -> ScreenCaptureKit capture (BlackHole optional for debugging)
  -> Airplayify live sender
  -> pyatv AirPlay adapters
  -> one or more Roku receivers
```

## Deep modules and seams

The menu is a projection over four domain modules:

- `PartyRuntime` owns Party lifecycle, rollback, degraded state, and stop
  cleanup. `LocalOutputGroupManager` and `SpotifyBridge` are adapters at its
  internal seams; `PartySessionController` publishes the runtime state for
  SwiftUI.
- `OutputInventory` owns discovery snapshots, stale-member reconciliation,
  Everywhere creation, group sanitization, persistence, and refresh state.
  Core Audio and Bonjour discovery remain adapters.
- `SpotifyLaneCoordinator` owns profile/device/status policy for Connect lanes.
  PKCE authorization, Keychain token storage, Web API transport, and profile
  metadata storage remain adapters below it.
- `JamMenuProjection` renders those state projections as compact Outputs,
  Party, and Spotify Connect sections. Client-ID entry lives in the native
  `SpotifyConnectSetupView` window because editable text fields are not a
  reliable interaction surface inside a SwiftUI `MenuBarExtra` menu. Neither
  view owns orchestration.

These seams increase depth and leverage for callers while concentrating bugs,
policy changes, and verification in the owning module. The interface is also
the test surface: direct tests cover planning, reconciliation, rollback, PKCE,
and lane metadata without requiring the GUI or network.

Core Audio and Bonjour are used for local output inventory and AirPlay
discovery. `pyatv` owns the public sender adapter. The app never stores Spotify
credentials, AirPlay pairing keys, or private protocol material. Spotify access
and refresh tokens are stored only in Keychain; profile metadata contains no
token fields. Desktop OAuth uses PKCE and therefore stores only the Spotify
client ID. A client secret must never be placed in this app, its preferences,
the repository, or a packaged DMG; revoke any secret that is pasted into a
chat, issue, log, or public page.

The local group is created from direct HDMI/USB/built-in device UIDs only. It
never includes Tutti, an existing multi-output device, or the collapsed macOS
AirPlay device, so the app does not create nested output aggregates.

## Output groups

`Everywhere` is a persisted group of stable device IDs. HDMI, USB, and built-in
outputs are shown as optional local outputs. Roku AirPlay receivers are
discovered independently because macOS exposes them to Core Audio as one
collapsed `AirPlay` device during multi-output setup.

## Recovery

The menu-bar controller refreshes device health every five seconds. The live
sender keeps a bounded recent audio window and retries a receiver after a
connection failure. The app reports unavailable devices rather than silently
claiming that all rooms are playing.

## Control surface

The menu bar exposes one Start/Stop AirPlay Party action for the selected group.
Spotify Connect is a compact lane panel: each profile has client-ID metadata,
independently refreshed devices, one assigned device, and an explicit transfer
action. OAuth remains user initiated; tokens stay in Keychain and are never
serialized in lane metadata.

## Private packaging

`scripts/package-private.sh` builds, verifies, ad-hoc signs, and creates a local
DMG without modifying `/Applications/Tutti.app`, publishing to GitHub, or
uploading the artifact. The private install target is
`~/Applications/Airplayify Jam.app`.
