# Milestone 87 — Full-video restoration application controller

Milestone 87 adds the application-state boundary for one approved full-video restoration without yet exposing a control that can start the job.

## Approved request construction

The controller accepts the current source, inspection, destination, restoration plan, gain choice, AAC-stereo choice, and explicit subtitle selection. Before constructing the production pipeline, it:

- requires valid duration and source-size metadata;
- derives the complete frame count with the same bounded-storage planner shown in the interface;
- requires the approved primary audio stream;
- converts the selected FFprobe subtitle stream index into the subtitle ordinal FFmpeg's subtitle filter requires;
- refuses unresolved, missing, or non-SubRip subtitle choices;
- preserves chapter count and case-insensitive container title metadata; and
- creates a unique, recognizably named workspace on the temporary volume.

No source-specific subtitle choice or workspace is reused across jobs.

## Observable lifecycle

The controller publishes idle, preparing, running, cancelling, completed, cancelled, and failed phases. Running and active-pipeline cancellation phases retain the pipeline's exact stage; cancellation during preparation remains accurately stage-free. It also publishes the pipeline's aggregate progress, including the smooth within-chunk progress added in Milestone 85.

Core ML pipeline construction occurs away from the main interface thread. Cancellation is forwarded to the active production pipeline. A cancellation requested during preparation prevents the newly constructed pipeline from starting. Terminal states preserve the pipeline's reported adjacent partial-output URL so a later interface can label and reveal it accurately.

The controller can be reset only after work has stopped.

## Verification

Isolated controller tests use the same small runner and builder boundaries as production. They verify exact request derivation, subtitle ordinal conversion, chapter and title preservation, progress and completion publication, cancellation forwarding with partial-output reporting, resource-construction failure, and refusal of unresolved subtitle decisions before the factory is called.

## Current boundary

The controller is deliberately not owned by `ContentView` yet, and the existing plan approval remains blocked when full-video restoration is enabled. The next milestone can add a dedicated restoration conversion display and connect one reviewed start/cancel path while preserving the ordinary conversion and batch workflows. That user-visible milestone will require hands-on review before full-file processing continues further.
