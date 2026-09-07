#!/usr/bin/env python3
"""Duplicate one encoded audio stdin stream to several AirPlay receivers."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import pathlib
import sys
from collections import deque

from pyatv import connect, scan


def write_status(state: str, detail: str) -> None:
    destination = os.environ.get("AIRPLAYIFY_STATUS_FILE")
    if not destination:
        return
    path = pathlib.Path(destination)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps({"state": state, "detail": detail}), encoding="utf-8")
    os.replace(temporary, path)


def normalize_device_name(name: str) -> str:
    """Match UI and pyatv names despite receiver whitespace/case quirks."""
    return " ".join(name.split()).casefold()


def match_requested_devices(discovered, device_names: list[str]):
    """Return matching pyatv configs and any UI names that were not found."""
    requested = {normalize_device_name(name): name.strip() for name in device_names}
    wanted = set(requested)
    configs = [device for device in discovered if normalize_device_name(device.name) in wanted]
    for name in wanted:
        if sum(normalize_device_name(device.name) == name for device in configs) > 1:
            raise RuntimeError(f"Ambiguous AirPlay receiver name: {requested[name]}. Rename the receivers before starting.")
    found = {normalize_device_name(device.name) for device in configs}
    missing = sorted(requested[name] for name in wanted - found)
    return configs, missing


class ReaderFlowControl(asyncio.Transport):
    """Connect manual StreamReader feeding to its public backpressure API."""

    def __init__(self):
        super().__init__()
        self.ready = asyncio.Event()
        self.ready.set()

    def pause_reading(self):
        self.ready.clear()

    def resume_reading(self):
        self.ready.set()

    def is_reading(self):
        return self.ready.is_set()


async def feed_audio(queue, reader, flow):
    while True:
        await asyncio.wait_for(flow.ready.wait(), timeout=5)
        chunk = await queue.get()
        if chunk is None:
            reader.feed_eof()
            return
        reader.feed_data(chunk)


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", action="append", dest="devices", required=True)
    parser.add_argument("--timeout", type=int, default=5)
    parser.add_argument("--retry-delay", type=float, default=2.0)
    parser.add_argument("--capture-device", help="Capture a macOS AVFoundation audio input instead of stdin")
    parser.add_argument("--min-buffer-bytes", type=int, default=16 * 1024)
    parser.add_argument("--check-devices", action="store_true", help="Verify receiver discovery and exit")
    args = parser.parse_args()
    write_status("starting", "Discovering AirPlay receivers")
    default_volume = float(os.environ.get("AIRPLAYIFY_VOLUME", "100"))
    configured_volumes = json.loads(os.environ.get("AIRPLAYIFY_VOLUMES_JSON", "{}"))
    normalized_volumes = {
        normalize_device_name(str(key)): value
        for key, value in configured_volumes.items()
    }

    loop = asyncio.get_running_loop()
    discovered = await scan(loop, timeout=args.timeout)
    configs, missing = match_requested_devices(discovered, args.devices)
    if missing:
        raise RuntimeError(f"AirPlay devices not found: {', '.join(missing)}")
    if args.check_devices:
        print(json.dumps({"receivers": [device.name.strip() for device in configs]}))
        return 0

    queues = [asyncio.Queue(maxsize=8) for _ in configs]
    history: deque[bytes] = deque()
    history_bytes = 0
    audio_ready = asyncio.Event()
    connected_workers: set[int] = set()
    connection_lock = asyncio.Lock()
    capture_process = None
    capture_bytes = 0
    source_ended = False
    if args.capture_device:
        capture_process = await asyncio.create_subprocess_exec(
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "avfoundation", "-i", f":{args.capture_device}",
            "-ac", "2", "-ar", "44100", "-c:a", "libmp3lame", "-f", "mp3", "-",
            stdout=asyncio.subprocess.PIPE,
        )

    async def read_chunk() -> bytes:
        if capture_process is not None and capture_process.stdout is not None:
            return await capture_process.stdout.read(64 * 1024)
        return await asyncio.to_thread(sys.stdin.buffer.read, 64 * 1024)

    async def fanout() -> None:
        nonlocal history_bytes, capture_bytes, source_ended
        received_audio = False
        while chunk := await read_chunk():
            received_audio = True
            capture_bytes += len(chunk)
            if not audio_ready.is_set():
                if capture_bytes >= args.min_buffer_bytes:
                    audio_ready.set()
            history.append(chunk)
            history_bytes += len(chunk)
            while history_bytes > 256 * 1024 and history:
                history_bytes -= len(history.popleft())
            for queue in queues:
                await queue.put(chunk)
        source_ended = True
        for queue in queues:
            await queue.put(None)
        audio_ready.set()
        if capture_process is not None:
            await capture_process.wait()
            if capture_process.returncode != 0:
                raise RuntimeError(f"capture process exited with code {capture_process.returncode}")
        if not received_audio:
            raise RuntimeError("capture source produced no audio")

    async def worker(index, config, queue) -> None:
        await audio_ready.wait()
        if capture_process is not None and capture_bytes < args.min_buffer_bytes:
            return
        ended = False
        first_attempt = True
        while not ended:
            reader = asyncio.StreamReader(limit=128 * 1024)
            flow = ReaderFlowControl()
            reader.set_transport(flow)
            if not first_attempt:
                for chunk in history:
                    reader.feed_data(chunk)
            first_attempt = False

            feeder = asyncio.create_task(feed_audio(queue, reader, flow))
            streaming = None
            player = None
            try:
                player = await connect(config, loop)
                async with connection_lock:
                    connected_workers.add(index)
                    if len(connected_workers) == len(configs):
                        write_status("ready", f"{len(configs)} AirPlay receiver(s) connected")
                requested_volume = configured_volumes.get(
                    config.identifier,
                    normalized_volumes.get(normalize_device_name(config.name), default_volume / 100),
                )
                requested_volume = float(requested_volume)
                if requested_volume <= 1:
                    requested_volume *= 100
                try:
                    await player.audio.set_volume(max(0, min(requested_volume, 100)))
                except Exception as volume_error:  # receiver may not expose volume
                    print(f"{config.name}: volume unavailable ({type(volume_error).__name__})", file=sys.stderr)
                streaming = asyncio.create_task(player.stream.stream_file(reader))
                await asyncio.gather(streaming, feeder)
                ended = True
            except Exception as error:  # noqa: BLE001 - device recovery boundary
                if source_ended:
                    raise RuntimeError(f"Audio source ended while reconnecting to {config.name}") from error
                async with connection_lock:
                    connected_workers.discard(index)
                    write_status("starting", f"Reconnecting to {config.name}")
                print(f"{config.name}: reconnecting after {type(error).__name__}", file=sys.stderr)
                if reader.at_eof():
                    return
                await asyncio.sleep(args.retry_delay)
            finally:
                pending = [task for task in (feeder, streaming) if task is not None]
                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
                if player is not None:
                    player.close()

    tasks = [
        asyncio.create_task(fanout()),
        *(asyncio.create_task(worker(index, config, queue))
          for index, (config, queue) in enumerate(zip(configs, queues))),
    ]
    try:
        await asyncio.gather(*tasks)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if capture_process is not None and capture_process.returncode is None:
            capture_process.terminate()
    print(f"streamed stdin to {len(configs)} AirPlay devices")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:  # noqa: BLE001 - process boundary
        write_status("failed", str(error))
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
