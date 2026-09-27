# SwiftyTranscoder

SwiftyTranscoder is a native macOS SwiftUI application for turning MKV and compatible MP4 sources into understandable, Plex-friendly MP4 files. It inspects every source first, explains every automatic choice, and uses Apple VideoToolbox hardware encoding for HEVC output.

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
- When forced metadata is missing, show a confirmation-only likely-forced recommendation if one short English SubRip track is clearly sparse compared with a fuller English track.
- For foreign-language audio, prefer a complete ordinary English subtitle over English SDH and burn the visible choice into the video.
- Require explicit confirmation before treating missing color metadata as SDR and tagging the output as limited-range BT.709.
- Explain the exact unresolved safety requirement whenever approval or conversion is disabled.
- Show progress, support safe cancellation, retain clearly labeled incomplete output, and offer confirmation-gated movement of that file to the macOS Trash.
- Review and approve an entire batch before encoding, then process its files sequentially with overall progress, completion notifications, and sleep prevention.
- Move through a focused four-step Choose, Review, Plan, and Convert wizard instead of placing the entire workflow on one long scrolling screen.
- Remove an unwanted source from a batch before encoding without deleting its file or discarding the other approved plans.
- Refuse to overwrite existing output, verify aggregate destination free space, and block duplicate output paths before a batch starts.
- Validate video profile, pixel format, color metadata, dimensions, frame rate, audio format, channel layout, bitrate, duration, and subtitle policy before completing a file.

## Requirements

- macOS 14 or later
- Apple Silicon Mac with VideoToolbox HEVC support
- Xcode 27 or a compatible newer version for development builds
- A source-build environment with `curl`, `shasum`, `tar`, `cmake`, `make`, and `pkg-config` when building the application from source

Release application builds contain their own checksum-pinned FFmpeg 9.0.2 tools. Homebrew FFmpeg is not required for normal use. The former Homebrew locations remain development fallbacks if code is run outside a prepared application bundle.

## Build and run

1. Prepare the pinned self-contained tools with `Scripts/build-toolchain.sh` and `Scripts/stage-toolchain-bundle.sh`, then prepare the verified restoration model with `Scripts/prepare-restoration-model.sh`.
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

Run the Foundation-only media-decision and queue-safety regression tests with:

```fish
swift test
```

## Local 1.0 release

The personal, arm64 `1.0.0` release is available at `dist/SwiftyTranscoder_1.0.0_arm64.dmg`, with its SHA-256 checksum in `dist/SHA256SUMS.txt`. It contains its own checksum-pinned FFmpeg and FFprobe tools, so Homebrew FFmpeg is not required for normal use. It is ad-hoc signed for local use, not Developer ID signed or notarized.

Create a verified local release from the repository root with:

```fish
Scripts/build-release.sh
```

The script runs the regression suite, rebuilds the pinned toolchain, verifies the signed application, creates and verifies the DMG, mounts it read-only, and repeats the app checks from the packaged copy. It refuses to replace an existing DMG for the current version. To deliberately rebuild and replace that artifact, use `Scripts/build-release.sh --force`.

## Workflow

1. On **Choose**, select one or more MKV/MP4 sources.
2. On **Review**, read the current file's human-readable media summary. Technical stream details remain available in a disclosure section when needed.
3. On **Plan**, resolve any required color or subtitle decision, choose an output folder, review the storage preflight, and turn protected +6 dB gain on or off.
4. For one source, continue to **Convert** and start the approved plan normally.
5. For a multi-file queue, approve each plan before encoding begins. The wizard returns to **Review** for each waiting video, and any earlier approved video can be revisited from the queue. Before starting, an unwanted queue entry can be removed without changing its source file. At the ready checkpoint, use the separate **Start Approved Batch** button to convert every approved source in order.
6. On **Convert**, follow progress and ETA, then inspect or play the validated final MP4 files before removing the sources.

The wizard returns to the top when changing steps, keeps the current video visible in long queues, and preserves the loaded batch if **Choose** is revisited accidentally.

After successful validation, **Show in Finder** opens the destination folder with the completed MP4 selected.

SwiftyTranscoder never deletes or modifies the source MKV.

While FFmpeg is converting, SwiftyTranscoder asks macOS to prevent automatic idle system sleep. The request ends after completion, cancellation, or failure; it does not block manually selected sleep or closing a MacBook lid.

During a batch, the running display shows the current video's position and per-video ETA alongside a separate overall batch progress bar.

Before a reviewed batch can start, SwiftyTranscoder adds the conservative requirements for all approved outputs on each destination volume and blocks the batch if the combined requirement cannot be satisfied.

Multi-file queues can optionally send a macOS notification when the batch completes, fails, or is cancelled. This is off by default and requires SwiftyTranscoder to be allowed in **System Settings → Notifications**.

The conversion plan can remember gain and subtitle-policy defaults across sources and app launches. Specific subtitle stream numbers and color confirmations are always source-specific and are never reused.

## Supported version-1 path

| Area | Supported behavior |
| --- | --- |
| Source container | Matroska/MKV or compatible MP4/M4V; multiple sources may be reviewed first and then converted as an unattended sequential batch |
| Source video | H.264 or HEVC; `yuv420p` or `yuv420p10le`; confirmed SDR or explicitly user-confirmed untagged SDR |
| Output video | HEVC Main/Main10 in MP4, `hvc1`, VideoToolbox hardware only |
| MP4 video behavior | Copy compatible H.264/HEVC video unchanged when only audio is processed |
| Source audio | AAC, E-AC-3, AC-3, or DTS when decoded by FFmpeg; mono, stereo, or 5.1 layouts |
| Output audio | Primary/default AC-3 mono 96 kb/s, stereo 192 kb/s, or 5.1 224 kb/s at 48 kHz; optional secondary/non-default AAC stereo at 192 kb/s |
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
- Every queued plan must be reviewed and approved before unattended batch conversion begins. A failure or cancellation stops the batch.
- Automatic crop detection and broad encoder controls remain deferred. Optional restoration and AI upscaling are being developed for the 1.1 line and are not present in 1.0.
- Likely-forced analysis depends on trustworthy Matroska subtitle statistics. Missing, malformed, lone, or ambiguous statistical evidence produces no recommendation.
- The current personal release is arm64 and ad-hoc signed; it is not a Developer ID signed or notarized public distribution.

The self-contained distribution design is documented in `Documentation/Milestone-52.md`. Milestone 53 adds a checksum-pinned minimal FFmpeg build that passed isolated capability and representative media tests. Milestone 54 proves bundle-relative loading and catches that Homebrew's current supporting libraries require macOS 26 or 27, so they cannot be shipped in an app targeting macOS 14. Milestone 55 replaces that runtime closure with checksum-pinned, macOS 14 static builds of libass, FreeType, FriBidi, and HarfBuzz. Milestone 56 embeds the two verified helpers and six license-notice files in the signed app. Milestone 57 makes inspection and conversion prefer those app-contained helpers and retains Homebrew solely as a development fallback. Milestone 58 packages and independently validates the self-contained `0.9.0` DMG. Milestone 59 makes the automated tests and mounted-DMG inspection mandatory release gates. Milestone 60 completes the verified `1.0.0` local release. The approximately 21 MB Release app passed signed, bundled inspection and conversion tests.

Post-1.0 restoration work begins with the safety and architecture boundary in `Documentation/Milestone-61.md`. Milestone 62 adds a checksum-pinned, reproducible evaluation harness for a provisional Real-ESRGAN 2× Core ML candidate. Milestone 63 adds color-gated, read-only full-frame extraction and side-by-side SD comparisons against conventional Lanczos scaling. Milestone 64 adds deterministic consecutive-frame processing, bounded-memory evidence, cancellation checkpoints, temporal diagnostics, and playable comparison clips. Milestone 65 proves a short hardware-HEVC restored MP4 with synchronized protected-gain audio, explicit color tags, partial-output safety, and independent validation. Milestone 66 adds a pure Swift eligibility planner that refuses unsafe or ambiguous sources and records bounded output dimensions, frame rate, and SDR color metadata before any restoration can run. Milestone 67 adds a reusable Swift restoration-job lifecycle with ordered stages, active cancellation, conflict refusal, labeled partial-output retention, and promotion only after validation. Milestone 68 implements bounded, cancellable native Swift frame extraction through the bundled FFmpeg helper, with exact ordered-frame validation and real SD-source evidence. Milestone 69 adds strict native Core ML model-contract inspection and verified finite Float16 tile inference against the external research model. Milestone 70 extends that boundary to complete native frames with reflected padding, overlapping tiles, stride-safe tensor access, feathered assembly, exact cropping, cancellation, and direct comparison with the confirmed Python result. Milestone 71 adds bounded, sequential native frame restoration with strict input ordering, sequence progress, cancellation propagation, owned-output cleanup, and four-frame temporal comparison evidence. Milestone 72 assembles those native frames into an independently validated silent hardware-HEVC segment with exact cadence, dimensions, and SDR color metadata, while retaining cancellation output only under a clearly labeled partial filename. Milestone 73 coordinates extraction, native restoration, and silent-video assembly with aggregate progress, active-stage cancellation, safely owned workspace cleanup, and a real end-to-end SD preview run. Milestones 74–76 integrate audio, expose the bounded preview, and complete hands-on picture and playback review. Milestone 77 embeds the approved model and its license behind checksum-enforced build and release gates. Milestone 78 adds an off-by-default full-video plan and exposes its conservative temporary-storage cost without enabling production execution. Milestone 79 replaces full-sequence retention with deterministic 120-frame chunks, single-chunk cleanup, and a bounded workspace estimate. Conventional Metal scaling and Core Image noise reduction remain accurately labeled as non-AI processing.

## Plex validation

Representative outputs have been tested through Plex:

- Safari on the MacBook Neo Direct Played both video and audio for HEVC Main10/AC-3 mono, HEVC Main/AC-3 5.1 converted from E-AC-3/Atmos, and HEVC Main/AC-3 5.1 converted from DTS.
- Firefox on the Rossum Linux PC Direct Streamed video and transcoded audio; playback through the normal HomePod pair was successful.
- The official Plex HTPC application on Rossum Direct Played copied H.264 video with the optional AAC stereo track, while Firefox/Plex Web transcoded both AC-3 and AAC audio.
- Confirmed checks include picture and BT.709 color, gain without audible distortion, burned forced and full-English subtitles, audio/video sync, seeking, and chapters.

The Plex application on the Roku TV also passed the representative picture, audio, subtitle, synchronization, seeking, and chapter checks, and Direct Played the dual-audio compatibility output.

Detailed implementation and test evidence is recorded in `Documentation/`.

## Source structure

- `SwiftyTranscoder/App` — application entry point and window configuration
- `SwiftyTranscoder/Models` — inspection summaries, subtitle decisions, and conversion plans
- `SwiftyTranscoder/Services` — `ffprobe`, FFmpeg command construction, progress, cancellation, and output validation
- `SwiftyTranscoder/Views` — native SwiftUI workflow and technical details
- `Documentation` — milestone decisions and runtime validation evidence
