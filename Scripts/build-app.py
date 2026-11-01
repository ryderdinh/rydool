#!/usr/bin/env python3
"""Build, assemble, and sign a Rydool app bundle for macOS."""
from __future__ import annotations

import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
BUILD = PROJECT / "build"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=PROJECT, text=True, check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def signing_identity() -> str:
    if "RYDOOL_SIGN_IDENTITY" in os.environ:
        return os.environ["RYDOOL_SIGN_IDENTITY"]
    try:
        listing = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
    except (OSError, subprocess.CalledProcessError):
        return "-"
    candidates = re.findall(r'\b([A-F0-9]{40})\s+"Apple Development:', listing)
    return candidates[0] if len(candidates) == 1 else "-"


def build_slices(configuration: str, architectures: list[str], temporary: Path) -> list[Path]:
    slices: list[Path] = []
    for architecture in architectures:
        print(f"→ Compiling {architecture} ({configuration})…", flush=True)
        args = ("swift", "build", "-c", configuration, "--arch", architecture)
        run(*args)
        binary_dir = Path(run(*args, "--show-bin-path", capture=True).splitlines()[-1])
        destination = temporary / f"Rydool-{architecture}"
        shutil.copy2(binary_dir / "Rydool", destination)
        slices.append(destination)
    return slices


def create_icon(temporary: Path) -> Path:
    print("→ Generating app icon…", flush=True)
    iconset = temporary / "AppIcon.iconset"
    icon = temporary / "AppIcon.icns"
    run("swift", str(PROJECT / "Scripts/make-icon.swift"), str(iconset))
    run("iconutil", "-c", "icns", str(iconset), "-o", str(icon))
    return icon


def assemble(temporary: Path, slices: list[Path], icon: Path, bundle_id: str) -> Path:
    print("→ Assembling Rydool.app…", flush=True)
    app = temporary / "Rydool.app"
    contents = app / "Contents"
    executable_dir = contents / "MacOS"
    resources = contents / "Resources"
    executable_dir.mkdir(parents=True)
    resources.mkdir()
    run("lipo", "-create", *(str(p) for p in slices), "-output", str(executable_dir / "Rydool"))

    with (PROJECT / "Rydool/Resources/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleIdentifier"] = bundle_id
    with (contents / "Info.plist").open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)
    shutil.copy2(icon, resources / "AppIcon.icns")
    for language in ("en", "vi", "zh-Hans"):
        name = f"{language}.lproj"
        shutil.copytree(PROJECT / "Rydool/Resources" / name, resources / name)
    shutil.copy2(PROJECT / "LICENSE", resources / "LICENSE")
    return app


def install_bundle(staged: Path, temporary: Path) -> Path:
    destination = BUILD / "Rydool.app"
    backup = temporary / "previous.app"
    had_previous = destination.exists()
    if had_previous:
        destination.rename(backup)
    try:
        staged.rename(destination)
    except OSError:
        if had_previous:
            backup.rename(destination)
        raise
    return destination


def main() -> None:
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] not in ("debug", "release")):
        raise SystemExit("Usage: Scripts/build-app.sh [debug|release]")
    configuration = sys.argv[1] if len(sys.argv) == 2 else "release"
    architectures = shlex.split(os.environ.get("ARCHS", "arm64 x86_64"))
    if not architectures:
        raise SystemExit("ARCHS must contain at least one architecture")
    bundle_id = os.environ.get("RYDOOL_BUNDLE_ID", "com.rydool.app")
    BUILD.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".rydool-build-", dir=BUILD) as directory:
        temporary = Path(directory)
        slices = build_slices(configuration, architectures, temporary)
        app = assemble(temporary, slices, create_icon(temporary), bundle_id)
        identity = signing_identity()
        print("→ Signing app…", flush=True)
        run("codesign", "--force", "--sign", identity, "--identifier", bundle_id, "--timestamp=none", str(app))
        run("codesign", "--verify", "--strict", str(app))
        destination = install_bundle(app, temporary)
    print(f"✓ Built {destination}\n  Run it with: open \"{destination}\"")


if __name__ == "__main__":
    main()
