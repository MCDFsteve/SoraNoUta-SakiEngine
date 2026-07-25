#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_file="${1:-/Library/Afolder/RenpyProject/SoraNoUta/game/images/anime/smoke.webm}"
output_file="${2:-$project_root/Assets/movies/smoke.webp}"
temporary_dir="$(mktemp -d /tmp/soranouta-smoke.XXXXXX)"

cleanup() {
  case "$temporary_dir" in
    /tmp/soranouta-smoke.*) rm -rf "$temporary_dir" ;;
  esac
}
trap cleanup EXIT

for command_name in ffmpeg img2webp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if [[ ! -f "$source_file" ]]; then
  echo "Missing smoke source: $source_file" >&2
  exit 1
fi

frames_dir="$temporary_dir/frames"
encoded_file="$temporary_dir/smoke.webp"
mkdir -p "$frames_dir" "$(dirname "$output_file")"

# Ren'Py used the same grayscale VP9 movie as both the visible image and its
# Movie mask. Rebuild that luma mask as a real alpha channel for SakiEngine.
# Keep the full 21.6-second simulation, but downsample this soft effect to
# 960x540 at 16 fps. The source-sized WebP is about 91 MB with no visible gain
# in-game; this version is materially smaller and cheaper to decode.
ffmpeg \
  -hide_banner \
  -loglevel error \
  -i "$source_file" \
  -filter_complex \
  "[0:v]split=2[color][mask];[color]format=rgba[color_rgba];[mask]format=gray[alpha];[color_rgba][alpha]alphamerge,format=rgba,scale=960:540:flags=lanczos,fps=16[smoke]" \
  -map "[smoke]" \
  -fps_mode passthrough \
  "$frames_dir/frame-%04d.png"

# 63 ms is the closest integer WebP frame duration to the output's 16 fps.
# The file is explicitly infinite-looping; the engine removes it with
# `stop anime` at the authored scene boundary.
img2webp \
  -loop 0 \
  -d 63 \
  -lossy \
  -q 80 \
  -m 3 \
  -exact \
  "$frames_dir"/frame-*.png \
  -o "$encoded_file"

mv "$encoded_file" "$output_file"
echo "Created smoke animation: $output_file"
