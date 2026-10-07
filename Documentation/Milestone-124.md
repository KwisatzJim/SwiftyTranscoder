# Milestone 124 — Video-only ordinary conversion

The user requested audio removal for tech-support videos. An explicit per-source **Remove all audio** switch now produces video-only ordinary conversions. Gain and secondary AAC settings are ignored and their controls disabled while removing audio; underlying audio preferences are preserved, and removal is not saved as a global default. Already-silent sources select video-only mode on inspection. Reviewed ordinary batch jobs retain their own audio-removal choice.

Compatible MP4/M4V sources keep their compressed video unchanged; MKV follows the existing Apple hardware HEVC path. Every audio track is omitted with video-only mapping and `-an`; no audio codec, filter, bitrate, or audio metadata options are emitted in this mode. Output validation requires zero audio streams before promotion. Existing source protection, color/video eligibility, subtitle choice, collision refusal, partial naming, and video checks remain in place.

The CLI exposes `--audio convert|omit`, defaulting to existing conversion. `--audio omit` works without a source audio stream and the dry run explicitly reports video-only output. AI restoration currently retains its existing audio contract: the CLI refuses combining removal with `--restore`, and GUI controls prevent that combination. This checkpoint focuses on ordinary support-video processing rather than changing the accepted restoration pipeline.

Video-only duration validation prefers the video stream's duration, Matroska DURATION tag, or frame-count/rate duration before container duration. This prevents a longer audio tail from falsely invalidating an otherwise complete video-only output. Source inspection now decodes the optional stream duration without changing existing frame-count or restoration behavior.

The optimized development app is `.build/Milestone124DerivedData/Build/Products/Release/SwiftyTranscoder.app`. Focused parser and duration checks passed (10 tests). Real checks passed for video-only MP4, identical compressed HEVC stream hash, smaller file size (3,814,925 → 3,650,085 bytes), silent input, a longer audio tail, MKV hardware HEVC output, existing-file refusal, and unchanged source content. A deliberately faulty helper retained audio; the app rejected it with Expected 0 output audio streams, retained the labeled partial, and never promoted a final file. Evidence: `.build/milestone124-evidence/`.

The user confirmed silent playback and the audio-removal interface; this checkpoint is accepted. Version 1.6.0 includes this option. The public 1.5.0 installer does not contain this new option.

Final automated validation: all 169 tests in 41 suites passed, ordinary MKV/MP4 audio/gain/video-copy/cancellation smoke checks passed, and the final optimized app passed strict signatures and resource/helper/model checks. User review is complete.
