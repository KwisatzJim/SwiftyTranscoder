# Milestone 63 — Representative SD Frame Comparisons

## Goal

Extract source frames without modifying the video, process the full frame through the provisional model, and compare it honestly with ordinary Lanczos scaling before attempting video restoration.

## Evaluation harness

Run the Milestone 62 preparation once, then provide a source video:

```fish
Scripts/prepare-restoration-model.sh
Scripts/create-restoration-comparisons.sh "source-video.m4v"
```

Optional timestamps may follow the source path. Without them, the harness extracts frames at `00:04:30`, `00:09:00`, `00:22:30`, and `00:31:30`.

The comparison path is deliberately separate from the application. It:

- uses FFprobe to reject unidentified color, HDR, non-square pixels, and unsupported pixel formats before inference;
- extracts lossless RGB PNG frames without changing the source;
- preserves the complete frame instead of selecting a favorable crop;
- reflect-pads short dimensions, processes overlapping 522-pixel Core ML tiles, feather-blends their overlap, and removes the padding;
- produces an original-pixel view, conventional Lanczos 2× output, and clearly labeled provisional Real-ESRGAN output at matching dimensions; and
- stores source metadata and an exact timestamp manifest beside the ignored comparison images.

Generated media stays beneath `.build/restoration-evaluation/comparisons` and is not committed or included in the app.

## First SD source

`Alphas - s01e11 - Original Sin.m4v` was supplied as the first representative SD source. Read-only inspection reported:

- H.264 at 624 × 352 with square pixels;
- 8-bit `yuv420p`, limited range;
- SMPTE 170M color primaries and matrix with BT.709 transfer;
- approximately 23.9 fps and 45 minutes duration; and
- approximately 843 kb/s total bitrate.

The selected frames include fine credit text and a wide interior, a close face with glasses and hair detail, motion plus broadcast graphics, and a very dark blue-lit scene.

## Evidence

Each 624 × 352 frame required two overlapping tiles and produced a 1248 × 704 result. Warm runs took approximately 0.36–0.39 seconds per complete frame on the development Mac. A second complete run produced identical SHA-256 hashes for all four Real-ESRGAN images.

Visual inspection found:

- credit text, broadcast graphics, clothing edges, and hair were cleaner than Lanczos;
- faces remained natural in these samples, without obvious invented eyes or skin texture;
- the dark frame retained its shadow and haze structure without obvious amplified noise; and
- no tile boundary was visible after feather blending.

The improvement is real but moderate, which is preferable to aggressive invented detail. These still images cannot establish temporal consistency: flicker, shimmer, and changing facial detail require adjacent-frame and short-clip tests.

## Result and next gate

The provisional model passes this first full-frame SD still-image gate. It remains excluded from the app and is not yet approved for video use.

The next milestone will test consecutive frames from short bright, facial, text/graphics, and dark clips. It will measure deterministic ordering, bounded memory, cancellation points, and visible frame-to-frame instability before audio or subtitle integration begins.
