# Milestone 68 — Native Restoration Frame Extraction

## Goal

Replace the research script's first operation with a reusable native Swift component: bounded, cancellable extraction of ordered RGB frames through SwiftyTranscoder's bundled FFmpeg.

Restoration remains unavailable in the interface. No Core ML model is bundled or invoked by the application in this milestone.

## Extraction contract

`RestorationFrameExtraction` defines one exact request:

- an existing source selected by the user;
- a new `source-frames` folder inside the restoration job workspace;
- a finite start time at or after zero; and
- between 1 and 240 frames.

The 240-frame limit bounds this intermediate step to a short preview or development clip rather than accidentally decoding an entire feature into PNG files.

`RestorationFrameExtractor` locates the same bundled FFmpeg helper used by normal conversions and launches it without a shell. FFmpeg receives individual path arguments, refuses overwrites, selects only the first video stream, preserves the source frame cadence, and writes deterministic eight-digit PNG names in RGB24 format.

The actor permits only one active extraction. It parses FFmpeg's machine-readable progress, terminates the process when cancelled, and distinguishes cancellation from failure.

## Validation

Completion is accepted only when the new folder contains exactly the requested number of ordered `frame-########.png` files and every frame is nonempty. An existing `source-frames` folder is refused rather than reused or overwritten.

Automated tests use a temporary fake FFmpeg process to prove:

- exact non-shell argument construction;
- the 1–240 frame boundary;
- successful ordered-frame validation;
- refusal to reuse an existing frame directory; and
- active process termination with correct cancellation reporting.

The complete suite passes 45 tests across 14 suites, and the macOS app builds successfully with Swift 6 complete concurrency checking.

## Representative media evidence

The exact extraction contract was also run read-only against `Alphas - s01e11 - Original Sin.m4v` at 00:09:00. It produced exactly 24 nonempty RGB PNG frames, covering approximately one second of source video and occupying 4.3 MB in a temporary workspace.

## Result and next gate

The first real restoration stage is now implemented natively and independently verified. It is still disconnected from the job runner and interface.

The next milestone can implement native Core ML frame restoration behind a replaceable processor boundary, then compare its output dimensions, count, and ordering with this extractor before joining the two stages.
