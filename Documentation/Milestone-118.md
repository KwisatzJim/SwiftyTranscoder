# Milestone 118 — Local 1.4.0 release

The user accepted milestone 115 completion summaries, milestone 116 saved model choice after relaunch, and milestone 117 CLI dry-run and restored-clip playback, then explicitly authorized release packaging. The complete Original Sin dry run confirmed the intended lightweight method, SD 2× dimensions, hardware HEVC, protected +6 dB gain, AC-3/AAC, and omitted subtitles.

Version metadata is 1.4.0, build 14. This release includes the three accepted improvements, retains the four pinned bundled models, and packages the existing CLI launcher with updated usage instructions. The CLI requires an explicit `--restore lightweight` flag; ordinary conversion and saved GUI preferences remain separate.

Packaging retains local ad-hoc signing and earlier installers. No automatic app installation, CLI replacement in `/usr/local/bin`, public upload, or Git commit is performed. Completed artifact: `dist/SwiftyTranscoder_1.4.0_arm64.dmg` (approximately 73 MB).

SHA-256: `6c12ccb6f35ada071dc6651c0fd0eeadf6c3c83bbcffb526df4dbbdac6b95a94`.

All 154 regression tests in 38 suites passed. The self-contained toolchain was rebuilt and checked, pinned models validated, and the optimized app verified as 1.4.0 (14). All four model packages, nine notices, architecture, strict signing, helper linkage, media capabilities, and DMG integrity checks passed. App and launcher CLI help checks passed from the read-only mounted installer.

A second read-only mount passed real ordinary MP4 gain and MKV hardware-HEVC conversion, video-copy stream hash preservation, collision/overwrite refusal, and ordinary cancellation. The packaged executable's `--restore lightweight` path passed dry-run with no output creation, real 240-frame Pilot restoration (1920×1080 HEVC with AC-3/AAC), elapsed/speed/model reporting, source hash preservation, existing-output refusal, invalid-option exit 2, and active Ctrl-C exit 130 without final output promotion. The completed run reported 27 seconds elapsed and 8.9 frames/s including preparation, audio, and saving. The mount was ejected after checks.

Independent installer SHA-256 verification passed for retained 1.0–1.3 and new 1.4 artifacts. Shell syntax and whitespace checks passed. Evidence is retained under `.build/milestone118-evidence/`, including the validated CLI output. The user confirmed installed-release acceptance.

The user confirmed About shows 1.4.0 and the installed CLI help includes `--restore lightweight`, then authorized resumable-restoration work. The local 1.4.0 release milestone is complete.
