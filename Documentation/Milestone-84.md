# Milestone 84 — Full-video restoration coordination

Milestone 84 connects the independently validated full-video boundaries into one ordered coordinator without enabling the feature in the interface.

## Ordered pipeline

The coordinator now performs these steps:

1. Refuse missing sources, recognizable workspace conflicts, existing final files, existing adjacent partial files, unavailable destination folders, and unsafe canonical paths before processing starts.
2. Build the bounded 120-frame chunk plan and process every chunk sequentially.
3. Join the ordered silent HEVC segments without recompressing them.
4. Add and validate the approved audio, chapters, and container metadata without recompressing the restored picture.
5. Copy the validated result to the destination's adjacent `.partial.mp4` file.
6. Atomically promote that staged file to the finished `.mp4` filename.
7. Remove the safely recognizable owned workspace after success, cancellation, or failure.

## State and progress

The pipeline exposes explicit running and cancelling states for chunk processing, silent-video assembly, audio and metadata, destination staging, and final promotion. Aggregate progress reserves 90 percent for the expensive chunk work and the remaining 10 percent for assembly, audio, and destination handoff.

Cancellation is routed to the active long-running media component. If cancellation or failure occurs after destination staging, the adjacent `.partial.mp4` remains visible and is reported to the caller. The source is never changed. Once atomic final promotion succeeds, completion wins even if a late cancellation request arrives.

## Safety status

Full-video restoration remains disabled in the interface. The next milestone supplies the production chunk processor that performs extraction, native Core ML restoration, subtitle-aware HEVC encoding, and durable segment placement for each bounded chunk. App-level controls and hands-on full-file testing follow only after that concrete wiring passes automated and representative-media verification.
