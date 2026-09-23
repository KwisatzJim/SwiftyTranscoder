# SwiftyTranscoder — Codex Project Brief

## Purpose

Build a native macOS application that converts MKV video files into Plex-friendly MP4 files through a much simpler and more understandable interface than HandBrake.

The application should inspect each source, recommend sensible settings, clearly explain what it will do, and use Apple hardware acceleration for the expensive video work. It should be designed around the user's actual Plex workflow rather than attempting to expose every possible transcoding option.

## Working style for Codex

Work in small, discrete, sequential milestones.

For each milestone:

1. Explain the single focused change and why it is needed.
2. Inspect the existing project before editing it.
3. Preserve everything that already works.
4. Implement only that milestone.
5. Build and run appropriate tests.
6. When UI or media behavior is involved, ask the user to verify it with the real application or a representative MKV before moving forward.
7. Record what was attempted, what was observed, what was expected, and any follow-up work.

Avoid large batches of speculative features. Do not begin a later milestone until the current milestone works.

## Product goals

- A polished native macOS SwiftUI application.
- A simple workflow: choose a source, review an understandable recommendation, choose an output location, and convert.
- Reliable support for real-world MKV files containing H.264 or HEVC video, surround audio, many subtitle tracks, and chapters.
- Apple hardware acceleration through VideoToolbox and the Apple Media Engine.
- An inspection and decision layer that explains its choices instead of silently guessing.
- Safe output behavior that never modifies or replaces the source MKV.
- MP4 output intended primarily for Plex playback.
- Accessibility-oriented audio processing, including the user's normal +6 dB gain preference.

## Actual playback environment

The resulting MP4 files will normally be added to Plex and played through:

- The Plex application on a Roku TV.
- Firefox on the Rossum gaming/media-center PC.
- A stereo pair of HomePods used as the normal living-room output.
- The Plex application on a laptop.

The user normally applies **+6 dB audio gain** because their mother is hard of hearing. This must be treated as a first-class, visible option rather than a hidden implementation detail. Gain processing must include peak protection or a loudness-aware limiter so louder passages do not clip.

## Architecture decision

SwiftyTranscoder should be a native Swift/SwiftUI macOS application that uses Apple hardware and frameworks wherever they are the right tool, while permitting FFmpeg components as a focused compatibility layer.

Proposed responsibility split:

- **SwiftUI:** interface and user workflow.
- **Swift application layer:** jobs, recommendations, validation, presets, progress, errors, and cancellation.
- **`ffprobe`:** dependable read-only inspection of MKV containers and their streams during the first milestones.
- **FFmpeg/libav compatibility layer:** MKV demuxing and codecs or subtitle formats Apple frameworks cannot reliably read.
- **VideoToolbox:** hardware video decoding and HEVC/H.264 encoding where practical.
- **AVFoundation/Core Audio:** supported media handling, audio processing, and MP4-oriented integration where appropriate.
- **Core Image/Metal:** future scaling and image-processing work.
- **Vision/Core ML:** future content analysis, OCR, restoration, or intelligent recommendations—not initial transcoding.

The application should not become a thin interface that exposes raw FFmpeg options. Third-party media components are implementation details beneath a Mac-native decision engine and interface.

## Version 1 boundaries

### Include

- macOS only.
- One MKV job at a time initially.
- Read-only source analysis.
- H.264 and HEVC source video.
- HEVC MP4 output using Apple hardware acceleration.
- Source-resolution preservation with 1080p and 2160p output profiles.
- Source-frame-rate preservation.
- Sensible handling of 5.1 E-AC-3, DTS, and AAC sources.
- Optional +6 dB audio gain with clipping protection.
- Reliable forced-English subtitle selection.
- Full English subtitle selection for foreign-language films.
- Subtitle decision preview before conversion.
- Chapter and useful metadata preservation where MP4 supports them.
- Clear progress, cancellation, success, and failure states.

### Defer

- Batch queues.
- Cross-platform support.
- AI upscaling.
- AI denoising or restoration.
- Automatic black-bar removal.
- Subtitle OCR.
- Broad manual access to encoder internals.
- Every codec and container combination.
- Automatic guessing when metadata is ambiguous.

## Representative source findings

Twelve sample MKV files have already been inspected with `ffprobe`.

- Video codecs: H.264 and HEVC Main 10.
- Observed video is SDR, with some older files lacking complete color declarations.
- Every sample has one 5.1 audio track.
- Audio codecs include E-AC-3, DTS, and HE-AAC.
- Five E-AC-3 tracks are explicitly identified as Dolby Digital Plus with Atmos.
- Four other E-AC-3 tracks are not explicitly identified as Atmos by `ffprobe`; absence of an Atmos label must not be treated as definitive proof that Atmos is absent.
- Two samples contain DTS 5.1.
- Subtitle tracks are SubRip text in the current sample set, ranging from zero to 43 tracks per file.
- Two samples contain chapters.
- No attachments were found.

Use the existing combined analysis as the media evidence source:

`SwiftyTranscoder-MKV-analysis.md`

## Existing HandBrake behavior to preserve or improve

The user's normal preset is `1080p 6db gain.json`. A second preset is `2160p with 6db gain.json`.

Important current preferences:

- MP4 output.
- VideoToolbox HEVC encoding.
- Maximum dimensions of 1920×1080 or 3840×2160.
- 5.1 AC-3 audio at 224 kb/s with +6 dB gain.
- Chapter and metadata preservation.
- Denoising and sharpening disabled.

The app should improve these behaviors:

- Preserve the source frame rate rather than routinely targeting a 60 fps peak unless the user deliberately changes it.
- Do not upscale automatically.
- Do not depend on the first English subtitle being the correct subtitle.
- Do not reproduce HandBrake's unreliable foreign-audio search as a silent automatic rule.

## Video policy

- Preserve the source resolution by default.
- Never upscale automatically.
- Preserve the source frame rate by default.
- Use hardware HEVC encoding when the source and requested output are supported.
- Preserve aspect ratio.
- Do not apply denoising, sharpening, deblocking, cropping, or other destructive filters without a specific recommendation that the user can review.
- Preserve HDR and color metadata when supported; never silently convert HDR to SDR or discard Dolby Vision metadata.
- If a requested operation cannot preserve important color information, stop and explain the conflict.

## Audio policy

The initial audio policy should prioritize reliable Plex playback over preserving every exotic source format.

- Identify the primary audio track and show its language, codec, channel layout, title, and Atmos/DTS/TrueHD indicators.
- Create a dependable 5.1 compatibility track for the first working version.
- Support an explicit +6 dB gain option.
- Apply peak protection or limiting when gain is enabled.
- Do not claim to preserve Atmos after decoding and re-encoding it to ordinary channel-based audio.
- Clearly state when Atmos or another advanced format will be lost, preserved, or cannot be confirmed.
- Do not assume that failure to detect Atmos means it is absent.
- Add a stereo compatibility track only after the first 5.1 conversion path has been tested through the user's actual Plex clients.

The exact long-term choice between AC-3, E-AC-3, and AAC compatibility tracks should be based on playback tests on the Roku, Rossum/Firefox/HomePods, and laptop—not assumptions alone.

## Subtitle policy

Forced English subtitles and complete English subtitles must be treated as separate concepts.

### Forced English

1. Inspect every English subtitle track rather than selecting the first English track.
2. Prefer a track whose Matroska disposition is explicitly `forced`.
3. Also recognize clear titles such as `Forced`, `English Forced`, and `Foreign Parts Only`.
4. When a forced-English track is reliably identified, select it and burn it into the video by default.
5. Prefer a non-SDH forced track when the distinction is clear.
6. If multiple credible candidates remain, show them and ask the user rather than guessing.
7. If no forced flag or title exists, a short track may be analyzed as a possible forced track using packet count and on-screen duration. Label this **Likely forced—confirmation needed** and do not silently burn it.

### Foreign-language films

When the primary audio language is not English:

1. Recommend the best complete English subtitle track.
2. Prefer ordinary English over English SDH unless the user chooses SDH.
3. Preselect burn-in, but make the decision visible and changeable before conversion.
4. Offer a selectable MP4 subtitle alternative when the subtitle format supports it.
5. Treat image-based PGS/VobSub tracks separately: burn them directly or send them through a later, explicitly confirmed OCR workflow. Never pretend image subtitles were converted to text without OCR and verification.

### Required conversion summary

Before conversion, show:

- Source stream number.
- Language.
- Track title.
- Forced/default/SDH status.
- Whether it will be burned in, retained as selectable, or omitted.
- The reason for any automatic selection.

Use these user-facing states:

- **Forced English found—burn in**
- **Foreign-language audio—burn full English**
- **No forced English identified**
- **Possible forced track—confirmation needed**

### Initial subtitle test case

`Reacher - s04e08 - Cut.mkv` contains:

- Stream 2: `American English [Forced]`, marked both default and forced.
- Stream 3: `American English [SDH]`.

The app must automatically recommend burning stream 2 and must not confuse stream 3 with the forced track.

## Safety and error behavior

- Never modify the input MKV.
- Never overwrite an existing output without explicit approval.
- Default to a separate output location and provide a predictable proposed filename.
- Validate free disk space before conversion.
- Make cancellation safe and remove or clearly label incomplete output files.
- Errors must identify the affected file, stream, codec, or setting and explain what the user can correct.
- Never silently fall back to a materially different codec, resolution, subtitle track, or audio policy.
- Preserve logs needed to diagnose failed jobs without exposing an overwhelming raw command-line interface in the normal UI.

## Milestones

### Milestone 1 — Project foundation

Create a minimal macOS SwiftUI application that launches successfully. Establish a small, understandable folder structure and document how to build and run it.

Acceptance checks:

- The project builds without errors.
- The application opens to one simple window.
- No media processing has been added yet.
- The user confirms the app launches on the intended Mac.

### Milestone 2 — Choose and inspect one MKV

Add a native file picker for one MKV. Run `ffprobe` read-only and decode its JSON into typed Swift models.

Acceptance checks:

- The source file remains unchanged.
- The app reports container, duration, size, overall bitrate, video, audio, subtitles, chapters, and attachments.
- Probe failures identify the file and provide a useful reason.
- Test against `Reacher - s04e08 - Cut.mkv` and at least one file with many subtitle tracks.

### Milestone 3 — Human-readable analysis screen

Display the inspection results in a clean summary designed for ordinary use, with expandable technical details.

Acceptance checks:

- The main view communicates resolution, codec, frame rate, SDR/HDR state, audio layout, and subtitle decision without requiring codec expertise.
- Detailed stream metadata remains accessible.
- Missing metadata is labeled as unknown rather than invented.

### Milestone 4 — Deterministic subtitle recommendation

Implement the explicit forced-English selection rules using language, disposition, and track title. Do not add statistical “likely forced” guessing yet.

Acceptance checks:

- The Reacher forced track is selected and recommended for burn-in.
- The Reacher SDH track is not selected as forced.
- The interface explains why the track was chosen.
- Ambiguous files produce no silent selection.

### Milestone 5 — Conversion plan preview

Create a conversion-plan model and screen. It should show the intended output container, video behavior, audio behavior, gain, subtitles, output path, and warnings before any conversion begins.

Acceptance checks:

- Every automatic choice is visible.
- The user can change the subtitle choice and gain setting.
- Existing destination-file conflicts are caught before conversion.
- No conversion occurs in this milestone.

### Milestone 6 — First video-only conversion path

Implement the smallest end-to-end hardware HEVC MP4 conversion path for one known-supported sample. Keep audio and subtitle scope deliberately narrow.

Acceptance checks:

- VideoToolbox hardware encoding is actually used and verified.
- Resolution and frame rate match the approved plan.
- The source remains unchanged.
- The partial output is safely handled on cancellation or failure.
- The resulting video is visually inspected.

### Milestone 7 — 5.1 audio and +6 dB gain

Add the initial supported 5.1 audio conversion path, then add optional +6 dB gain with clipping protection.

Acceptance checks:

- The output contains the planned codec and 5.1 channel layout.
- Gain is measurably applied when enabled.
- Test audio does not clip.
- Sync remains correct throughout the video.
- Playback is tested through Plex on at least one real target client.

### Milestone 8 — Subtitle burn-in

Burn the chosen forced-English SubRip track into the video.

Acceptance checks:

- The Reacher forced subtitles appear only where expected.
- The full SDH track is not accidentally burned.
- Styling is legible and safe within the visible frame.
- Audio/video/subtitle timing remains synchronized.

### Milestone 9 — Full English subtitles for foreign films

Detect non-English primary audio and recommend a full English subtitle track, keeping the choice visible and changeable.

Acceptance checks:

- Ordinary English is preferred over SDH when both exist.
- The app never labels a full dialogue track as forced.
- Burn-in and selectable-subtitle behavior are described accurately.

### Milestone 10 — End-to-end Plex validation

Convert representative H.264, HEVC, E-AC-3/Atmos, DTS, and subtitle-heavy samples, then test the resulting MP4 files through the actual Plex playback environment.

Record for each device:

- Direct Play, Direct Stream, or transcoding behavior.
- Video quality and color correctness.
- Audio format received by the client.
- Dialogue level with and without +6 dB gain.
- Subtitle timing, legibility, and forced-track correctness.
- Seeking, chapter behavior, and sync.

Do not call version 1 compatible until the results are based on these real playback tests.

### Later milestones

Only after the core workflow is reliable, consider:

- Batch queues.
- Saved user profiles.
- A stereo AAC compatibility track.
- Likely-forced subtitle analysis based on packet density and duration.
- PGS/VobSub handling and OCR.
- Automatic crop detection.
- Content analysis and intelligent compression recommendations.
- Metal/Core ML upscaling, denoising, or restoration.

## Definition of a successful first version

The first version is successful when the user can choose one representative MKV, understand the application's proposed actions, correct any choice, and create a Plex-friendly MP4 using Apple hardware acceleration with:

- Preserved resolution and frame rate.
- Working 5.1 audio.
- Optional safe +6 dB gain.
- Correct forced-English burn-in.
- Full English subtitle support for foreign-language films.
- No modification of the source.
- Verified playback through the user's real Plex environment.

## First instruction for Codex

Begin with **Milestone 1 only**. Inspect the project folder before creating anything. Briefly explain the proposed Xcode project structure and the minimum macOS deployment target, then create the smallest SwiftUI application that builds and launches. Do not add `ffprobe`, media models, transcoding, or speculative infrastructure yet. Stop after verifying the build and ask the user to launch the app and confirm the initial window appears.
