#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="$project_dir/build/Rydool.app"
output="$project_dir/build/Rydool-macos.dmg"
python="${DMG_PYTHON:-python3}"

if [[ ! -d "$app" ]]; then
  echo "Build Rydool.app first with Scripts/build-app.sh release" >&2
  exit 1
fi
if ! "$python" -c 'import dmgbuild' 2>/dev/null; then
  echo 'Install dmgbuild==1.6.6 or set DMG_PYTHON to a Python containing it.' >&2
  exit 1
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/rydool-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
swift "$project_dir/Scripts/make-dmg-background.swift" "$staging/background.png"
rm -f "$output"
"$python" -m dmgbuild -s "$project_dir/Scripts/dmg-settings.py" \
  -D "app=$app" -D "background=$staging/background.png" Rydool "$output"
echo "Created $output"
