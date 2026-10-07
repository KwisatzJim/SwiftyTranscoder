# Milestone 129 — Smaller ordinary video output

The user requested lower resolutions for support videos that exceed email attachment limits. Ordinary conversion now offers an explicit per-file Output size picker: Original size, 720p, or 480p. Original size is the default and resets for each new source; reviewed ordinary batch plans retain their own selected size. Resolution changes are separate from AI restoration and can be combined with Remove all audio.

Landscape output fits within 1280×720 or 854×480. Portrait bounds are rotated. Pixel dimensions are rounded down to even values for chroma-subsampled encoding; sources smaller than the bounds are not enlarged. The scale filter preserves display proportions. The plan shows the exact source and output dimensions.

Compatible MP4/M4V video remains a stream copy when no reduction is needed. Actual reduction uses Lanczos scaling and Apple hardware HEVC encoding, retaining existing SDR/color, frame-rate, audio, subtitle, source protection, collision, and partial-output rules. Output validation checks the selected dimensions rather than requiring source dimensions.

CLI: `--resolution original|720p|480p`, with Original as the default. Dry runs report exact dimensions. Combining a smaller resolution with AI restoration is refused.

Focused dimension/parser tests and the optimized app build passed. Real short conversions verified 1080p→720p, 1080p→480p, 720p→480p MKV, silent output, full frame count/duration, decodable outputs, unchanged smaller MP4 compressed video, source protection, and portrait 720×1280 with 9:16 display proportions. A 10-second fixture reduced from 7,812,503 bytes to 1,448,239 bytes at 720p, 1,089,948 bytes at 480p, and 607,151 bytes at silent 480p. Results depend on content and duration; no fixed email-size guarantee is provided.

Ordinary conversion/gain/audio/cancellation regression checks and strict development-app resource/signature checks passed. All 175 regression tests in 43 suites passed. The user confirmed the controls and playback; this feature is accepted. This accepted feature is packaged in local version 1.7.0; installed-version acceptance is confirmed and publication is authorized.
