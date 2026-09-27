# Milestone 58 — Self-Contained 0.9.0 Release Candidate

## Goal

Package the confirmed self-contained media toolchain as a locally installable release candidate that does not require Homebrew FFmpeg for normal use.

## Included changes

- Include checksum-pinned FFmpeg 9.0.2 and FFprobe helpers inside the application bundle.
- Statically include the pinned libass, FreeType, FriBidi, and HarfBuzz subtitle dependencies while preserving the macOS 14 deployment target.
- Include six third-party license-notice files in the application resources.
- Prefer the bundled helpers for inspection and conversion, while retaining Homebrew paths only as development fallbacks outside a prepared bundle.
- Retain the likely-forced subtitle evidence and confirmation workflow added after the previous release candidate.

## Release identity

The marketing version is `0.9.0` and the build number is `9`. The candidate is an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

All 33 automated tests across 11 suites pass. `Scripts/build-release.sh` rebuilt the pinned static subtitle dependencies and narrow FFmpeg toolchain, completed the optimized Release build, verified the strict app signature, created and verified the DMG, and generated its SHA-256 checksum.

Independent read-only mounting confirmed that the packaged app:

- reports version `0.9.0 (9)` and contains an arm64 executable;
- passes strict signature verification for the app, FFmpeg, and FFprobe;
- contains both executable helpers and all six third-party notices;
- has no Homebrew or `/usr/local` runtime linkage in either helper;
- exposes the required subtitle filter and includes the Applications shortcut; and
- can inspect a real MKV and produce a two-second HEVC/AC-3 MP4 using subtitle burn-in, VideoToolbox encoding, and peak-protected +6 dB gain entirely with the helpers mounted from the DMG.

The generated output was independently inspected as HEVC video with AC-3 audio. The independently calculated SHA-256 matched `dist/SHA256SUMS.txt`:

```text
11e12fc4aa5be123e6c4bf192a6e9078596ac6238f27909672309d12b728a10a  SwiftyTranscoder_0.9.0_arm64.dmg
```

Milestone 58 is complete; installing the DMG over the current application and running a normal conversion remains the final optional hands-on validation.
