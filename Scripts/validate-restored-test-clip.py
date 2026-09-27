#!/usr/bin/env python3
"""Validate the short restored MP4 before it is promoted from partial output."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffprobe", type=Path, required=True)
    parser.add_argument("--expected-duration", type=float, required=True)
    parser.add_argument("file", type=Path)
    args = parser.parse_args()

    result = subprocess.run(
        [
            str(args.ffprobe), "-v", "error", "-show_streams", "-show_format",
            "-of", "json", str(args.file),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    document = json.loads(result.stdout)
    video = next(stream for stream in document["streams"] if stream["codec_type"] == "video")
    audio = next(stream for stream in document["streams"] if stream["codec_type"] == "audio")
    duration = float(document["format"]["duration"])

    expected_video = {
        "codec_name": "hevc",
        "codec_tag_string": "hvc1",
        "width": 1248,
        "height": 704,
        "pix_fmt": "yuv420p",
        "color_range": "tv",
        "color_space": "smpte170m",
        "color_transfer": "bt709",
        "color_primaries": "smpte170m",
    }
    for key, expected in expected_video.items():
        if video.get(key) != expected:
            raise RuntimeError(f"unexpected video {key}: {video.get(key)!r}; expected {expected!r}")

    expected_audio = {
        "codec_name": "ac3",
        "sample_rate": "48000",
        "channels": 2,
        "channel_layout": "stereo",
    }
    for key, expected in expected_audio.items():
        if audio.get(key) != expected:
            raise RuntimeError(f"unexpected audio {key}: {audio.get(key)!r}; expected {expected!r}")
    if abs(duration - args.expected_duration) > 0.15:
        raise RuntimeError(f"unexpected duration: {duration:.3f} seconds")
    if args.file.stat().st_size == 0:
        raise RuntimeError("output file is empty")

    print(f"Validated restored clip: {duration:.3f} seconds, {args.file.stat().st_size} bytes")


if __name__ == "__main__":
    main()
