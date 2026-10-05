# Milestone 108 — Reviewed restoration batch interface

Implemented; the user accepted short batch playback, cancellation behavior, and longer multi-chunk batch playback with memory observation.

The queue now preserves the AI restoration plan with each approved video. After every plan is approved, a restoration batch runs one video at a time through the milestone 107 coordinator. Each video's gain, AAC stereo, subtitle choice, metadata, and exact frame count travel with its own request. Shared request preparation preserves the existing single-video path and rechecks restoration eligibility before starting.

The interface displays aggregate progress, current preparation/processing stages, and individual completed, failed, cancelled, or not-run results. Completed and retained partial outputs can be revealed in Finder. A failed video is reported and processing continues; cancellation stops the active job and leaves remaining videos unstarted. Queue editing is disabled while displaying batch results so file/result indices stay aligned. Choosing a new queue clears the previous results.

This first interface supports batches in which every approved video uses AI restoration. Mixed ordinary/restoration plans are blocked with an explanation. Ordinary conversion batches retain their existing behavior. Installed 1.2.0 is unchanged; this is a development build awaiting acceptance.

## Verification

- Debug application build passed.
- Ten focused Release tests passed across the batch and existing single-video controllers, covering request settings, eligibility/subtitle refusal, completion, cancellation, repeated runs, and factory failure.
- An additional opt-in real-resource test passed in 36.956 seconds. Two two-second SD clips completed through the new batch controller with different gain/AAC settings, production output validation, and removal of both owned workspaces.
- Evidence is retained in `.build/milestone108-evidence/`.
- Five focused cancellation tests passed, covering immediate cancellation, active-job cancellation, preparation cancellation, caller-task cancellation, and keeping the remaining job unstarted.

## Focused user checkpoint

Open `.build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app`. Choose the two clips in `.build/milestone108-review/inputs/`, enable full-video AI restoration and approve each plan, and choose `.build/milestone108-review/outputs/` for the outputs. Start the approved restoration batch, check that both files report completion, and review picture and sound.

The review clips are separate excerpts from the existing Alphas source, encoded with the bundled hardware HEVC helper and explicit SDR color tags. The source is unchanged. Short tests do not establish episode-length playback or memory behavior; longer batch acceptance and cancellation review remain future checkpoints.

## Cancellation checkpoint

Two 30-second test inputs are prepared in `.build/milestone108-cancellation/inputs/`, with an empty destination at `.build/milestone108-cancellation/outputs/`. Both contain the same separately encoded source excerpt under different names. Approve AI restoration for both, start the batch, then cancel when the first file says “Restoring video frames…”. Confirm that the interface remains responsive, the first file reports “Cancelled”, and the second reports “Not run”. An incomplete output, if retained, must be labeled as incomplete rather than completed. The initial sandboxed helper could not open VideoToolbox; preparation succeeded with approved hardware access.

The user confirmed this checkpoint passed.

## Longer multi-chunk checkpoint

Two distinct one-minute SD excerpts are prepared in `.build/milestone108-longer/inputs/`, with an empty destination at `.build/milestone108-longer/outputs/`. Approve restoration for both and allow the batch to finish. These exercise repeated 120-frame chunk boundaries and the transition between jobs. Review both complete outputs for continuous picture, sound, and synchronization. Observe SwiftyTranscoder memory in Activity Monitor early and near completion; a persistent increase warrants investigation. This is a longer bounded test, not full-episode acceptance.

The user confirmed both videos look and sound good. Activity Monitor showed approximately 57 MB during preparation, 307–311 MB during the first restoration, and a drop to 67 MB when the second job began. During the second restoration, memory fluctuated around 306–313 MB, including a mid-job drop to approximately 306 MB. These observed readings support stable memory across the tested chunks and release of substantial job resources between videos; they are not a measured peak or a full-episode memory guarantee.

All prepared hands-on milestone 108 checkpoints passed. Full-episode batch acceptance remains a separate checkpoint before release packaging.

Full-episode acceptance found a capped-dimension assembly failure on the 1280×720 Pilot input. The corrective change and mixed-dimension review checkpoint are recorded in `Milestone-109.md`. Release packaging remains pending.
