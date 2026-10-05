# Milestone 117 — Explicit Lightweight AI CLI restoration

After saved-model-choice acceptance, the user authorized the next focused improvement. The CLI accepts `--restore lightweight`. Without this flag, ordinary MP4/M4V video copy and MKV hardware conversion behavior is unchanged. Only the tested lightweight method is exposed in this first CLI restoration step; the CLI never takes its model selection from the saved GUI preference.

Inspection, audio gain/AAC choices, explicit subtitle choices, path checks, and ordinary compatibility checks remain shared. Restoration additionally checks the same planner eligibility as the GUI, constructs the full restoration request, and performs source/destination/temporary-storage preflight before dry-run completion or actual processing. Dry run prints the AI method and approved dimensions without loading the model or creating outputs/workspaces. Untagged assumptions do not override the AI planner's stricter tagged-SDR requirements.

Actual processing uses FullVideoRestorationController and the existing bundled pipeline. It prints model preparation/stages, numeric progress, a measured remaining-time estimate when available, and the milestone 115 completion summary. SIGINT and SIGTERM cancel the active controller; existing exit codes and labeled-partial handling apply. The full-restoration path retains frame counting, 1080p cap, protected gain, audio/subtitle/metadata validation, final promotion, and bounded cleanup.

Validation: all five CLI parser tests passed, including 14 invalid/ambiguous cases, explicit lightweight parsing, and unchanged ordinary defaults. The optimized app build and strict deep signature check passed. A real ten-second Pilot CLI restoration validated 1920×1080 HEVC, all 240 frames, AC-3 plus AAC, and printed elapsed/speed/model statistics. Dry-run output creation refusal, unchanged source hash, existing-output refusal, invalid model selection, and active Ctrl-C exit 130 passed. Ordinary MP4 gain and MKV conversion regression checks, video-copy stream hash, collision/refusal checks, and ordinary cancellation passed.

Evidence: `.build/milestone117-evidence/`; review video: `Pilot-CLI-Lightweight.mp4`. The installed 1.3.0 app and installer have not been replaced. Test app: `.build/Milestone117DerivedData/Build/Products/Release/SwiftyTranscoder.app`.

Use the existing launcher with `SWIFTYTRANSCODER_APP` pointing at this test app, or run its `Contents/MacOS/SwiftyTranscoder` executable directly. Start with `--restore lightweight --dry-run`; then remove `--dry-run` for an eligible short source and a fresh output path. The user confirmed the dry run completed without writing output and the CLI-restored test clip looks good. The scoped Lightweight AI CLI checkpoint is accepted.


The user supplied the complete Original Sin dry run: Lightweight FSRCNN with Apple hardware HEVC, 624×352 → 1248×704, protected +6 dB gain, primary AC-3 plus AAC stereo, omitted subtitles, and no output written. This matches the intended CLI plan. The user then authorized the next release package.
