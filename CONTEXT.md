# Airplayify Jam domain glossary

## Party

A coordinated playback session for one selected group. A Party may use local
outputs, AirPlay receivers, or both. It can be running with degraded members
when selected devices are unavailable.

## Output

A named playback destination visible to Airplayify Jam. A local output is
controlled through macOS audio; an AirPlay receiver is reached through the
network. A device may be visible but unavailable.

## Output group

A saved set of Outputs selected together. `Everywhere` is the default group
name, not a promise that every saved member is currently available.

## Spotify profile

Metadata identifying one Spotify account lane. A profile has one client ID and
may be assigned one Spotify Connect device. Authentication material is not
part of the profile's domain data.

## Spotify lane

The playback-control path for one Spotify profile. Separate independent lanes
require separate authenticated Spotify accounts; lanes are not guaranteed to be
synchronized.
