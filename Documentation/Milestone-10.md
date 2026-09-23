# Milestone 10 — End-to-end compatibility and Plex validation

## Step 1: Compatibility matrix

The 14-file live inventory was probed again before broadening the conversion policy.

### Fits the verified 8-bit SDR, 48 kHz 5.1 path

- `Dark Matter - s02e03 - Everything Beautiful, Everything Terrible.mkv` — H.264, E-AC-3/Atmos
- `Lanterns - s01e05 - Lights Out.mkv` — H.264, E-AC-3/Atmos
- `Lioness - s03e07 - Kiss the Girls.mkv` — H.264, E-AC-3
- `Reacher - s04e08 - Cut.mkv` — H.264, E-AC-3/Atmos, verified forced subtitles
- `Slow Horses - s06e01 - Circle of Life.mkv` — H.264, E-AC-3/Atmos
- `Star Trek Strange New Worlds - s04e09 - Once La'an a Time.mkv` — H.264, E-AC-3

### Confirmed 10-bit SDR requiring Main10 support

- `Lanterns - s01e06 - Bad Optics.mkv` — HEVC Main10, `yuv420p10le`, BT.709, E-AC-3/Atmos 5.1
- `The Paper - s01e02 - The Five W's.mkv` — HEVC Main10, `yuv420p10le`, BT.709, HE-AAC 5.1
- `Tony (2026).mkv` — HEVC Main10, `yuv420p10le`, BT.709, E-AC-3 5.1

These files are explicitly SDR despite their 10-bit pixel format. Supporting them does not require HDR-to-SDR conversion.

### DTS samples with incomplete color metadata

- `Designated Survivor - s01e11 - Warriors.mkv`
- `Designated Survivor - s01e16 - Party Lines.mkv`

Both are H.264 8-bit with DTS 5.1, but their transfer characteristic is not identified. They remain blocked until the app can show and obtain an explicit color-handling decision rather than assuming SDR.

`Designated Survivor - s03e09 - #undecided.mkv` has the same unconfirmed-color issue with E-AC-3 audio.

### Foreign-language samples needing layout expansion

- `Come and See (1985).mkv` — HEVC Main10 with unconfirmed color plus Russian AAC mono at 48 kHz
- `Mr. Nobody Against Putin (2025).mkv` — H.264 8-bit BT.709 plus Russian AAC stereo at 44.1 kHz

The current first audio path accepts 48 kHz 5.1 input only. Mono and stereo policy must be deliberately added rather than silently expanded to six channels.

### Expansion order

1. Add confirmed 10-bit SDR to Main10 hardware encoding.
2. Add explicit mono/stereo audio handling without inventing surround channels.
3. Add a visible decision for untagged 8-bit color before testing DTS sources.
4. Convert representative H.264, HEVC, Atmos/E-AC-3, DTS, AAC, forced-subtitle, subtitle-heavy, and foreign-language samples.
5. Record real Plex client behavior before calling version 1 compatible.

No media was created or modified during this inventory step.

## Step 2: Confirmed 10-bit SDR hardware path

A five-second video-only smoke test used `Lanterns - s01e06 - Bad Optics.mkv`, which is explicitly HEVC Main10, `yuv420p10le`, and BT.709 SDR. VideoToolbox encoded it with software fallback disabled.

Independent validation reported:

- HEVC Main10 with the Apple-compatible `hvc1` tag
- 2160 × 1080
- 10-bit `yuv420p10le` decoded output
- TV range with BT.709 space, transfer, and primaries
- 24000/1001 frame rate
- 5.005-second duration

The temporary artifact is `/tmp/SwiftyTranscoderMain10Smoke-01.partial.mp4`.

The opening five seconds produced an atypically large 17 MB sample, so that clip alone was not used to lower picture quality. Five additional five-second samples spread from 10 to 50 minutes encoded at approximately 0.3–0.8 MB each with the existing quality setting. This confirmed that the opening burst was not representative of the episode and avoided an unnecessary quality reduction.

The application now accepts only the two validated SDR input formats: `yuv420p` and `yuv420p10le`. It selects HEVC Main or Main10 and `yuv420p` or `p010le` encoder input accordingly. Post-encode validation requires the expected profile, decoded pixel format, and matching color space/transfer/primaries before promotion. HDR and unconfirmed color remain blocked.

The expanded inventory also exposed a metadata assumption: compatibility audio was always labeled English. The command now preserves the source audio language code and uses `und` when the source language is unknown. Its title is language-neutral and describes the actual output layout, so foreign or untagged audio is never mislabeled.

## Mono and stereo audio expansion

The compatibility path now preserves supported source channel layouts instead of expanding every source to 5.1. Mono becomes AC-3 mono at 96 kb/s, stereo becomes AC-3 stereo at 192 kb/s, and 5.1 remains AC-3 5.1 at 224 kb/s. All three paths normalize to 48 kHz for predictable playback. Output validation derives its expected layout and bitrate from the approved source, so a silent channel-layout change cannot be promoted as complete.

A five-second `Mr. Nobody Against Putin (2025).mkv` smoke test confirmed conversion from 44.1 kHz AAC stereo to 48 kHz AC-3 stereo at 192 kb/s while preserving BT.709 video metadata. `Come and See (1985).mkv` now passes the mono audio check but remains blocked by default because its source color transfer is not explicitly identified.

## Explicit decision for missing color metadata

Files with missing color declarations remain blocked by default. Their conversion plan now presents a visible `I confirmed SDR — tag as BT.709` choice. The option is only available when dynamic range is not identified; confirmed SDR continues automatically, while explicitly identified PQ or HLG HDR remains unsupported and cannot use this override.

When the user confirms an untagged source as SDR, the command applies limited-range BT.709 color space, transfer, and primaries metadata through FFmpeg's `setparams` filter. This labels the approved interpretation without applying a color-space transformation. Post-encode validation requires all three BT.709 declarations before the partial output may be promoted. A two-second Main10 check with `Come and See (1985).mkv` verified that VideoToolbox retained `color_space=bt709`, `color_transfer=bt709`, and `color_primaries=bt709`; direct output flags alone were tested and rejected because VideoToolbox dropped two of those declarations.

The user confirmed the full `Come and See (1985).mkv` conversion completed and passed visual, subtitle, mono-audio, synchronization, and local playback checks. Independent inspection of the 5.6 GB final MP4 confirmed HEVC Main10 with `hvc1`, 1480 × 1080 `yuv420p10le`, limited-range BT.709 space/transfer/primaries, 24000/1001 fps, and Russian AC-3 mono at 48 kHz and 96 kb/s. The duration is 8598.740 seconds and no subtitle stream remains because the selected full-English SubRip track was burned into the video.

## Plex client results

`Come and See (1985).mp4` was tested through Plex on two real clients:

- Firefox on the Rossum Linux PC: video **Direct Stream**, audio **Transcode**; playback through the normal HomePod pair was successful.
- Safari on the MacBook Neo: video **Direct Play**, audio **Direct Play**.

The Safari result confirms that the complete MP4/HEVC Main10/AC-3 mono combination can Direct Play through Plex. The Firefox result is client-specific: Plex can reuse the video without re-encoding it but must remux the delivery stream, while the browser requires the audio to be transcoded.

On the MacBook Neo Safari Direct Play session, the user confirmed natural picture color and brightness, readable and correctly timed burned English subtitles, synchronized audio, working seeking, and working chapter navigation. The `Come and See` representative Plex check is complete.

`Reacher - s04e08 - Cut.mp4` was then tested through Plex in Safari on the MacBook Neo. Plex reported **Direct Play** for both video and audio. The user confirmed that picture, audio, and the burned forced-only subtitles all looked correct. This validates the representative H.264 source, E-AC-3/Atmos-to-AC-3 5.1 compatibility conversion, protected +6 dB gain, and forced-English burn-in workflow on that client.

`Designated Survivor - s01e11 - Warriors.mkv` completed the representative DTS-input conversion with user-confirmed BT.709 SDR handling, protected gain, and omitted subtitles. The user confirmed correct local playback and synchronized audio. Independent inspection of the 325 MB output confirmed HEVC Main with `hvc1`, 1920 × 1080 `yuv420p`, limited-range BT.709 space/transfer/primaries, 24000/1001 fps, and English AC-3 `5.1(side)` at 48 kHz and 224 kb/s. Its 2495.660-second duration matches the source, and no subtitle stream is present.

In Plex Safari on the MacBook Neo, this DTS-derived output reported **Direct Play** for both video and audio. The user confirmed that picture and audio were good.

The user also confirmed that audio remained synchronized after seeking, seeking worked at several points, and Plex chapter navigation worked. The representative DTS Plex check is complete.

For the final gain comparison, the user played the matching Reacher no-gain and protected +6 dB outputs through Plex Safari on the MacBook Neo at unchanged playback volume. The gain-enabled version had noticeably louder dialogue without audible clipping, crackling, or distortion. Together with the earlier measured -2.0 dBFS true peak, this completes the gain acceptance check.

The real Plex matrix now covers H.264 and HEVC/Main10 sources, E-AC-3/Atmos and DTS inputs converted to AC-3 5.1, mono foreign-language audio, forced-only and full-English burned subtitles, client-specific Firefox fallback behavior, Safari Direct Play, color correctness, sync, seeking, and chapters. Milestone 10 playback validation is complete.
