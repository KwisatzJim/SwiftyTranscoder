# Milestone 74 — Restoration Audio and Metadata Mux

## Goal

Combine a validated silent restoration preview with the matching source audio range while preserving SwiftyTranscoder's established Plex compatibility and protected-gain policy.

This remains a development boundary. Its output is named `restored-preview.partial.mp4`, stays inside the owned restoration workspace, and cannot replace or promote a user-facing output file.

## Mux contract

`RestorationAudioMux` accepts only `restored-video.partial.mp4` from the same preview workspace. It rejects missing inputs, an existing output, unsupported audio layouts, negative start times, and preview durations outside the bounded 30-second maximum.

FFmpeg copies the validated HEVC/hvc1 video without another video encode and creates:

- a default AC-3 compatibility track using the same mono, stereo, and 5.1 rates as normal conversion;
- an optional non-default AAC stereo track at 192 kb/s; and
- the established optional `volume=6dB` plus peak limiter filter on every generated audio track.

Container metadata is copied from the source. Chapters are intentionally omitted because chapter timestamps from a full program cannot safely describe a short preview excerpt.

The partial-output suffix and FFmpeg's no-overwrite mode make interrupted or pre-existing output unambiguous. Cancellation terminates the active helper and never promotes the partial.

## Independent validation

After muxing, ffprobe must confirm:

- exactly one HEVC video stream with the `hvc1` compatibility tag;
- the approved number of audio streams and no subtitle or chapter streams;
- AC-3 sample rate, channels, layout, exact compatibility bitrate, language, and default disposition;
- optional AAC stereo sample rate, layout, language, and non-default disposition; and
- a nonempty file whose duration matches the requested preview within the audio-frame tolerance.

The real-media verification combined the four-frame restored segment beginning at 00:09:00 of `Alphas - s01e11 - Original Sin.m4v` with protected-gain AC-3 and AAC audio. ffprobe confirmed the copied HEVC/hvc1 video, both expected audio tracks, source show/season/episode metadata, and stream start times within approximately 21 milliseconds.

## Verification

- The complete suite passes 72 tests across 20 suites.
- The full macOS application builds successfully with Swift 6 complete concurrency checking.
- The real mux output remains clearly labeled at `/private/tmp/SwiftyTranscoder-Restoration-Milestone73/restored-preview.partial.mp4` for development inspection only.

## Result and next gate

The native restoration path now has independently validated video, compatible audio, protected gain, metadata carry-through, progress, and cancellation boundaries.

The next milestone can integrate this fourth stage into the native preview coordinator. That integrated result should remain a partial preview and must receive picture, audio, and synchronization review before restoration controls are exposed in the application UI.
