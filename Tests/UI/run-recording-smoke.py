#!/usr/bin/env python3
"""Record the actual screen for a few seconds in an isolated temporary directory."""
import os
import math
import struct
import wave
import signal
import sys
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
with tempfile.TemporaryDirectory(prefix="rydool-real-recording-") as directory:
    suite = "rydool-test-" + uuid.uuid4().hex
    tone = pathlib.Path(directory) / "test-tone.wav"
    if "--system-audio" in sys.argv:
        with wave.open(str(tone), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(48000)
            wav.writeframes(b"".join(struct.pack("<h", int(1200 * math.sin(2 * math.pi * 440 * n / 48000))) for n in range(96000)))
    seed_shortcuts(suite)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite)
    # Launch the bundle through Launch Services so macOS attributes capture permission to Rydool.
    keys = ("RYDOOL_TEST_DATA_DIR", "RYDOOL_TEST_PASTEBOARD", "RYDOOL_TEST_DEFAULTS")
    def running_pids():
        listing = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
        return {int(line.strip().split(None, 1)[0]) for line in listing.splitlines()
                if line.strip().endswith(str(app))}

    backdrop = None
    if "--region" in sys.argv:
        backdrop = subprocess.Popen(["swift", str(root / "Tests/UI/RecordingBackdrop.swift")],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2)
        if backdrop.poll() is not None:
            raise SystemExit("Could not launch recording test backdrop")
    previous_pids = running_pids()
    args = ["open", "-n"]
    for key in keys:
        args.extend(["--env", f"{key}={env[key]}"])
    subprocess.run(args + [str(root / "build/Rydool.app")], check=True)
    pid = None
    try:
        for _ in range(30):
            matches = running_pids() - previous_pids
            if matches:
                pid = matches.pop()
                break
            time.sleep(0.2)
        if pid is None:
            raise SystemExit("Test app did not launch")
        time.sleep(1)
        subprocess.run(["swift", str(root / "Tests/UI/RecordingSmoke.swift"), str(pid), directory, str(tone)] + sys.argv[1:],
                       env=env, timeout=55, check=True)
    finally:
        if pid is not None:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if backdrop is not None:
            backdrop.terminate()
            backdrop.wait(timeout=5)
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
