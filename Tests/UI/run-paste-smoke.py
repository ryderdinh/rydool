#!/usr/bin/env python3
"""Test automatic paste in a temporary target using an isolated pasteboard and database."""
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
with tempfile.TemporaryDirectory(prefix="rydool-paste-test-") as directory:
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite,
               RYDOOL_TEST_PASTE_RESULT=str(pathlib.Path(directory) / "result"))
    target_path = pathlib.Path(directory) / "PasteTarget"
    subprocess.run(["swiftc", str(root / "Tests/UI/PasteTarget.swift"), "-o", str(target_path)], check=True)
    target = subprocess.Popen([str(target_path)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    process = subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        subprocess.run(["swift", str(root / "Tests/UI/PasteSmoke.swift"), str(process.pid), str(target.pid), suite,
                        env["RYDOOL_TEST_PASTE_RESULT"]], env=env, timeout=40, check=True)
        with sqlite3.connect(pathlib.Path(directory) / "history.sqlite") as db:
            rows = db.execute("SELECT payload FROM history ORDER BY pinned DESC, copied DESC, rowid DESC").fetchall()
        if rows != [(b"Rydool paste fixture",), (b"Rydool newer fixture",)]:
            raise SystemExit("FAIL: clicked item was duplicated or did not move to the top")
        print("PASS: selected item moved to the top without duplication", flush=True)
    finally:
        for child in [process, target]:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait()
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
