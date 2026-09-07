import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "live_airplay_sender.py"
SPEC = importlib.util.spec_from_file_location("live_airplay_sender", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class DeviceNameMatchingTests(unittest.TestCase):
    def test_trailing_space_from_pyatv_matches_ui_name(self):
        self.assertEqual(
            MODULE.normalize_device_name("Roku Express 4K "),
            MODULE.normalize_device_name("Roku Express 4K"),
        )

    def test_case_and_repeated_whitespace_are_ignored(self):
        self.assertEqual(
            MODULE.normalize_device_name(" 50IN   Hisense Roku TV "),
            MODULE.normalize_device_name("50in Hisense Roku TV"),
        )

    def test_requested_devices_are_selected_after_normalization(self):
        class Config:
            def __init__(self, name):
                self.name = name

        matched, missing = MODULE.match_requested_devices(
            [Config("Roku Express 4K "), Config("50in Hisense Roku TV")],
            ["Roku Express 4K", "50IN  Hisense Roku TV"],
        )

        self.assertEqual([config.name for config in matched], ["Roku Express 4K ", "50in Hisense Roku TV"])
        self.assertEqual(missing, [])

    def test_missing_devices_are_reported_with_ui_names(self):
        matched, missing = MODULE.match_requested_devices([], ["Bedroom Roku"])

        self.assertEqual(matched, [])
        self.assertEqual(missing, ["Bedroom Roku"])


class AlphaSafetyTests(unittest.IsolatedAsyncioTestCase):
    async def test_ambiguous_names_are_rejected_by_both_senders(self):
        from types import SimpleNamespace
        from unittest.mock import AsyncMock, patch
        devices = [SimpleNamespace(name="Bedroom"), SimpleNamespace(name=" bedroom ")]
        with self.assertRaisesRegex(RuntimeError, "Ambiguous"):
            MODULE.match_requested_devices(devices, ["Bedroom"])
        spec = importlib.util.spec_from_file_location("finite_sender", MODULE_PATH.with_name("airplay_sender.py"))
        finite = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(finite)
        with patch.object(finite, "scan", AsyncMock(return_value=devices)):
            with self.assertRaisesRegex(RuntimeError, "Ambiguous"):
                await finite.find_devices(["Bedroom"], 1)

    async def test_stalled_consumer_bounds_production_and_resumes(self):
        import asyncio
        queue = asyncio.Queue(maxsize=8)
        reader = asyncio.StreamReader(limit=128 * 1024)
        flow = MODULE.ReaderFlowControl()
        reader.set_transport(flow)
        produced = 0

        async def produce():
            nonlocal produced
            for _ in range(64):
                await queue.put(b"x" * (64 * 1024))
                produced += 1
            await queue.put(None)

        feeder = asyncio.create_task(MODULE.feed_audio(queue, reader, flow))
        producer = asyncio.create_task(produce())
        try:
            await asyncio.sleep(0.1)
            self.assertFalse(producer.done())
            self.assertLessEqual(produced, 14)
            self.assertFalse(flow.is_reading())
            received = await asyncio.wait_for(reader.read(), timeout=3)
            await asyncio.gather(feeder, producer)
            self.assertEqual(len(received), 64 * 64 * 1024)
        finally:
            feeder.cancel()
            producer.cancel()
            await asyncio.gather(feeder, producer, return_exceptions=True)

    async def test_permanently_stalled_reader_times_out(self):
        import asyncio
        queue = asyncio.Queue(maxsize=8)
        reader = asyncio.StreamReader(limit=128 * 1024)
        flow = MODULE.ReaderFlowControl()
        reader.set_transport(flow)
        for _ in range(8):
            queue.put_nowait(b"x" * (64 * 1024))
        with self.assertRaises(TimeoutError):
            await asyncio.wait_for(MODULE.feed_audio(queue, reader, flow), timeout=6)
        self.assertFalse(flow.is_reading())
        self.assertGreater(queue.qsize(), 0)

    async def test_secret_scan_preserves_symlink_target(self):
        import os
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "scripts").mkdir()
            (root / "bin").mkdir()
            victim = root / "victim"
            victim.write_text("preserve me")
            link = root / "airplayify-secret-scan-current"
            link.symlink_to(victim)
            source = MODULE_PATH.with_name("secret-scan.sh").read_text()
            scanner = root / "scripts" / "secret-scan.sh"
            scanner.write_text(source.replace("/tmp/airplayify-secret-scan-current", str(link)))
            git = root / "bin" / "git"
            git.write_text('#!/bin/sh\nif [ "$1" = rev-list ]; then exit 0; fi\nexit 1\n')
            git.chmod(0o755)
            result = subprocess.run(["/bin/bash", str(scanner)],
                                    env={**os.environ, "PATH": str(root / "bin") + ":/usr/bin:/bin"},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(victim.read_text(), "preserve me")


if __name__ == "__main__":
    unittest.main()
