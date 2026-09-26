# Milestone 53 — Isolated Minimal FFmpeg Proof Build

## Goal

Build and exercise a narrowly configured FFmpeg toolchain without changing the application or its working Homebrew executable lookup.

## Reproducible build

`Scripts/build-toolchain.sh` now:

- Downloads the official FFmpeg 9.0.2 source archive.
- Verifies its pinned SHA-256 checksum before extracting it.
- Builds native arm64 `ffmpeg` and `ffprobe` executables under the ignored `.build/toolchain/stage` directory.
- Disables networking, automatic feature discovery, documentation, shared FFmpeg libraries, and all features not explicitly enabled.
- Enables only the current MKV/MP4 inspection and conversion surface, including VideoToolbox HEVC, AC-3, AAC, SubRip/libass rendering, PGS and cover-art inspection, the audio and color filters, and local file/pipe protocols.
- Verifies the essential encoders, decoders, filters, version, configure boundary, and LGPL license text after installation.

The resulting configure report identifies the build as **LGPL version 2.1 or later**. No GPL option or GPL codec library is enabled.

## Inspection correction

The first build successfully inspected and converted the selected streams, but a complex Matroska source produced an `Unsupported encoding type` warning for a compressed attachment. Enabling system zlib removed the warning. MJPEG and PGS decoders were also enabled so cover art and image-subtitle streams can be inspected even though SwiftyTranscoder does not convert or burn them.

The final staged `ffprobe` inspected `Come and See (1985).mkv`, including streams, chapters, format metadata, its compressed attachment, PGS subtitle, and cover image, with an empty error stream.

## Media smoke tests

Three ignored two-second outputs exercised the actual application paths:

1. `Likely Forced Subtitle Test.mkv` decoded H.264 and AAC, rendered a selected SubRip stream through libass/CoreText, encoded hardware-only HEVC Main with an `hvc1` tag, applied protected +6 dB gain, encoded AC-3 stereo, and wrote fast-start MP4.
2. `Spa Weekend (2026).mp4` copied H.264 video unchanged while downmixing, applying protected +6 dB gain, and encoding AAC stereo into fast-start MP4.
3. `Come and See (1985).mkv` decoded ten-bit HEVC, applied the BT.709 `setparams` labeling filter, encoded hardware-only HEVC Main 10 with an `hvc1` tag, and encoded AC-3 mono.

Staged `ffprobe` validation confirmed the expected codecs, profiles, pixel formats, dimensions, audio layouts, sample rates, codec tags, and durations. The Main 10 result retained `yuv420p10le` and reported BT.709 color space, transfer, and primaries.

The restricted command environment initially denied access to the VideoToolbox compression service with error `-12908`. The unchanged tests succeeded with normal access to the Mac's hardware service and software fallback remained disabled.

## Size and remaining dependency boundary

The staged executables are approximately 6.5 MB for `ffmpeg` and 6.3 MB for `ffprobe`. FFmpeg's own libraries are statically included, so each executable directly references only macOS system frameworks and Homebrew `libass`.

`libass` still leads to four Homebrew libraries: FreeType, FriBidi, HarfBuzz, and libunibreak. Their complete transitive closure has not yet been copied or rewritten. Therefore the staged proof is not yet distributable and the application correctly continues using its existing Homebrew paths.

## Result

The minimal configuration is reproducible and has passed capability, representative inspection, subtitle, audio, MP4-copy, eight-bit VideoToolbox, and ten-bit VideoToolbox tests. The next focused milestone is to stage the libass dependency closure, rewrite every non-system install name to bundle-relative paths, and prove that the tools run with Homebrew paths unavailable.
