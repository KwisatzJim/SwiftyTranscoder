# Milestone 57 — Bundled-First Runtime Selection

## Goal

Make inspection and conversion use the verified helpers inside SwiftyTranscoder first, while retaining the established Homebrew locations only as a development fallback.

## Shared tool locator

`MediaToolLocator` now owns executable selection for both services:

1. `Contents/Helpers/ffprobe` or `Contents/Helpers/ffmpeg` inside the running app.
2. The previous Apple Silicon Homebrew path.
3. The previous Intel Homebrew path.

Only executable files are accepted. If no candidate is available, the user-facing error now explains that the bundled helper is missing and recommends reinstalling SwiftyTranscoder. `MediaProbe` and `VideoConversionCommand` no longer maintain separate path lists.

Homebrew remains useful when running development code from a context without an application bundle, such as tests or previews. It is no longer a requirement for a properly built release app.

## Automated checks

Three focused locator tests prove that:

- A bundled helper is selected even when a fallback is also executable.
- The fallback is selected when the bundle does not contain the requested helper.
- No executable candidate returns `nil` rather than guessing a path.

The complete Foundation-only suite passed with 33 tests in 11 suites.

## Release-app runtime proof

A new Release application built successfully and passed strict signature verification. Using the helpers from that app's own `Contents/Helpers` directory:

- `ffprobe` produced the full JSON inspection for `Likely Forced Subtitle Test.mkv` and reported all four streams.
- `ffmpeg` burned the selected SubRip track through libass, FriBidi, HarfBuzz, and CoreText.
- VideoToolbox produced hardware-only HEVC Main with the `hvc1` tag.
- The audio path applied protected +6 dB gain and produced 48 kHz AC-3 stereo.
- Fast-start relocation completed.
- The embedded `ffprobe` verified a two-second HEVC Main `yuv420p` and AC-3 stereo output.

## Result

Inspection and conversion now select the self-contained helpers in a built SwiftyTranscoder app. The legacy Homebrew paths remain available solely as a development fallback.

The existing `0.8.0` DMG predates this work and is not reclassified. A later release milestone must build and validate a new DMG from the current self-contained source.
