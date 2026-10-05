# Milestone 119 — Saved restoration progress foundation

Installed 1.4.0 acceptance is complete. The user authorized resumable restoration; their sequential-step preference makes the first checkpoint an isolated saved-progress record, before changing cancellation cleanup or adding a Resume action.

Existing restoration processes up to 120 frames per block. The new standalone checkpoint store records a contiguous prefix of completed segments, each with its index, frame span, byte count, and SHA-256. A caller must record a block only after normal media validation. A file that exists without a corresponding completed record is not counted. This store does not independently validate video contents; media validation remains the caller's contract.

Identity creation hashes the complete source file in 1 MiB buffers and fingerprints canonical input/output paths, model choice, source/output dimensions, frame rate/count/duration, color settings, chunk limit, gain/AAC/subtitle choices, audio selection, chapters/title, and a required processing-engine signature. Future integration must derive that signature from the actual model/processing version and recompute identity before reopening progress. Loading verifies expected identity and rehashes every recorded segment before reuse.

Initial creation stages a complete record then moves it into place without replacing an existing record. Updates use atomic replacement only after validating the existing record. The first test found Foundation does not support combining atomic write with withoutOverwriting; staged creation corrected this, and all five tests passed on rerun. Invalid schema/records, changed settings/source/engine, altered same-size segments, out-of-order records, and linked segments are refused. Metadata is bounded to 4 MiB. The actor serializes access within a process; exclusive ownership across processes must be added before production resume integration.

This foundation is not connected to live restoration, GUI, or CLI. Existing cancel/failure cleanup and installed 1.4.0 are unchanged. No resume behavior is claimed yet, and no user playback run is required at this checkpoint.

Validation: five tests passed, covering reopen/unfinished-file handling, identity changes, content corruption, ordering, existing/schema refusal, and external-file preservation. The optimized app build and strict deep signature verification also passed. Evidence: `.build/milestone119-evidence/`.

Next focused change: retain validated blocks and record progress in an explicit opt-in backend path, verify interruption/reopen/reuse with real short clips, then expose a clear resume workflow. Stable non-temporary storage, ownership/locking, source/model revalidation, stale/incomplete-stage cleanup, and resumed timing/ETA require integration before user-facing availability.
