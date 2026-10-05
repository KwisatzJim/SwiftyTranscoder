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

## Packaged-app acceptance

On October 3, 2026, the user confirmed that the installed 1.1.0 release converted three MKV sources successfully: Dark Matter, Outlander Blood of My Blood, and WAR. The resulting MP4 files in `~/DVDtemp` looked and sounded good and played well on Plex. This completes the hands-on packaged-app checkpoint for ordinary conversion.

Read-only FFprobe inspection confirmed HEVC video with the `hvc1` tag, BT.709 SDR color metadata, primary AC-3 5.1 audio, and secondary AAC stereo in all three outputs. Dark Matter used Main 10 video; the other two used Main. Reported audio and video durations differed by less than 40 milliseconds. These checks and the user's playback confirmation do not constitute a new packaged-app AI restoration test.

The user subsequently confirmed a successful AI restoration preview from the installed release on a new Mac mini, reported as M6 with 24 GB RAM. The app became unresponsive for several seconds before completing the preview successfully. This startup responsiveness issue remains open for diagnosis; successful output does not establish responsive execution.

Read-only FFprobe inspection of `SwiftyTranscoder-Restoration-Preview-337EC4C6-F0EA-460E-9285-09B30B5EC337/restored-preview.partial.mp4` in the system temporary directory confirmed approximately 10 seconds of 1248×704 HEVC Main video with the `hvc1` tag, AC-3 stereo, and AAC stereo, both at 48 kHz. This completes the short packaged-app restoration-preview checkpoint, with the reported temporary UI freeze retained as a follow-up issue.
