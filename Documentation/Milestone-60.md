# Milestone 60 — SwiftyTranscoder 1.0 Release

## Goal

Complete the first stable local release from the feature-complete, runtime-confirmed, self-contained application.

## Release identity

The marketing version is `1.0.0` and the build number is `10`. This is an arm64 personal release for macOS 14 or later. It is locally ad-hoc signed, not Developer ID signed or Apple-notarized.

## Release contents

Version 1.0 includes the confirmed four-step wizard, full-batch review and unattended sequential conversion, protected optional +6 dB gain, deterministic subtitle decisions, destination and overwrite safeguards, cancellation and incomplete-file handling, progress and ETA reporting, notifications, remembered safe defaults, and the self-contained checksum-pinned media toolchain.

Post-1.0 work remains intentionally outside this release: AI upscaling/restoration, automatic crop and restoration filters, PGS/VobSub OCR, selectable MP4 subtitles, HDR-to-SDR conversion, broader encoder controls, and public Developer ID/notarized distribution.

## Automated release gate

The strengthened `Scripts/build-release.sh` gate completed successfully:

- 33 tests passed across 11 suites;
- pinned FreeType 2.14.3, FriBidi 1.0.17, HarfBuzz 14.5.0, libass 0.17.5, and FFmpeg 9.0.2 were rebuilt;
- the Release app, FFmpeg, and FFprobe passed strict signature checks;
- arm64 architecture, six third-party notices, required media capabilities, and absence of Homebrew or `/usr/local` runtime linkage were confirmed;
- the DMG passed image verification; and
- its read-only mounted copy repeated all packaged-app checks and included the Applications shortcut.

## Real-media verification

The bundled helpers from a separately mounted `1.0.0` DMG inspected `Likely Forced Subtitle Test.mkv` and completed a two-second conversion with SubRip burn-in, VideoToolbox HEVC, protected +6 dB gain, and AC-3 audio. The mounted FFprobe identified the result as HEVC Main `yuv420p` video with AC-3 stereo audio.

The independently calculated SHA-256 matched `dist/SHA256SUMS.txt`:

```text
ad891509a1e04ef1d53bdd6f2533fa157b07f8693e0552ccf62b634d72146e16  SwiftyTranscoder_1.0.0_arm64.dmg
```

The immediately preceding self-contained `0.9.0` candidate was also installed and confirmed by the user with a normal conversion. Version 1.0 changes only the release identity, About-panel fallback values, documentation, and release verification gate; the confirmed conversion behavior is unchanged.

Milestone 60 and the SwiftyTranscoder 1.0 local release are complete.
