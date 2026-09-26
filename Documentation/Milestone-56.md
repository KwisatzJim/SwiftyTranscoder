# Milestone 56 — Embedded Toolchain Packaging

## Goal

Place the verified self-contained media helpers and their license notices inside every application build without changing which executables the running app selects.

## Build integration

The Xcode target now runs `Scripts/embed-toolchain.sh` after its normal resource phase. The script:

- Requires the previously built and staged `ffmpeg` and `ffprobe` helpers.
- Copies them to `SwiftyTranscoder.app/Contents/Helpers` with executable permissions.
- Signs each nested helper with the current build identity and hardened-runtime option before Xcode signs the outer application.
- Copies the FFmpeg, FreeType, FriBidi, HarfBuzz, and libass notices to `Contents/Resources/ThirdPartyNotices`.
- Stops with a direct preparation instruction if any required helper or notice is missing.

`Scripts/build-release.sh` now runs the pinned toolchain build and bundle staging steps before invoking Xcode, so a release cannot silently package absent or stale helpers.

## Verification

An ad-hoc-signed Release build completed successfully. Inspection of the resulting application confirmed:

- `ffmpeg` and `ffprobe` are executable in `Contents/Helpers`.
- Both helpers and the outer application pass strict code-signature verification.
- Both helpers report a macOS 14 minimum.
- Neither helper links to `/opt/homebrew` or `/usr/local`.
- The embedded FFmpeg reports version 9.0.2 and includes the libass subtitle filter.
- Six notice files are present: two for FFmpeg and one for each static subtitle dependency.
- The complete built application is approximately 21 MB.

The Xcode phase declares all eight generated files as outputs and their corresponding staged files as inputs. A second build after changing an input notice re-ran embedding and produced another application that passed strict signature verification. This prevents incremental builds from leaving newly copied resources outside the app's signature seal.

## Result

SwiftyTranscoder's app bundle now contains the verified self-contained toolchain and its notices. Runtime behavior intentionally remains unchanged: inspection and conversion still select the established Homebrew paths.

The next focused milestone is to make the app prefer its embedded helpers, retain Homebrew as a development fallback, and verify real inspection and conversion through the bundled paths.
