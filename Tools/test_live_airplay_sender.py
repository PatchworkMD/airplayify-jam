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


if __name__ == "__main__":
    unittest.main()
