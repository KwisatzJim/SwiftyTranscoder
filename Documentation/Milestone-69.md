# Milestone 69 — Native Core ML Tile Boundary

## Goal

Replace the research harness's raw model invocation with a native Swift Core ML boundary while keeping the provisional model external, ignored, and unavailable to the application interface.

This milestone processes one fixed-size model tile. It does not yet decode PNG pixels, tile a complete frame, feather overlaps, or save restored frames.

## Exact model contract

`RestorationModelContract` inspects a loaded model rather than assuming feature names. It accepts only:

- exactly one numeric input and one numeric output;
- Float16 tensors;
- input shape `[1, 3, 522, 522]`; and
- output shape `[1, 3, 1044, 1044]`.

Any different model, shape, feature type, or precision is rejected before inference. This prevents a similarly named but incompatible model from silently producing corrupted images.

`CoreMLRestorationTileProcessor` compiles an external `.mlpackage` when needed, loads it using Core ML, validates its live description, and performs one prediction at a time. It verifies the supplied tensor, the returned tensor, and every output value. NaN or infinite output is rejected.

The processor checks cancellation immediately before and after each tile. Core ML does not expose a safe way to interrupt this model in the middle of a single synchronous prediction, so the tile remains the bounded cancellation unit.

## Verification

Tests prove acceptance of the exact pinned contract and rejection of incorrect input and output shapes. When the ignored research model is present, an integration test also:

1. compiles and loads `RealESRGAN_x2plus_522_fp16.mlpackage` through native Core ML;
2. supplies an explicitly zero-initialized Float16 tile;
3. performs a real local prediction; and
4. verifies a finite Float16 `[1, 3, 1044, 1044]` result.

The complete suite passes 49 tests across 15 suites. The full macOS app builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

SwiftyTranscoder can now invoke the provisional restoration model directly through Core ML without Python or `coremltools`. The model itself remains outside the app and no production workflow can reach the processor.

The next milestone can implement native PNG decoding, reflected edge padding, overlapping 522-pixel tiles, feathered 2× assembly, cropping, and PNG output for one complete frame. Its result will be compared directly with the already confirmed research-harness output before sequence processing is connected.
