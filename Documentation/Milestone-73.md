# Milestone 73 — Native Preview Pipeline Coordination

## Goal

Connect the verified native extraction, Core ML restoration, and silent-video assembly boundaries behind one coordinator with ordered stages, aggregate progress, active cancellation, and safe workspace ownership.

The coordinator deliberately stops at a validated silent partial segment. It does not invoke the final-output job runner, so an audio-less development artifact cannot be promoted to a user-facing completed filename.

## Pipeline contract

`NativeRestorationPreviewRequest` records one source, a bounded start time and frame count, the approved restoration plan, and a new workspace whose leaf name begins with `SwiftyTranscoder-Restoration-`. The recognizable name is required because the pipeline may remove that entire workspace after cancellation or failure.

`NativeRestorationPreviewPipeline` executes exactly three stages:

1. bounded RGB frame extraction through FFmpeg;
2. ordered, one-frame-at-a-time native Core ML restoration; and
3. hardware-only assembly and independent validation of `restored-video.partial.mp4`.

The coordinator refuses a missing source or an existing workspace. It creates the workspace itself and therefore owns only that directory and its derived contents. On failure or cancellation, it removes that owned workspace while leaving the source untouched. On success, it retains the source frames, restored frames, and validated silent partial for development inspection.

Aggregate progress assigns 10 percent to extraction, 85 percent to restoration, and 5 percent to assembly. These weights reflect that Core ML inference dominates the representative runtime. Short-lived monitor tasks read each component's own progress and are cancelled on both success and failure.

Cancellation is routed only to the active stage. The coordinator records whether it is running, cancelling, completed, cancelled, or failed, including the exact active stage.

## Verification

Automated tests prove:

- the three stages run in order;
- successful output remains a clearly labeled silent partial;
- no final user output is created;
- an existing workspace blocks all stage execution; and
- cancellation reaches the active component, removes only the owned workspace, and preserves the source.

The complete native pipeline was also run against four frames beginning at 00:09:00 of `Alphas - s01e11 - Original Sin.m4v`. It extracted the frames directly from the source, restored all four through the external research Core ML model, and assembled the result through hardware-only VideoToolbox. The assembler's independent ffprobe gate accepted the silent partial.

The complete test suite passes 68 tests across 19 suites. The full macOS application builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

SwiftyTranscoder now has one native, cancellable coordinator for the complete video-only restoration preview path. The external model remains ignored, and no application UI can reach the pipeline.

The next milestone can add an audio-and-metadata mux boundary that combines this validated silent video with the corresponding source time range. It must preserve the established protected-gain audio policy and independently validate synchronization before any final-output promotion is connected.
