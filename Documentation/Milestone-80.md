# Milestone 80 — Validated Silent Segment Assembly

## Goal

Join an ordered set of restored HEVC chunks into one silent partial MP4 without recompressing the restored picture, then independently verify that the assembled result still matches the approved restoration plan.

## Segment contract

The assembly request accepts only one complete numeric sequence named `segment-000001.partial.mp4`, `segment-000002.partial.mp4`, and so on. Every segment must be in the same segment directory and present before assembly starts. Missing, duplicated, out-of-order, or differently named inputs are refused.

The FFmpeg concat manifest is generated inside the owned restoration workspace, safely quotes literal file paths, and is removed when assembly ends. The final silent working file remains clearly labeled `restored-silent.partial.mp4`. FFmpeg uses video stream copy rather than another HEVC encode, avoiding both generation loss and unnecessary work.

## Independent validation

After joining, ffprobe must report exactly one video stream and no audio or subtitle streams. The result is rejected unless all of the following still match the approved plan:

- HEVC Main profile with the `hvc1` tag and `yuv420p` pixels
- restored width and height
- rational source cadence within the existing precise tolerance
- limited-range SDR color range, space, transfer, and primaries
- duration derived from the total planned frame count
- a positive file size

Cancellation terminates the active helper, removes the temporary concat manifest, and retains any incomplete output only under its `.partial.mp4` name for clear recovery handling.

## Safety state

Full-file execution remains disabled. The chunk planner and silent joining boundary are now independently tested, but the app does not yet connect them to final audio, subtitle, chapter, metadata, and destination promotion.

## Next gate

The next milestone should add full-duration audio integration to the validated silent restored video while preserving the approved primary-audio choice, optional protected gain, AAC stereo fallback, exact duration, and cancellation behavior.
