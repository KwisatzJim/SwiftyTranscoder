# Milestone 81 — Full-Duration Restoration Audio

## Goal

Extend the proven restoration-preview audio boundary to a complete restored program while preserving the user's approved audio stream, gain, and stereo-fallback decisions.

## Full-duration request

The full-duration request accepts only the validated `restored-silent.partial.mp4` inside the owned restoration workspace. It starts at program time zero, requires a positive finite duration, and writes a separate `restored-audio.partial.mp4`. The existing preview request remains limited to 30 seconds and continues to use its established filenames.

FFmpeg copies the restored HEVC video without recompression and maps the exact approved source-audio stream index. The output audio policy is the same one already confirmed in normal conversions and restoration previews:

- primary AC-3 compatibility audio at 48 kHz with the source's supported mono, stereo, or 5.1 layout
- optional secondary AAC stereo at 192 kb/s
- optional +6 dB gain through the existing peak-protected limiter
- preserved audio language and explicit track titles
- primary audio marked as the default track

The output is limited to the validated restored-video duration so source-container overhang cannot extend it.

## Validation and cancellation

After muxing, ffprobe must find one HEVC/hvc1 video stream, the exact expected number of audio tracks, no subtitles or chapters, the approved codecs, layouts, sample rates, bit rates, language, and dispositions, plus a positive file size. Full-duration timing uses a strict 0.1 percent tolerance rather than the preview's intentionally wider short-clip tolerance.

Cancellation terminates active FFmpeg work and leaves any incomplete output clearly labeled `.partial.mp4`. Existing files are never overwritten.

## Safety state

Full-file execution remains disabled. The next boundary must reintegrate the approved subtitle decision, chapters, and container metadata, then validate and promote the final destination atomically.
