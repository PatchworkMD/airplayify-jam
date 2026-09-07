"""Exercise the installer driver choice without running installation."""
from pathlib import Path
import subprocess
import tempfile
import unittest


class BlackHoleChoiceTests(unittest.TestCase):
    def run_choice(self, answer, installed=False):
        source = (Path(__file__).resolve().parents[1] /
                  "scripts/Install Airplayify Jam.command").read_text()
        block = source.split("BLACKHOLE_INSTALLED=0", 1)[1].split("PYTHON_FOUND=0", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            driver = Path(directory) / "BlackHole2ch.driver"
            if installed:
                driver.mkdir()
            block = block.replace("/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver", str(driver))
            # Only this decision block runs. brew is a shell stub; no app,
            # package manager, privilege prompt, or playback process is invoked.
            shell = (
                'set -eu\nBLACKHOLE_INSTALLED=0\n'
                'brew() { printf "BREW %s\\n" "$*"; }\n' + block +
                '\nprintf "INSTALLED=%s\\n" "$BLACKHOLE_INSTALLED"\n'
            )
            return subprocess.run(
                ["/bin/bash", "-c", shell], input=answer + "\n",
                text=True, capture_output=True, check=True,
                env={"PATH": "/usr/bin:/bin"},
            ).stdout

    def test_default_skips_driver(self):
        self.assertNotIn("BREW", self.run_choice(""))

    def test_no_skips_driver(self):
        self.assertNotIn("BREW", self.run_choice("n"))

    def test_yes_installs_driver(self):
        output = self.run_choice("yes")
        self.assertIn("BREW install --cask blackhole-2ch", output)
        self.assertIn("INSTALLED=1", output)

    def test_existing_driver_is_preserved(self):
        self.assertNotIn("BREW", self.run_choice("yes", installed=True))


if __name__ == "__main__":
    unittest.main()
