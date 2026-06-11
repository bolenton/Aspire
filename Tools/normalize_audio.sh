#!/usr/bin/env bash
# Normalize game audio to consistent loudness and convert to mono CAF.
# Spatial sources must be mono — PHASE positions them in 3D space.
#
# Usage: Tools/normalize_audio.sh input.wav [more inputs...]
# Output: Assets/Audio/<name>.caf, normalized to -23 LUFS.
set -euo pipefail

OUT_DIR="$(dirname "$0")/../Assets/Audio"
mkdir -p "$OUT_DIR"

for input in "$@"; do
  name="$(basename "${input%.*}")"
  out="$OUT_DIR/$name.caf"
  ffmpeg -y -i "$input" \
    -af "loudnorm=I=-23:TP=-2:LRA=11" \
    -ac 1 -ar 44100 -c:a pcm_s16le -f caf \
    "$out"
  echo "normalized: $out"
done
