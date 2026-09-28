# Milestone 88 — Reviewed full-video restoration controls

Milestone 88 connects one reviewed, eligible restoration plan to the production full-video pipeline and gives that long-running work its own conversion display. Ordinary conversion and approved-batch execution continue to use their existing controller and interface.

## Deliberate single-video boundary

Full-video AI restoration is available only when exactly one source is selected. Before the start button is enabled, the app still requires the ordinary output, audio, color, and subtitle decisions, and it separately confirms that the bounded restoration workspace fits on the temporary volume. Batch restoration is not inferred or silently mixed with ordinary batch plans.

The production pipeline and Core ML model are constructed only after the user starts the reviewed plan. Resource-location failures therefore appear as a normal restoration failure in the conversion display instead of preventing the app from opening.

## Dedicated progress and cancellation

The restoration display reports an aggregate percentage and names the current plain-language stage:

- preparing the restoration;
- restoring video frames;
- joining restored video;
- adding approved audio and metadata;
- copying validated output; and
- finalizing the restored output.

Cancel remains available while work is active. The controller forwards cancellation to the active pipeline and keeps macOS awake until the pipeline reaches a terminal state.

## Output reporting

Successful work shows the final output path and a **Show in Finder** action. Cancellation and failure distinguish between no incomplete output and a retained, clearly labeled `.partial.mp4` file. The latter can be moved to the Trash only through an explicit confirmation; the controller refuses to trash a filename that does not end in `.partial.mp4`.

## Verification

The complete 106-test suite passes, including the real Core ML model and representative native restoration pipeline checks. A clean Xcode Debug build also succeeds with the bundled FFmpeg helpers, FFprobe helper, restoration model, and notices embedded in the application.

## Hands-on checkpoint

The next required step is a short real-app review with the SD test video. Confirm that enabling full-video AI restoration changes the primary button to **Restore and Convert Approved Plan**, then start it and verify the stage text, percentage, Cancel button, and keep-awake message. A complete episode does not need to finish for this first interface checkpoint; cancellation should stop safely and accurately report whether a partial output remains.
