#!/usr/bin/env python3
"""Check live language switching and persistence using isolated preferences."""
import os
import pathlib
import struct
import subprocess
import tempfile
import time
import uuid
import zlib
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "build/Rydool.app/Contents/MacOS/Rydool"
with tempfile.TemporaryDirectory(prefix="rydool-language-test-") as directory:
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    env = os.environ.copy()
    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data) & 0xffffffff)
    image = pathlib.Path(directory) / "synthetic.png"
    width, height = 360, 240
    raw = b"".join(b"\x00" + bytes([235, 240, 250]) * width for _ in range(height))
    image.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", width, height, 8, 2, 0, 0, 0))
                      + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite,
               RYDOOL_TEST_CAPTURE_IMAGE=str(image))
    try:
        for restoring in [False, True]:
            process = subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                time.sleep(2)
                subprocess.run(["swift", str(root / "Tests/UI/LanguageSmoke.swift"), str(process.pid),
                                "restore" if restoring else "switch"], env=env, timeout=35, check=True)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
    finally:
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
