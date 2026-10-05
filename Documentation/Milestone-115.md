# Milestone 115 — Restoration completion summary

The user authorized the first suggested follow-up: a small completion summary for restored videos. The single-video result and each completed batch row now show elapsed time, average frames per second, and the AI model used. Finished or cancelled batches also show total batch elapsed time.

Elapsed time uses monotonic system uptime. It begins before model preparation/per-file preflight and ends after the pipeline has completed final output handling. Per-video measurements exclude time queued behind an earlier batch file. Average speed is the validated request frame count divided by whole-job elapsed time, including preparation, audio, and saving; the interface states this definition. This is an end-to-end average, not AI inference speed or the file's playback frame rate.

Only completed videos receive speed/model summaries. Failed, cancelled, and unstarted files do not receive success summaries. Completed earlier batch files retain their summaries after a later failure or cancellation. Resetting or starting a new run clears old summaries. Batch total elapsed time includes all work and failed/cancelled attempts.

The summary is held with the current results, not written into the output video or persisted as a benchmark log. Encoding/restoration settings and the installed 1.3.0 release are unchanged.

Validation: 25 focused tests in four suites passed, covering deterministic single-job and separate per-file/batch timing, model preservation, invalid measurements, reset/new-run clearing, failure and cancellation, and a real two-file restoration. The separate optimized app build and strict deep signature verification passed. Evidence: `.build/milestone115-evidence/`.

Test app: `.build/Milestone115DerivedData/Build/Products/Release/SwiftyTranscoder.app`. The user confirmed the short restoration completion summary and authorized the next focused improvement. The milestone 115 UI checkpoint is accepted.
