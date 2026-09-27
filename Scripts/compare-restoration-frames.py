#!/usr/bin/env python3
"""Create full-frame Lanczos and tiled Core ML restoration comparisons."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import coremltools as ct
import numpy as np
from PIL import Image, ImageDraw


TILE_SIZE = 522
SCALE = 2
SUPPORTED_PIXEL_FORMATS = {"yuv420p"}
SUPPORTED_TRANSFERS = {"bt709", "smpte170m"}
SUPPORTED_PRIMARIES = {"bt709", "smpte170m"}
SUPPORTED_SPACES = {"bt709", "smpte170m"}


def validate_metadata(path: Path) -> dict:
    document = json.loads(path.read_text())
    video_streams = [stream for stream in document["streams"] if stream.get("codec_type") == "video"]
    if len(video_streams) != 1:
        raise RuntimeError("the comparison harness requires exactly one video stream")

    stream = video_streams[0]
    checks = {
        "pixel format": (stream.get("pix_fmt"), SUPPORTED_PIXEL_FORMATS),
        "color transfer": (stream.get("color_transfer"), SUPPORTED_TRANSFERS),
        "color primaries": (stream.get("color_primaries"), SUPPORTED_PRIMARIES),
        "color space": (stream.get("color_space"), SUPPORTED_SPACES),
    }
    for label, (value, supported) in checks.items():
        if value not in supported:
            raise RuntimeError(f"unsupported or unidentified {label}: {value!r}")
    if stream.get("color_range") != "tv":
        raise RuntimeError(f"unsupported or unidentified color range: {stream.get('color_range')!r}")
    if stream.get("sample_aspect_ratio") not in (None, "1:1"):
        raise RuntimeError("non-square source pixels are not supported by this evaluation harness")
    return stream


def tile_positions(length: int) -> list[int]:
    if length <= TILE_SIZE:
        return [0]
    positions = list(range(0, length - TILE_SIZE + 1, TILE_SIZE - 64))
    final = length - TILE_SIZE
    if positions[-1] != final:
        positions.append(final)
    return positions


def axis_weights(index: int, positions: list[int]) -> np.ndarray:
    weights = np.ones(TILE_SIZE * SCALE, dtype=np.float32)
    position = positions[index]
    if index > 0:
        overlap = (positions[index - 1] + TILE_SIZE - position) * SCALE
        weights[:overlap] = np.linspace(0.0, 1.0, overlap, dtype=np.float32)
    if index + 1 < len(positions):
        overlap = (position + TILE_SIZE - positions[index + 1]) * SCALE
        weights[-overlap:] = np.minimum(
            weights[-overlap:],
            np.linspace(1.0, 0.0, overlap, dtype=np.float32),
        )
    return weights


def restore(image: Image.Image, model: ct.models.MLModel) -> tuple[Image.Image, int, float]:
    pixels = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    height, width, _ = pixels.shape
    pad_height = max(0, TILE_SIZE - height)
    pad_width = max(0, TILE_SIZE - width)
    top = pad_height // 2
    bottom = pad_height - top
    left = pad_width // 2
    right = pad_width - left
    padded = np.pad(pixels, ((top, bottom), (left, right), (0, 0)), mode="reflect")

    output_height = padded.shape[0] * SCALE
    output_width = padded.shape[1] * SCALE
    accumulated = np.zeros((output_height, output_width, 3), dtype=np.float32)
    counts = np.zeros((output_height, output_width, 1), dtype=np.float32)

    input_name = model.get_spec().description.input[0].name
    output_name = model.get_spec().description.output[0].name
    x_positions = tile_positions(padded.shape[1])
    y_positions = tile_positions(padded.shape[0])
    positions = [
        (x_index, y_index, x, y)
        for y_index, y in enumerate(y_positions)
        for x_index, x in enumerate(x_positions)
    ]
    started = time.perf_counter()
    for x_index, y_index, x, y in positions:
        tile = padded[y : y + TILE_SIZE, x : x + TILE_SIZE]
        tensor = np.transpose(tile, (2, 0, 1))[None, ...]
        result = model.predict({input_name: tensor})[output_name][0]
        restored_tile = np.transpose(result, (1, 2, 0))
        horizontal = axis_weights(x_index, x_positions)
        vertical = axis_weights(y_index, y_positions)
        weights = (vertical[:, None] * horizontal[None, :])[:, :, None]
        destination_y = y * SCALE
        destination_x = x * SCALE
        accumulated[
            destination_y : destination_y + TILE_SIZE * SCALE,
            destination_x : destination_x + TILE_SIZE * SCALE,
        ] += restored_tile * weights
        counts[
            destination_y : destination_y + TILE_SIZE * SCALE,
            destination_x : destination_x + TILE_SIZE * SCALE,
        ] += weights

    restored = np.clip(accumulated / counts, 0.0, 1.0)
    cropped = restored[
        top * SCALE : (top + height) * SCALE,
        left * SCALE : (left + width) * SCALE,
    ]
    output = Image.fromarray(np.rint(cropped * 255.0).astype(np.uint8), mode="RGB")
    return output, len(positions), time.perf_counter() - started


def labeled_panel(image: Image.Image, label: str) -> Image.Image:
    panel = Image.new("RGB", (image.width, image.height + 36), "black")
    panel.paste(image, (0, 36))
    ImageDraw.Draw(panel).text((12, 11), label, fill="white")
    return panel


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("frames", nargs="+", type=Path)
    args = parser.parse_args()

    metadata = validate_metadata(args.metadata)
    model = ct.models.MLModel(str(args.model))
    args.output.mkdir(parents=True, exist_ok=True)

    for frame in args.frames:
        source = Image.open(frame).convert("RGB")
        expected_size = (metadata["width"], metadata["height"])
        if source.size != expected_size:
            raise RuntimeError(f"{frame.name} is {source.size}; expected {expected_size}")

        nearest = source.resize((source.width * SCALE, source.height * SCALE), Image.Resampling.NEAREST)
        lanczos = source.resize((source.width * SCALE, source.height * SCALE), Image.Resampling.LANCZOS)
        restored, tile_count, duration = restore(source, model)

        lanczos.save(args.output / f"{frame.stem}-lanczos.png")
        restored.save(args.output / f"{frame.stem}-real-esrgan.png")
        panels = [
            labeled_panel(nearest, "Source pixels (nearest-neighbor 2x display)"),
            labeled_panel(lanczos, "Conventional Lanczos 2x"),
            labeled_panel(restored, "Real-ESRGAN x2plus (provisional AI candidate)"),
        ]
        comparison = Image.new("RGB", (sum(panel.width for panel in panels), panels[0].height), "black")
        offset = 0
        for panel in panels:
            comparison.paste(panel, (offset, 0))
            offset += panel.width
        comparison.save(args.output / f"{frame.stem}-comparison.png")
        print(f"{frame.name}: {tile_count} tiles, {duration:.3f} seconds")


if __name__ == "__main__":
    main()
