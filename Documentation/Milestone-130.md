# Milestone 130 — Local 1.7.0 release

The user accepted the smaller-output controls and playback, then authorized release packaging. Version 1.7.0 (17) includes per-file Original/720p/480p ordinary conversion choices and CLI `--resolution`, as described in Milestone 129.

Reduced output uses Apple hardware HEVC, preserves display proportions, and never enlarges smaller sources. Original-size compatible MP4/M4V video keeps the existing stream-copy path. Audio removal can be combined with reduced output; AI restoration remains a separate workflow.

Artifact: `dist/SwiftyTranscoder_1.7.0_arm64.dmg`.

All 175 tests in 43 suites passed. The release process rebuilt the media tools, validated pinned models, checked app/helper signatures and resources, and verified disk-image integrity and mounted-app/launcher contents. Packaged checks passed for 1080p→720p/480p, 720p→480p MKV, audio conversion/removal, full frame counts/duration, decodable output, reduced size, unchanged smaller MP4 video, no upscaling, portrait 720×1280 at 9:16, ordinary conversion, and cancellation. All earlier installer checksums remain valid. Evidence: `.build/milestone130-evidence/`.

SHA-256: `7c45cdb426e380fd5157374e94304671b013e9945fff9221448bad101cb87230`.

Local packaging is complete. The user confirmed installed version 1.7.0. GitHub publication is complete: the public v1.7.0 release contains the installer, third-party source bundle, and checksums. All remote asset sizes and SHA-256 digests match local files. A fresh source build and release-app verification passed.
