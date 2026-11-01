#!/usr/bin/env python3
"""Interactive macOS UI smoke test. Uses a named pasteboard and temporary DB."""
import os
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "build/Rydool.app/Contents/MacOS/Rydool"
if not app.exists():
    raise SystemExit("Run Scripts/build-app.sh debug first")
with tempfile.TemporaryDirectory(prefix="rydool-ui-test-") as directory:
    token = uuid.uuid4().hex
    suite = "rydool-test-" + token
    seed_shortcuts(suite)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite)
    command = ["arch", "-x86_64", str(app)] if "--x86-64" in sys.argv else [str(app)]
    process = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        if process.poll() is not None:
            raise SystemExit("Rydool exited during startup")
        result = subprocess.run(["swift", str(root / "Tests/UI/AccessibilitySmoke.swift"), str(process.pid), suite], timeout=30)
        if result.returncode:
            raise SystemExit(result.returncode)
        db_path = pathlib.Path(directory) / "history.sqlite"
        with sqlite3.connect(db_path) as db:
            rows = db.execute("SELECT kind, payload, pinned FROM history").fetchall()
        expected = {("text", b"RYDOOL synthetic clipboard 741", 1), ("text", b"RYDOOL synthetic clipboard 742", 0)}
        if set(rows) != expected:
            raise SystemExit("FAIL: persisted history or pinned state differs from expected")
        print("PASS: pinned item persisted in isolated database", flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
