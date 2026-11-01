#!/usr/bin/env python3
"""Check that recording settings and the setup window share preferences."""
import os
import pathlib
import subprocess
import tempfile
import time
import uuid
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "build/Rydool.app/Contents/MacOS/Rydool"
if not app.exists():
    raise SystemExit("Run Scripts/build-app.sh debug first")
with tempfile.TemporaryDirectory(prefix="rydool-recording-settings-") as directory:
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite,
               RYDOOL_TEST_DEFAULTS=suite, RYDOOL_TEST_RECORDING_SETUP="1")
    process = subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        subprocess.run(["swift", str(root / "Tests/UI/RecordingSettingsSmoke.swift"), str(process.pid)],
                       env=env, timeout=40, check=True)
    finally:
        process.terminate()
        process.wait(timeout=5)
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
