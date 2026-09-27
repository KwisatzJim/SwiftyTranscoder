# Milestone 70 — Native Complete-Frame Restoration

## Goal

Extend the native Core ML boundary from one fixed tile to one complete image frame while preserving the research harness's edge padding, overlap, feathering, crop, and exact 2× output geometry.

This milestone remains an internal boundary. It does not restore a video sequence or expose restoration in the application interface.

## Frame pipeline

`RestorationFrameProcessor` now:

1. accepts a PNG source and refuses to replace an existing destination;
2. decodes the frame to 8-bit RGBA;
3. applies reflected edge padding without repeating the edge pixel;
4. divides the padded frame into overlapping 522×522 tiles;
5. invokes the native Core ML tile processor sequentially;
6. combines the 2× results with linear overlap feathering;
7. crops away the scaled padding; and
8. writes an exact 2× PNG.

The processor reports progress per completed tile and checks cancellation between every bounded inference operation. It honors the strides reported by each `MLMultiArray`; Core ML tensors must not be assumed to use a simple contiguous plane layout.

## Verification

Unit tests cover the confirmed 624×352 SD frame geometry, a larger six-tile frame, and NumPy-compatible reflection behavior. When the ignored research model and representative source frame are present, an integration test runs the full native pipeline and writes a 1248×704 result.

The native image was compared directly with the earlier Python Real-ESRGAN output:

- dimensions: exact 1248×704 match;
- mean absolute RGB difference: 4.46 levels on a 0–255 scale;
- 95th-percentile absolute difference: 9 levels;
- maximum isolated difference: 41 levels; and
- visual inspection: correct orientation and color, with no visible tile seam.

The small numerical difference is expected because the native boundary uses the model's required Float16 tensors and macOS image decoding/color conversion, while the research path used its Python image stack.

The complete suite passes 53 tests across 16 suites. The full macOS application also builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

SwiftyTranscoder can now restore a complete SD frame through native Swift and Core ML without Python. The provisional model remains external and ignored, and no production UI can reach this code.

The next milestone can connect bounded ordered frame sequences to this processor, verify cancellation and cleanup across multiple frames, and produce native temporal comparison evidence before any production conversion integration.
