#!/usr/bin/env python3
"""Validate the fixed-shape Core ML restoration candidate and time inference."""

from __future__ import annotations

import argparse
import statistics
import time
from pathlib import Path

import coremltools as ct
import numpy as np


EXPECTED_INPUT = (1, 3, 522, 522)
EXPECTED_OUTPUT = (1, 3, 1044, 1044)


def shape_for(feature) -> tuple[int, ...]:
    return tuple(feature.type.multiArrayType.shape)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()

    if args.runs < 1:
        parser.error("--runs must be at least 1")

    model = ct.models.MLModel(str(args.model))
    specification = model.get_spec()
    input_feature = specification.description.input[0]
    output_feature = specification.description.output[0]

    input_shape = shape_for(input_feature)
    output_shape = shape_for(output_feature)
    if input_shape != EXPECTED_INPUT:
        raise RuntimeError(f"unexpected input shape: {input_shape}")
    if output_shape != EXPECTED_OUTPUT:
        raise RuntimeError(f"unexpected output shape: {output_shape}")

    test_input = np.zeros(EXPECTED_INPUT, dtype=np.float16)
    warmup = model.predict({input_feature.name: test_input})[output_feature.name]
    if warmup.shape != EXPECTED_OUTPUT or not np.isfinite(warmup).all():
        raise RuntimeError("warm-up inference returned invalid output")

    durations = []
    reference = None
    for _ in range(args.runs):
        start = time.perf_counter()
        output = model.predict({input_feature.name: test_input})[output_feature.name]
        durations.append(time.perf_counter() - start)
        if not np.isfinite(output).all():
            raise RuntimeError("inference returned non-finite output")
        if reference is not None and not np.array_equal(reference, output):
            raise RuntimeError("repeated inference was not deterministic")
        reference = output

    print(f"Input:  {input_feature.name} {input_shape}")
    print(f"Output: {output_feature.name} {output_shape}")
    print(f"Runs:   {args.runs}")
    print(f"Median: {statistics.median(durations):.3f} seconds per 522x522 tile")
    print("Deterministic zero-frame inference: PASS")


if __name__ == "__main__":
    main()
