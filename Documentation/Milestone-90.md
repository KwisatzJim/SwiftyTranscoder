# Milestone 90 — Exact full-video frame planning

Milestone 90 corrects an end-of-video frame-count mismatch found during the first episode-length restoration run.

## Root cause

The original plan estimated the total frame count by multiplying the container duration by the video frame rate. For the test episode, that calculation produced 64,800 expected frames, while FFprobe reported that the video stream actually contains 64,797 frames.

The difference appeared only in the final 120-frame chunk. FFmpeg correctly extracted the 117 frames that remained, but the restoration validator rejected the chunk because the plan had requested 120.

## Correction

Media inspection now reads FFprobe's exact `nb_frames` value. Full-video restoration uses that positive exact count when it is available and retains the duration-based calculation only as a fallback for formats that do not report a frame count.

Strict validation remains in place: every chunk must still contain exactly the number of frames approved by the corrected plan. For this episode, the plan contains 539 full 120-frame chunks followed by one 117-frame chunk.

## Verification

- A regression test reproduces the 64,797-frame stream with a slightly longer container duration and confirms the final chunk contains 117 frames.
- The application controller test confirms that an exact probed count overrides the duration estimate.
- The real production completion test confirms the frame-count field survives FFprobe decoding and the full restoration pipeline still completes.
- The complete suite passed with 108 tests across 28 suites.
- The macOS Debug application target built successfully with code signing disabled for local verification.

## Hands-on checkpoint

Rebuild and run SwiftyTranscoder from Xcode, approve the same episode, and start restoration again. The corrected plan should complete the final 117-frame chunk rather than failing after expecting 120 frames.
