# Contributing to Rydool

Thanks for your interest in improving Rydool! Bug reports, feature ideas, and pull requests are all welcome.

## Reporting issues

Before opening an issue, please search [existing issues](https://github.com/ryderdinh/rydool/issues). When reporting a bug, include:

- Your macOS version and Mac model (Apple Silicon or Intel)
- The Rydool version (from the menu or the release you downloaded)
- Steps to reproduce, and what you expected to happen
- Screenshots or a short recording, if relevant

For larger changes, please open an issue to discuss the idea before starting work.

## Development setup

Requirements: macOS 14 or later and Xcode 16.2 (or the matching Command Line Tools).

```sh
swift test
Scripts/build-app.sh debug
open build/Rydool.app
```

Open the `.app` bundle in Finder or with `open`, as above. Running the executable inside `Contents/MacOS` directly from a terminal or VS Code can cause macOS to attribute permission requests to that app instead of Rydool.

### Code signing

By default, the build script creates a universal binary for Apple Silicon and Intel.

- If exactly one valid Apple Development identity is available, the script uses it so the signature stays stable across builds. Otherwise, it signs ad hoc.
- Set `ARCHS=arm64` to build only for Apple Silicon.
- Set `RYDOOL_SIGN_IDENTITY` to choose an identity (`-` means ad hoc).

Builds are not notarized, so macOS may require you to allow them in **Privacy & Security**. Screen Recording permission may need to be granted again after changing the signing identity or using an ad hoc build; use **Settings → Permissions → Reset permission** if macOS keeps a stale entry.

### Release build

To package a release DMG locally, install `dmgbuild==1.6.6` in a Python environment, then run:

```sh
Scripts/build-app.sh release
DMG_PYTHON=/path/to/python Scripts/package-dmg.sh
```

## UI tests

Interactive UI tests use simulated data and require a desktop session and Accessibility permission for the test process:

```sh
python3 Tests/UI/run-smoke.py
python3 Tests/UI/run-capture-smoke.py --region
python3 Tests/UI/run-capture-smoke.py --save
```

These tests use a separate pasteboard and database, and temporarily control the mouse and keyboard. Simulated data mode is available only in debug builds.

## Pull requests

1. Create a branch from `main`.
2. Keep each pull request focused on one change.
3. Make sure `swift test` passes, and run the relevant UI tests for UI changes.
4. Add user-facing changes to [CHANGELOG.md](CHANGELOG.md).
5. Include screenshots or a short recording for visual changes.

## Project documents

- [Implementation plan](docs/rydool-plan.md)
- [Product behavior](docs/product-behavior.md)
- [Verification status](docs/verification.md)

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
