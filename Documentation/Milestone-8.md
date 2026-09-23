# Milestone 8 — Forced-English subtitle burn-in

## Step 1: Subtitle renderer preflight

The existing deterministic recommendation correctly selects source stream 2:

- Codec: SubRip
- Language: English
- Title: `American English [Forced]`
- Forced disposition: set

The first five subtitle packets begin at 668.668 seconds (about 11:09), providing a useful short visual-test interval where captions are known to appear.

### Dependency finding

The installed Homebrew FFmpeg 9.0.2 build does not provide the `subtitles` or `ass` video filters. Direct filter help returns `Unknown filter 'subtitles'`, and the build configuration does not include libass. Therefore this FFmpeg executable cannot safely implement SubRip burn-in.

Homebrew identifies the system-linked executable as the regular `ffmpeg` formula and states that `ffmpeg-full` includes additional libraries omitted from the regular formula. An approved install check then revealed that `ffmpeg-full` 9.0.2 was already installed and current, but not system-linked.

The keg-specific executable at `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` explicitly enables libass and provides both the `subtitles` and `ass` filters. SwiftyTranscoder can use this path without replacing or relinking the machine's default FFmpeg.

No media was created or modified during this preflight.

## Step 2: Forced-subtitle visual smoke test

An 18-second video-only test clip was encoded from approximately 11:05 through 11:23, covering the first five packets from the chosen forced-English track:

`/tmp/SwiftyTranscoderSubtitleSmoke-01.partial.mp4`

The command used the libass-capable `ffmpeg-full` executable, explicitly selected subtitle stream index 0 within the subtitle streams (global source stream 2), and retained the validated hardware HEVC settings. Subtitle styling was forced to:

- Helvetica
- 22-point libass size
- White text
- Two-pixel black outline
- No shadow
- Bottom margin 36

Extracted frames at 4.5, 7.5, and 12.5 seconds visibly contained the expected forced dialogue. The text was synchronized, centered, inside the picture, and readable against both dark and bright content. The source MKV and completed application outputs were unchanged.

The user approved the subtitle size and appearance.

## Step 3: App command integration

The conversion command now requires the libass-capable `ffmpeg-full` executable. For a selected burn-in track, it:

- Resolves the displayed global stream index back to the inspected stream
- Confirms that the stream still exists and uses SubRip
- Converts the global stream index to FFmpeg's subtitle-only ordinal
- Applies the visually approved Helvetica/libass style
- Continues to exclude soft subtitle streams from the MP4

If the user selects `Omit subtitles`, no video subtitle filter is applied. An unresolved selection or unsupported subtitle codec blocks conversion with an explicit explanation.

The Debug application build succeeded. Full application conversion and playback verification remain pending.

## Final integrated verification

The user completed the full conversion and confirmed that the burned forced-English subtitles look correct in playback.

Independent inspection of the final MP4 confirmed:

- HEVC Main video with the Apple-compatible `hvc1` tag
- 1920 × 960, 24000/1001, 8-bit `yuv420p`
- AC-3 `5.1(side)` audio at 48 kHz and 224 kb/s
- No soft subtitle stream, as expected for burn-in
- Duration 3463.482667 seconds
- No `.partial.mp4` remained after promotion

A frame extracted from the completed application output at 11:12.5 visibly contains the expected text `Crop duster rental 25 miles outside the city.` using the approved styling. Milestone 8 is complete.
