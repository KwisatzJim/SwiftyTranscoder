# Milestone 75 — Complete Native Restoration Preview Pipeline

## Goal

Connect the validated audio mux boundary to the native restoration preview coordinator so one cancellable operation produces a complete, playable partial preview with restored video and compatibility audio.

## Four-stage coordinator

`NativeRestorationPreviewPipeline` now runs these stages in order:

1. extract the bounded source frame sequence;
2. restore every frame through the pinned Core ML model;
3. assemble and validate silent hardware HEVC; and
4. copy that HEVC into a validated preview container with protected-gain compatibility audio and source metadata.

The request now carries the explicitly selected source audio stream and the approved gain and AAC-stereo choices. Preview duration is derived from the exact frame count and rational source frame rate, so video restoration and source-audio extraction use one shared time range.

Progress is weighted 10 percent extraction, 83 percent restoration, 5 percent video assembly, and 2 percent audio muxing. Cancellation is routed to whichever of the four stages is active. Any failure or cancellation removes only the recognizable workspace created and owned by the pipeline.

Success returns only `restored-preview.partial.mp4`. The coordinator still has no final-output promotion and no application UI entry point.

## Verification

Automated tests prove all four stages run in order, success cannot create a final output, existing workspaces remain protected, and cancellation still removes only the owned workspace while preserving the source.

The complete four-stage path also ran against four frames beginning at 00:09:00 of `Alphas - s01e11 - Original Sin.m4v`. The result contains:

- copied HEVC with the `hvc1` compatibility tag;
- default AC-3 stereo at 48 kHz and 192 kb/s;
- non-default AAC stereo at 48 kHz and approximately 192 kb/s;
- source show, season, and episode metadata; and
- audio/video stream starts within approximately 21 milliseconds.

The complete suite passes 72 tests across 20 suites. The full macOS application builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

The complete native restoration preview backend is integrated and independently machine-validated. The next milestone must add a deliberately bounded application preview control and produce a long enough comparison clip for human review.

That step requires hands-on confirmation of picture quality, audio quality, synchronization, responsiveness, progress, and cancellation before any full-file restoration or final-output promotion is allowed.
