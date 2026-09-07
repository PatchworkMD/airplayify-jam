# Airplayify Jam private install

1. Double-click **Install Airplayify Jam.command** in this disk image. Homebrew is required for the sender dependencies.
2. Leave **Install BlackHole 2ch?** at **No** for normal use. BlackHole is an optional capture fallback. If you choose to install it, approve the installer and restart the Mac before using it.
3. Open Airplayify Jam from `~/Applications` and choose **Setup & Help**.
4. Allow Screen & System Audio Recording, restart Airplayify Jam, and run **Test Capture** with Spotify open.
5. To control Party volume with the Mac volume keys, allow Accessibility and restart Airplayify Jam. This is optional.
6. Play audio in Spotify on this Mac, choose your outputs, and press **Start AirPlay Party**. Spotify Connect setup is optional; use it for separate account lanes.

The installer keeps an existing private app as a timestamped backup. It installs the Python sender runtime in `~/Library/Application Support/Airplayify Jam/runtime`. Spotify passwords, OAuth tokens, and client secrets are not included in the disk image.

This is a private test build. Confirm audible playback, volume control, and output restoration with your devices before relying on it.
