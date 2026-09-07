# Contributing

Airplayify Jam is a small open-source macOS audio-routing project.

- Do not add Spotify credentials or private AirPlay keys.
- Use public APIs and preserve the adapter seam around AirPlay/device control.
- Reproduce device behavior with tests or generated audio before changing live routing.
- Do not claim perfect synchronization without measuring it on the target hardware.
- Run `./scripts/build.sh` and the sender smoke test before opening a pull request.
