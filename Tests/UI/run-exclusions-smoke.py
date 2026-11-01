#!/usr/bin/env python3
"""Interactive app-picker test with isolated preferences and a temporary app bundle."""
import os
import pathlib
import plistlib
import subprocess
import tempfile
import time
import uuid
from test_defaults import seed_shortcuts

root = pathlib.Path(__file__).resolve().parents[2]
binary = root / "build/Rydool.app/Contents/MacOS/Rydool"
if not binary.exists():
    raise SystemExit("Run Scripts/build-app.sh debug first")
with tempfile.TemporaryDirectory(prefix="rydool-exclusions-") as directory:
    app = pathlib.Path(directory) / "Rydool Fixture.app"
    contents = app / "Contents"
    contents.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "test.rydool.fixture",
        "CFBundleName": "Rydool Fixture",
        "CFBundlePackageType": "APPL",
    }))
    suite = "rydool-test-" + uuid.uuid4().hex
    seed_shortcuts(suite)
    subprocess.run(["defaults", "write", suite, "excludedBundleIDs", "-string", "legacy.unavailable"], check=True)
    env = os.environ.copy()
    env.update(RYDOOL_TEST_DATA_DIR=directory, RYDOOL_TEST_PASTEBOARD=suite, RYDOOL_TEST_DEFAULTS=suite)
    process = subprocess.Popen([str(binary)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        if process.poll() is not None:
            raise SystemExit("Rydool exited during startup")
        subprocess.run(["swift", str(root / "Tests/UI/ExclusionsSmoke.swift"), str(process.pid), directory],
                       env=env, timeout=40, check=True)
        output = subprocess.run(["defaults", "read", suite, "excludedBundleIDs"], capture_output=True, text=True, check=True)
        if output.stdout.strip() != "legacy.unavailable":
            raise SystemExit("FAIL: removing selected app did not preserve the existing entry")
        print("PASS: existing exclusion preserved", flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
