# Milestone 64 — Consecutive-Frame Restoration Gate

## Goal

Test the provisional model on ordered adjacent frames, measure its working memory and repeatability, prove a frame-boundary cancellation checkpoint, and produce playable comparison clips for human temporal-quality review.

## Harness

After preparing the Milestone 62 model, run:

```fish
Scripts/create-restoration-clip-comparisons.sh "source-video.m4v"
```

The harness extracts four one-second, 24-frame sequences from the established credits, face, motion/graphics, and dark-scene timestamps. It never modifies the source.

For each sequence, it:

- retains the source frame order and processes one full frame at a time;
- uses the same color gate, padding, overlapping tiles, and feather blending as Milestone 63;
- writes a checkpoint after every completed frame with timing, tile count, and output SHA-256;
- handles `SIGINT` or `SIGTERM` between frames and labels the checkpoint `cancelled` rather than `complete`;
- records peak resident memory;
- records how much the model's enhancement relative to Lanczos changes between adjacent frames; and
- creates a one-second H.264 review clip containing source pixels, Lanczos, and Real-ESRGAN side by side.

The enhancement-change value is diagnostic evidence, not an automatic quality score. Camera motion and subject motion also change that value. A person must still inspect the clips for shimmer, flicker, unstable faces, changing text edges, and visible tile boundaries.

## SD evidence

The `Alphas - s01e11 - Original Sin.m4v` run completed all 96 requested frames:

| Sequence | Frames | Median frame time | Peak memory | Median enhancement change | Maximum enhancement change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Credits | 24 | 0.361 s | 546.2 MiB | 0.008869 | 0.012305 |
| Face | 24 | 0.360 s | 544.4 MiB | 0.007202 | 0.009046 |
| Motion/graphics | 24 | 0.360 s | 545.0 MiB | 0.007853 | 0.008976 |
| Dark | 24 | 0.360 s | 544.7 MiB | 0.007452 | 0.009232 |

Each review MP4 contains exactly 24 frames at the source average frame rate, measures 3744 × 740 for the three labeled panels, and lasts approximately 1.001 seconds.

A separate 24-frame rerun of the face sequence reproduced every ordered Real-ESRGAN PNG SHA-256 exactly. A forced three-frame cancellation stopped after frame two, exited with code 130, recorded two completed hashes, and left `state: cancelled` in the atomic status file.

## Current result

The sequence pipeline passes its technical ordering, deterministic-output, memory, progress-checkpoint, cancellation, dimensions, and container gates. Its roughly 545 MiB process peak is acceptable for continued development but must remain bounded when application integration begins.

Human review of the four generated clips is still required before the model passes the temporal-quality gate. Until that confirmation, the model remains provisional and excluded from SwiftyTranscoder.

If the clips pass, the next milestone will design the restoration video pipeline around these proven frame boundaries and begin reintegrating the existing audio, subtitle, metadata, cancellation, and partial-output protections without changing the version 1.0 path.
