#!/usr/bin/env python3
"""Master SoraNoUta's BGM and dialogue voice assets to a stable mix.

The mix policy is intentionally simple and reproducible:

* Each BGM track is attenuated to -27 LUFS-I so music stays behind dialogue.
* Dialogue keeps its within-performance dynamics. A single gain is calculated
  for each chapter/performer recording batch. Most performers target
  -17.5 LUFS-I; the brighter, more compressed Xiayo recordings target
  -19.5 LUFS-I so their perceived loudness matches the rest of the cast.
* A -1.5 dBFS limiter catches only peaks introduced by a positive voice gain.

The script is a dry run unless ``--apply`` is passed. Applying is atomic per
asset: ffmpeg writes a sibling temporary file, validates it, and only then
replaces the source asset.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile
from dataclasses import dataclass


ROOT = Path(__file__).resolve().parents[1]
MUSIC_DIR = ROOT / "Assets" / "music"
VOICE_DIR = ROOT / "Assets" / "voice"

MUSIC_TARGET_LUFS = -27.0
VOICE_BATCH_TARGET_LUFS = -17.5
VOICE_PERFORMER_TARGET_LUFS = {
    "xiayo": -19.5,
}
TRUE_PEAK_LIMIT_LINEAR = 10 ** (-1.5 / 20.0)
LOUDNORM_JSON = re.compile(r'\{\s*"input_i".*?\}', re.DOTALL)


@dataclass(frozen=True)
class Measurement:
    integrated_lufs: float
    true_peak_dbtp: float


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )


def measure(path: Path) -> Measurement:
    result = _run(
        [
            "ffmpeg",
            "-nostats",
            "-hide_banner",
            "-i",
            str(path),
            "-af",
            "loudnorm=I=-18:TP=-1.5:LRA=7:print_format=json",
            "-f",
            "null",
            "-",
        ]
    )
    matches = LOUDNORM_JSON.findall(result.stderr)
    if result.returncode != 0 or not matches:
        raise RuntimeError(f"Could not measure {path}:\n{result.stderr[-1200:]}")
    payload = json.loads(matches[-1])
    return Measurement(
        integrated_lufs=float(payload["input_i"]),
        true_peak_dbtp=float(payload["input_tp"]),
    )


def voice_batch(path: Path) -> str:
    performer = path.stem.split("_", 1)[0]
    return f"{path.parent.name}/{performer}"


def voice_batch_target_lufs(batch: str) -> float:
    performer = batch.rsplit("/", 1)[-1]
    return VOICE_PERFORMER_TARGET_LUFS.get(
        performer,
        VOICE_BATCH_TARGET_LUFS,
    )


def discover() -> tuple[list[Path], list[Path]]:
    music = sorted(MUSIC_DIR.glob("*.mp3"))
    voice = sorted(VOICE_DIR.glob("**/*.m4a"))
    if not music:
        raise RuntimeError(f"No BGM files found under {MUSIC_DIR}")
    if not voice:
        raise RuntimeError(f"No voice files found under {VOICE_DIR}")
    return music, voice


def measure_all(paths: list[Path], jobs: int) -> dict[Path, Measurement]:
    measured: dict[Path, Measurement] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(measure, path): path for path in paths}
        for future in concurrent.futures.as_completed(futures):
            path = futures[future]
            measured[path] = future.result()
    return measured


def calculate_gains(
    music: list[Path],
    voice: list[Path],
    measured: dict[Path, Measurement],
) -> tuple[dict[Path, float], dict[str, float]]:
    music_gains = {
        path: MUSIC_TARGET_LUFS - measured[path].integrated_lufs for path in music
    }

    batches: dict[str, list[float]] = {}
    for path in voice:
        loudness = measured[path].integrated_lufs
        if math.isfinite(loudness):
            batches.setdefault(voice_batch(path), []).append(loudness)

    voice_batch_gains: dict[str, float] = {}
    for batch, values in batches.items():
        if not values:
            raise RuntimeError(f"Voice batch has no measurable clips: {batch}")
        voice_batch_gains[batch] = (
            voice_batch_target_lufs(batch) - statistics.median(values)
        )
    return music_gains, voice_batch_gains


def _transcode(path: Path, gain_db: float, is_voice: bool) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.stem}.mastering.",
        suffix=path.suffix,
        dir=path.parent,
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    temporary.unlink()

    audio_filter = f"volume={gain_db:.6f}dB"
    if is_voice and gain_db > 0:
        audio_filter += (
            f",alimiter=limit={TRUE_PEAK_LIMIT_LINEAR:.9f}:"
            "attack=5:release=50:level=false:latency=true"
        )

    command = [
        "ffmpeg",
        "-nostats",
        "-hide_banner",
        "-y",
        "-i",
        str(path),
        "-map",
        "0:a:0",
        "-map_metadata",
        "0",
        "-af",
        audio_filter,
    ]
    if is_voice:
        command.extend(["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"])
    else:
        command.extend(["-c:a", "libmp3lame", "-b:a", "128k", "-id3v2_version", "3"])
    command.append(str(temporary))

    original_mode = path.stat().st_mode
    try:
        result = _run(command)
        if result.returncode != 0:
            raise RuntimeError(f"Could not master {path}:\n{result.stderr[-1600:]}")
        probe = _run(
            [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "a:0",
                "-show_entries",
                "stream=codec_name",
                "-of",
                "csv=p=0",
                str(temporary),
            ]
        )
        if probe.returncode != 0:
            raise RuntimeError(f"Could not validate mastered asset {temporary}")
        os.chmod(temporary, original_mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def apply_mastering(
    music_gains: dict[Path, float],
    voice: list[Path],
    voice_batch_gains: dict[str, float],
    jobs: int,
) -> None:
    tasks = [(path, gain, False) for path, gain in music_gains.items()]
    tasks.extend(
        (path, voice_batch_gains[voice_batch(path)], True) for path in voice
    )
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {
            executor.submit(_transcode, path, gain, is_voice): path
            for path, gain, is_voice in tasks
        }
        completed = 0
        for future in concurrent.futures.as_completed(futures):
            future.result()
            completed += 1
            if completed % 100 == 0 or completed == len(tasks):
                print(f"Mastered {completed}/{len(tasks)} assets")


def print_plan(
    music: list[Path],
    voice: list[Path],
    measured: dict[Path, Measurement],
    music_gains: dict[Path, float],
    voice_batch_gains: dict[str, float],
) -> None:
    music_loudness = [measured[path].integrated_lufs for path in music]
    print(
        "BGM: "
        f"{len(music)} tracks, median {statistics.median(music_loudness):.2f} LUFS-I, "
        f"target {MUSIC_TARGET_LUFS:.1f} LUFS-I"
    )
    print(
        "BGM gain range: "
        f"{min(music_gains.values()):+.2f} to {max(music_gains.values()):+.2f} dB"
    )

    for batch in sorted(voice_batch_gains):
        values = [
            measured[path].integrated_lufs
            for path in voice
            if voice_batch(path) == batch
            and math.isfinite(measured[path].integrated_lufs)
        ]
        print(
            f"Voice {batch}: {len(values)} measurable clips, "
            f"median {statistics.median(values):.2f} LUFS-I, "
            f"target {voice_batch_target_lufs(batch):.1f} LUFS-I, "
            f"gain {voice_batch_gains[batch]:+.2f} dB"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Atomically replace the source audio assets (default: dry run)",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=min(8, os.cpu_count() or 4),
        help="Number of parallel ffmpeg processes (default: up to 8)",
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    for command in ("ffmpeg", "ffprobe"):
        if shutil.which(command) is None:
            parser.error(f"Required command is unavailable: {command}")

    music, voice = discover()
    measured = measure_all(music + voice, args.jobs)
    music_gains, voice_batch_gains = calculate_gains(
        music, voice, measured
    )
    print_plan(
        music,
        voice,
        measured,
        music_gains,
        voice_batch_gains,
    )

    if not args.apply:
        print("Dry run only; pass --apply to master the assets.")
        return 0

    apply_mastering(music_gains, voice, voice_batch_gains, args.jobs)
    print("Audio mastering complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
