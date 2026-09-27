# Milestone 65 — Restored MP4 Assembly Prototype

## Goal

Prove that restored frames can rejoin the established SwiftyTranscoder media path: hardware HEVC video, synchronized protected-gain audio, explicit SDR color tags, incomplete-output safety, independent validation, and promotion only after success.

This remains an ignored development prototype. It does not add restoration controls or a model to the application.

## Prototype

Run:

```fish
Scripts/create-restored-test-clip.sh "source-video.m4v"
```

The current focused test uses two seconds beginning at `00:09:00`. It:

1. verifies that neither the partial nor final test output already exists;
2. extracts 48 ordered source frames without modifying the source;
3. applies the color-gated, feather-blended Real-ESRGAN path;
4. encodes the restored frames as hardware-only HEVC Main with the `hvc1` tag;
5. applies the established `volume=6dB` and peak-protecting limiter before creating 48 kHz AC-3 stereo;
6. writes `restored-test.partial.mp4`;
7. independently validates codec, tag, dimensions, pixel format, color metadata, audio format, channel layout, duration, and nonzero size; and
8. renames the partial file to `restored-test.mp4` only after every check passes.

An interruption or validation failure leaves the clearly labeled partial file and never produces a completed filename.

## Evidence

The first run demonstrated the value of validating the partial file: VideoToolbox initially omitted the source transfer and primary tags even though output color options were present. Validation refused promotion and retained `restored-test.partial.mp4`.

Adding the same explicit `setparams` handoff used by the version 1 path supplied VideoToolbox with limited-range SMPTE 170M primaries/matrix and BT.709 transfer. After removing only the failed generated partial test artifact, the complete two-second run passed:

- HEVC Main, `hvc1`, 1248 × 704, `yuv420p`;
- limited-range SMPTE 170M primaries and matrix with BT.709 transfer;
- AC-3 stereo at 48 kHz with protected +6 dB gain;
- exactly 2.000 seconds and approximately 1.0 MB;
- hardware-only VideoToolbox encoding; and
- no `.partial.mp4` remaining after successful promotion.

The supplied M4V has no subtitle or chapter streams, so this milestone does not claim those paths are restored yet. Source show, season, and episode metadata are mapped into the prototype output, but broader metadata validation remains part of the next integration gate.

## Result and next gate

The restored video/audio assembly and partial-output safety design are technically proven for this representative SD source. Human playback confirmation is still required for picture, color, sound, gain, and synchronization.

After confirmation, the next milestone will generalize this prototype into reusable Swift-side restoration planning and validate subtitle, chapter, metadata, cancellation, and batch boundaries before exposing any restoration UI.
