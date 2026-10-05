# Milestone 110 — Visible progress and experimental faster AI

The user found the 720p Pilot batch too slow and requested faster AI, numeric percentages, and estimated time remaining. Read-only workspace checks confirmed that it was advancing, from 16 completed chunks to 98, despite an unchanged completed-file counter.

## Progress display

The batch interface now shows overall percentage and current-video percentage to one decimal place. The controller estimates remaining time for the current video after at least 20 seconds of measured processing progress. Preparation is excluded, and the estimator resets for each video. A batch-wide estimate would incorrectly assume that different dimensions and models process at the same speed. The estimate is approximate and depends on observed progress; stalled or invalid initial measurements display “Estimating time remaining…” instead of a fabricated time.

## Compact AI candidate

The candidate is the official `realesr-general-x4v3` compact general-purpose network, not the animation-specific model. Its native 4× output is average-pooled to 2× within Core ML, preserving the application's existing Float16 tensor and tiling contracts; the approved dimension cap remains enforced during encoding. The existing detailed AI remains available. The compact option appears only in a bundle containing its verified resource and is labeled experimental. Reviewed plans preserve the selected method; missing compact resources fail rather than silently changing models.

Sources:
- https://github.com/xinntao/Real-ESRGAN/blob/master/docs/model_zoo.md
- https://github.com/xinntao/Real-ESRGAN/blob/master/realesrgan/archs/srvgg_arch.py
- Official weights: https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth

`Scripts/prepare-fast-restoration-candidate.py` verifies the official weights and the existing pinned converter before strict loading and conversion. The official weights SHA256 is `8dc7edb9ac80ccdc30c3a5dca6616509367f05fbc184ad95b731f05bece96292`. The model's three bundled files are checksum-enforced by the embedding script. Existing Real-ESRGAN license notices are included. Ordinary release builds exclude this experimental asset; Debug builds include it when prepared, and the optimized test build explicitly enables `SWIFTY_INCLUDE_FAST_CANDIDATE=1`.

## Measured results and limits

Release Swift frame processing on the same four 1280×720 Pilot frames:

| Configuration | Model setup | Four frames |
| --- | ---: | ---: |
| Existing x2plus, all Core ML units | 15.17 s | 2.301 s |
| Compact, all Core ML units | 79.21 s | 1.111 s |
| Compact, CPU/GPU only (separate run) | 0.103 s | 2.057 s |

The compact all-units path was about 2.07× faster in frame processing, but substantially slower to prepare. CPU/GPU-only execution avoided the lengthy preparation but reduced the throughput benefit to about 1.12×. These are short measurements, not an episode runtime guarantee; even a twofold improvement would leave an hour-long HD episode taking several hours. No claim is made about which individual device Core ML used. Further throughput work remains necessary for a much shorter target.

The full compact-model production run restored the 48-frame Pilot fixture to 1920×1080, preserved all frames, produced AC-3 plus AAC audio, and cleaned its workspace. The validated clip is `.build/milestone110-review/Faster-Pilot-Validated.mp4`.

An initial 48-frame test exposed existing full-restoration mux behavior: `-shortest` dropped the final frame when the source audio ended at 2.000 seconds and video at 2.002 seconds. The previously accepted detailed-model fixture also contained 47 frames. Full restoration now retains all restored video frames; source audio remains bounded to the planned duration. Preview's shorter-stream policy is unchanged. The corrected real compact output retained all 48 frames. This resolves the separate full-restoration boundary issue recorded in milestone 109.

Seventeen focused tests passed for progress estimates, audio integration, reviewed compact plans, missing-model refusal, and controller cancellation/results. Both compact real-resource runs passed after the audio correction. Debug and optimized test app builds passed, as did strict deep code-signature verification, shell syntax validation, and `git diff --check`. Evidence is retained in `.build/milestone110-evidence/`.

## User checkpoint

The optimized test app is `.build/Milestone110DerivedData/Build/Products/Release/SwiftyTranscoder.app`. It is not a newly packaged release and does not replace installed 1.2.0. Quit the older test app before opening it.

Choose the two ten-second clips in `.build/milestone110-review/inputs/`, enable AI restoration, select “Faster AI · Compact model (experimental)” for each, and approve the plans with `.build/milestone110-review/outputs/` as the destination. Verify that percentages advance and the current-video time estimate appears after processing has had time to be measured. Review both outputs for picture and sound before another episode-length attempt. First preparation may take around 80 seconds in this configuration.

The user confirmed the short faster-AI checkpoint looks and sounds good, then began a single full Pilot restoration at approximately 4:35 PM. At 5:47 PM it displayed 13% progress. This is approximately 72 minutes elapsed, projecting about 554 minutes (9.2 hours) total and 482 minutes (8 hours) remaining if the same overall-progress rate continues. This projection is approximate, includes preparation and stage weighting, and does not establish final runtime. Full-episode completion and playback remain pending. The result confirms that the compact model alone does not make HD episode restoration quick enough to assume a practical one-hour turnaround.
