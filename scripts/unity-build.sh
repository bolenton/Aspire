#!/usr/bin/env bash
set -euo pipefail

lantern_root="$(cd "$(dirname "$0")/.." && pwd)"
lantern_editor="${LANTERN_UNITY_EDITOR:-/Applications/Unity/Hub/Editor/6000.3.23f1/Unity.app/Contents/MacOS/Unity}"
if [[ ! -x "$lantern_editor" ]]; then
  echo 'Unity 6000.3.23f1 is not installed at the configured path.' >&2
  echo 'Complete Unity Hub license setup, install the Apple Silicon editor with iOS support, and set LANTERN_UNITY_EDITOR if needed.' >&2
  exit 2
fi
lantern_library="$lantern_root/Clients/Lantern.Unity/Library"
if [[ -L "$lantern_library" && ! -d "$lantern_library" ]]; then
  echo 'The Unity Library cache is unavailable. Mount its external volume before building.' >&2
  echo "See $lantern_root/Clients/Lantern.Unity/README.md for the local storage setup." >&2
  exit 2
fi
python3 "$lantern_root/scripts/prepare-unity-content.py"
mkdir -p "$lantern_root/.artifacts/unity"
export LANTERN_BUILD_PATH="${LANTERN_BUILD_PATH:-$lantern_root/.artifacts/unity/iOS}"
"$lantern_editor" -batchmode -quit -projectPath "$lantern_root/Clients/Lantern.Unity" \
  -buildTarget iOS -executeMethod Lantern.Unity.Editor.LanternProject.BuildIOS \
  -logFile "$lantern_root/.artifacts/unity/editor-build.log"
