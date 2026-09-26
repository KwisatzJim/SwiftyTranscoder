# Milestone 54 — Bundle-Relative Linkage Proof

## Goal

Prove that the minimal tools and the complete libass runtime closure can be arranged like macOS application contents, loaded without Homebrew paths, and signed in the correct inner-to-outer order. Also verify that every binary is compatible with SwiftyTranscoder's macOS 14 deployment target before permitting release use.

## Staging process

`Scripts/stage-toolchain-bundle.sh` creates an ignored proof bundle under `.build/toolchain/bundle`:

- `Contents/Helpers` contains the minimal `ffmpeg` and `ffprobe` executables.
- `Contents/Frameworks` receives every recursively discovered non-system dynamic library.
- Homebrew and `/usr/local` install names are rewritten to `@rpath` references.
- Each library receives a bundle-relative identity.
- Both helpers receive an `@executable_path/../Frameworks` run path.
- Libraries are ad-hoc signed first, followed by the helper executables.
- Static inspection rejects any remaining Homebrew or `/usr/local` dependency.
- Runtime tracing rejects any library actually loaded from those locations.
- A final `vtool` check rejects code requiring a newer macOS version than the application supports.

The script begins from a fresh, tightly validated staging path. It also detects two different source libraries attempting to use the same bundled filename.

## Dependency closure

The current Homebrew-based proof closure contains 10 libraries:

- libass
- FreeType
- FriBidi
- HarfBuzz
- libunibreak
- libpng
- GLib
- Graphite2
- gettext/libintl
- PCRE2

The two helpers and all 10 libraries were rewritten without remaining `/opt/homebrew` or `/usr/local` references. Runtime loader tracing confirmed that all 10 libraries were loaded from `Contents/Frameworks`. The resulting proof bundle is approximately 18 MB.

## End-to-end proof

The rewritten `ffprobe` inspected the complex `Come and See (1985).mkv` source successfully. The rewritten `ffmpeg` then completed a two-second hardware-only HEVC conversion with libass subtitle rendering, protected +6 dB audio processing, AC-3 output, the `hvc1` tag, and fast-start MP4 relocation.

Validation with the rewritten `ffprobe` reported HEVC Main `yuv420p`, AC-3 stereo at 48 kHz, and a two-second output. This proves that the relative linkage survives real probing, decoding, subtitle shaping, font selection, filtering, hardware encoding, audio encoding, and MP4 muxing.

## Deployment-target blocker

SwiftyTranscoder targets macOS 14. The purpose-built FFmpeg and ffprobe executables were corrected to build with a macOS 14 minimum and now report that target.

The copied Homebrew libraries report minimum versions of macOS 26 or 27. They run on the development Mac but cannot be shipped in an application that claims macOS 14 compatibility. Changing their metadata would not prove that they avoid newer APIs, so the staging script correctly exits with a failure after listing every incompatible library.

This confirms that copying and rewriting Homebrew bottles is useful as a linkage proof but is not an acceptable release implementation.

## Result

Bundle layout, recursive dependency discovery, install-name rewriting, signing order, runtime resolution, and the deployment-target safety gate are proven. No application lookup or release packaging behavior changed.

The next focused milestone is to build libass and its minimum supporting libraries from checksum-pinned source with the macOS 14 deployment target. Static linking should be preferred where licensing permits so the 10-library Homebrew closure can be reduced before app integration.
