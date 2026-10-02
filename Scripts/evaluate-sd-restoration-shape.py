#!/usr/bin/env python3
"""Research-only rectangular x2 model conversion and paired clip evaluation."""
import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import coremltools as ct
import numpy as np
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / ".build/restoration-evaluation"
OUTPUT = WORK / "sd-shape-experiment"
BORDER = 16
WIDTH, HEIGHT = 624, 352
SHAPE = (1, 3, HEIGHT + 2 * BORDER, WIDTH + 2 * BORDER)
MODEL = OUTPUT / "RealESRGAN_x2plus_656x384_fp16.mlpackage"
WEIGHTS_HASH = "49fafd45f8fd7aa8d31ab2a22d14d91b536c34494a5cfe31eb5d89c2fa266abb"
CONVERTER_HASH = "152404e3021958c6e51edcde9fd17f2757ccf15f0e0d4e5c485495fd852b4af4"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise RuntimeError(f"Pinned research input checksum mismatch: {path}")


def prepare():
    import torch
    original = WORK / "downloads/convert-88b473f383bd69e0e52ea1f266e6585c4fab34bf.py"
    weights = WORK / "downloads/RealESRGAN_x2plus.pth"
    verify(original, CONVERTER_HASH)
    verify(weights, WEIGHTS_HASH)
    if MODEL.exists():
        raise RuntimeError(f"Experimental model already exists: {MODEL}")
    converter = load_module("pinned_converter", original)
    torch.set_num_threads(2)
    torch.manual_seed(0)
    model = converter.build_torch_rrdb(scale=2)
    checkpoint = torch.load(weights, map_location="cpu", weights_only=True)
    model.load_state_dict(checkpoint["params_ema"], strict=True)
    model.eval()
    print(f"Tracing experimental input {SHAPE} with unchanged learned weights", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(model, torch.zeros(SHAPE))
    converted = ct.convert(
        traced, inputs=[ct.TensorType(name="input", shape=SHAPE)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    MODEL.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(MODEL))
    # Core ML creates random package UUIDs; stabilize the manifest for build pins.
    manifest_path = MODEL / "Manifest.json"
    manifest = json.loads(manifest_path.read_text())
    identifiers = {
        "model.mlmodel": "5429D13D-AB33-4ED3-B0EC-C0EC50B782C5",
        "weights": "525D3899-A2C5-46E7-98D2-66EB5060469D",
    }
    manifest["itemInfoEntries"] = {
        identifiers[entry["name"]]: entry for entry in manifest["itemInfoEntries"].values()
    }
    manifest["rootModelIdentifier"] = identifiers["model.mlmodel"]
    manifest_path.write_text(json.dumps(manifest, indent=4, sort_keys=True) + "\n")
    hashes = {str(p.relative_to(MODEL)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(MODEL.rglob("*")) if p.is_file()}
    (OUTPUT / "model-checksums.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print(f"Prepared {MODEL}", flush=True)


def full_frame(image, model):
    pixels = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    if pixels.shape != (HEIGHT, WIDTH, 3):
        raise RuntimeError(f"Unexpected source frame shape {pixels.shape}")
    padded = np.pad(pixels, ((BORDER, BORDER), (BORDER, BORDER), (0, 0)), mode="reflect")
    tensor = np.transpose(padded, (2, 0, 1))[None, ...]
    result = model.predict({"input": tensor})
    if len(result) != 1:
        raise RuntimeError("Unexpected model output count")
    values = next(iter(result.values()))
    if values.shape != (1, 3, SHAPE[2] * 2, SHAPE[3] * 2) or not np.isfinite(values).all():
        raise RuntimeError("Invalid experimental model output")
    rgb = np.transpose(values[0], (1, 2, 0))[BORDER * 2:-BORDER * 2, BORDER * 2:-BORDER * 2]
    return Image.fromarray(np.rint(np.clip(rgb, 0, 1) * 255).astype(np.uint8))


def evaluate():
    source = ROOT / "Alphas - s01e11 - Original Sin.m4v"
    ffmpeg = ROOT / ".build/toolchain/stage/bin/ffmpeg"
    ffprobe = ROOT / ".build/toolchain/stage/bin/ffprobe"
    baseline = WORK / "converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
    comparison = load_module("comparison", ROOT / "Scripts/compare-restoration-frames.py")
    if not MODEL.is_dir():
        raise RuntimeError("Prepare the experimental model first")
    verify(baseline / "Data/com.apple.CoreML/model.mlmodel",
           "b79575977211ba89fb7856076e652fdd34f822b5228858e15b8d61169720e1ac")
    verify(baseline / "Data/com.apple.CoreML/weights/weight.bin",
           "a8904f0bb627d5dbce2468a96c648764a63ece561cfcf118da6321831bb3a926")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    metadata = subprocess.check_output([
        str(ffprobe), "-v", "error", "-show_streams", "-of", "json", str(source)
    ])
    metadata_path = OUTPUT / "source-metadata.json"
    metadata_path.write_bytes(metadata)
    video = comparison.validate_metadata(metadata_path)
    if (video["width"], video["height"]) != (WIDTH, HEIGHT):
        raise RuntimeError("This experiment supports only the approved 624x352 SD source")
    records = []
    # Compile from the local startup volume, matching the existing research harness.
    with tempfile.TemporaryDirectory(prefix="SwiftyTranscoder-SDShape-") as local:
        local = Path(local)
        shutil.copytree(MODEL, local / "candidate.mlpackage")
        shutil.copytree(baseline, local / "baseline.mlpackage")
        candidate_model = ct.models.MLModel(str(local / "candidate.mlpackage"), compute_units=ct.ComputeUnit.ALL)
        baseline_model = ct.models.MLModel(str(local / "baseline.mlpackage"), compute_units=ct.ComputeUnit.ALL)
        for name, seconds in [("face", 540), ("motion", 1350), ("dark", 1890)]:
            directory = OUTPUT / name
            if directory.exists():
                raise RuntimeError(f"Refusing to overwrite existing comparison: {directory}")
            frames = directory / "source-frames"
            frames.mkdir(parents=True)
            subprocess.run([
                str(ffmpeg), "-hide_banner", "-loglevel", "error", "-n",
                "-ss", str(seconds), "-i", str(source), "-map", "0:v:0",
                "-frames:v", "24", "-fps_mode", "passthrough", "-pix_fmt", "rgb24",
                str(frames / "frame-%04d.png")
            ], check=True)
            inputs = sorted(frames.glob("frame-*.png"))
            if len(inputs) != 24:
                raise RuntimeError("Incomplete source extraction")
            # Warm each shape before measuring clip throughput.
            first = Image.open(inputs[0]).convert("RGB")
            full_frame(first, candidate_model)
            comparison.restore(first, baseline_model)
            baseline_seconds = candidate_seconds = 0.0
            differences, edge_differences, temporal_differences = [], [], []
            previous_delta = None
            for index, path in enumerate(inputs, 1):
                image = Image.open(path).convert("RGB")
                started = time.perf_counter()
                old, _, _ = comparison.restore(image, baseline_model)
                baseline_seconds += time.perf_counter() - started
                started = time.perf_counter()
                new = full_frame(image, candidate_model)
                candidate_seconds += time.perf_counter() - started
                delta = np.asarray(new, dtype=np.float32) - np.asarray(old, dtype=np.float32)
                differences.append(float(np.abs(delta).mean()))
                edge = np.ones(delta.shape[:2], dtype=bool)
                edge[32:-32, 32:-32] = False
                edge_differences.append(float(np.abs(delta[edge]).mean()))
                if previous_delta is not None:
                    temporal_differences.append(float(np.abs(delta - previous_delta).mean()))
                previous_delta = delta
                panel = Image.new("RGB", (WIDTH * 4, HEIGHT * 2 + 36), "black")
                panel.paste(old, (0, 36))
                panel.paste(new, (WIDTH * 2, 36))
                draw = ImageDraw.Draw(panel)
                draw.text((12, 10), "Current tiled model", fill="white")
                draw.text((WIDTH * 2 + 12, 10), "Experimental single frame + reflected border", fill="white")
                panel.save(directory / f"comparison-{index:04d}.png")
                if index == 1:
                    old.save(directory / "current-frame.png")
                    new.save(directory / "experimental-frame.png")
            subprocess.run([
                str(ffmpeg), "-hide_banner", "-loglevel", "error", "-n",
                "-framerate", video["avg_frame_rate"], "-i", str(directory / "comparison-%04d.png"),
                "-frames:v", "24", "-an", "-c:v", "hevc_videotoolbox", "-allow_sw", "0",
                "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-q:v", "70", "-movflags", "+faststart",
                str(directory / "comparison.mp4")
            ], check=True)
            record = dict(scene=name, start_seconds=seconds, frames=24,
                          baseline_seconds=baseline_seconds, candidate_seconds=candidate_seconds,
                          speedup=baseline_seconds / candidate_seconds,
                          mean_absolute_rgb_difference=float(np.mean(differences)),
                          edge_mean_absolute_rgb_difference=float(np.mean(edge_differences)),
                          temporal_delta_difference=float(np.mean(temporal_differences)))
            records.append(record)
            print(json.dumps(record), flush=True)
    report = dict(input_shape=SHAPE, source_size=[WIDTH, HEIGHT], border=BORDER,
                  same_weights_sha256=WEIGHTS_HASH, compute_units="ALL", scenes=records)
    (OUTPUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    reel()
    print(f"Comparisons and measurements: {OUTPUT}", flush=True)


def reel():
    manifest = OUTPUT / "review.ffconcat"
    # Repeat the three one-second samples for easier hands-on playback review.
    lines = ["ffconcat version 1.0"]
    for _ in range(4):
        for name in ["face", "motion", "dark"]:
            lines.append(f"file '{name}/comparison.mp4'")
    manifest.write_text("\n".join(lines) + "\n")
    subprocess.run([
        str(ROOT / ".build/toolchain/stage/bin/ffmpeg"), "-hide_banner", "-loglevel", "error", "-n",
        "-f", "concat", "-safe", "0", "-i", str(manifest), "-map", "0:v:0",
        "-c:v", "copy", "-tag:v", "hvc1", "-movflags", "+faststart", str(OUTPUT / "review.mp4")
    ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "evaluate", "reel"])
    args = parser.parse_args()
    {"prepare": prepare, "evaluate": evaluate, "reel": reel}[args.mode]()
