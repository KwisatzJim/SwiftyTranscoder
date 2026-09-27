# Milestone 71 — Native Ordered Frame Sequences

## Goal

Extend native complete-frame restoration to a bounded, deterministic sequence while preserving strict order, limited memory use, cancellation, and safe derived-file cleanup.

This milestone remains internal. It does not assemble a movie or expose restoration in the application interface.

## Sequence boundary

`RestorationFrameSequence` accepts between 1 and 240 PNG frames. It requires:

- positive expected dimensions;
- unique filenames;
- filenames already supplied in ascending order; and
- a new `restored-frames` destination inside the job workspace.

The boundary rejects invalid or reordered inputs instead of silently guessing their intended order.

`RestorationFrameSequenceProcessor` processes exactly one frame at a time through `RestorationFrameProcessor`. This keeps the working set bounded to one decoded source frame, its tile tensors, and one assembled output frame. It reports completed-frame progress and preserves each source filename in the derived output sequence.

If processing fails or is cancelled, the processor removes only the `restored-frames` directory that it created. It never removes the extracted source frames. An existing output directory is refused rather than reused or overwritten.

## Verification

Tests prove ordered sequential processing, preserved filenames, progress, rejection of unordered input, refusal to reuse an output directory, cancellation propagation, and cleanup limited to the owned derived sequence.

The ignored research model was also used for a real four-frame native sequence covering bright, face, dark, and blue-lit scenes. All four frames completed at exactly 1248×704 and visual inspection found correct orientation and color with no visible tile seams.

Direct comparisons with the earlier Python Real-ESRGAN results produced these mean absolute RGB differences on a 0–255 scale:

| Frame | Mean | 95th percentile | Maximum |
| --- | ---: | ---: | ---: |
| 1 | 4.458 | 9 | 41 |
| 2 | 3.205 | 8 | 26 |
| 3 | 4.102 | 9 | 52 |
| 4 | 3.647 | 9 | 34 |

The mean differences between native and Python consecutive-frame deltas were 3.884, 3.254, and 3.834. This confirms that the small Float16 and image-stack differences remain stable across the representative sequence rather than appearing as a large temporal discontinuity.

The complete test suite passes 58 tests across 17 suites. The full macOS application builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

SwiftyTranscoder can now process bounded extracted-frame sequences natively, deterministically, and safely. The provisional model remains external and ignored, and production conversion cannot reach this boundary.

The next milestone can assemble the restored PNG sequence into a silent hardware-HEVC video segment with the approved frame rate and explicit SDR color metadata. Audio and final-container integration will remain separate until that video-only result passes independent validation.
