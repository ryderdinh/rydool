#!/usr/bin/env python3
"""Exercise reopening a long history with an isolated temporary database."""
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import time
import uuid
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "build/Rydool.app/Contents/MacOS/Rydool"
with tempfile.TemporaryDirectory(prefix="rydool-scroll-test-") as directory:
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    with sqlite3.connect(pathlib.Path(directory) / "history.sqlite") as db:
        db.execute("CREATE TABLE history (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload BLOB NOT NULL, digest TEXT NOT NULL, copied REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source TEXT, thumbnail BLOB)")
        for index in range(40):
            text = f"Scroll fixture {index:02d}"
            db.execute("INSERT INTO history (id, kind, payload, digest, copied) VALUES (?, 'text', ?, ?, ?)",
                       (str(index), text.encode(), str(index), float(index + 1)))
        db.execute("PRAGMA user_version=2")
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite)
    process = subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        subprocess.run(["swift", str(root / "Tests/UI/HistoryScrollSmoke.swift"), str(process.pid)], env=env, timeout=30, check=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
