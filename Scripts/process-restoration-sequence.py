#!/usr/bin/env python3
"""Process an ordered frame sequence with checkpoints and temporal metrics."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import resource
import signal
import statistics
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
from PIL import Image


def load_comparison_module():
    path = Path(__file__).with_name("compare-restoration-frames.py")
    specification = importlib.util.spec_from_file_location("restoration_comparison", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("could not load the frame comparison module")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_status(path: Path, status: dict) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(status, indent=2) + "\n")
    temporary.replace(path)


def image_array(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cancel-after", type=int, help=argparse.SUPPRESS)
    parser.add_argument("frames", nargs="+", type=Path)
    args = parser.parse_args()

    comparison = load_comparison_module()
    metadata = comparison.validate_metadata(args.metadata)
    args.output.mkdir(parents=True, exist_ok=True)
    status_path = args.output / "sequence-status.json"
    status = {
        "state": "running",
        "requested_frames": len(args.frames),
        "completed_frames": 0,
        "frames": [],
    }
    write_status(status_path, status)

    cancellation_requested = False

    def request_cancellation(_signal, _frame) -> None:
        nonlocal cancellation_requested
        cancellation_requested = True

    signal.signal(signal.SIGINT, request_cancellation)
    signal.signal(signal.SIGTERM, request_cancellation)
    model = ct.models.MLModel(str(args.model))
    previous_lanczos = None
    previous_restored = None
    residual_changes = []

    for frame in args.frames:
        if cancellation_requested:
            break
        result = comparison.process_frame(frame, args.output, model, metadata)
        lanczos = image_array(result["lanczos"])
        restored = image_array(result["restored"])
        if previous_lanczos is not None and previous_restored is not None:
            previous_residual = previous_restored - previous_lanczos
            current_residual = restored - lanczos
            residual_changes.append(float(np.mean(np.abs(current_residual - previous_residual))))
        previous_lanczos = lanczos
        previous_restored = restored
        status["frames"].append(
            {
                "name": frame.name,
                "seconds": round(result["duration"], 6),
                "tiles": result["tile_count"],
                "restored_sha256": sha256(result["restored"]),
            }
        )
        status["completed_frames"] += 1
        status["peak_resident_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        write_status(status_path, status)
        print(
            f"{status['completed_frames']}/{status['requested_frames']} "
            f"{frame.name}: {result['duration']:.3f} seconds",
            flush=True,
        )
        if args.cancel_after == status["completed_frames"]:
            cancellation_requested = True

    if residual_changes:
        status["temporal_enhancement_change"] = {
            "median": round(statistics.median(residual_changes), 8),
            "maximum": round(max(residual_changes), 8),
        }
    status["state"] = "cancelled" if cancellation_requested else "complete"
    write_status(status_path, status)
    if cancellation_requested:
        print("Sequence processing cancelled at a frame boundary.", file=sys.stderr)
        raise SystemExit(130)


if __name__ == "__main__":
    main()
