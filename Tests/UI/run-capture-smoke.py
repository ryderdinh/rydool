#!/usr/bin/env python3
"""Interactive capture UI test with a generated image and isolated clipboard/database."""
import os
import pathlib
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "build/Rydool.app/Contents/MacOS/Rydool"
if not app.exists():
    raise SystemExit("Run Scripts/build-app.sh debug first")
def chunk(kind, data):
    return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data) & 0xffffffff)
with tempfile.TemporaryDirectory(prefix="rydool-capture-test-") as directory:
    width, height = 360, 240
    raw = b"".join(b"\x00" + bytes([235, 240, 250]) * width for _ in range(height))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    image = pathlib.Path(directory) / "synthetic.png"
    image.write_bytes(png)
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite, RYDOOL_TEST_CAPTURE_IMAGE=str(image))
    command = ["arch", "-x86_64", str(app)] if "--x86-64" in sys.argv else [str(app)]
    process = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        if process.poll() is not None:
            raise SystemExit("Rydool exited during startup")
        mode = "preview-save-wait" if "--preview-save-wait" in sys.argv else "preview-timer" if "--preview-timer" in sys.argv else "preview-stack" if "--preview-stack" in sys.argv else "preview-copy" if "--preview-copy" in sys.argv else "editor"
        result = subprocess.run(["swift", str(root / "Tests/UI/CaptureSmoke.swift"), str(process.pid), suite, "region" if "--region" in sys.argv or "--cancel-region" in sys.argv else "full", "save" if "--save" in sys.argv else "copy", "shortcut" if "--shortcut" in sys.argv else "menu", mode, "history-disabled" if "--history-disabled" in sys.argv else "history-enabled", "cancel-region" if "--cancel-region" in sys.argv else "complete", "editor-recapture-region" if "--editor-recapture-region" in sys.argv else "editor-recapture" if "--editor-recapture" in sys.argv else "normal"], env=env, timeout=45)
        if result.returncode:
            raise SystemExit(result.returncode)
        with sqlite3.connect(pathlib.Path(directory) / "history.sqlite") as db:
            rows = db.execute("SELECT kind, length(payload) FROM history").fetchall()
        expected_count = 0 if "--history-disabled" in sys.argv or "--cancel-region" in sys.argv else 1 if "--save" in sys.argv or mode != "editor" else 2
        if "--editor-recapture-region" in sys.argv and "--region" not in sys.argv and expected_count:
            expected_count += 1
        if len(rows) != expected_count or any(kind != "image" or length <= 0 for kind, length in rows):
            raise SystemExit(f"FAIL: expected {expected_count} distinct history entries, got {len(rows)}")
        print(f"PASS: {expected_count} expected image(s) in isolated history", flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
