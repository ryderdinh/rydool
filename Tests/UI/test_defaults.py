"""Seed isolated UI test shortcuts so tests never trigger the user's shortcuts."""
import json
import plistlib
import subprocess


def seed_shortcuts(suite):
    # Control + Option + Shift, using NSEvent.ModifierFlags raw values.
    modifiers = (1 << 18) | (1 << 19) | (1 << 17)
    shortcuts = {"shortcut": 21, "fullScreenShortcut": 20, "historyShortcut": 9, "recordingShortcut": 40}
    data = {name: json.dumps({"keyCode": code, "modifiers": modifiers}).encode()
            for name, code in shortcuts.items()}
    subprocess.run(["defaults", "import", suite, "-"], input=plistlib.dumps(data), check=True)
