# Milestone 100 — Local version 1.1.0 release

The user confirmed playback of the faster-model full episode on the requested Plex clients before release packaging. This follows confirmed native previews, full restoration, saved AAC defaults, folder selection, and Finder drag and drop.

Version metadata is 1.1.0, build 11. This personal Apple Silicon release includes optional local Real-ESRGAN restoration for one eligible 8-bit limited-range SDR source, short previews, bounded chunks and storage checks, cancellation, preserved compatibility audio and subtitles, and independently validated final output. The reviewed 624×352 model roughly halves Alphas restoration time; other eligible dimensions retain the existing tiled model. AI restoration is off by default and batch restoration is not supported.

Folder selection and Finder drops import supported MKV/MP4/M4V files with immediate-folder filtering, natural sorting, and duplicate exclusion. New selections replace the queue without starting conversion. Gain, AAC stereo, and safe subtitle-policy defaults can be explicitly saved.

Packaging retains older DMGs and now retains checksum entries for other versions rather than replacing the entire checksum list. The release remains ad-hoc signed for personal local use, not notarized or Developer ID signed. Public distribution, HDR restoration, 4K output, OCR, and batch restoration remain outside this release.

## Packaging evidence

The release script completed successfully. All 116 tests in 30 suites passed again in Debug, supplementing the preceding Release regression pass. The pinned media helpers and model preparation passed, the Release app built as 1.1.0 (11), and both the build output and mounted-DMG copy passed signature, model checksum, notices, architecture, and media-capability checks. The DMG's internal checksum passed independent verification.

Artifact: `dist/SwiftyTranscoder_1.1.0_arm64.dmg`.

SHA-256: `fc2b8a61b7192c81155591a22dff35ad96eef97f6308529a7e08d671202dac14`.

Both entries in `dist/SHA256SUMS.txt` verified successfully, including the unchanged 1.0 artifact. The temporary packaging workspace was cleaned up by the release script; the final artifacts remain in `dist`. A hands-on launch of the installed packaged application is the final user checkpoint. No public release or upload was performed.
