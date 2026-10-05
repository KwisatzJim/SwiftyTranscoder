# Milestone 109 — Restore to the approved dimension cap

During full-episode mixed-dimension batch acceptance, the user reported that the first file failed with “The restored video dimensions do not match the approved plan.” Memory exceeded 800 MB at the start of restoration.

Read-only FFprobe inspection identified Pilot as 1280×720 and Cause & Effect as 624×352. The planner correctly caps Pilot at 1920×1080, but the AI frame processor always produces 2× output (2560×1440 for Pilot). The assembly command omitted the final resize required by capped plans. This is a missing assembly step, not a shared batch dimension plan.

The assembly filter now applies Lanczos resizing to the approved dimensions when those dimensions differ from the model's 2× result, before subtitle burning and the existing color-tag filter. Resizing occurs during the existing hardware HEVC encode; the completed-output dimension check remains enforced. Uncapped 2× SD plans retain their previous filter sequence. This shared assembly correction applies to single-video, preview, and batch restoration.

Nine assembly tests passed, including a regression verifying 720p-to-1080p resize before subtitle burning. The development app rebuilt successfully. An opt-in HD integration test exercises real tiled inference and hardware encoding, with independent dimension/frame inspection and workspace cleanup.

The four-frame HD integration test passed in 21.182 seconds: the complete production pipeline promoted a 1920×1080 HEVC output with all four frames and removed its workspace. Evidence is retained in `.build/milestone109-evidence/`. An exploratory two-frame AC-3-only run produced one final frame despite correct dimensions; that ultra-short audio/video boundary requires separate investigation and is not addressed by this dimension-only correction. The four-frame check retains an exact frame-count assertion.

Two short review inputs are prepared in `.build/milestone108-dimensions/inputs/` (Pilot HD and Alphas SD), with a separate output folder at `.build/milestone108-dimensions/outputs/`. The HD excerpt is re-encoded at exact 24000/1001 cadence to avoid stream-copy seek preroll in this bounded fixture. Original episodes are unchanged.

The larger Pilot frames use the tiled model rather than the optimized fixed-size SD model. The user's SD memory readings do not establish expected HD memory. Sustained HD memory and full-episode acceptance remain pending after the dimension fix.

The user confirmed both short mixed-dimension test files completed with expected memory usage and played well. This accepts the focused dimension-fix checkpoint. Retrying the two original full episodes remains the next checkpoint before release packaging.

The user subsequently found full HD restoration too slow. Milestone 110 records visible progress, a compact AI candidate, and correction of the separate full-restoration audio-end frame loss.
