# Milestone 105 — Initial local command-line interface

The updated app executable routes explicit command-line arguments to a small runner and preserves the SwiftUI entry point for normal launches. A `Scripts/swiftytranscoder` launcher provides the requested lowercase command name; a bundle-path override supports development testing without replacing the installed app. No system PATH edits or release packaging occurred.

The initial CLI accepts one MKV/MP4/M4V source, the Plex preset, an MP4 output path, help, dry-run inspection, explicit 0/+6 dB gain, optional AAC stereo, subtitle omission or source-index burn-in, and confirmed BT.709 labeling for untagged MKV SDR. Defaults are deterministic and independent of saved GUI preferences. Subtitle-bearing inputs require a choice. Unsupported or ambiguous sources fail with actionable errors. AI restoration is outside this CLI.

The runner reuses `MediaProbe`, `VideoConversionCommand`, and `VideoConversionController`: hardware HEVC for MKV, unchanged compatible MP4/M4V video, peak-protected gain with audio encoding, storage preflight, partial-file protection, shared output validation, and final promotion. SIGINT/SIGTERM request cancellation through the existing controller. A signal during inspection is honored after inspection returns; inspection itself is not actively terminated. Cancellation reports exit code 130 and any retained partial file.

## Verification

- Debug Xcode app build passed.
- Four parser tests passed, including 11 invalid-request cases, spaced paths, supported options, and input/output equality rejection.
- Read-only dry-run inspection succeeded without creating output.
- A short real-source MP4 clip completed gain processing and validation. Extracted H.264 elementary-stream SHA-256 matched before and after processing.
- A generated constant-frame-rate SDR MKV completed hardware HEVC encoding, AC-3/AAC audio processing, and independent inspection. The fixture required explicit BT.709 confirmation with the bundled probe.
- Existing destinations were refused and their checksums remained unchanged. Requests to reuse the input path were refused.
- Real SIGINT during an active conversion returned 130, retained the partial file, and did not promote a final file.
- `git diff --check` passed.

The first cut-and-remux MKV fixture failed the shared exact-frame-rate validation and retained a partial file correctly. It was replaced in the verification harness with a generated constant-frame-rate fixture; production validation was not relaxed. Development FFmpeg created fixtures and extracted elementary streams; actual CLI conversions used the app's bundled helper.

Evidence and the smoke harness are retained under `.build/milestone105-evidence/`. The preexisting memory-fix regression passed 117 tests; this CLI change adds four parser tests and focused executable checks rather than rerunning unrelated hardware suites. Installed 1.1.0 remains unchanged.

## User checkpoint

Run the updated CLI's help and a dry run against a familiar MP4, then confirm normal GUI launch still works. Actual user-media processing and packaged CLI acceptance follow this initial checkpoint.

The user confirmed the read-only dry run on `~/DVDtemp/WAR - s01e01 - It's Done.mp4`. It reported unchanged video copying, primary AC-3, protected +6 dB gain, AAC stereo enabled, subtitle omission, and no output written. Actual conversion and normal GUI-launch checkpoints remain pending. The next conversion test uses 0 dB gain on this already-converted MP4 to avoid unintentionally applying gain twice; testing +6 dB on original media follows separately.

The user subsequently confirmed successful conversion and playback of `/tmp/WAR-cli-test.mp4`, using the MP4 video-copy path with gain disabled. The user also tested `/Users/example/tempDir/Outlander Blood of My Blood - s02e03 - Rabbits Don't Swim.mkv` with gain enabled and subtitles omitted, and confirmed its output played well. These complete the hands-on MP4 and MKV CLI conversion checkpoints. Normal GUI launch with the new entry point and packaged CLI acceptance remain pending; no new release has been packaged.

The user subsequently confirmed normal GUI launch from Finder. The development CLI and GUI checkpoints are complete; packaged acceptance follows in milestone 106.
