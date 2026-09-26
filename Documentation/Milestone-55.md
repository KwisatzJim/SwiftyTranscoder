# Milestone 55 — Static Subtitle Dependency Build

## Goal

Replace the incompatible Homebrew runtime-library closure with checksum-pinned source builds that support SwiftyTranscoder's macOS 14 deployment target.

## Pinned dependency build

`Scripts/build-subtitle-dependencies.sh` downloads and verifies these source releases:

- FreeType 2.14.3
- FriBidi 1.0.17
- HarfBuzz 14.5.0
- libass 0.17.5

All four are built for arm64 with a macOS 14 minimum and installed as static libraries under the ignored `.build/toolchain/dependencies` directory. Optional dependency branches that SwiftyTranscoder does not need are disabled. libass uses the native CoreText font provider, and the four upstream license files are collected beside the build output.

`Scripts/build-toolchain.sh` now invokes that dependency build, restricts `pkg-config` to the private prefix, and statically includes the libraries in `ffmpeg` and `ffprobe`. The build rejects either helper if it still references `/opt/homebrew` or `/usr/local`.

## Bundle verification

`Scripts/stage-toolchain-bundle.sh` staged and signed the resulting helpers. Static linkage inspection and runtime loader tracing found no Homebrew or `/usr/local` dependency. The proof bundle contains zero non-system dynamic libraries, is approximately 17 MB, and every staged executable reports a macOS 14 minimum.

The helpers still use normal macOS system libraries and frameworks, including CoreText, VideoToolbox, zlib, and iconv. Those are supplied by macOS and do not need to be copied into the application.

## Media smoke test

The bundled helpers completed a two-second conversion of `Likely Forced Subtitle Test.mkv`:

- libass 0.17.5 rendered the selected SubRip track.
- FriBidi 1.0.17 and HarfBuzz 14.5.0 performed subtitle shaping.
- CoreText selected the system Arial font.
- VideoToolbox produced hardware-only HEVC Main with the `hvc1` tag.
- The audio path applied protected +6 dB gain and encoded AC-3 stereo.
- Fast-start MP4 relocation completed.

The bundled `ffprobe` verified HEVC Main `yuv420p`, AC-3 stereo, and a two-second duration.

## Result

The minimal FFmpeg toolchain is now reproducible without Homebrew runtime libraries and compatible with the application's macOS 14 target. The running application has not changed yet and continues using its established external-tool lookup.

The next focused milestone is to embed the verified helpers and third-party notices in the application build, then add a bundled-first lookup with the current Homebrew paths retained as a development fallback.
