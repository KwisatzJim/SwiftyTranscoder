# Milestone 85 — Production restoration chunk processing

Milestone 85 supplies the concrete processor used by the full-video coordinator for each bounded chunk. Full-video restoration remains disabled in the interface.

## One bounded production unit

Each approved chunk now performs the real production stages in order:

1. Extract only that chunk's ordered source frames with bundled FFmpeg.
2. Restore those frames sequentially with the embedded Core ML model boundary.
3. Encode one hardware-HEVC segment with the approved cadence, dimensions, and SDR color metadata.
4. Burn the approved subtitle stream during that same HEVC encode, using the chunk's absolute program start so subtitle timing remains correct.
5. Move the validated segment from the disposable frame workspace into the restoration workspace's durable `segments` directory.

The coordinator can then delete the chunk's extracted and restored PNG frames without deleting its completed video segment.

## Safety, cancellation, and progress

The processor accepts only the exact numbered chunk directory beneath the approved, recognizably named restoration workspace. Filesystem paths are standardized and resolved before that ownership check so macOS's `/tmp` and `/private/tmp` aliases cannot cause an approved chunk to be rejected. Existing workspaces and existing segments are never overwritten.

Cancellation is forwarded to the currently active extractor, Core ML sequence processor, or video assembler. Progress inside a chunk is weighted 8 percent extraction, 87 percent restoration, 4 percent encoding, and 1 percent durable placement. The outer coordinator combines that value with completed chunks, so a later application progress display will move smoothly within each chunk instead of jumping only every 120 frames.

## Verification

Unit coverage verifies ordered stage execution, absolute subtitle timing, durable placement, unsafe-path rejection, and active extraction cancellation. A representative four-frame run also used the real SD source, the approved Real-ESRGAN 2× Core ML package, bundled media-tool lookup, native frame restoration, and hardware HEVC assembly. It produced and validated `segments/segment-000001.partial.mp4` through the same processor used by the future production pipeline.

## Current boundary

This milestone does not add a start button or change the confirmed normal conversion path. The next milestone can construct the complete production pipeline from the app's embedded model and bundled helpers, then connect it to application state behind the existing off-by-default restoration choice. Hands-on full-file review remains required before restoration is released.
