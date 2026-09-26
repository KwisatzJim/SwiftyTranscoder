# Milestone 52 — Self-Contained Toolchain Design

## Goal

Define a safe, maintainable path to ship `ffprobe` and FFmpeg inside SwiftyTranscoder so a future release does not require a separate Homebrew installation.

This milestone is a design and dependency audit. It deliberately does not change which executables the working application uses.

## Why the Homebrew executables will not be copied

The installed FFmpeg 9.0.2 executables are dynamically linked to Homebrew libraries using paths under `/opt/homebrew`. Copying only the executables would therefore fail on a Mac without the same Homebrew installation.

Copying the entire dependency closure is also unsuitable. The regular `ffmpeg` formula reports 14 installed runtime dependencies, while `ffmpeg-full` reports 102. The full build includes many features SwiftyTranscoder does not use, such as OCR, speech recognition, network transports, and numerous unrelated codecs. That would create a large, fragile bundle and a much broader license-compliance obligation.

Both installed formulae report a GPL license. SwiftyTranscoder does not need the GPL encoders commonly used for software H.264 or HEVC output because it already requires Apple's `hevc_videotoolbox` hardware encoder.

## Required FFmpeg surface

The purpose-built arm64 toolchain needs only the capabilities exercised by the current application:

- Inspect streams, chapters, formats, dispositions, tags, and Matroska subtitle statistics as JSON with `ffprobe`.
- Demux Matroska, MP4, and M4V input and mux MP4 output.
- Decode supported H.264 and HEVC video input.
- Encode HEVC with `hevc_videotoolbox`, with software fallback disabled by the app.
- Copy compatible MP4 video without re-encoding.
- Decode the audio formats accepted by the current inspection and conversion path.
- Encode AC-3 and native AAC output.
- Decode SubRip subtitles and render them through the `subtitles` filter with libass.
- Provide the `volume`, `alimiter`, `aformat`, and `setparams` filters.
- Preserve metadata and chapters, write `hvc1`, perform fast-start relocation, and report machine-readable progress through a pipe.
- Support the pixel formats used by the current SDR path: `yuv420p`, `yuv420p10le`, and VideoToolbox `p010le` output.

The exact configure flags will be recorded from a successful reproducible build rather than guessed in advance. Each required capability must be tested directly before the application is allowed to select the bundled tools.

## Bundle layout

Apple's standard macOS bundle locations will be used:

- Command-line helper executables in `SwiftyTranscoder.app/Contents/Helpers`.
- Their non-system dynamic libraries in `SwiftyTranscoder.app/Contents/Frameworks`.
- License notices and the exact FFmpeg build configuration in the application's resources.

All bundled library references must use loader-relative or run-path-relative install names. No `/opt/homebrew`, `/usr/local`, or build-machine path may remain in the packaged executables or libraries.

Nested executable code and libraries will be signed before the main application. The release script will verify the completed bundle rather than relying on recursive signing to conceal an invalid internal layout.

## License boundary

The target is an LGPL-compatible FFmpeg configuration with GPL components disabled. Dynamic linking, attribution, license text, configuration disclosure, and a way to obtain the corresponding source will be included in the release process. Third-party dependencies such as libass and its font-rendering libraries will receive their own required notices.

This is an engineering target, not a claim that the eventual binary is compliant before its final dependency list and build configuration have been reviewed.

## Incremental implementation plan

1. Build the smallest candidate toolchain in a temporary staging directory, without changing the application.
2. Verify every capability above and inspect every dynamic-library path.
3. Run representative probe, video, audio, subtitle, and MP4-copy smoke tests against the staged tools.
4. Add bundle lookup with a temporary Homebrew fallback during development.
5. Package, sign, mount, and test the DMG on a machine where Homebrew FFmpeg is unavailable.
6. Remove the fallback and the Homebrew requirement only after that clean-machine test passes.

## Result

The self-contained distribution approach is defined without disturbing the verified conversion paths. The next focused milestone is the isolated minimal-toolchain build and capability test.
