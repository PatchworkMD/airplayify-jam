#!/usr/bin/env python3
"""Small open-source AirPlay sender adapter used by Airplayify Jam.

It intentionally uses pyatv's public stream interface instead of reimplementing
or bypassing AirPlay encryption. The input is a finite audio file for the MVP;
live Spotify capture is a separate adapter that will feed this same interface.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import tempfile
import wave
from pathlib import Path

from pyatv import connect, scan


def normalize_device_name(name: str) -> str:
    return " ".join(name.split()).casefold()


async def find_devices(names: list[str], timeout: int):
    loop = asyncio.get_running_loop()
    devices = await scan(loop, timeout=timeout)
    requested = {normalize_device_name(name): name.strip() for name in names}
    wanted = set(requested)
    selected = [device for device in devices if normalize_device_name(device.name) in wanted]
    missing = sorted(requested[name] for name in wanted - {normalize_device_name(device.name) for device in selected})
    if missing:
        raise RuntimeError(f"AirPlay devices not found: {', '.join(missing)}")
    return selected


async def stream_file(path: Path, names: list[str], timeout: int) -> None:
    configs = await find_devices(names, timeout)
    loop = asyncio.get_running_loop()
    players = await asyncio.gather(*(connect(config, loop) for config in configs))
    try:
        await asyncio.gather(*(player.stream.stream_file(str(path)) for player in players))
    finally:
        for player in players:
            player.close()


def make_test_tone() -> Path:
    handle = tempfile.NamedTemporaryFile(prefix="airplayify-tone-", suffix=".wav", delete=False)
    handle.close()
    with wave.open(handle.name, "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        for index in range(44100 * 3):
            value = int(12000 * __import__("math").sin(2 * __import__("math").pi * 523.25 * index / 44100))
            wav.writeframesraw(value.to_bytes(2, "little", signed=True) * 2)
    return Path(handle.name)


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", action="append", dest="devices", required=True)
    parser.add_argument("--file", type=Path)
    parser.add_argument("--test-tone", action="store_true")
    parser.add_argument("--timeout", type=int, default=5)
    args = parser.parse_args()
    if not args.file and not args.test_tone:
        parser.error("provide --file or --test-tone")
    path = args.file or make_test_tone()
    await stream_file(path, args.devices, args.timeout)
    print(f"streamed {path.name} to {len(args.devices)} AirPlay devices")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        raise SystemExit(130)
