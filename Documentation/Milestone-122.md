# Milestone 122 — Local 1.5.0 release

The user confirmed both the resumed test clip and the saved-progress interface, then authorized proceeding. Version 1.5.0 (15) packages the accepted single-video resume workflow and CLI `--checkpoint-dir` / `--resume` options. Saved job identity, completed-block reuse, exclusive ownership, refusal of changed work/settings, interruption retention, and resumed timing are described in Milestones 120–121. Batch resume remains a later enhancement.

Artifact: `dist/SwiftyTranscoder_1.5.0_arm64.dmg` (approximately 73 MB).
SHA-256: `86c086d1f605b76969da2a6d75f9225ced40055440c12898c85a9e0ab0968cdc`.

All 165 regression tests in 40 suites passed. The self-contained media toolchain was rebuilt, pinned models validated, and the optimized app verified as 1.5.0 (15). Architecture, strict app/helper signatures, all four models and nine notices, helper linkage, media capabilities, and DMG integrity passed. The read-only mounted app and packaged launcher expose the new CLI options. Independent checksum verification passed for retained installers from 1.0.0 through 1.5.0.

A second read-only installer mount passed real ordinary MKV hardware-HEVC and MP4 copy-mode gain conversions, elementary-video-stream hash preservation for MP4, source/overwrite conflict refusal, and Ctrl-C cancellation. Packaged restoration checks validate matching source/model/settings and completed-block reuse after Ctrl-C and process force quit, with unchanged saved first-block hash and modification time. Each completed output independently inspects as all 240 HEVC frames at 1920×1080 and 24000/1001 with AC-3/AAC audio. Saved workspaces are removed after success and source content remains unchanged. Dry-run verification and changed-settings/folder-reuse/concurrent-run refusal are checked explicitly.

Evidence is retained in `.build/milestone122-evidence/`. App installation, public upload, Git commit, and replacement of the user's CLI launcher are not performed. The existing `/usr/local/bin/swiftytranscoder` launcher delegates to `/Applications/SwiftyTranscoder.app`, so updating that app also updates the CLI implementation. Installed-release acceptance remains the next user checkpoint.

The final assembly-only interruption case also passed: after a force quit with both blocks recorded, the packaged app reused all 240 restored frames, completed audio/promotion, and reported elapsed time without inventing an inference speed. The second installer mount was ejected after verification. Release packaging and all automated release checks are complete.

The user confirmed installed 1.5.0 acceptance. The scoped local release milestone is complete.
