# Milestone 7 — 5.1 audio and optional +6 dB gain

## Step 1: Audio encoder preflight

The first audio step will add the planned compatibility track without gain. Gain and limiting will be introduced only after the basic 5.1 path is verified.

### Live Reacher source inspection

The current source file reports one primary audio stream:

- Stream index 1
- English E-AC-3
- Profile explicitly identified as Dolby Digital Plus + Dolby Atmos
- 6 channels in a `5.1(side)` layout
- 48 kHz floating-point audio
- 576 kb/s reported source bitrate

The live 576 kb/s bitrate differs from the older MKV analysis document's 768 kb/s entry. Runtime probing is authoritative for conversion decisions. This difference does not change the initial compatibility-track policy.

### Installed FFmpeg capabilities

The installed FFmpeg AC-3 encoder supports:

- 48 kHz input
- Floating-point samples
- Both `5.1(side)` and `5.1` channel layouts

The installed build also provides the `alimiter` lookahead limiter needed for the later accessibility-gain step. Its input-level control supports the approximately 1.995 linear multiplier corresponding to +6 dB, along with an explicit output ceiling and latency compensation.

### Initial audio policy

- Select the explicitly identified primary audio stream rather than using an implicit first-match rule
- Decode the source E-AC-3/Atmos audio and encode ordinary channel-based AC-3
- Preserve six channels and a defined 5.1 layout
- Preserve the 48 kHz sample rate
- Encode at the planned 224 kb/s
- Clearly report that Atmos is not preserved by this compatibility encode
- Apply no gain or limiter in the first audio test
- Validate codec, channel count, layout, sample rate, bitrate, duration, and stream count before accepting the result
- Keep the source and the already validated video-only result unchanged

No media was created or modified during this preflight.

## Step 2: Isolated AC-3 5.1 smoke test

The first 10 seconds of the Reacher primary audio stream were decoded and encoded to a new temporary audio-only MP4:

`/tmp/SwiftyTranscoderAudioSmoke-01.partial.mp4`

The no-overwrite command explicitly mapped source audio stream 1, excluded video, subtitles, and data, applied no audio filter or gain, and encoded AC-3 at 224 kb/s, 48 kHz, and six channels.

Independent `ffprobe` validation confirmed:

- Exactly one audio stream and no video
- AC-3 with the MP4 `ac-3` tag
- 48 kHz
- 6 channels in the `5.1(side)` layout
- 224,000 b/s
- 10.000-second duration
- English language metadata

The entire sample was decoded through FFmpeg's audio statistics filter. It decoded 480,000 samples per channel without errors. The highest measured sample peak was -2.91 dBFS, confirming that the no-gain baseline does not clip.

The source MKV and completed video-only MP4 were not modified.

## Step 3: App integration for the no-gain path

The conversion command now explicitly maps both the first video stream and the identified primary audio stream. With gain switched off, it encodes:

- Hardware HEVC Main video using the already validated policy
- AC-3 audio at 224 kb/s
- Six channels at 48 kHz
- English language metadata and a compatibility-track title
- No subtitle streams yet

The default +6 dB setting is deliberately blocked at command construction until peak protection is implemented. The plan tells the user to turn gain off for this initial test rather than silently applying unprotected gain or ignoring the enabled preference.

Before promoting the partial output, validation now requires:

- Exactly one HEVC `hvc1` video stream with preserved dimensions and frame rate
- Exactly one AC-3 `ac-3` audio stream
- Six-channel `5.1` or `5.1(side)` layout
- 48 kHz and 224,000 b/s audio
- No subtitle streams
- Output duration within 0.1 second of the probed source duration

The Debug application build succeeded. Runtime conversion and sync/playback checks remain pending.

### Runtime verification

The user completed the integrated no-gain conversion and confirmed that the resulting file looks and plays well, with audio synchronized correctly:

`/Volumes/myMedia/programming_projects/SwiftyTranscoder/Reacher - s04e08 - Cut.mp4`

Direct filesystem inspection confirmed that the intermediate `.partial.mp4` no longer exists; only the promoted final output remains. Independent `ffprobe` inspection confirmed:

- HEVC Main `hvc1`, 1920 × 960, 24000/1001
- AC-3 `ac-3`, 48 kHz, 6-channel `5.1(side)`, 224,000 b/s
- Duration 3463.482667 seconds
- File size 697,074,546 bytes

The complete output audio stream decoded without reported errors. Across 166,247,168 samples per channel, its highest measured peak was -2.35 dBFS, confirming that the no-gain output does not clip.

## Step 4: Protected +6 dB smoke test

Two 10-second AC-3 smoke encodes were compared with the no-gain baseline. The gain chain applies `volume=6dB` followed by FFmpeg's lookahead `alimiter`, with automatic make-up level disabled and latency compensation enabled.

The first test used a -1 dBFS limiter ceiling. It raised integrated loudness from -22.5 LUFS to -16.7 LUFS, a measurable 5.8 LU increase, but lossy AC-3 encoding produced a decoded true peak of -0.2 dBFS. This remained below clipping but did not leave a comfortable playback margin.

The second smoke-test policy used a -2 dBFS limiter ceiling (`0.794328` linear). It preserved the same -16.7 LUFS integrated loudness and 5.8 LU increase while reducing the 10-second sample's decoded true peak to -1.4 dBFS. The protected sample is:

`/tmp/SwiftyTranscoderAudioSmoke-03.partial.mp4`

The user then completed a full episode using that setting and confirmed that the output was noticeably louder. Full-track analysis found an important peak absent from the short sample: the decoded AC-3 true peak reached +0.3 dBFS. The -2 dBFS pre-encode ceiling was therefore rejected.

A complete audio-only encode was repeated with a -4 dBFS limiter ceiling (`0.630957` linear). Across the full 57:43 track, it measured -16.5 LUFS integrated loudness and a safe -2.0 dBFS decoded true peak. The accepted validation artifact is:

`/tmp/SwiftyTranscoderAudioSmoke-04-full.partial.mp4`

The app command now applies this full-track-verified -4 dBFS filter chain when Gain is enabled and labels the audio track `English AC-3 5.1 Compatibility +6 dB Limited`. With Gain off, the already verified unfiltered path remains unchanged.

Full-episode analysis of the retained no-gain output measured -22.2 LUFS. Compared with the accepted protected-gain audio at -16.5 LUFS, the final policy produces a measurable 5.7 LU integrated-loudness increase while retaining 2 dB of decoded true-peak headroom.

### Active-partial warning correction

Runtime testing clarified that the earlier incomplete-output warning appeared only after conversion started. The command correctly creates its `.partial.mp4` work file at launch, but the conversion-plan disk check was treating that controller-owned file as a pre-existing conflict. The plan now suppresses the warning only while the active controller owns that exact partial path. Partial files discovered before a conversion or retained after cancellation/failure remain visible and recoverable.

## Final integrated verification

The user confirmed that the corrected build no longer showed the false partial-file warning during conversion. The final gain-enabled output completed successfully and retained synchronized playback.

Independent inspection confirmed:

- No `.partial.mp4` remained after promotion
- HEVC Main `hvc1`, 1920 × 960, 24000/1001
- AC-3 `ac-3`, 48 kHz, six-channel `5.1(side)`, 224,000 b/s
- Duration 3463.482667 seconds
- Integrated loudness -16.5 LUFS
- Full-track decoded true peak -2.0 dBFS

The no-gain copy measured -22.2 LUFS, so the protected path delivered a measurable 5.7 LU increase. The user also confirmed that it was noticeably louder. Milestone 7's implementation, format, gain, peak-protection, and local playback checks are complete. Plex client validation remains part of the later end-to-end Plex milestone.
