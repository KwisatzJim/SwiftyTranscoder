# Milestone 107 — Sequential restoration batch backend

The user accepted the installed 1.2.0 GUI, CLI launcher, and short restoration preview, then authorized the next batch-restoration milestone.

`RestorationBatchCoordinator` accepts an ordered array of reviewed, source-specific `FullVideoRestorationRequest` values. It builds and awaits one existing production pipeline at a time, releases that job before moving on, preserves each request's audio/subtitle/metadata choices, prevents idle system sleep during a batch, and publishes a snapshot with per-item states, active index, stages, and frame-count-weighted progress.

Before processing, the coordinator refuses empty queues, conflicting source/output/partial paths, overlapping workspace trees, and destinations without an MP4 extension. Canonical path checks include case normalization and symbolic-link resolution. Sources shared by multiple reviewed jobs are allowed when output/workspace paths are distinct; no source is modified.

Immediately before each job, background preflight checks source existence, destination/workspace conflicts, folder availability, and temporary/destination capacity using existing bounded-chunk and destination estimates. The existing pipeline and promotion service retain their own checks, including actual-size destination staging. A source-size estimate cannot guarantee the final encoded size. Storage is checked again for each job rather than assumed valid from the original queue review.

## Results and cancellation policy

A per-file failure is recorded with its message and partial-output URL, and subsequent jobs continue. Batch completion means all jobs were handled, not that every job succeeded; callers must display the individual results. Progress weights handled jobs by their planned frame counts.

Batch cancellation or cancellation of the calling task forwards to active preparation/processing, retains the active job's partial-output report, and marks remaining jobs as not run. Synchronous model loading must return before preparation cancellation completes. An already promoted completion remains successful while cancellation prevents the next job. Concurrent batch runs are rejected without replacing the active snapshot. The existing pipeline remains responsible for owned-workspace cleanup and output promotion.

## Verification

All 11 focused Release tests passed. They cover one-at-a-time order, source-specific gain/AAC/subtitle settings, continued processing after a failure, active and preparation cancellation, caller-task cancellation, cross-job path conflicts, workspace overlap, capacity rechecking, existing-partial preservation, and active-batch rejection.

The real-resource test ran two sequential two-frame SD restorations using the approved Core ML model and hardware HEVC. Each output passed production validation and independent FFprobe inspection; differing AC-3/AAC choices were preserved, partial files were promoted, and both owned workspaces were removed. This is short integration evidence, not an unattended multi-episode acceptance run. Source media was not changed, and test outputs were cleaned.

The Debug app build and `git diff --check` passed; evidence is retained in `.build/milestone107-evidence/`. The coordinator is not connected to production UI or CLI yet. Installed 1.2.0 remains unchanged. Milestone 108 will connect reviewed restoration plans to the queue and add user-visible progress/results before hands-on batch testing.
