# SwiftyTranscoder

SwiftyTranscoder is a native macOS SwiftUI application for turning one MKV at a time into an understandable, Plex-friendly MP4. It inspects the source first, explains every automatic choice, and uses Apple VideoToolbox hardware encoding for HEVC output.

The source MKV is always read-only. Conversion is written to a clearly named `.partial.mp4`, independently validated, and only then promoted to the final `.mp4` filename.

## Current capabilities

- Inspect MKV video, audio, subtitles, chapters, attachments, duration, size, and bitrate with `ffprobe`.
- Convert H.264 and HEVC SDR sources to hardware-encoded HEVC MP4 with the Apple-compatible `hvc1` tag.
- Accept compatible MP4/M4V sources for audio-only processing while copying their video stream unchanged.
- Preserve source resolution, aspect ratio, frame rate, chapters, and useful metadata without automatic upscaling, cropping, denoising, or sharpening.
- Preserve 8-bit SDR as HEVC Main and supported 10-bit SDR as HEVC Main10.
- Preserve mono, stereo, or 5.1 channel layout while creating Plex-friendly 48 kHz AC-3 audio.
- Apply optional +6 dB gain with peak protection. Gain is visible and enabled by default.
- Select explicit forced-English SubRip tracks without confusing them with SDH tracks.
- For foreign-language audio, prefer a complete ordinary English subtitle over English SDH and burn the visible choice into the video.
- Require explicit confirmation before treating missing color metadata as SDR and tagging the output as limited-range BT.709.
- Show progress, support safe cancellation, retain clearly labeled incomplete output, and offer confirmation-gated movement of that file to the macOS Trash.
- Refuse to overwrite existing output and verify destination free space before starting.
- Validate video profile, pixel format, color metadata, dimensions, frame rate, audio format, channel layout, bitrate, duration, and subtitle policy before completing a file.

## Requirements

- macOS 14 or later
- Apple Silicon Mac with VideoToolbox HEVC support
- Xcode 27 or a compatible newer version for development builds
- Homebrew FFmpeg tools:
  - `ffprobe` at `/opt/homebrew/bin/ffprobe` or `/usr/local/bin/ffprobe`
  - libass-enabled `ffmpeg-full` at `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` or `/usr/local/opt/ffmpeg-full/bin/ffmpeg`

The current app expects those exact Homebrew locations. FFmpeg is not bundled inside the application yet.

## Build and run

1. Install the required Homebrew `ffmpeg` and `ffmpeg-full` packages.
2. Open `SwiftyTranscoder.xcodeproj` in Xcode.
3. Select the **SwiftyTranscoder** scheme and **My Mac** as the destination.
4. Press **Run** (`Command-R`).

The command-line equivalent is:

```bash
xcodebuild \
  -project SwiftyTranscoder.xcodeproj \
  -scheme SwiftyTranscoder \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Local release candidate

The personal, arm64 `0.2.0` release candidate is available at `dist/SwiftyTranscoder_0.2.0_arm64.dmg`, with its SHA-256 checksum in `dist/SHA256SUMS.txt`. It is ad-hoc signed for local use, not Developer ID signed or notarized. Homebrew `ffprobe` and `ffmpeg-full` must already be installed at the paths listed above.

Create a verified local release from the repository root with:

```fish
Scripts/build-release.sh
```

The script refuses to replace an existing DMG for the current version. To deliberately rebuild and replace that artifact, use `Scripts/build-release.sh --force`.

## Workflow

1. Choose one or more MKV/MP4 sources.
2. Review the current file's human-readable media summary and proposed conversion.
3. Resolve any required color or subtitle decision.
4. Choose an output folder and review the storage preflight.
5. Turn protected +6 dB gain on or off.
6. Start the approved plan.
7. Inspect or play the validated final MP4 before removing the source.
8. For a multi-file queue, review and approve the next waiting source.

SwiftyTranscoder never deletes or modifies the source MKV.

## Supported version-1 path

| Area | Supported behavior |
| --- | --- |
| Source container | Matroska/MKV or compatible MP4/M4V; multiple sources may be queued and reviewed sequentially |
| Source video | H.264 or HEVC; `yuv420p` or `yuv420p10le`; confirmed SDR or explicitly user-confirmed untagged SDR |
| Output video | HEVC Main/Main10 in MP4, `hvc1`, VideoToolbox hardware only |
| MP4 video behavior | Copy compatible H.264/HEVC video unchanged when only audio is processed |
| Source audio | AAC, E-AC-3, AC-3, or DTS when decoded by FFmpeg; mono, stereo, or 5.1 layouts |
| Output audio | AC-3 mono 96 kb/s, stereo 192 kb/s, or 5.1 224 kb/s; 48 kHz |
| Gain | Optional +6 dB with a -4 dBFS pre-encode limiter ceiling |
| Subtitles | SubRip burn-in; deterministic forced-English or complete English recommendation |
| Chapters | Preserved as MP4 chapter metadata |

## Intentional limitations

- HDR, HLG, Dolby Vision, and unknown color are never silently converted to SDR.
- Missing color metadata requires the user to confirm that the source is SDR; the app labels the output BT.709 but does not transform the image colors.
- Atmos and DTS are not preserved as advanced formats when converted to ordinary AC-3 compatibility audio.
- PGS/VobSub burn-in and subtitle OCR are not implemented.
- Selectable MP4 subtitle output is not implemented; supported subtitles are either burned in or omitted.
- MP4/M4V audio-only processing cannot burn subtitles because that would require video re-encoding.
- Queue advancement remains user-approved; unattended batch conversion is not implemented.
- Automatic crop detection, restoration filters, AI upscaling, and broad encoder controls are deferred.
- The app currently depends on separately installed Homebrew tools and is not yet a self-contained distributable build.

## Plex validation

Representative outputs have been tested through Plex:

- Safari on the MacBook Neo Direct Played both video and audio for HEVC Main10/AC-3 mono, HEVC Main/AC-3 5.1 converted from E-AC-3/Atmos, and HEVC Main/AC-3 5.1 converted from DTS.
- Firefox on the Rossum Linux PC Direct Streamed video and transcoded audio; playback through the normal HomePod pair was successful.
- Confirmed checks include picture and BT.709 color, gain without audible distortion, burned forced and full-English subtitles, audio/video sync, seeking, and chapters.

The Plex application on the Roku TV also passed the representative picture, audio, subtitle, synchronization, seeking, and chapter checks.

Detailed implementation and test evidence is recorded in `Documentation/`.

## Source structure

- `SwiftyTranscoder/App` — application entry point and window configuration
- `SwiftyTranscoder/Models` — inspection summaries, subtitle decisions, and conversion plans
- `SwiftyTranscoder/Services` — `ffprobe`, FFmpeg command construction, progress, cancellation, and output validation
- `SwiftyTranscoder/Views` — native SwiftUI workflow and technical details
- `Documentation` — milestone decisions and runtime validation evidence
